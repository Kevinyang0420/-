import Foundation

/// **会员状态的单一来源** —— 全 App 判断"能不能用高级功能"都走这里，
/// 不许各处自己拼 `/api/pro` 请求（同一规矩多处实现＝必漂，见项目教训）。
///
/// 契约：`GET /api/pro`（带 `X-Alex-Pass`）→ `{pro: Bool, pro_until: Int}`。
/// 🚨 未登录时后端直接回 `{pro:false}`（不是 401），**不能拿"pro=false"当"读取失败"**，
///    两者都要区分对待：failure 时保留上一次的已知状态，false 时立刻收回权限。
enum ProStatus {
    private static let key = "pro.until.cached"

    /// 上一次确认的到期时间（本机缓存，秒级 UNIX 时间戳）。
    /// 🚨 **只用来在弱网时兜底显示，不用来放行** —— 放行判断永远走 `refresh` 拿到的新鲜值，
    ///    否则本机改一下 UserDefaults 就能白嫖会员，服务端配额形同虚设。
    private static var cachedUntil: TimeInterval {
        get { UserDefaults.standard.double(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// **当前这一刻是不是会员** —— 只读缓存，不发网络请求。
    /// 用于界面立刻着色（先給一个大概率对的答案），**不用于放行判断**。
    static var isProCached: Bool {
        cachedUntil > Date().timeIntervalSince1970
    }

    /// 🚨🚨 **真正要不要放行，必须调这个、等回调，不能只看 `isProCached`。**
    ///    - 网络失败：`onResult` 传 `nil`，调用方按"保守放行还是保守拒绝"自己决定
    ///      （这个类不替调用方做这个决定——不同功能的容错策略不一样）。
    ///    - 未登录 / 已过期：传 `false`，并把本机缓存清零（服务端说的算，
    ///      **不能因为本机缓存还没到期就继续放行**——今天验收判据④明确写了这条）。
    static func refresh(onResult: @escaping (_ isPro: Bool?) -> Void) {
        guard let url = URL(string: Backend.base + "/api/pro") else {
            return DispatchQueue.main.async { onResult(nil) }
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, resp, err in
            guard err == nil, let data = data,
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                KbBridge.note("会员状态：查不到（网络或服务端问题），保留上次已知状态")
                return DispatchQueue.main.async { onResult(nil) }
            }
            let isPro = (j["pro"] as? Bool) ?? false
            let until = (j["pro_until"] as? Double) ?? 0
            // 🚨 服务端返回什么就存什么，不做"看起来快过期了就多留一会"这种加工——
            //    那种加工正是"墙立在没人走到的地方"的另一种写法。
            cachedUntil = until
            KbBridge.note("会员状态：pro=" + String(isPro) + " until=" + String(Int(until)))
            DispatchQueue.main.async { onResult(isPro) }
        }.resume()
    }

    /// 🚨 供购买/恢复购买成功后**立刻**调一次，别等下一次自然刷新——
    ///    否则他刚付完钱，界面上看着还是没解锁，会以为没生效。
    static func refreshSoonAfterPurchase() {
        // 🚨 服务端从收到苹果通知到写完 `pro_until` 之间有个真实的处理时延
        //    （JWS 验签 + 落库），立刻查大概率还是旧值。轮询几次，不是查一次就放弃。
        var tries = 0
        func tick() {
            tries += 1
            refresh { pro in
                if pro == true || tries >= 6 { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: tick)
            }
        }
        tick()
    }

    /// 自测：好样本 + 坏样本各因不同原因失败。
    static func selftest() -> [String] {
        var bad: [String] = []
        UserDefaults.standard.set(0.0, forKey: key)
        if isProCached { bad.append("清零后 isProCached 仍是 true") }
        UserDefaults.standard.set(Date().timeIntervalSince1970 + 3600, forKey: key)
        if !isProCached { bad.append("设成一小时后过期，isProCached 却是 false") }
        UserDefaults.standard.set(Date().timeIntervalSince1970 - 3600, forKey: key)
        if isProCached { bad.append("设成一小时前过期，isProCached 却是 true") }
        return bad
    }
}
