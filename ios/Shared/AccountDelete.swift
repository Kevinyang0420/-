import Foundation

/// **删除账号**的网络层 —— 查状态 / 发码 / 确认 / 撤销。
///
/// ## 为什么必须做（0 台账 #72，卡 iOS 提交）
/// **App Store 明确要求 App 内提供账号删除入口。** 而同步确认弹窗上早就印着承诺
/// （`hs_ask_3`：「你删除账号时，云端的记录会一并删掉」），**三端却一个入口都没有**。
/// 网页那条（`transless.net/delete-account.html`）已上线，但**网页不算 App 内**。
///
/// ## 🚨 契约照**服务端源码**接（`backend/server_api.py:2432`），我读过原文
/// ```
/// GET                                  -> {stage:"none"|"pending", …}
/// POST {"confirm":"DELETE"}            -> 发码到他账号上的手机/邮箱
/// POST {"confirm":"DELETE","code":"…"} -> {stage:"pending", cooloff_days:7}
/// POST {"cancel":true}                 -> {stage:"none", cancelled:true}
/// 功能没开                              -> **200** {enabled:false, reason:"…"}
/// ```
///
/// 🚨🚨 **我第一版接错了，记在这里免得下一个人重犯**：
///    我照网页探针推出「第一步传 `{kind,target}`」，**结果是**
///    ① 服务端第一步就要 `confirm:"DELETE"`，只传 kind/target 会被 **400** 拒 ——
///       那个「发送验证码」按钮**根本不会成功**；
///    ② 源码里写死：`uid` **只从令牌解**，验证码的 target **只从他自己的账号行取**，
///       「不许客户端传 —— 让客户端指定 target 就等于送人一个接管账号的口子」。
///    **是 2.3 读源码提醒的，我核过原文确认他对。**
///    教训：**探针验的是"服务端会不会拒"，不是"客户端该怎么发"**。
///
/// 🚨 `enabled:false` 是 **HTTP 200**，是业务状态不是错误。
///    只看状态码会把「功能没开」读成「成功」，然后告诉用户账号删了。
///    所以**先判 `enabled` 再判 HTTP 码，顺序不能反**（2.3 在安卓侧同样处理）。
enum AccountDelete {

    enum Stage {
        case none
        case pending(days: Int)
        /// 服务端明说功能没开 —— 要跟"网络挂了"分开，否则他会一直重试。
        case notEnabled(String)
        case anon
    }

    enum Failure: Error {
        case notEnabled(String)
        case http(Int, String)
        case badRequest
    }

    /// 查当前状态（进账户页时后台查一次，`pending` 时入口变成「撤销」）。
    static func status(done: @escaping (Stage) -> Void) {
        send(method: "GET", body: nil) { r in
            switch r {
            case .failure(.notEnabled(let why)): done(.notEnabled(why))
            case .failure: done(.none)
            case .success(let o):
                if (o["anon"] as? Bool) == true { return done(.anon) }
                if (o["stage"] as? String) == "pending" {
                    done(.pending(days: (o["cooloff_days"] as? Int) ?? 7))
                } else {
                    done(.none)
                }
            }
        }
    }

    /// ① 发验证码 —— **服务端自己决定发到哪**（他账号行上的手机/邮箱）。
    static func requestCode(done: @escaping (Result<[String: Any], Failure>) -> Void) {
        send(method: "POST", body: ["confirm": "DELETE"], done: done)
    }

    /// ② 拿验证码确认。
    static func confirm(code: String,
                        done: @escaping (Result<[String: Any], Failure>) -> Void) {
        send(method: "POST", body: ["confirm": "DELETE", "code": code], done: done)
    }

    /// ③ 冷静期内撤销。
    static func cancel(done: @escaping (Result<[String: Any], Failure>) -> Void) {
        send(method: "POST", body: ["cancel": true], done: done)
    }

    // MARK: - 唯一的网络出口

    /// 🚨 四个动作**共用一个出口** —— 各写一份的话，改超时/改头/改错误分类必漏一处。
    private static func send(method: String, body: [String: Any]?,
                             done: @escaping (Result<[String: Any], Failure>) -> Void) {
        guard let url = URL(string: Backend.base + "/api/account/delete") else {
            return done(.failure(.badRequest))
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("application/json; charset=utf-8",
                     forHTTPHeaderField: "Content-Type")
        // 🚨 身份就靠这个头（服务端 `_uid_of(self.headers.get("X-Alex-Pass"))`）。
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        if let b = body {
            guard let d = try? JSONSerialization.data(withJSONObject: b) else {
                return done(.failure(.badRequest))
            }
            req.httpBody = d
        }
        URLSession.shared.dataTask(with: req) { d, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let obj = d.flatMap {
                try? JSONSerialization.jsonObject(with: $0)
            } as? [String: Any] ?? [:]
            // 🚨 **先判 enabled，再判 HTTP 码** —— 顺序反了就会把
            //    「功能没开」（200）读成成功。
            if let en = obj["enabled"] as? Bool, en == false {
                return done(.failure(.notEnabled((obj["reason"] as? String) ?? "")))
            }
            guard code == 200 else {
                return done(.failure(.http(code, (obj["error"] as? String)
                                           ?? (obj["reason"] as? String) ?? "")))
            }
            done(.success(obj))
        }.resume()
    }
}
