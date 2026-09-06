import Foundation

/// **删除账号**的两步网络调用 —— 发码 / 验码确认。
///
/// ## 为什么必须做（0 台账 #72，卡 iOS 提交）
/// **App Store 明确要求 App 内提供账号删除入口。** 而我们：
/// - 同步确认弹窗上早就印着承诺（`hs_ask_3`：「你删除账号时，云端的记录会一并删掉」）
/// - **三端都没有兑现它的入口**（1.1 换十种说法 grep 过，零命中；我自己也核了 iOS）
///
/// 网页那条（`transless.net/delete-account.html`）已经上线，
/// **但 App Store 要的是 App 内可达**，网页不算。
///
/// ## 🚨 契约照**活着的那条**接，不照文档猜
/// 线上有两个形状，我都探过：
/// ```
/// ① POST /api/account/delete {"confirm":"DELETE"}
///    -> 200 {"enabled": false, "reason": "删除账号功能还没开启"}   ← 关着的
/// ② POST /api/account/delete {"kind","target"}            发码
///    POST /api/account/delete {"kind","target","code","confirm":"DELETE"}  确认
///    -> 校验齐全、预检正常                                    ← 活的，网页走的就是它
/// ```
/// 接的是 ②。**①那条我不碰** —— 它连开关都没开。
///
/// 🚨 **发码/验码要真发短信，我没有真跑过**（探针也明说不发）。
///    所以这一层我只能保证"请求形状对、错误如实回"，
///    **端到端要等有人拿真号走一遍**。我不把「写了」说成「验了」。
enum AccountDelete {

    enum Failure: Error {
        /// 服务端明说功能没开（`enabled:false`）—— 要跟"网络挂了"分开，
        /// 否则他会一直重试一个根本没开的功能。
        case notEnabled(String)
        case http(Int, String)
        case badRequest
    }

    private static var base: String { Backend.base }

    /// ① 发验证码到他的账号。
    static func requestCode(kind: String, target: String,
                            done: @escaping (Result<Void, Failure>) -> Void) {
        post(["kind": kind, "target": target]) { r in
            switch r {
            case .success: done(.success(()))
            case .failure(let f): done(.failure(f))
            }
        }
    }

    /// ② 拿验证码确认删除。
    ///
    /// 🚨 `confirm: "DELETE"` 是**服务端要求的字面量**，不是随手写的 ——
    ///    少了它服务端会拒（探针里有这条坏样本）。
    static func confirm(kind: String, target: String, code: String,
                        done: @escaping (Result<[String: Any], Failure>) -> Void) {
        post(["kind": kind, "target": target,
              "code": code, "confirm": "DELETE"], done: done)
    }

    /// ③ 撤销（7 天冷静期内）。
    static func cancel(kind: String, target: String, code: String,
                       done: @escaping (Result<[String: Any], Failure>) -> Void) {
        post(["kind": kind, "target": target, "code": code, "cancel": true],
             done: done)
    }

    // MARK: - 唯一的网络出口

    /// 🚨 三个动作**共用一个出口** —— 三处各写一份 URLSession 的话，
    ///    改超时/改头/改错误分类必然漏一处。这摊活在"同一规矩多处实现"上栽过好几次。
    private static func post(_ body: [String: Any],
                             done: @escaping (Result<[String: Any], Failure>) -> Void) {
        guard let url = URL(string: base + "/api/account/delete"),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            return done(.failure(.badRequest))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json; charset=utf-8",
                     forHTTPHeaderField: "Content-Type")
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        URLSession.shared.dataTask(with: req) { d, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let obj = d.flatMap {
                try? JSONSerialization.jsonObject(with: $0)
            } as? [String: Any] ?? [:]
            // 🚨 **`enabled:false` 是 200**，不是错误码 ——
            //    只看 HTTP 状态码会把"功能没开"读成"成功"。
            if let en = obj["enabled"] as? Bool, en == false {
                let why = (obj["reason"] as? String) ?? ""
                return done(.failure(.notEnabled(why)))
            }
            guard code == 200 else {
                return done(.failure(.http(code, (obj["reason"] as? String) ?? "")))
            }
            done(.success(obj))
        }.resume()
    }
}
