import Foundation

/// **会员状态的单一来源** —— 全 App 判断"能不能用高级功能"都走这里，
/// 不许各处自己拼 `/api/pro` 请求（同一规矩多处实现＝必漂，见项目教训）。
///
/// 契约：`GET /api/pro`（带 `X-Alex-Pass`）→ 三种形状：
///   · `{pro: true, pro_until: N}`         —— 会员
///   · `{pro: false, reason: "未登录"}`     —— 没登录（**没有 `reason` 键就不是这一种**）
///   · `{pro: false, pro_until: 0}`        —— 登录了，没订阅
///   · HTTP 非 200（含 503）/ 网络失败      —— 查不到，跟上面三种都不是一回事
///
/// 🚨🚨 09-14 晚 Kevin 真机撞到的 bug：他的账号后端明明是十年 Pro，
///    界面却显示「未订阅」——根因是**这台设备没登录**，
///    而客户端把"没登录"和"登录了但没订阅"画成了同一句话、
///    还把"没登录"的人指去了付款页（他本来就付过钱，等于让他重复付费）。
///    `refresh()` 原来只读一个布尔、把 `reason` 整个丢掉，
///    调用方**没有任何办法**区分这两种状态。见 `ProCheckResult`。
enum ProStatus {
    private static let key = "pro.until.cached"

    // 🚨 `ProCheckResult` 和判定函数 `ProCheck.classify` 在 `Shared/ProCheck.swift`——
    //    那边拆出来是为了 UI 测试能编到它（这个文件牵着 Backend/KbBridge，
    //    UI 测试独立进程编不进去）。这里直接用，不重复定义。

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
        // GATE-OK: 纯展示占位，不做放行判断。权威结果由 refresh() 覆盖 ——
        //   AccountViewController 在 viewDidLoad/viewWillAppear/登录回调三处调 refresh()，
        //   回来后重写 proState，memberRow() 照权威结果画（0 2026-09-16 逐个查过调用链）。
        cachedUntil > Date().timeIntervalSince1970  // GATE-OK: 占位，refresh() 覆盖
    }

    /// 缓存的到期时间本身（只读）。给界面画"乐观占位"用，比如页面刚出现、
    /// 还没问完服务端时先按这个显示，回来后立刻用权威结果纠正。
    static var cachedUntilValue: TimeInterval { cachedUntil }

    /// 🚨🚨 09-17 Kevin 真机撞到：换一个从没注册过的邮箱登进去，界面直接显示会员。
    ///    `isProCached` 只是"乐观占位"，真值靠 `refresh()` 网络回来才纠正——
    ///    但账号切换和 `refresh()` 完成之间有个窗口期，这个窗口期内读到的是
    ///    **上一个账号**的缓存，不是"还没查到"，是"查错了人"。
    ///    在身份真正换掉的那一刻**同步、立刻**清零缓存，别等网络：
    ///    `Auth.save()`（新会话建立）和 `Auth.signOut()` 两处调用。
    static func clearCache() {
        cachedUntil = 0
    }

    /// 🚨🚨 **真正要不要放行，必须调这个、等回调，不能只看 `isProCached`。**
    ///    - `.unreachable`（网络失败 / 非 200，含 503）：调用方按"保守放行还是保守拒绝"
    ///      自己决定（这个类不替调用方做这个决定——不同功能的容错策略不一样），
    ///      **本机缓存原样不动**。
    ///    - `.notLoggedIn` / `.notSubscribed`（已过期）：本机缓存清零（服务端说的算，
    ///      **不能因为本机缓存还没到期就继续放行**——今天验收判据④明确写了这条）。
    static func refresh(onResult: @escaping (ProCheckResult) -> Void) {
        guard let url = URL(string: Backend.base + "/api/pro") else {
            return DispatchQueue.main.async { onResult(.unreachable) }
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
                // 🚨 这条**不许碰 `cachedUntil`**——网络抖一下不能把付费用户
                //    吓成没付费（`_spec_not_logged_in_vs_not_subscribed.md` ④）。
                KbBridge.note("会员状态：查不到（网络或服务端问题，含 503），保留上次已知状态")
                return DispatchQueue.main.async { onResult(.unreachable) }
            }
            let isPro = (j["pro"] as? Bool) ?? false
            let until = (j["pro_until"] as? Double) ?? 0
            // 🚨 服务端返回什么就存什么，不做"看起来快过期了就多留一会"这种加工——
            //    那种加工正是"墙立在没人走到的地方"的另一种写法。
            cachedUntil = until
            let result = ProCheck.classify(isPro: isPro, until: until, hasReason: j["reason"] != nil)
            KbBridge.note("会员状态：pro=" + String(isPro) + " until=" + String(Int(until))
                          + " reason=" + ((j["reason"] as? String) ?? "（无）"))
            DispatchQueue.main.async { onResult(result) }
        }.resume()
    }

    /// 🚨🚨 **购买时要传的 `appAccountToken`，由服务端按 `user_id` 确定性算出**——
    ///    客户端**绝不自己生成/派生**这个 UUID（那正是 09-12 报出来又被 1.1
    ///    修掉的洞：客户端瞎编的 UUID，服务端永远反查不回真实账号）。
    ///
    ///    契约：`GET /api/pro` 响应里带一个 `purchase_uuid` 字段（字符串）。
    ///    未登录时这个字段就是空/缺失——`onResult(nil)`，调用方（`IAP.purchase`）
    ///    要么先走 `loginGate`，要么干脆不让没登录的人看到订阅按钮
    ///    （现在的路径是前者：`SubscribeViewController` 靠 `loginGate` 挡在前面）。
    static func fetchPurchaseUUID(onResult: @escaping (UUID?) -> Void) {
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
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let s = j["purchase_uuid"] as? String,
                  let u = UUID(uuidString: s)
            else {
                KbBridge.note("购买凭证：读不到 purchase_uuid（未登录，或网络问题）")
                return DispatchQueue.main.async { onResult(nil) }
            }
            DispatchQueue.main.async { onResult(u) }
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
            refresh { result in
                if case .pro = result { return }
                if tries >= 6 { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: tick)
            }
        }
        tick()
    }

    /// 自测：好样本 + 坏样本各因不同原因失败。
    /// 🚨 三态判定的判据在 `Shared/ProCheck.swift`（`ProCheck.classify`）自己的
    ///    调用点里测，这里只测 `isProCached` 这个跟本地缓存直接挂钩的部分——
    ///    别把同一件事测两遍、也别指望这个跑不进 UI 测试包的函数覆盖到判定逻辑。
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
