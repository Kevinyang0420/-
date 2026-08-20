import Foundation

/// 调 Kevin 已经在跑的火山函数（Alex 的后端），不另建服务。
///
/// 🚨 必须走「提交 job + 轮询」。带 sync:1 会被 API 网关回 504 upstream request timeout
///    （2026-08-20 实测撞过）。
enum Backend {

    static let base = "https://sqg75i2mlmanf4sqde6nh.apigateway-cn-beijing.volceapi.com"

    enum Failure: Error, CustomStringConvertible {
        case http(Int)
        case unauthorized
        case quota(String)
        case message(String)
        case timeout

        var description: String {
            switch self {
            case .http(let c):      return "HTTP \(c)"
            case .unauthorized:     return "口令不对，重新装一次"
            case .quota(let m):     return m
            case .message(let m):   return m
            case .timeout:          return "等太久了，再点一次"
            }
        }
    }

    static func polish(text: String, tone: String,
                       done: @escaping (Result<String, Failure>) -> Void) {
        submit(text: text, tone: tone, attempt: 0, done: done)
    }

    /// 🚨 提交那一发也会 504（网关冷启动/抖动，2026-08-21 Kevin 真机撞到）。
    ///    5xx 和传输错误都自动重试，最多 4 发、间隔递增；401/429 是明确答复，不重试。
    private static func submit(text: String, tone: String, attempt: Int,
                               done: @escaping (Result<String, Failure>) -> Void) {
        func retryOrFail(_ f: Failure) {
            if attempt < 3 {
                DispatchQueue.global().asyncAfter(deadline: .now() + Double(attempt + 1) * 2) {
                    submit(text: text, tone: tone, attempt: attempt + 1, done: done)
                }
            } else {
                done(.failure(f))
            }
        }
        let system = Secrets.prompt
        let user = "Register: \(Prompts.tone(tone))\n\nRaw transcript:\n\"\"\"\n\(text)\n\"\"\"\n"
        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "temperature": 0.3,
            "max_tokens": 1200,
        ]
        guard let url = URL(string: base + "/api/llm"),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            return done(.failure(.message("请求组装失败")))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(Secrets.pass, forHTTPHeaderField: "X-Alex-Pass")
        req.httpBody = data

        URLSession.shared.dataTask(with: req) { d, resp, err in
            if let err = err { return retryOrFail(.message(err.localizedDescription)) }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { return done(.failure(.unauthorized)) }
            let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            if code == 429 {
                return done(.failure(.quota((obj?["error"] as? String) ?? "额度用完了")))
            }
            if code >= 500 { return retryOrFail(.http(code)) }
            // 🚨 提交 job 返回的是 **202 Accepted**，不是 200（2026-08-20 实测：
            //    `{"job": "..."}` 配 HTTP 202）。第一版写死 code == 200，
            //    真机上就直接报 "HTTP 202" 失败。
            //    而我的 Python 验证脚本压根没查状态码、直接读 j['job']，所以一路绿灯 ——
            //    典型的假检查：两边判据不一致时，宽松的那边先通过，严格的那边才炸。
            guard code == 200 || code == 202, let job = obj?["job"] as? String else {
                return done(.failure(.http(code)))
            }
            poll(job: job, tries: 0, done: done)
        }.resume()
    }

    private static func poll(job: String, tries: Int,
                             done: @escaping (Result<String, Failure>) -> Void) {
        if tries > 90 { return done(.failure(.timeout)) }
        guard let url = URL(string: base + "/api/job?id=" + job) else {
            return done(.failure(.message("job 地址不对")))
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue(Secrets.pass, forHTTPHeaderField: "X-Alex-Pass")

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.7) {
            URLSession.shared.dataTask(with: req) { d, _, _ in
                let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
                // 网络抖一下就再问一次，别直接判失败
                guard let obj = obj else { return poll(job: job, tries: tries + 1, done: done) }
                if let e = obj["error"] as? String, obj["done"] as? Bool == true {
                    return done(.failure(.message(e)))
                }
                if obj["done"] as? Bool == true {
                    let raw = (obj["text"] as? String) ?? ""
                    let en = Prompts.postprocess(Prompts.splitEn(raw))
                    if en.isEmpty { return done(.failure(.message("返回了空结果"))) }
                    return done(.success(en))
                }
                poll(job: job, tries: tries + 1, done: done)
            }.resume()
        }
    }
}
