import Foundation

/// 调 Kevin 已经在跑的火山函数（Alex 的后端），不另建服务。
///
/// 🚨 必须走「提交 job + 轮询」。带 sync:1 会被 API 网关回 504 upstream request timeout
///    （2026-08-20 实测撞过）。
enum Backend {

    /// 后端地址 —— **Transless 自己的网关**。
    ///
    /// 🚨 2026-08-26 起 Transless 从 Alex 拆成独立的云函数 + **独立网关**
    ///    （不再是 `/t` 前缀那一版）。指着 Alex 那个地址也能用，
    ///    所以**错了不会报错** —— 只是发 Transless 的后端改动时收不到，
    ///    还会被 Alex 的部署波及。
    ///
    /// 🚨 判据不是"两边返回一样"（两个函数跑同一份代码，本来就一样 ——
    ///    那是同源自比），是 `/api/health` 的 **instance 指纹**：
    ///    2026-08-26 实测 Alex `e1208c70` ／ Transless `6d279333`，零重叠；
    ///    build 相同是对照组，证明这个差别不是代码漂移造成的。
    ///    守这条的闸门：`D:\_build\gate_backend_split.py`。
    ///    源码/部署见 `voice_ime/backend/README.md`。
    static let base = "https://s473bcc0af89cidqeqrdr.apigateway-cn-beijing.volceapi.com"

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

    /// 输出模式。跟安卓 `Api.MODE_*` 一一对应（Kevin 规矩：两端一致）。
    enum Mode: String {
        case en    // 译成英文：清洗+结构化+译英（默认）
        case zh    // 结构化转写：清洗+结构化，中文，不翻译
        case raw   // 逐字转录：说什么写什么，**不过模型**
    }

    /// 目标语言。跟 engine.py 的 LANGS、安卓的 Gen.LANG_CODES 一一对应。
    /// 🚨 单一配置点在 engine.py；这里加语言要三处一起加，别只改一边。
    static let langs: [(code: String, label: String, name: String)] = [
        ("en", "英文", "English"),
        // 🚨 中文也是目标语言（Kevin 2026-08-23：「假如使用者是老外，
        //    他也要翻译成中文嘛」）。跟「结构化转写」那一档不是一回事：
        //    转写档是"说中文出中文"，这里是"说任何语言译成中文"。
        ("zh", "中文",
         "Simplified Chinese (简体中文). Use Mainland China wording "
         + "and simplified characters throughout, never traditional."),
        // 繁体中文是独立一档（Kevin 2026-08-25：「适合海外人群」），
        //    不是「中文」的显示变体。用台湾用语，跟 engine.py 那份逐字一致。
        ("zht", "繁体中文",
         "Traditional Chinese (繁體中文), TAIWAN conventions. THREE hard requirements: "
         + "(1) TRADITIONAL characters throughout (會/報/聽/開/實), never simplified; (2) "
         + "TAIWAN vocabulary — use 軟體/網路/影片/資訊/設定/檔案/程式/滑鼠/列印, NOT "
         + "软件/网络/视频/信息/设置/文件/程序/鼠标/打印; (3) Taiwan punctuation: full-width 「」 for "
         + "quotes, not “”. This is Mandarin in traditional script — do NOT write "
         + "Cantonese."),
        ("ja", "日语", "Japanese"),
        ("fr", "法语", "French"), ("de", "德语", "German"),
        ("es", "西班牙语", "Spanish"), ("ko", "韩语", "Korean"),
        // 🚨 粤语的 name 里那一长串要求不能省：只写 "Cantonese" 模型会吐普通话，
        //    实测过一次半吊子输出「下周一嘅会先取消住」（粤语虚词 + 普通话词汇 + 简体）。
        //    三条硬要求：繁体字、粤语词汇、粤语语法。跟 engine.py 那份保持一致。
        ("yue", "粤语",
         "written Cantonese (粤语书面语). THREE hard requirements: (1) TRADITIONAL "
         + "characters throughout (會/報/聽/嘅), never simplified; (2) Cantonese "
         + "VOCABULARY, not Mandarin words in traditional skin — use "
         + "聽日/尋日/下星期一/而家/依家/畀/同…講/唔該/點解/邊個/得閒/同埋, NOT 明天/昨天/下周一/现在/给/跟…说/谢谢/为什么/哪个; "
         + "(3) Cantonese grammar words: 嘅、唔、係、咗、喺、佢、冇、睇、啲、咁、乜嘢、㗎、嘞. (4) Use these "
         + "exact characters so text-to-speech reads them correctly: write 翻嚟 (NOT "
         + "返嚟/翻黎/返黎), 嚟 not 黎, 咁 not 甘, 嘅 not 既, 嘢 not 野, 啱 not 岩, 畀 not 比, 啲 not D. "
         + "Example: 「份報表我聽日下晝三點前畀你，仲要 cc 埋 Annie。」"),
    ]

    static func langName(_ code: String) -> String {
        langs.first { $0.code == code }?.name ?? "English"
    }

    static func langLabel(_ code: String) -> String {
        langs.first { $0.code == code }?.label ?? "英文"
    }

    static func polish(text: String, tone: String, mode: Mode = .en,
                       lang: String = "en",
                       done: @escaping (Result<String, Failure>) -> Void) {
        // 🚨 逐字转录直接短路：过一遍模型就有被润色的风险，还白等几秒、白花一次调用
        if mode == .raw { return done(.success(text)) }
        submit(text: text, tone: tone, mode: mode, lang: lang, attempt: 0, done: done)
    }

    /// 🚨 提交那一发也会 504（网关冷启动/抖动，2026-08-21 Kevin 真机撞到）。
    ///    5xx 和传输错误都自动重试，最多 4 发、间隔递增；401/429 是明确答复，不重试。
    private static func submit(text: String, tone: String, mode: Mode, lang: String,
                               attempt: Int,
                               done: @escaping (Result<String, Failure>) -> Void) {
        func retryOrFail(_ f: Failure) {
            if attempt < 3 {
                DispatchQueue.global().asyncAfter(deadline: .now() + Double(attempt + 1) * 2) {
                    submit(text: text, tone: tone, mode: mode, lang: lang,
                           attempt: attempt + 1, done: done)
                }
            } else {
                done(.failure(f))
            }
        }
        let zhOnly = (mode == .zh)
        let system = zhOnly ? Secrets.promptZh : Secrets.prompt
        // 🚨 "Target language:" 必须在最前面 —— 提示词按这个位置读
        let user = zhOnly
            ? "Raw transcript:\n\"\"\"\n\(text)\n\"\"\"\n"
            : "Target language: \(langName(lang))\nRegister: \(Prompts.tone(tone))"
              + "\n\nRaw transcript:\n\"\"\"\n\(text)\n\"\"\"\n"
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
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
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
            // 转写模式返回的是中文正文，没有 <<<OUT>>>/<<<ZH>>> 分段 —— 走 pollRaw
            if zhOnly { pollRaw(job: job, tries: 0, done: done) }
            else { poll(job: job, tries: 0, done: done) }
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
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")

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

    // MARK: - 朗读（Andrew 的声音，跟 Alex 陪练同一个）

    /// 把文字合成语音，返回 mp3 数据。
    /// 🚨 Kevin 2026-08-21：翻译完要能点一下听出来。跟安卓 `Api.speak` 同一个端点。
    static func speak(text: String, done: @escaping (Result<Data, Failure>) -> Void) {
        guard let url = URL(string: base + "/api/tts") else {
            return done(.failure(.message("地址不对")))
        }
        // voice 用短名，真正的 voice 名字由后端映射 —— 前端不硬编
        let body: [String: Any] = ["text": text, "voice": "andrew"]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            return done(.failure(.message("请求组装失败")))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        req.httpBody = data

        URLSession.shared.dataTask(with: req) { d, resp, err in
            if let err = err { return done(.failure(.message(err.localizedDescription))) }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { return done(.failure(.unauthorized)) }
            let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            guard code == 200 || code == 202, let job = obj?["job"] as? String else {
                return done(.failure(.http(code)))
            }
            pollAudio(job: job, tries: 0, done: done)
        }.resume()
    }

    private static func pollAudio(job: String, tries: Int,
                                  done: @escaping (Result<Data, Failure>) -> Void) {
        if tries > 60 { return done(.failure(.timeout)) }
        guard let url = URL(string: base + "/api/job?id=" + job) else {
            return done(.failure(.message("job 地址不对")))
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
            URLSession.shared.dataTask(with: req) { d, _, _ in
                let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
                guard let obj = obj else { return pollAudio(job: job, tries: tries + 1, done: done) }
                if let e = obj["error"] as? String, obj["done"] as? Bool == true {
                    return done(.failure(.message(e)))
                }
                if obj["done"] as? Bool == true {
                    guard let b64 = obj["audio"] as? String,
                          let mp3 = Data(base64Encoded: b64), !mp3.isEmpty else {
                        return done(.failure(.message("没返回音频")))
                    }
                    return done(.success(mp3))
                }
                pollAudio(job: job, tries: tries + 1, done: done)
            }.resume()
        }
    }

    // MARK: - 一次做完：录音 → 转写 → 整理/翻译（+ 自动判方向）

    /// `/api/voice` 一趟做完，并让后端顺带判"这句是谁说的"。
    ///
    /// 🚨🚨 **判方向的规则不在客户端**。唯一真值是后端 `backend/mylang.py`
    ///    的 `classify(text, ui_lang)`。**iOS 不许再抄一份判语种的逻辑** ——
    ///    三端各写一份必然漂，而且这条特别容易写成 `isChinese(text)`：
    ///    那样"界面=英文"的用户说英文会被判成「对方」、方向整个反过来，
    ///    **而它在中文界面下全绿**。
    ///
    /// 🚨 请求体**逐字对齐安卓 `Api.voice()`** —— 同一个后端，两端不该发不同的东西。
    ///    只在**翻译档**带 `__TARGET__`：逐字/只转写这两档没有"译成哪种语言"
    ///    这个概念，传了只会让后端去填一个用不上的占位符。
    ///
    /// 返回 `(out: 上屏内容, zh: ASR 原文, dir: MINE/THEIRS/UNKNOWN 或空)`。
    /// 🚨 `dir` 为 `UNKNOWN` 时**界面必须显式显示当前按哪个方向走、且一键可翻转**
    ///    （产品经理 T2-e）。后端兜底走"我说话"那侧但把 UNKNOWN 原样透出 ——
    ///    **不许静默按兜底走**：用户不知道它猜了，出错时会以为是翻译质量差。
    static func voice(wav: Data, tone: String, mode: Mode, lang: String,
                      uiLang: String?, mineTarget: String?, theirsTarget: String?,
                      done: @escaping (Result<(out: String, zh: String,
                                               dir: String), Failure>) -> Void) {
        guard let url = URL(string: base + "/api/voice") else {
            return done(.failure(.message("地址不对")))
        }
        let zhOnly = (mode == .zh)
        let rawOnly = (mode == .raw)
        // 🚨 逐字档也要过模型（只加标点），所以 mode 一律发 "en"。
        //    发 "raw" 后端会跳过模型，回来的是没标点的 ASR 原文。
        let autoDir = uiLang != nil && mineTarget != nil && theirsTarget != nil
            && !(zhOnly || rawOnly)
        let user = (zhOnly || rawOnly)
            ? "Raw transcript:\n\"\"\"\n__TEXT__\n\"\"\"\n"
            : "Target language: \(autoDir ? "__TARGET__" : langName(lang))\n"
              + "Register: \(Prompts.tone(tone))\n\n"
              + "Raw transcript:\n\"\"\"\n__TEXT__\n\"\"\"\n"
        var body: [String: Any] = [
            "audio": wav.base64EncodedString(),
            "format": "wav",
            "mode": "en",
            "max_tokens": 4000,
            "sys": zhOnly ? Secrets.promptZh : Secrets.prompt,
            "user": user,
        ]
        if autoDir {
            body["ui_lang"] = uiLang
            body["mine_target"] = mineTarget
            body["theirs_target"] = theirsTarget
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            return done(.failure(.message("请求组装失败")))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        req.httpBody = data
        URLSession.shared.dataTask(with: req) { d, resp, err in
            if let err = err { return done(.failure(.message(err.localizedDescription))) }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { return done(.failure(.unauthorized)) }
            let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            if code == 429 {
                return done(.failure(.quota((obj?["error"] as? String) ?? "额度用完了")))
            }
            guard code == 200 || code == 202, let job = obj?["job"] as? String else {
                return done(.failure(.http(code)))
            }
            pollVoice(job: job, tries: 0, zhOnly: zhOnly, rawOnly: rawOnly, done: done)
        }.resume()
    }

    private static func pollVoice(
        job: String, tries: Int, zhOnly: Bool, rawOnly: Bool,
        done: @escaping (Result<(out: String, zh: String, dir: String), Failure>) -> Void) {
        if tries > 90 { return done(.failure(.timeout)) }
        guard let url = URL(string: base + "/api/job?id=" + job) else {
            return done(.failure(.message("job 地址不对")))
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        URLSession.shared.dataTask(with: req) { d, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { return done(.failure(.unauthorized)) }
            let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            if code == 502, let e = obj?["error"] as? String {
                return done(.failure(.message(e)))
            }
            if (obj?["done"] as? Bool) != true {
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    pollVoice(job: job, tries: tries + 1, zhOnly: zhOnly,
                              rawOnly: rawOnly, done: done)
                }
                return
            }
            let raw = (obj?["text"] as? String) ?? ""
            let zh = (obj?["zh"] as? String) ?? ""
            let dir = (obj?["dir"] as? String) ?? ""
            var out = (zhOnly || rawOnly)
                ? raw.trimmingCharacters(in: .whitespacesAndNewlines)
                : Prompts.postprocess(Prompts.splitEn(raw))
            if out.isEmpty { return done(.failure(.message("返回了空结果"))) }
            // 🚨 逐字档的硬闸，跟安卓同一条判据：去掉标点空白后必须跟 ASR 原文
            //    一模一样，否则丢掉模型结果、用原文。
            if rawOnly && !zh.isEmpty && !sameWords(zh, out) {
                out = zh.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            done(.success((out: out, zh: zh.isEmpty ? out : zh, dir: dir)))
        }.resume()
    }

    /// 去掉标点空白后是不是同一串字（逐字档的硬闸用）。跟安卓 `sameWords` 同口径。
    private static func sameWords(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String {
            String(s.unicodeScalars.filter {
                !CharacterSet.whitespacesAndNewlines.contains($0)
                    && !CharacterSet.punctuationCharacters.contains($0)
                    && !CharacterSet.symbols.contains($0)
            })
        }
        return norm(a) == norm(b)
    }

    // MARK: - 语音转写（跟安卓同一条链：录 WAV → /api/audio → 火山 ASR）

    /// 把录好的 WAV 传火山 `/api/audio` 转写成中文。
    /// 🚨 两端一致（Kevin 2026-08-21 规矩）：安卓 `Api.transcribe` 走的就是这个端点。
    ///    iOS 原来用 `SFSpeechRecognizer`，现改成后端转写，两端行为拉齐。
    static func transcribe(wav: Data, done: @escaping (Result<String, Failure>) -> Void) {
        guard let url = URL(string: base + "/api/audio") else {
            return done(.failure(.message("地址不对")))
        }
        let body: [String: Any] = [
            "audio": wav.base64EncodedString(),
            "format": "wav",
            "prompt": "只输出这段话的中文逐字转写，不要翻译、不要润色、不要加任何解释。",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            return done(.failure(.message("请求组装失败")))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        req.httpBody = data

        URLSession.shared.dataTask(with: req) { d, resp, err in
            if let err = err { return done(.failure(.message(err.localizedDescription))) }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { return done(.failure(.unauthorized)) }
            let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            if code == 429 {
                return done(.failure(.quota((obj?["error"] as? String) ?? "额度用完了")))
            }
            guard code == 200 || code == 202, let job = obj?["job"] as? String else {
                return done(.failure(.http(code)))
            }
            pollRaw(job: job, tries: 0, done: done)
        }.resume()
    }

    /// 转写用的轮询：返回**原始文字**（不做 splitEn/翻译），只清掉汉字间空格。
    private static func pollRaw(job: String, tries: Int,
                               done: @escaping (Result<String, Failure>) -> Void) {
        if tries > 90 { return done(.failure(.timeout)) }
        guard let url = URL(string: base + "/api/job?id=" + job) else {
            return done(.failure(.message("job 地址不对")))
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.7) {
            URLSession.shared.dataTask(with: req) { d, _, _ in
                let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
                guard let obj = obj else { return pollRaw(job: job, tries: tries + 1, done: done) }
                if let e = obj["error"] as? String, obj["done"] as? Bool == true {
                    return done(.failure(.message(e)))
                }
                if obj["done"] as? Bool == true {
                    let zh = cleanZh((obj["text"] as? String) ?? "")
                    if zh.isEmpty { return done(.failure(.message("没听清，再说一次"))) }
                    return done(.success(zh))
                }
                pollRaw(job: job, tries: tries + 1, done: done)
            }.resume()
        }
    }

    /// 火山 ASR 会把中文逐字用空格隔开（"明 天 下 午"）—— 去掉汉字之间的空格。
    /// 跟安卓 `Api.cleanZh` 逻辑一致。
    static func cleanZh(_ s: String) -> String {
        func cjk(_ c: Character) -> Bool {
            guard let v = c.unicodeScalars.first?.value else { return false }
            return v >= 0x4E00 && v <= 0x9FFF
        }
        let a = Array(s)
        var out = [Character]()
        for (i, ch) in a.enumerated() {
            if ch == " " {
                let p = out.last
                let n = i + 1 < a.count ? a[i + 1] : nil
                if let p = p, let n = n, cjk(p), cjk(n) { continue }
            }
            out.append(ch)
        }
        return String(out).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
