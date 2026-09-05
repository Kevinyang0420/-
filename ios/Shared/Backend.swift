import Foundation

/// 调 Kevin 已经在跑的火山函数（Alex 的后端），不另建服务。
///
/// 🚨 必须走「提交 job + 轮询」。带 sync:1 会被 API 网关回 504 upstream request timeout
///    （2026-08-20 实测撞过）。
enum Backend {

    /// 这次出稿用哪份系统提示词 —— **全 iOS 唯一的一处**。
    ///
    /// 🚨🚨 建这个咽喉是因为同一件事已经在这个文件里栽过一次：三档分支原来在
    ///    `submit()` 和 `/api/voice` 两处各写一遍，改了前者漏了后者，
    ///    **而键盘走的正是后者**，于是逐字档拿着翻译档的提示词跑
    ///    （见下面 `"sys":` 那段的原始注释）。现在两处都调这里。
    ///
    /// 🚨 常用词的出稿侧提示（`kind = style`/`both` 的词）**只在这里拼**。
    ///    2026-09-04 之前 iOS 根本没接这一段 —— 识别侧的 `vocab` 数组发了，
    ///    出稿侧一个字都没发，「只喂出稿」那一档静默失效。
    ///    模板由 `sync_vocabhint_ios.py` 从 engine.py 的 `VOCAB_HINT` 生成，
    ///    三端同一句话，别在这里手写。
    ///
    /// 🚨 **逐字档不加词表**（跟安卓 `sysFor` 一致：`if (punctOnly) return base`）：
    ///    那一档只许加标点、不许改字，塞词表进去是在请模型改写。
    static func sysFor(rawOnly: Bool, zhOnly: Bool) -> String {
        let base = rawOnly ? Secrets.promptPunct
                           : (zhOnly ? Secrets.promptZh : Secrets.prompt)
        if rawOnly { return base }
        return base + Prompts.vocabHint(KbBridge.styleVocab())
    }

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

    /// 从 job 响应里读出失败。**四个错误出口都走它 —— 只有这一份。**
    ///
    /// 🚨 上一版是四处各写一遍，**其中一处形状不同**
    ///    （`code == 502, let e = obj?["error"]`），
    ///    于是"按形状找"的时候它不在集合里、被漏掉 ——
    ///    **规则写对了，覆盖面比以为的小一处。**
    ///    抽成一份之后，**"只有一份"是物理事实，不是我记得**。
    /// 提交出口拿到响应体之后，**该停还是该重试**。四个端点共用这一份。
    ///
    /// 🚨🚨 低-4：这段判据原来**只在 `submit`（/api/llm）里有**，
    ///    另外三个端点（tts / voice / audio）的提交出口是
    ///    `if let f = failureFrom(obj) { return done(.failure(f)) }` ——
    ///    **无 kind 的 5xx 也一次判死**。
    ///    而中-1 恢复那条重试的依据（2026-08-21 网关冷启动 502/504 +
    ///    `{"error":"upstream request timeout"}`，第 2 发就过）
    ///    **对四个端点同样成立** —— 所以四个端点现在**都**接了重试通道
    ///    （复审 中-2：上一版只有 `/api/llm` 接了，而这段文档却说四个都成立，
    ///     "抽了共享判据、点名的症状一次都没修"）。
    ///
    /// 🚨 抽出来还有一个理由：这是第四次要写同一段判据。
    ///    **抄第四遍 = 迟早有一处跟另外三处不一样**（今晚已经出现过）。
    ///
    /// - Returns: `true` = 已经处理掉了（调用方直接 return）
    /// 一次**业务请求**的幂等 id（同一次的所有重试共用一个）。
    ///
    /// 🚨🚨 后端的去重**早就建好了**（`server_api.py` 的 `_REQ_SEEN`，120 秒窗口，
    ///    排在埋点和 `quota_bump()` **之前**），而客户端一个都没发 ——
    ///    **这个能力从建好那天起一次都没被用过**，
    ///    我还据一句「req_id 还没有」把重试上限砍到 1 次。
    ///    **把某时刻为真的当成此刻为真**（记忆 `feedback_check_rule_freshness_first`）。
    ///
    /// 🚨 **必须在入口生成一次、贯穿所有 attempt**。
    ///    在 `retryOrFail` 里重生成 = 每次都是新 id = 等于没接。
    ///
    /// 🚨🚨 **接上 ≠ 重复计费解决了**：`_REQ_SEEN` 是**进程内的 dict**，
    ///    火山 FaaS 多实例时，重试落到另一个实例就完全绕过去。
    ///    判据不能是「我发了这个头」——要拿**两发相同 id、看 `quota_used`
    ///    有没有 +2** 去量，且要在**冷启动扩容**那种真换实例的场景下量一次。
    ///    跨实例要真解决，得把 `_REQ_SEEN` 挪到 `device_store` 那条 Supabase 路上。
    static func newReqId() -> String { UUID().uuidString }

    static func handleSubmitBody(
        code: Int, obj: [String: Any]?,
        retry: ((Failure) -> Void)? = nil,
        fail: (Failure) -> Void) -> Bool {
        guard let r = JobErrorParse.parse(obj), let f = failureFrom(obj) else {
            return false
        }
        // 有 kind = 后端明确分类过 → 立刻停，不重试
        if !r.kind.isEmpty { fail(f); return true }
        // 无 kind 的 5xx = 可能是网关抖动 → 能重试就重试
        if code >= 500, let retry = retry { retry(f); return true }
        // 其余（无 kind 的 4xx，或这个端点没有重试通道）→ 明确答复
        fail(f)
        return true
    }

    static func failureFrom(_ obj: [String: Any]?) -> Failure? {
        // 🚨🚨 **解析本身在 `JobErrorParse`，这里不许再写一份。**
        //    那边是纯函数、有自测（含「错误体不带 done」那条坏样本）；
        //    在这里另写一份 = 自测保的是另一个对象，绿了也不作数。
        guard let r = JobErrorParse.parse(obj) else { return nil }
        // 后端给了分类就用分类，别再按内容猜（kind 见 server_api.py:283-288）
        return r.kind.isEmpty ? .message(r.message)
                              : .kinded(r.kind, r.message, r.retryKind)
    }

    enum Failure: Error, CustomStringConvertible {
        case http(Int)
        case unauthorized
        case quota(String)
        case message(String)
        /// 🚨 后端明确给了分类的那一档。**有它就不猜。**
        ///    `kind` 取值见 `server_api.py:283-288`：
        ///    `asr_empty / blocked / bad_request / auth / upstream / internal`
        /// 第三个值 = 后端显式给的 `retry_kind`（`respeak` / `resend`，空 = 没给）。
        /// 🚨 **别由 `kind` 推它** —— 见 `JobErrorParse.parse` 的说明。
        case kinded(String, String, String)
        case timeout
        /// 🚨 **够不着服务器**（拔网线/超时/DNS）。判定在 `NetClassify`，
        ///    **不按错误文字猜** —— 文字随系统语言变。
        case network

        /// 🚨🚨 **重试到底怎么重 —— 唯一判据出口。**
        ///
        /// `retry:true` 老路径的动作是**重传同一段音频**（那套 pending 就是为它写的）。
        /// 静音那段重传必然还是 `no_speech` → **无限重试、每次都花 Kevin 的钱**，
        /// 而他什么也拿不到。所以后端显式给 `retry_kind`，客户端**不许猜**。
        ///
        /// 🚨 **不许写成 `kind == "no_speech"`**：那是把后端的语义硬编在客户端，
        ///    后端一改我们就静默错；更要命的是**测试改不动行为**
        ///    （2.1 的坏样本：把 `retry_kind` 去掉或改成 `resend`，
        ///     客户端行为必须跟着变回"重传同段"—— 怎么改都一样 = 分叉没接上）。
        ///
        /// - Returns: `true` = 这段音频作废、要他**重新说一次**；
        ///            `false` = 老路径（重传同一段）或本来就不可重试。
        var needsRespeak: Bool {
            if case .kinded(_, _, let rk) = self { return rk == "respeak" }
            return false
        }

        /// 给用户看的那一句。🚨 **`description` 是给我们看的，不许直接上屏。**
        var userText: String {
            let k: FailureText.Kind
            switch self {
            case .http: k = .http
            case .unauthorized: k = .unauthorized
            case .quota: k = .quota
            case .message: k = .message
            case .kinded(let kk, _, _): return FailureText.byKind(kk)
            case .timeout: k = .timeout
            case .network: k = .network
            }
            return FailureText.userText(kind: k, raw: description)
        }

        /// 朗读失败时给用户看的那一句。
        ///
        /// 🚨 **M-D：不许一律硬写 `err_tts_failed`。**
        ///    额度用完 / 口令不对 / 断网 这三种**跟朗读没关系**，
        ///    它们会让**下一次翻译也失败**；说成「读不出来」会让他以为
        ///    只是朗读坏了，接着去点翻译再撞一次，而且不知道该干什么。
        ///
        /// 🚨 其余一律回 `err_tts_failed` —— 它的重点是**「文字还在」**，
        ///    朗读是次要动作，不能让他以为整件事失败了。
        var ttsText: String {
            switch self {
            case .quota, .unauthorized, .network: return userText
            case .kinded(let k, _, _) where k == "auth" || k == "quota": return userText
            default: return L.err_tts_failed
            }
        }

        var description: String {
            switch self {
            case .http(let c):      return "HTTP \(c)"
            case .unauthorized:     return "口令不对，重新装一次"
            case .quota(let m):     return m
            case .message(let m):   return m
            case .kinded(let k, let m, let rk):
                return "[\(k)] \(m)" + (rk.isEmpty ? "" : " retry=\(rk)")
            case .timeout:          return "等太久了，再点一次"
            case .network:          return "NSURLError 网络不可达"
            }
        }
    }

    /// 输出模式。跟安卓 `Api.MODE_*` 一一对应（Kevin 规矩：两端一致）。
    enum Mode: String {
        case en    // 译成英文：清洗+结构化+译英（默认）
        case zh    // 结构化转写：清洗+结构化，中文，不翻译
        case raw   // 逐字转录：说什么写什么，**不过模型**
    }

    /// 目标语言 —— **从 `engine.py` 的 `LANGS` 生成**（`ios/Shared/Langs.g.swift`）。
    ///
    /// 🚨🚨 这里原来是**手抄的一份**，注释写着「跟 engine.py 的 LANGS、安卓的
    ///    `Gen.LANG_CODES` 一一对应」—— **注释是承诺，不是机制**。
    ///    2026-09-05 实测：`LANGS` 已经 31 门，安卓（`build_apk.py` 从 engine 生成）
    ///    和 PC（`gen_shared.py`）重建即跟，**只有 iOS 静默停在 9 门**，
    ///    是 Kevin 自己抓到的：「iOS 这边我看还是 23 门呢…怎么都还是漏了呢」。
    ///    **手抄的东西不会报错，只会一直是旧的。**
    ///
    /// 🚨 加语言只改 `engine.py` 的 `LANGS`，然后跑 `pc/gen_shared.py`。
    ///    **别在这里加**，也别把生成出来的那份改成手写。
    static let langs = GenLangs.langs

    /// **界面用的语言清单** —— 三个选择器都读它，不要直接读 `langs`。
    ///
    /// 🚨 存在的唯一理由是**坏样本注入**：`TRANSLESS_FAKE_LANGS=40`
    ///    把清单临时撑到 40 门，验"选择器能不能滚到最后一门"。
    ///    没有这个开关的话，这条判据要等语言表真的更长了才测得了 ——
    ///    **等真数据来了再测 = 缺陷先上线**。
    /// 🚨 注入的是**输入数据**，被测的选择器本身没被碰过。
    ///
    /// 🚨 这段 2026-09-05 被我自己删过一次：把手抄的语言表换成生成件时，
    ///    区间锚点取得太宽，**连隔壁这段一起吃掉了**，编译才报出来。
    ///    删整段要用**上下两个唯一锚点**，别用"从这里到那个函数"。
    static var langsForUI: [(code: String, label: String, name: String)] {
        guard let n = Int(ProcessInfo.processInfo
                            .environment["TRANSLESS_FAKE_LANGS"] ?? ""),
              n > langs.count else { return langs }
        var v = langs
        for i in langs.count..<n {
            v.append(("fake\(i)", "测试语言\(i)", "Test\(i)"))
        }
        return v
    }

    static func langName(_ code: String) -> String {
        langs.first { $0.code == code }?.name ?? "English"
    }

    static func langLabel(_ code: String) -> String {
        // 🚨 用 `langsForUI` 而不是 `langs`：注入的假语言也要能显示出名字，
        //    否则坏样本跑起来 40 门全叫「英文」，看着像通过其实什么都没验。
        langsForUI.first { $0.code == code }?.label ?? "英文"
    }

    static func polish(text: String, tone: String, mode: Mode = .en,
                       lang: String = "en",
                       done: @escaping (Result<String, Failure>) -> Void) {
        // 🚨🚨 **逐字档不再直接短路（2026-08-31 与安卓拉齐）。**
        //
        //    原来这里 `return done(.success(text))`，理由是"过一遍模型就有被润色的风险"。
        //    安卓 2026-08-23 已经废掉这个做法，因为 Kevin 当场撞到：
        //    「它就真的是逐字记录，**连逗号、句号这些标点符号都没有**」——
        //    ASR 本身不给标点，一大段不断句根本没法读。
        //
        //    改成：走一次极窄的提示词（`Secrets.promptPunct`，只许加标点），
        //    拿到结果后由 `isSubsequence()` 核对 —— 结果必须是原文的**子序列**
        //    （只删不改），对不上就丢掉模型结果、用回 ASR 原文。
        //    🚨 2026-09-03 判据从「完全相等」换成「子序列」：他改了口径，
        //       要求删掉口水话和重复字。旧判据会把删过口水话的结果判成"擅自改写"，
        //       **静默丢掉** —— 提示词改了也看不出变化。
        //    **「逐字」这个承诺由代码保证，不靠模型自觉**（跟安卓同一条思路）。
        //    ⚠️ 那道核对闸在 `submit` 的回调里（`rawOnly && !isSubsequence(...)`）。
        submit(text: text, tone: tone, mode: mode, lang: lang, attempt: 0, done: done)
    }

    /// 🚨 提交那一发也会 504（网关冷启动/抖动，2026-08-21 Kevin 真机撞到）。
    ///    5xx 和传输错误都自动重试，最多 4 发、间隔递增；401/429 是明确答复，不重试。
    private static func submit(text: String, tone: String, mode: Mode, lang: String,
                               attempt: Int, rid: String = newReqId(),
                               done rawDone: @escaping (Result<String, Failure>) -> Void) {
        // 🚨🚨🚨 **整理档的排版闸挂在这里 —— 这是唯一出口。**
        //
        //    2026-08-31 交叉审查抓到：同一条规矩我修了两次，两次都修在
        //    **没人走的路**上 ——
        //      第一次加进 `poll()`      → 它只在 `zhOnly == false` 时才被调，是死代码
        //      第二次加进 `pollVoice()` → 键盘出稿走 /api/audio + /api/llm，不经过它
        //      真实链路 `submit() → pollRaw()` 两次都没碰到
        //
        //    **同一个错三次，说明「往某条 poll 里加」这个做法本身是错的。**
        //    在 `submit` 把 `done` 包一层，`poll` / `pollRaw` / 以后任何新变体
        //    都必然经过这里。判据也跟着换：**不查 `renderPoints` 出现几次，
        //    查 zh 档下有没有一条 `done(.success)` 绕过了它。**
        let zhGate = (mode == .zh)
        let done: (Result<String, Failure>) -> Void = { r in
            guard zhGate, case .success(let t) = r else { return rawDone(r) }
            // 🚨 `text` 就是他这次说的话（送给模型的 ASR 原文）。
            //    整理档排不出来时退回它 —— 绝不把我们的提示语当正文交出去。
            // 🚨🚨 **把模型的原始返回留一条痕**（2026-09-04，2.1 要的分因判据）。
            //
            //    他报了两条：整理**不分点**、整理**吃字**。2.1 的假设是同一个根：
            //    模型这次回的是**自由重写的散文**而不是我们要的 JSON ——
            //    那同时解释「没结构可分点」和「重写时把『没事，有』一起改掉」。
            //
            // 🚨 **这条不确认，后面全是盲修。** 而现在这一层
            //    **一个字都没留** —— 原始返回进了 `renderPoints` 就再也看不见了，
            //    出问题时只能对着最终结果猜模型干了什么。
            //
            // 🚨 只记**形状和长度，不记正文**：正文是他说的话，
            //    痕迹是会被读出来的东西，不该把他的内容留在里面。
            let looksJSON = t.contains("\"items\"") || t.contains("\"lead\"")
            KbBridge.note("整理档·模型原始返回：" + (looksJSON ? "JSON" : "散文")
                          + "｜长度 " + String(t.count)
                          + "｜原话长度 " + String(text.count)
                          + (t.count < text.count / 2 ? "｜🚨 只剩不到一半" : ""))
            rawDone(.success(Prompts.renderPoints(t, fallback: text)))
        }
        func retryOrFail(_ f: Failure) {
            if attempt < 3 {
                DispatchQueue.global().asyncAfter(deadline: .now() + Double(attempt + 1) * 2) {
                    submit(text: text, tone: tone, mode: mode, lang: lang,
                           attempt: attempt + 1, rid: rid, done: done)
                }
            } else {
                done(.failure(f))
            }
        }
        let zhOnly = (mode == .zh)
        // 🚨🚨 **三档，不是两档**（2026-08-31 与安卓拉齐）。
        //    原来只有 `zhOnly ? promptZh : prompt` —— 逐字档当时被上面短路掉了，
        //    所以这里没有它。短路一去掉，逐字档就会拿**翻译**的提示词去跑，
        //    那比不加标点还糟。安卓 `Api.polish()` 是标准的三分支，照它来。
        let rawOnly = (mode == .raw)
        let system = rawOnly ? Secrets.promptPunct
                             : (zhOnly ? Secrets.promptZh : Secrets.prompt)
        // 🚨 "Target language:" 必须在最前面 —— 提示词按这个位置读。
        //    逐字档和整理档都没有"译成哪种语言"这回事，只送原文。
        let user = (zhOnly || rawOnly)
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
            return done(.failure(.message(FailureText.Local.assembleFailed)))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        // 🚨 幂等 id：同一次业务请求的所有重试共用一个，后端据它去重（见 `newReqId`）。
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        req.setValue(rid, forHTTPHeaderField: "X-Req-Id")
        req.httpBody = data

        URLSession.shared.dataTask(with: req) { d, resp, err in
            if let err = err {
                return retryOrFail(NetClassify.isNetwork(err)
                                   ? .network : .message(err.localizedDescription))
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { return done(.failure(.unauthorized)) }
            let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            if code == 429 {
                return done(.failure(.quota((obj?["error"] as? String) ?? "额度用完了")))
            }
            // 🚨🚨 **必须先看错误体，再考虑重试**（复审 高-1）。
            //    上一版我把 `failureFrom` 插在这一行**后面** ——
            //    而注释还写着「在 `code >= 500` 之前」，**说明和实物相反**。
            //    根因：我选的锚点是「每个出口都有的 `guard code == 200`」，
            //    它在这一行之后。**锚点相同 ≠ 上下文相同。**
            //    后果：四个出口里只有 `submit` 有这条 500 重试分支，
            //    **唯一需要这个修复的地方就是唯一没修上的地方**，
            //    带 error+kind 的 500 照样重发 4 次、kind 照样不可达。
            // 🚨🚨 中-1：**提交侧也要走 kind 判据，不能一律单次判死。**
            //    上一版为了修 高-1 把 `failureFrom` 提到 500 之前，
            //    结果**把「提交那一发的 5xx 自动重试」整条废掉了** ——
            //    而那条重试是 2026-08-21 Kevin 真机撞到网关冷启动之后加的
            //    （502/504 + `{"error":"upstream request timeout"}`，第 2 发就过）。
            //    M4 的论证恰恰是「没有 kind 就不能单次判死」，两边要一致。
            if handleSubmitBody(code: code, obj: obj,
                                retry: retryOrFail,
                                fail: { done(.failure($0)) }) { return }
            if code >= 500 { return retryOrFail(.http(code)) }
            // 🚨 提交 job 返回的是 **202 Accepted**，不是 200（2026-08-20 实测：
            //    `{"job": "..."}` 配 HTTP 202）。第一版写死 code == 200，
            //    真机上就直接报 "HTTP 202" 失败。
            //    而我的 Python 验证脚本压根没查状态码、直接读 j['job']，所以一路绿灯 ——
            //    典型的假检查：两边判据不一致时，宽松的那边先通过，严格的那边才炸。
            // 🚨🚨 **提交出口也必须先看错误体**（复审 H1）。
            //    H-A 的依据是「`_send` 把 502 改写成 500」——
            //    **这条依据在提交侧同样成立**，而这里原来一次都没看过：
            //    `obj` 解析出来了，只用来取 `job` 和 429 文案，
            //    `error`/`kind` 直接丢掉。
            //    后果不只是分类不可达 —— 带 error 的 500 会被当成
            //    **可重试**错误重发 4 次（≈12 秒），既违反
            //    「401/429 是明确答复，不重试」，也可能重复建 job。
            //    位置：在 401/429 之后、`code >= 500` 重试之前（见上面那处）。
            guard code == 200 || code == 202, let job = obj?["job"] as? String else {
                return done(.failure(.http(code)))
            }
            // 转写模式返回的是中文正文，没有 <<<OUT>>>/<<<ZH>>> 分段 —— 走 pollRaw
            if zhOnly { pollRaw(job: job, tries: 0, done: done) }
            else { poll(job: job, tries: 0, rawOnly: rawOnly, zhOnly: zhOnly,
                        original: text, done: done) }
        }.resume()
    }

    // MARK: - 云端整句（拼音 → 中文）

    /// 把一串**没有声调、没有分隔**的拼音交给模型还原成中文句子。
    ///
    /// 🚨🚨 Kevin 2026-09-04 拍板「①②一起做」之后才有这条。他的原话：
    ///    「不能够只有词库里的词…能不能直接搜互联网上有的呢？联想呢？」
    ///    —— "搜互联网"这条路不成立（没有公开服务吃拼音吐句子），
    ///    能做这件事的只有大模型，所以就是这条。
    ///
    /// 🚨 **代价必须写在这里，别让下一个人以为它免费**：
    ///    每调一次＝一次模型请求（**花他的钱**）＋一次网络往返（几百毫秒到两秒）。
    ///    所以调用方**绝不许每敲一个字母就调** —— 见 `TypingKeyboardView`
    ///    那边的停顿触发和同串去重。
    ///
    /// 🚨 **给不出就静默放弃**：这是"锦上添花的一条候选"，
    ///    不是主链路。任何失败都不许弹错误、不许阻塞打字。
    ///
    /// 🚨 轮询上限压到 12 次（约 3 秒）：候选栏等不了 90 次那么久，
    ///    等太久他早就自己选完了，回来再插一条反而打断他。

    // MARK: - 查词（Kevin 2026-09-05）

    /// **查一个词。**
    ///
    /// 🚨🚨 **提示词单独一份，不许复用 `SYSTEM_PROMPT`**（2.1 规格硬约束）。
    ///    翻译回答的是「这句话怎么说」，查词回答的是「这个词是什么意思、怎么用」。
    ///    复用的话会拿到"把这个词翻译一遍" —— **那正是他说的"现在只有翻译"**。
    ///    判据：输入「报价」要出 `quote / quotation` 那一组，不是整句翻译。
    ///
    /// 🚨 **判语种复用 `Reverse.isMine`**，不许再抄第三份
    ///    （`MyLang.classify` 那一套已经有了）。
    ///
    /// 🚨 **缓存命中时一次网络都不打**（判据 6）——
    ///    判据是"没有网络请求"，不是"感觉快了点"，所以这里直接在进函数就返回。
    static func lookup(_ raw: String,
                       done: @escaping (Result<DictEntry, Failure>) -> Void) {
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else {
            return done(.failure(.kinded("empty", "", "")))
        }
        if let hit = DictStore.cached(word) {
            KbBridge.note("查词命中缓存，不打后端：" + word)
            return done(.success(hit))
        }

        let mine = Reverse.isMine(word)      // true = 中文输入
        let sys = mine ? dictSysZhToEn : dictSysEnToZh
        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": sys],
                ["role": "user", "content": word],
            ],
            "temperature": 0.2,
            // 🚨 3 条义项 + 例句 + 搭配，够用；token 是钱。
            "max_tokens": 420,
        ]
        guard let url = URL(string: base + "/api/llm"),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            return done(.failure(.kinded("badreq", "", "")))
        }
        // 🚨 **可数的痕迹**：判据 6 要的是"第二次没有网络请求"，
        //    而"感觉快了点"不是判据。每真发一次就 +1，用例比前后计数。
        //    记在**发请求这一处**（唯一出口），不记在调用方 —— 调用方有好几个。
        DictStore.bumpNetCount()
        KbBridge.note("查词打后端：" + word)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        req.setValue(newReqId(), forHTTPHeaderField: "X-Req-Id")
        req.httpBody = data
        URLSession.shared.dataTask(with: req) { d, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            guard code == 200 || code == 202, let job = obj?["job"] as? String else {
                return done(.failure(.kinded("http", String(code), "")))
            }
            pollRaw(job: job, tries: 60) { r in
                switch r {
                case .success(let t):
                    guard let e = parseDict(word: word, raw: t) else {
                        return done(.failure(.kinded("parse", "", t)))
                    }
                    // 🚨 **截断走模型层那个唯一出口**（`trimmed()`），
                    //    不在渲染层砍 —— 渲染层砍的话缓存里存的还是十条，
                    //    换个入口渲染就漏（判据：查 take 仍然只出 3 条）。
                    let cut = e.trimmed()
                    DictStore.put(cut)
                    done(.success(cut))
                case .failure(let f):
                    done(.failure(f))
                }
            }
        }.resume()
    }

    /// 英文词 → 中文释义。**英文释义在上、中文在下**（2.1：英文教用法、中文确认理解）。
    private static let dictSysEnToZh =
        "你是一本给中文母语者用的英语学习词典。用户给你一个英文单词或短语，"
        + "你输出严格的 JSON，不要任何解释文字、不要代码块标记。字段："
        + "word(原词) phonetic(国际音标，不带斜杠) pos(词性缩写，如 adj.) "
        + "senses(数组，**最多 3 条**，按使用频率从高到低；每条 {en, zh, register}，"
        + "en 是英文释义、zh 是中文对译、register 是 formal/informal 之类的用法标注，没有就空串) "
        + "example_en example_zh(一个例句及其中文) "
        + "collocations(数组，最多 3 个常见搭配)。"
        + "🚨 只给最常用的 3 条义项；生僻义不要列。"

    /// 中文 → 英文说法。**不是整句翻译**（判据 7 打的就是这个）。
    private static let dictSysZhToEn =
        "用户给你一个中文词，你要告诉他英文里**对应的说法有哪些**，"
        + "而不是把它当句子翻译。输出严格的 JSON，不要解释、不要代码块标记。字段："
        + "word(最常用的那个英文说法) phonetic(音标，不带斜杠) pos(词性缩写) "
        + "senses(数组，最多 3 条，每条 {en, zh, register}："
        + "en 写这个英文说法及其用法差别、zh 写中文说明) "
        + "example_en example_zh collocations(最多 3 个)。"

    /// 解析。**容忍模型多包一层代码块**，但不做别的加工。
    static func parseDict(word: String, raw: String) -> DictEntry? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a = t.firstIndex(of: "{"), let b = t.lastIndex(of: "}") {
            t = String(t[a...b])
        }
        guard let d = t.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        else { return nil }
        let ss = (o["senses"] as? [[String: Any]] ?? []).map {
            DictSense(en: ($0["en"] as? String) ?? "",
                      zh: ($0["zh"] as? String) ?? "",
                      register: ($0["register"] as? String) ?? "")
        }
        guard !ss.isEmpty else { return nil }
        return DictEntry(word: (o["word"] as? String) ?? word,
                         phonetic: (o["phonetic"] as? String) ?? "",
                         pos: (o["pos"] as? String) ?? "",
                         senses: ss,
                         exampleEn: (o["example_en"] as? String) ?? "",
                         exampleZh: (o["example_zh"] as? String) ?? "",
                         collocations: (o["collocations"] as? [String]) ?? [])
    }

    static func pinyinGuess(_ py: String,
                            done: @escaping (String) -> Void) {
        let sys = "你是中文拼音输入法的解码器。用户给你一串没有声调、没有分隔的拼音，"
            + "你只输出**最可能的那一句中文**。"
            + "规则：①只输出中文句子本身，不要解释、不要标点以外的任何符号、不要引号；"
            + "②不确定就输出你认为最通顺的一种；"
            + "③如果这串拼音明显不是一句话，输出空。"
        let body: [String: Any] = [
            "messages": [
                ["role": "system", "content": sys],
                ["role": "user", "content": py],
            ],
            "temperature": 0.2,
            // 🚨 上限压到 64：一句话足够了，而 token 是钱。
            "max_tokens": 64,
        ]
        guard let url = URL(string: base + "/api/llm"),
              let data = try? JSONSerialization.data(withJSONObject: body) else {
            return done("")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        req.setValue(newReqId(), forHTTPHeaderField: "X-Req-Id")
        req.httpBody = data
        URLSession.shared.dataTask(with: req) { d, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            guard code == 200 || code == 202, let job = obj?["job"] as? String else {
                return done("")
            }
            pollRaw(job: job, tries: 78) { r in       // 78 → 只剩 12 次预算
                switch r {
                case .success(let t):
                    // 🚨 模型偶尔会带引号或多余空白，清掉；**不做别的加工**
                    //    （改字就是另一回事了，那不是我该替他做的决定）。
                    // 🚨 引号用 `union` 加进去，**不写成一个含转义的字面量** ——
                    //    生成这段代码时反斜杠被吃掉过一次，Swift 串里塞进了真的换行，
                    //    编译当场报 unterminated string。这类"生成代码时被转义坑"
                    //    的地方，一律改成不依赖转义的写法。
                    let quotes = CharacterSet(charactersIn: "\"" + "\u{27}\u{201C}\u{201D}\u{300C}\u{300D}")
                    let clean = t.trimmingCharacters(
                        in: CharacterSet.whitespacesAndNewlines.union(quotes))
                    done(clean)
                case .failure:
                    done("")
                }
            }
        }.resume()
    }

    /// - Parameters:
    ///   - rawOnly / zhOnly: 档位。🚨 **必须传进来** —— 结果怎么处理三档完全不同，
    ///     而 `poll` 是独立函数、看不见外面的 `mode`。
    ///   - original: ASR 原文。逐字档的硬闸要拿它跟模型结果**逐字符核对**。
    private static func poll(job: String, tries: Int,
                             rawOnly: Bool = false, zhOnly: Bool = false,
                             original: String = "",
                             st: PollState = PollState(),
                             done: @escaping (Result<String, Failure>) -> Void) {
        if tries > 90 { return done(.failure(.timeout)) }
        guard let url = URL(string: base + "/api/job?id=" + job) else {
            return done(.failure(.message(FailureText.Local.badJobURL)))
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.7) {
            URLSession.shared.dataTask(with: req) { d, resp, err in
                // 🚨 低-1：**看一眼状态码**。原来这三处把 `resp` 直接丢掉，
                //    只有 `pollVoice` 看 —— 又一次「同一条规则四个实现、
                //    三个跟另一个不一样」。
                //    后果：轮询期间口令失效（换设备/后端轮换 pass）→
                //    401 + 非 JSON 体 → 走「抖动」分支磨满 90 轮 →
                //    报「等太久了」，他再点一次还是 401。
                if (resp as? HTTPURLResponse)?.statusCode == 401 {
                    return done(.failure(.unauthorized))
                }
                // 🚨 M3：**接住 `err`**。原来是 `{ d, _, _ in }`，断网时 `obj` 为 nil，
                //    被当成抖动一直重试，磨满轮询变成「等太久了」——
                //    `err_network` 在轮询链上**根本不可达**。
                //    但**一次网络错不下结论**（可能只是抖了一下），
                //    连着两次才终结。
                if let e = err {
                    if NetClassify.isNetwork(e), st.noteNetwork() {
                        return done(.failure(.network))
                    }
                    return poll(job: job, tries: tries + 1, rawOnly: rawOnly, zhOnly: zhOnly,
                     original: original, st: st, done: done)
                }
                st.noteTransportOK()
                let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
                // 网络抖一下就再问一次，别直接判失败
                guard let obj = obj else {
                    // 🚨🚨 复审 中-1：**这条分支原来绕过了 `noteCleanBody()`**。
                    //    非 JSON 的响应（网关错误页、空体）也是一次
                    //    「体里没有 error」，错误的连续性该在这里被打断。
                    //    不清的话：错A → 非JSON → 错A 会被判成「连着两次」，
                    //    **把一个还在跑的 job 当场判死**。
                    //    `pollVoice` 走可选链、天然会清 —— 
                    //    **同一条规则四个实现，三个跟另一个不一样。**
                    st.noteCleanBody()
                    return poll(job: job, tries: tries + 1, rawOnly: rawOnly, zhOnly: zhOnly,
                     original: original, st: st, done: done)
                }
                // 🚨🚨 **失败判断必须在 `done` 之前** —— 真实错误体
                //    `{"error":…, "kind":…}` **根本没有 `done` 字段**
                //    （实读 `server_api.py:783-787`）。
                //    上一版把它放在 `done == true` 后面 → **整套 kind 分类不可达**，
                //    所有 job 级失败都磨满轮询变成「等太久了」。
                //    **我当时验的是代码结构，不是真实响应的形状。**
                // 🚨🚨 M4：**「体里有 error」不等于「这个 job 死了」。**
                //    `/api/job` 上的 error 有两个作者：job 自己（必带 `kind`）
                //    和**网关**（`_send`/`_GATEWAY_EATS`），两者形状一样。
                //    有 kind → 一次就终结；没 kind → 同一条错连出两次才终结。
                if let r = JobErrorParse.parse(obj), let f = failureFrom(obj) {
                    if JobErrorParse.isTerminal(kind: r.kind, message: r.message,
                                                previous: st.prevError) {
                        return done(.failure(f))
                    }
                    st.prevError = r.message
                    return poll(job: job, tries: tries + 1, rawOnly: rawOnly, zhOnly: zhOnly,
                     original: original, st: st, done: done)
                }
                // 🚨 高-1：**只有「体里没有 error」才打断错误的连续性**。
                //    放到上面去（拿到任何响应就清）会让「连着两次才终结」永不可达
                //    —— 那正是上一版的做法：错误体本身就是一次正常 HTTP 响应。
                st.noteCleanBody()

                if obj["done"] as? Bool == true {
                    let raw = (obj["text"] as? String) ?? ""
                    // 🚨 KPI ①：后端回的 `words` 是**中性词数**（这段有几个英文词），
                    //    它分不出「说英文走逐字档」——那种 words>0 **是转写不是翻译**。
                    //    只有客户端知道按的哪一档，所以**只有翻译档才累加**
                    //    （规格 `_后端_词数字段_客户端规格.md` §2：宁可少算，不许多算）。
                    //    🚨 客户端**绝不自己数词**（三端各数一套会给出三个不同总数）。
                    // 🚨 走 `addFromBody`：它自带"失败体不计"的守卫（见那边说明）。
                    if !zhOnly && !rawOnly { KpiWords.addFromBody(obj) }
                    // 🚨🚨 **三档三种处理，照安卓 `Api.polish()`（2026-08-31 拉齐）。**
                    //    原来无条件跑 `postprocess(splitEn(raw))` —— 那是翻译档的处理：
                    //    `splitEn` 找 `<<<OUT>>>` 分段（逐字/整理档根本没有这些标记），
                    //    `postprocess` 还会替换破折号等字符 —— **在逐字档里那就是改字**，
                    //    而逐字档的全部承诺就是"一个字都不动"。
                    var en = (zhOnly || rawOnly)
                        ? raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        : Prompts.postprocess(Prompts.splitEn(raw))
                    if en.isEmpty { return done(.failure(.message(FailureText.Local.emptyResult))) }
                    // 🚨 逐字档硬闸：去掉标点空白后必须跟 ASR 原文**一模一样**。
                    //    模型偷偷删口水词、改措辞、自作主张翻译，全部拦下用回原文 ——
                    //    宁可没标点，也不能破坏"逐字"这个承诺。
                    if rawOnly, !original.isEmpty, !isSubsequence(original, en) { en = original }
                    // 🚨 整理档硬闸：多条事实必须编号，不许挤成一段散文。
                    // 🚨 这里原来有一句 `if zhOnly { renderPoints }` —— **是死代码**
            //    （`poll` 只在 `zhOnly == false` 时被调）。已上移到 `submit` 的
            //    单一出口。留着它会让下一个人以为整理档已经被覆盖了。
                    return done(.success(en))
                }
                poll(job: job, tries: tries + 1, rawOnly: rawOnly, zhOnly: zhOnly,
                     original: original, st: st, done: done)
            }.resume()
        }
    }

    // MARK: - 朗读（Andrew 的声音，跟 Alex 陪练同一个）

    /// 把文字合成语音，返回 mp3 数据。
    /// 🚨 Kevin 2026-08-21：翻译完要能点一下听出来。跟安卓 `Api.speak` 同一个端点。
    static func speak(text: String, attempt: Int = 0, rid: String = newReqId(),
                      done: @escaping (Result<Data, Failure>) -> Void) {
        // 🚨 复审 中-2：**这三个端点原来没有重试通道**，而
        //    `handleSubmitBody` 的文档白纸黑字说「对四个端点同样成立」
        //    —— 抽了共享判据，点名的症状一次都没修。**不骑墙，真接上。**
        //    代价对比：voice/audio 失败＝**他刚说的那段话没了**，
        //    tts 失败＝「读不出来」。重试只在「无 kind 的 5xx」上发生。
        func retryOrFail(_ f: Failure) {
            if attempt < 3 {
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + Double(attempt + 1) * 2) {
                    speak(text: text, attempt: attempt + 1, rid: rid, done: done)
                }
            } else {
                done(.failure(f))
            }
        }
        guard let url = URL(string: base + "/api/tts") else {
            return done(.failure(.message(FailureText.Local.badURL)))
        }
        // voice 用短名，真正的 voice 名字由后端映射 —— 前端不硬编
        let body: [String: Any] = ["text": text, "voice": "andrew"]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            return done(.failure(.message(FailureText.Local.assembleFailed)))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        // 🚨 幂等 id：同一次业务请求的所有重试共用一个，后端据它去重（见 `newReqId`）。
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        req.setValue(rid, forHTTPHeaderField: "X-Req-Id")
        req.httpBody = data

        URLSession.shared.dataTask(with: req) { d, resp, err in
            if let err = err {
                // 🚨 中-1：**这一处故意不重试**（跟 `voice`/`transcribe` 不同）。
                //    朗读失败的代价是「读不出来，文字还在」——译文没丢，
                //    不值得为它多发一次付费请求。**说实话，别写"跟 submit 一样"。**
                return done(.failure(NetClassify.isNetwork(err)
                                     ? .network : .message(err.localizedDescription)))
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { return done(.failure(.unauthorized)) }
            let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            // 🚨🚨 **这里原来没有 429 分支**（复审 中-3），而抄过来的注释
            //    还写着「位置：在 401/429 之后」—— **描述了一个不存在的分支**。
            //    后果：`/api/tts` 额度用完 → `.message` → `ttsText` 落 default
            //    → 「读不出来，文字还在」，**正是 `ttsText` 注释说不许发生的那件事**
            //    （额度这种他必须知道，因为下一次翻译也会失败）。
            if code == 429 {
                return done(.failure(.quota((obj?["error"] as? String) ?? "额度用完了")))
            }
            // 提交出口必须先看错误体（复审 H1）：`_send` 会把 502 改写成 500，
            // 带 error 的 500 不能当可重试错误。
            // 跟 `submit` 用**同一份判据**（`handleSubmitBody`），
            // 现在也跟它一样有重试通道（复审 中-2）。
            if handleSubmitBody(code: code, obj: obj,
                                retry: retryOrFail,
                                fail: { done(.failure($0)) }) { return }
            // 🚨 复审 中-1：**这一条原来只有 `submit` 有**，而这三处的注释
            //    却写着「跟 submit 一样」。缺它的后果：网关冷启动回一个
            //    **HTML 错误页**配 502/504 → `obj` 为 nil → `handleSubmitBody`
            //    返回 false → 一次判死，**他刚说的那段话没了**。
            //    （正是 2026-08-21 加这条重试要救的那类场景的另一半形态。）
            if code >= 500 { return retryOrFail(.http(code)) }
            guard code == 200 || code == 202, let job = obj?["job"] as? String else {
                return done(.failure(.http(code)))
            }
            pollAudio(job: job, tries: 0, done: done)
        }.resume()
    }

    private static func pollAudio(job: String, tries: Int,
                             st: PollState = PollState(),
                             done: @escaping (Result<Data, Failure>) -> Void) {
        if tries > 60 { return done(.failure(.timeout)) }
        guard let url = URL(string: base + "/api/job?id=" + job) else {
            return done(.failure(.message(FailureText.Local.badJobURL)))
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
            URLSession.shared.dataTask(with: req) { d, resp, err in
                // 🚨 低-1：**看一眼状态码**。原来这三处把 `resp` 直接丢掉，
                //    只有 `pollVoice` 看 —— 又一次「同一条规则四个实现、
                //    三个跟另一个不一样」。
                //    后果：轮询期间口令失效（换设备/后端轮换 pass）→
                //    401 + 非 JSON 体 → 走「抖动」分支磨满 90 轮 →
                //    报「等太久了」，他再点一次还是 401。
                if (resp as? HTTPURLResponse)?.statusCode == 401 {
                    return done(.failure(.unauthorized))
                }
                // 🚨 M3：**接住 `err`**。原来是 `{ d, _, _ in }`，断网时 `obj` 为 nil，
                //    被当成抖动一直重试，磨满轮询变成「等太久了」——
                //    `err_network` 在轮询链上**根本不可达**。
                //    但**一次网络错不下结论**（可能只是抖了一下），
                //    连着两次才终结。
                if let e = err {
                    if NetClassify.isNetwork(e), st.noteNetwork() {
                        return done(.failure(.network))
                    }
                    return pollAudio(job: job, tries: tries + 1, st: st, done: done)
                }
                st.noteTransportOK()
                let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
                guard let obj = obj else {
                    // 🚨🚨 复审 中-1：**这条分支原来绕过了 `noteCleanBody()`**。
                    //    非 JSON 的响应（网关错误页、空体）也是一次
                    //    「体里没有 error」，错误的连续性该在这里被打断。
                    //    不清的话：错A → 非JSON → 错A 会被判成「连着两次」，
                    //    **把一个还在跑的 job 当场判死**。
                    //    `pollVoice` 走可选链、天然会清 —— 
                    //    **同一条规则四个实现，三个跟另一个不一样。**
                    st.noteCleanBody()
                    return pollAudio(job: job, tries: tries + 1, st: st, done: done)
                }
                // 🚨🚨 **失败判断必须在 `done` 之前** —— 真实错误体
                //    `{"error":…, "kind":…}` **根本没有 `done` 字段**
                //    （实读 `server_api.py:783-787`）。
                //    上一版把它放在 `done == true` 后面 → **整套 kind 分类不可达**，
                //    所有 job 级失败都磨满轮询变成「等太久了」。
                //    **我当时验的是代码结构，不是真实响应的形状。**
                // 🚨🚨 M4：**「体里有 error」不等于「这个 job 死了」。**
                //    `/api/job` 上的 error 有两个作者：job 自己（必带 `kind`）
                //    和**网关**（`_send`/`_GATEWAY_EATS`），两者形状一样。
                //    有 kind → 一次就终结；没 kind → 同一条错连出两次才终结。
                if let r = JobErrorParse.parse(obj), let f = failureFrom(obj) {
                    if JobErrorParse.isTerminal(kind: r.kind, message: r.message,
                                                previous: st.prevError) {
                        return done(.failure(f))
                    }
                    st.prevError = r.message
                    return pollAudio(job: job, tries: tries + 1, st: st, done: done)
                }
                // 🚨 高-1：**只有「体里没有 error」才打断错误的连续性**。
                //    放到上面去（拿到任何响应就清）会让「连着两次才终结」永不可达
                //    —— 那正是上一版的做法：错误体本身就是一次正常 HTTP 响应。
                st.noteCleanBody()

                if obj["done"] as? Bool == true {
                    guard let b64 = obj["audio"] as? String,
                          let mp3 = Data(base64Encoded: b64), !mp3.isEmpty else {
                        return done(.failure(.message(FailureText.Local.noAudio)))
                    }
                    return done(.success(mp3))
                }
                pollAudio(job: job, tries: tries + 1, st: st, done: done)
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
                      attempt: Int = 0, rid: String = newReqId(),
                      done: @escaping (Result<(out: String, zh: String,
                                               dir: String), Failure>) -> Void) {
        // 🚨 复审 中-2：**这三个端点原来没有重试通道**，而
        //    `handleSubmitBody` 的文档白纸黑字说「对四个端点同样成立」
        //    —— 抽了共享判据，点名的症状一次都没修。**不骑墙，真接上。**
        //    代价对比：voice/audio 失败＝**他刚说的那段话没了**，
        //    tts 失败＝「读不出来」。重试只在「无 kind 的 5xx」上发生。
        // 🚨 重试上限统一 3 次。**幂等 id 已接上**（`X-Req-Id`），
        //    所以重试不再等于重复计费 —— 但**跨实例那半没解决**，
        //    见 `newReqId` 的注释，别把它读成"已解决"。
func retryOrFail(_ f: Failure) {
            // 🚨🚨 中-3：**这一处上限是 2，不是 3。**
            //    后端 `_REQ_SEEN` 的去重窗是 **120 秒（以首发到达计）**，
            //    而 `voice` 的 `timeoutInterval` 是 60 秒 ——
            //    走满 3 次重试的到达时刻是 0 / 62 / **126** / **192**，
            //    第 3、4 发**出窗**，rid 幂等对它们失效
            //    → 同一句最多仍被计 **3 次**费，而 voice 是最贵的那个端点。
            //    （llm/audio/tts 的 timeout 是 30 秒，0/32/66/102 全在窗内。）
            //    判据不是「我发了这个头」——要**两发相同 id、间隔调到 130 秒**，
            //    看 `quota_used` 有没有 +2。
            // 🚨 复审 中-2：**`< 2` 仍然是三发**（attempt 从 0 起，
            //    0 和 1 都会重试）→ 到达 0 / 62 / **126**，第 3 发出 120 秒窗。
            //    **判据是「到达时刻」，不是「上限数字」** —— 我按数字想了。
            //    `< 1` = 两发（0 / 62），稳在窗内。
            if attempt < 1 {
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + Double(attempt + 1) * 2) {
                    voice(wav: wav, tone: tone, mode: mode, lang: lang,
                          uiLang: uiLang, mineTarget: mineTarget,
                          theirsTarget: theirsTarget, attempt: attempt + 1,
                          rid: rid, done: done)
                }
            } else {
                done(.failure(f))
            }
        }
        guard let url = URL(string: base + "/api/voice") else {
            return done(.failure(.message(FailureText.Local.badURL)))
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
            // 🚨🚨 **三档，不是两档。** 2026-08-31 我在 `submit()` 那条路上改成了三档，
            //    **却漏了这一条 —— 而键盘走的正是这一条**。于是逐字档拿着
            //    翻译档的提示词去跑。「同一规矩两个出口只落地一个」，
            //    昨晚刚写进教训，今天原样重演。
            "sys": rawOnly ? Secrets.promptPunct
                           : (zhOnly ? Secrets.promptZh : Secrets.prompt),
            "user": user,
        ]
        // 🚨 2026-09-03 常用词接线（2.1 递的规格 + 后端契约）。
        //    键名必须是 **`vocab`**、值是**纯文本数组** ——
        //    PC 端一直发的 `asr_terms` 是错的，等于词表从来没生效过。
        //    只带 kind != "style" 的词（那类只管说得像，不管听得准），
        //    🚨 style 那类词不进 vocab —— 那条过滤的**唯一实现**在
        //       `VocabCore.wordsFor(_:asr:)`；`KbBridge.asrVocab()` 只是转调它。
        //    空数组就整个不带这个字段，别发 "vocab": []。
        let vocab1 = KbBridge.asrVocab()
        if !vocab1.isEmpty {
            body["vocab"] = vocab1
            KbBridge.note("识别带上常用词 " + String(vocab1.count) + " 个（/api/voice）")
        }
        if autoDir {
            body["ui_lang"] = uiLang
            body["mine_target"] = mineTarget
            body["theirs_target"] = theirsTarget
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            return done(.failure(.message(FailureText.Local.assembleFailed)))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        // 🚨 幂等 id：同一次业务请求的所有重试共用一个，后端据它去重（见 `newReqId`）。
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        req.setValue(rid, forHTTPHeaderField: "X-Req-Id")
        req.httpBody = data
        URLSession.shared.dataTask(with: req) { d, resp, err in
            if let err = err {
                // 🚨 中-1：传输错误也重试（跟 `submit` 一致）——
                //    这两个端点失败＝**他刚说的那段话没了**，值得补一发。
                return retryOrFail(NetClassify.isNetwork(err)
                                   ? .network : .message(err.localizedDescription))
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { return done(.failure(.unauthorized)) }
            let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            if code == 429 {
                return done(.failure(.quota((obj?["error"] as? String) ?? "额度用完了")))
            }
            // 🚨🚨 **提交出口也必须先看错误体**（复审 H1）。
            //    H-A 的依据是「`_send` 把 502 改写成 500」——
            //    **这条依据在提交侧同样成立**，而这里原来一次都没看过：
            //    `obj` 解析出来了，只用来取 `job` 和 429 文案，
            //    `error`/`kind` 直接丢掉。
            //    后果不只是分类不可达 —— 带 error 的 500 会被当成
            //    **可重试**错误重发 4 次（≈12 秒），既违反
            //    「401/429 是明确答复，不重试」，也可能重复建 job。
            //    位置：在 401/429 之后、`code >= 500` 重试之前。
            // 跟 `submit` 用**同一份判据**（`handleSubmitBody`），
            // 现在也跟它一样有重试通道（复审 中-2）。
            if handleSubmitBody(code: code, obj: obj,
                                retry: retryOrFail,
                                fail: { done(.failure($0)) }) { return }
            // 🚨 复审 中-1：**这一条原来只有 `submit` 有**，而这三处的注释
            //    却写着「跟 submit 一样」。缺它的后果：网关冷启动回一个
            //    **HTML 错误页**配 502/504 → `obj` 为 nil → `handleSubmitBody`
            //    返回 false → 一次判死，**他刚说的那段话没了**。
            //    （正是 2026-08-21 加这条重试要救的那类场景的另一半形态。）
            if code >= 500 { return retryOrFail(.http(code)) }
            guard code == 200 || code == 202, let job = obj?["job"] as? String else {
                return done(.failure(.http(code)))
            }
            pollVoice(job: job, tries: 0, zhOnly: zhOnly, rawOnly: rawOnly, done: done)
        }.resume()
    }

    private static func pollVoice(
        job: String, tries: Int, zhOnly: Bool, rawOnly: Bool,
        st: PollState = PollState(),
        done: @escaping (Result<(out: String, zh: String, dir: String), Failure>) -> Void) {
        if tries > 90 { return done(.failure(.timeout)) }
        guard let url = URL(string: base + "/api/job?id=" + job) else {
            return done(.failure(.message(FailureText.Local.badJobURL)))
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        URLSession.shared.dataTask(with: req) { d, resp, err in
            // 🚨 M3：接住 err，连着两次网络错才终结（这一处形状跟另外三个不一样，
            //    "按形状找"时又差点漏掉 —— 跟 H2 当初漏它是同一个原因）。
            if let e = err {
                if NetClassify.isNetwork(e), st.noteNetwork() {
                    return done(.failure(.network))
                }
                // 🚨 中-1：**必须退避**。另外三个轮询把 `asyncAfter` 包在
                //    函数体最外层，递归自带延迟；`pollVoice` 的延迟只包在
                //    not-done 那一支里 —— 我新加的这条重试是**零间隔**的，
                //    最坏 91 次请求在几百毫秒内打出去。
                return DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    pollVoice(job: job, tries: tries + 1, zhOnly: zhOnly,
                              rawOnly: rawOnly, st: st, done: done)
                }
            }
            st.noteTransportOK()
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { return done(.failure(.unauthorized)) }
            let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            // 🚨 这一处形状跟另外三处不一样，"按形状找"时曾被漏掉。
            // 🚨🚨 **不许再挂 `code == 502` 这个前提** ——
            //    后端 `_send` 会把网关会吃掉的码（502…）**改写成 500**
            //    并塞一个 `intended_status`（`_GATEWAY_EATS`），
            //    所以 `code == 502` **永远不成立**。
            //    判据挂在**响应体里有没有 error**，不挂状态码。
            // 🚨🚨 M4：有 kind → 一次终结；没 kind → 同一条错连出两次才终结。
            //    网关的错误信封跟 job 自己的错形状一样，单次判死会掐掉还在跑的 job。
            if let r = JobErrorParse.parse(obj), let f = failureFrom(obj) {
                if JobErrorParse.isTerminal(kind: r.kind, message: r.message,
                                            previous: st.prevError) {
                    return done(.failure(f))
                }
                st.prevError = r.message
                // 🚨 中-1：同上，这条也要退避。
                return DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    pollVoice(job: job, tries: tries + 1, zhOnly: zhOnly,
                              rawOnly: rawOnly, st: st, done: done)
                }
            }
            // 🚨 高-1：**只有「体里没有 error」才打断错误的连续性**。
            //    放到上面去（拿到任何响应就清）会让「连着两次才终结」永不可达
            //    —— 那正是上一版的做法：错误体本身就是一次正常 HTTP 响应。
            st.noteCleanBody()
            if (obj?["done"] as? Bool) != true {
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    pollVoice(job: job, tries: tries + 1, zhOnly: zhOnly,
                              rawOnly: rawOnly, st: st, done: done)
                }
                return
            }
            let raw = (obj?["text"] as? String) ?? ""
            let zh = (obj?["zh"] as? String) ?? ""
            // 🚨 KPI ①：同上 —— 只有翻译档累加，逐字档 words>0 也不算（那是转写）。
            // 🚨 同上，走带守卫的那个出口，别在这里另写一个 if。
            if !zhOnly && !rawOnly { KpiWords.addFromBody(obj) }
            let dir = (obj?["dir"] as? String) ?? ""
            var out = (zhOnly || rawOnly)
                ? raw.trimmingCharacters(in: .whitespacesAndNewlines)
                : Prompts.postprocess(Prompts.splitEn(raw))
            if out.isEmpty { return done(.failure(.message(FailureText.Local.emptyResult))) }
            // 🚨 逐字档的硬闸，跟安卓同一条判据：去掉标点空白后必须跟 ASR 原文
            //    一模一样，否则丢掉模型结果、用原文。
            if rawOnly && !zh.isEmpty && !isSubsequence(zh, out) {
                out = zh.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            // 🚨🚨 **整理档的排版硬闸也必须落在这一条路上。**
            //    Kevin 2026-08-31：「产出的文字里还残留很多代码（lead、null、items）」
            //    —— 那就是 `TRANSCRIBE_PROMPT` 让模型吐的 JSON **原样上屏了**。
            //    我昨晚把 `renderPoints` 加进了 `poll()`（/api/llm 那条），
            //    **而键盘走的是这条 /api/voice**，一个字都没加。
            //    「同一规矩两个出口只落地一个」——而我那道闸只查"函数有没有出现在文件里"，
            //    出现了一次就绿了。**查存在 ≠ 查覆盖。**
            // 🚨 排版闸已统一到 `submit` 的单一出口，这里不再重复施加
            //    （`pollVoice` 走的是 /api/voice，宿主出稿不经过它；
            //     真要经过时也由那一层负责，**同一规矩不许有第二份实现**）。
            done(.success((out: out, zh: zh.isEmpty ? out : zh, dir: dir)))
        }.resume()
    }

    /// 逐字档的**结果核对闸**。判据 2026-09-03 换过一次，两版都记在这里。
    ///
    /// **旧判据**：去掉标点空白后，结果跟 ASR 原文**完全相等**。
    /// **新判据**：结果必须是原文的**子序列**（只删不改）＋ 留下的字 ≥ 一半。
    ///
    /// 🚨 为什么换：Kevin 改了口径 ——
    ///    「逐字档**不要完全逐字，把口水话和重复的字过滤掉**……
    ///     不去揣摩他的意思，也不做过度整理」。
    ///    旧判据下，模型删掉「那个」「呃」之后就跟原文对不上 →
    ///    被判「擅自改写」→ **丢掉模型结果用回原文** →
    ///    他看到的还是带口水话那份，而且**没有任何东西会报错**。
    ///
    /// 🚨 **这道闸没有被削弱，承诺没变**：「一个字都不替他编」仍然成立 ——
    ///    子序列意味着**只能删，不能改、不能加、不能调序**。
    ///    改写（我们开会→我们开工）、编造（加"明天"）、调序（开会我们）全判不过。
    /// 🚨 下限「留下 ≥ 一半」挡的是**删过头**（13 个字只剩 4 个）。
    ///
    /// 判据 12 条在 `voice_ime/verbatim_gate_cases.json`，**三端跑出来必须一模一样**。
    private static func isSubsequence(_ src: String, _ out: String) -> Bool {
        func norm(_ s: String) -> [Character] {
            Array(String(s.unicodeScalars.filter {
                !CharacterSet.whitespacesAndNewlines.contains($0)
                    && !CharacterSet.punctuationCharacters.contains($0)
                    && !CharacterSet.symbols.contains($0)
            }))
        }
        let a = norm(src)
        let b = norm(out)
        // 🚨 原文是空的：没什么可判的，**别在这里报错**（判据第 10 条）。
        if a.isEmpty { return true }
        // 输出空 = 判不过（第 9 条）。
        if b.isEmpty { return false }
        // 删过头：留下的字少于一半。
        if b.count * 2 < a.count { return false }
        // 🚨🚨 否定守卫（判据第 ③ 条，2026-09-04 加）：**出稿的否定词数不能比原文少**。
        //    「只删不改」有个致命漏洞 —— 删掉一个『不』就是合法子序列，但意思整个反了
        //    （「我明天不去开会」→「我明天去开会」）。删否定词回退到原话（安全方向）。
        //    英文用**原始串**数（要词边界 + n't 缩写），不能用去标点后的 `norm`。
        if negCount(out) < negCount(src) { return false }
        var i = 0
        for ch in a where i < b.count && b[i] == ch { i += 1 }
        return i == b.count
    }

    /// 数否定词：中文『不没别未勿无』逐字，英文按词边界数
    /// not/never/no/nor/none/cannot/without + 缩写 `n't`。防『不去→去』语义反转。
    private static func negCount(_ s: String) -> Int {
        var n = 0
        for ch in s where "不没别未勿无".contains(ch) { n += 1 }
        let lower = s.lowercased()
        // n't 缩写（don't/won't/can't…）：直接数子串出现次数。
        n += lower.components(separatedBy: "n't").count - 1
        // 英文否定词按词边界数（用非字母切词，避免 "notion" 里的 "not" 被误数）。
        let words = lower.split { !($0.isLetter) }.map(String.init)
        let negWords: Set<String> = ["not", "never", "no", "nor", "none",
                                     "cannot", "without"]
        for w in words where negWords.contains(w) { n += 1 }
        return n
    }

    // MARK: - 语音转写（跟安卓同一条链：录 WAV → /api/audio → 火山 ASR）

    /// 把录好的 WAV 传火山 `/api/audio` 转写成中文。
    /// 🚨 两端一致（Kevin 2026-08-21 规矩）：安卓 `Api.transcribe` 走的就是这个端点。
    ///    iOS 原来用 `SFSpeechRecognizer`，现改成后端转写，两端行为拉齐。
    static func transcribe(wav: Data, attempt: Int = 0, rid: String = newReqId(),
                           done: @escaping (Result<String, Failure>) -> Void) {
        // 🚨 复审 中-2：**这三个端点原来没有重试通道**，而
        //    `handleSubmitBody` 的文档白纸黑字说「对四个端点同样成立」
        //    —— 抽了共享判据，点名的症状一次都没修。**不骑墙，真接上。**
        //    代价对比：voice/audio 失败＝**他刚说的那段话没了**，
        //    tts 失败＝「读不出来」。重试只在「无 kind 的 5xx」上发生。
        // 🚨 重试上限统一 3 次。**幂等 id 已接上**（`X-Req-Id`），
        //    所以重试不再等于重复计费 —— 但**跨实例那半没解决**，
        //    见 `newReqId` 的注释，别把它读成"已解决"。
func retryOrFail(_ f: Failure) {
            if attempt < 3 {
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + Double(attempt + 1) * 2) {
                    transcribe(wav: wav, attempt: attempt + 1, rid: rid, done: done)
                }
            } else {
                done(.failure(f))
            }
        }
        guard let url = URL(string: base + "/api/audio") else {
            return done(.failure(.message(FailureText.Local.badURL)))
        }
        var body: [String: Any] = [
            "audio": wav.base64EncodedString(),
            "format": "wav",
            // 🚨🚨 **别在这里手写提示词** —— 原来这行写的是
            //    「只输出这段话的**中文**逐字转写」，而安卓那边早就是
            //    「说什么语种就转什么语种」。他说英文时，iOS 在命令模型输出中文。
            //    Kevin 2026-08-31 点名的第一条就是这个。
            //    现在两端都从 `engine.ASR_PROMPT` 生成，单一配置点。
            "prompt": Secrets.promptAsr,
        ]
        // 🚨 2026-09-03 常用词接线（2.1 递的规格 + 后端契约）。
        //    键名必须是 **`vocab`**、值是**纯文本数组** ——
        //    PC 端一直发的 `asr_terms` 是错的，等于词表从来没生效过。
        //    只带 kind != "style" 的词（那类只管说得像，不管听得准），
        //    🚨 style 那类词不进 vocab —— 那条过滤的**唯一实现**在
        //       `VocabCore.wordsFor(_:asr:)`；`KbBridge.asrVocab()` 只是转调它。
        //    空数组就整个不带这个字段，别发 "vocab": []。
        let vocab2 = KbBridge.asrVocab()
        if !vocab2.isEmpty {
            body["vocab"] = vocab2
            KbBridge.note("识别带上常用词 " + String(vocab2.count) + " 个（/api/audio）")
        }
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            return done(.failure(.message(FailureText.Local.assembleFailed)))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        // 🚨 幂等 id：同一次业务请求的所有重试共用一个，后端据它去重（见 `newReqId`）。
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        req.setValue(rid, forHTTPHeaderField: "X-Req-Id")
        req.httpBody = data

        URLSession.shared.dataTask(with: req) { d, resp, err in
            if let err = err {
                // 🚨 中-1：传输错误也重试（跟 `submit` 一致）——
                //    这两个端点失败＝**他刚说的那段话没了**，值得补一发。
                return retryOrFail(NetClassify.isNetwork(err)
                                   ? .network : .message(err.localizedDescription))
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 { return done(.failure(.unauthorized)) }
            let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            if code == 429 {
                return done(.failure(.quota((obj?["error"] as? String) ?? "额度用完了")))
            }
            // 🚨🚨 **提交出口也必须先看错误体**（复审 H1）。
            //    H-A 的依据是「`_send` 把 502 改写成 500」——
            //    **这条依据在提交侧同样成立**，而这里原来一次都没看过：
            //    `obj` 解析出来了，只用来取 `job` 和 429 文案，
            //    `error`/`kind` 直接丢掉。
            //    后果不只是分类不可达 —— 带 error 的 500 会被当成
            //    **可重试**错误重发 4 次（≈12 秒），既违反
            //    「401/429 是明确答复，不重试」，也可能重复建 job。
            //    位置：在 401/429 之后、`code >= 500` 重试之前。
            // 跟 `submit` 用**同一份判据**（`handleSubmitBody`），
            // 现在也跟它一样有重试通道（复审 中-2）。
            if handleSubmitBody(code: code, obj: obj,
                                retry: retryOrFail,
                                fail: { done(.failure($0)) }) { return }
            // 🚨 复审 中-1：**这一条原来只有 `submit` 有**，而这三处的注释
            //    却写着「跟 submit 一样」。缺它的后果：网关冷启动回一个
            //    **HTML 错误页**配 502/504 → `obj` 为 nil → `handleSubmitBody`
            //    返回 false → 一次判死，**他刚说的那段话没了**。
            //    （正是 2026-08-21 加这条重试要救的那类场景的另一半形态。）
            if code >= 500 { return retryOrFail(.http(code)) }
            guard code == 200 || code == 202, let job = obj?["job"] as? String else {
                return done(.failure(.http(code)))
            }
            pollRaw(job: job, tries: 0, done: done)
        }.resume()
    }

    /// 转写用的轮询：返回**原始文字**（不做 splitEn/翻译），只清掉汉字间空格。
    private static func pollRaw(job: String, tries: Int,
                             st: PollState = PollState(),
                             done: @escaping (Result<String, Failure>) -> Void) {
        if tries > 90 { return done(.failure(.timeout)) }
        guard let url = URL(string: base + "/api/job?id=" + job) else {
            return done(.failure(.message(FailureText.Local.badJobURL)))
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.7) {
            URLSession.shared.dataTask(with: req) { d, resp, err in
                // 🚨 低-1：**看一眼状态码**。原来这三处把 `resp` 直接丢掉，
                //    只有 `pollVoice` 看 —— 又一次「同一条规则四个实现、
                //    三个跟另一个不一样」。
                //    后果：轮询期间口令失效（换设备/后端轮换 pass）→
                //    401 + 非 JSON 体 → 走「抖动」分支磨满 90 轮 →
                //    报「等太久了」，他再点一次还是 401。
                if (resp as? HTTPURLResponse)?.statusCode == 401 {
                    return done(.failure(.unauthorized))
                }
                // 🚨 M3：**接住 `err`**。原来是 `{ d, _, _ in }`，断网时 `obj` 为 nil，
                //    被当成抖动一直重试，磨满轮询变成「等太久了」——
                //    `err_network` 在轮询链上**根本不可达**。
                //    但**一次网络错不下结论**（可能只是抖了一下），
                //    连着两次才终结。
                if let e = err {
                    if NetClassify.isNetwork(e), st.noteNetwork() {
                        return done(.failure(.network))
                    }
                    return pollRaw(job: job, tries: tries + 1, st: st, done: done)
                }
                st.noteTransportOK()
                let obj = d.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
                guard let obj = obj else {
                    // 🚨🚨 复审 中-1：**这条分支原来绕过了 `noteCleanBody()`**。
                    //    非 JSON 的响应（网关错误页、空体）也是一次
                    //    「体里没有 error」，错误的连续性该在这里被打断。
                    //    不清的话：错A → 非JSON → 错A 会被判成「连着两次」，
                    //    **把一个还在跑的 job 当场判死**。
                    //    `pollVoice` 走可选链、天然会清 —— 
                    //    **同一条规则四个实现，三个跟另一个不一样。**
                    st.noteCleanBody()
                    return pollRaw(job: job, tries: tries + 1, st: st, done: done)
                }
                // 🚨🚨 **失败判断必须在 `done` 之前** —— 真实错误体
                //    `{"error":…, "kind":…}` **根本没有 `done` 字段**
                //    （实读 `server_api.py:783-787`）。
                //    上一版把它放在 `done == true` 后面 → **整套 kind 分类不可达**，
                //    所有 job 级失败都磨满轮询变成「等太久了」。
                //    **我当时验的是代码结构，不是真实响应的形状。**
                // 🚨🚨 M4：**「体里有 error」不等于「这个 job 死了」。**
                //    `/api/job` 上的 error 有两个作者：job 自己（必带 `kind`）
                //    和**网关**（`_send`/`_GATEWAY_EATS`），两者形状一样。
                //    有 kind → 一次就终结；没 kind → 同一条错连出两次才终结。
                if let r = JobErrorParse.parse(obj), let f = failureFrom(obj) {
                    if JobErrorParse.isTerminal(kind: r.kind, message: r.message,
                                                previous: st.prevError) {
                        return done(.failure(f))
                    }
                    st.prevError = r.message
                    return pollRaw(job: job, tries: tries + 1, st: st, done: done)
                }
                // 🚨 高-1：**只有「体里没有 error」才打断错误的连续性**。
                //    放到上面去（拿到任何响应就清）会让「连着两次才终结」永不可达
                //    —— 那正是上一版的做法：错误体本身就是一次正常 HTTP 响应。
                st.noteCleanBody()

                if obj["done"] as? Bool == true {
                    let zh = cleanZh((obj["text"] as? String) ?? "")
                    if zh.isEmpty { return done(.failure(.message(FailureText.Local.emptyAsr))) }
                    return done(.success(zh))
                }
                pollRaw(job: job, tries: tries + 1, st: st, done: done)
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
