import Foundation

/// 跟 engine.py / worker 那两份保持同一套逻辑。
/// 🚨 提示词本身**不在这里**，它由构建时生成的 Secrets.swift 提供，
///    源头永远是 engine.py。别在这个文件里手抄一份。
enum Prompts {
    // <<<VOCABHINT-GEN>>>
    // 🚨🚨 **这一段由 `D:\_build\sync_vocabhint_ios.py` 从 engine.py
    //    的 `VOCAB_HINT` 生成，不要手改。** 改文案去改 engine.py，
    //    再跑一次同步 —— 三端（PC/安卓/iOS）从同一处出。
    //
    // 出稿侧的常用词提示。`{terms}` 由 `vocabHint(_:)` 替换成顿号分隔的词。
    static let vocabHintTemplate = "\n\nThe user has these personal terms (names, companies, habitual phrases): {terms}. Spell them exactly as written, and prefer their wording when it fits. Do not add or explain them."

    /// 把常用词拼进系统提示词。**空表回空串** —— 调用方据此决定加不加。
    ///
    /// 🚨 空表绝不能回一段「（无）」这类占位：那会在指令里平白多出
    ///    一句没有内容的话，模型会去解释它（`VocabCore.joinFor` 同款理由）。
    static func vocabHint(_ terms: String) -> String {
        terms.isEmpty ? ""
            : vocabHintTemplate.replacingOccurrences(of: "{terms}",
                                                     with: terms)
    }
    // <<<VOCABHINT-END>>>


    /// 🚨 语气档位的**唯一一份**（iOS 侧）。顺序也要跟 engine.TONES 一致。
    ///    2026-08-25 之前 App 和键盘各抄一份，结果键盘一直留着已经删掉的
    ///    第四档「正式」——而闸门只查 App 那份，整整漏了过去。
    ///    要加/删档位就只改这里，别再在界面文件里写字面量数组。
    static let all = ["casual", "work", "email"]

    /// 界面上显示的名字。跟 all 是同一套 key，别各排各的顺序。
    static func label(_ t: String) -> String {
        switch t {
        case "casual": return L.tone_casual
        case "email":  return L.tone_email
        default:       return L.tone_work
        }
    }

    /// 存过的旧值可能已经被删掉（比如「正式」），落回 work 而不是崩或者发个后端不认的档位。
    static func normalize(_ t: String?) -> String {
        guard let t = t, all.contains(t) else { return "work" }
        return t
    }


    static func tone(_ t: String) -> String {
        switch t {
        case "email":
            return "a real business email, also used for formal written communication to a "
                 + "client, regulator or auditor. It must be laid out as an email (salutation "
                 + "line, blank line, short paragraphs, closing, sign-off) and worded as a "
                 + "formal request, not as a spoken instruction. Complete sentences, no "
                 + "contractions, hedged where the speaker hedged, no slang. See EMAIL SHAPE "
                 + "below - it is mandatory for this register."
        case "casual":
            return "a casual message to someone you know well. Relaxed, short, contractions."
        default:
            return "a direct work message to a colleague or counterpart (Slack / WhatsApp / Teams). "
                 + "Professional but not stiff. Contractions are fine."
        }
    }

    /// **整理档的排版硬闸** —— 移植自安卓 `Api.renderPoints`（2026-08-31 拉齐）。
    ///
    /// 🚨🚨 Kevin 2026-08-23（在安卓上）：「整理给出的结果和逐字没什么区别…
    ///    整理功能的初衷是把零散的点做结构化分层，**提炼并按 1、2、3 列出核心要点**」。
    ///
    /// 🚨 为什么不靠提示词：安卓那边改了四轮 prompt 都不灵 —— 模型照样把
    ///    「一个事件的多个事实」写成一段散文。**归并它做得很好，差的只是排版**，
    ///    而排版正是代码该管的部分。跟逐字档「一个字都不许改」由 `sameWords()`
    ///    保证是同一个思路：**承诺由代码兑现，不靠模型自觉。**
    ///
    /// 模型给了 `{"lead":…, "items":[…]}` 就按它排；给不了就退回 `numberPoints`。
    /// 🚨 解析失败**绝不能把花括号原样丢给他看** —— 一律有兜底。
    /// **终局闸：无论内部怎么走，带花括号的东西一律不许上屏。**
    ///
    /// 🚨🚨 2026-08-31 交叉审查抓到：`{"lead": null, "items": []}` 这种
    ///    （模型"没什么可列"时的常见返回）会一路穿过所有分支原样上屏 ——
    ///    salvage 捞不到东西返回 nil，`numberPoints` 又原样返回。
    ///    **五个禁词全中，正是 Kevin 看到的那一幕。**
    ///
    /// 所以把判断收在这一层：**结果里还带 `{` 或 `}` 就不要它**，
    /// 宁可给一句"没听清"，也不许把代码丢给他看。
    /// 这条是结构性的 —— 内部再加多少分支，都绕不过它。
    /// - Parameter fallback: **他自己说的那句话（ASR 原文）**。排不出来时退回它。
    ///
    /// 🚨🚨 2026-09-03：这里原来 `return L.err_zh_unreadable` ——
    ///    也就是**我们自己的提示语**。而 `Backend.swift` 把 renderPoints 的返回值
    ///    当作 `.success` 交出去，于是那句提示语被 commit 进他正在写的文档里。
    ///    安卓 / PC 同一个洞已修，iOS 是最后一个（0 → 2.2 转来）。
    ///
    /// 🚨 **修法不是在外面加个 if 判断，是让那句文案够不着这一层**：
    ///    ① 收 `fallback` 参数，排不出来就退回**他的原话** —— 他说的字一个都不能丢；
    ///    ② `L.err_zh_unreadable` 从本文件**删干净**（不是留着不走）。
    ///    只做 ① 的话，改一个 if 就能让测试全绿而结构没变 —— 那是假修。
    ///    配套反向控制见 `selfTest()`：把提示语喂进输出路径，必须走不通。
    static func renderPoints(_ raw: String, fallback: String) -> String {
        let out = renderPointsInner(raw)
        // 带花括号 = 没排出来。宁可原样给他他自己说的话，也不许把代码或
        // 我们的提示语丢进他的文档。
        if out.contains("{") || out.contains("}") {
            let f = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            return f.isEmpty ? out.replacingOccurrences(of: "{", with: "")
                                  .replacingOccurrences(of: "}", with: "")
                             : f
        }
        return out
    }

    private static func renderPointsInner(_ raw: String) -> String {
        // 换行用 \u{0A} 拼，不写反斜杠 n 的字面量 ——
        // 生成这段代码时反斜杠被吃掉过好几次，Swift 串里塞进真换行、编译报错。
        let NL = "\u{0A}"
        // 🚨 模型常把 JSON 包在 ```json … ``` 里。不剥掉就永远解析不出来，
        //    然后原样上屏 —— Kevin 2026-08-31 看到的 `lead`/`null`/`items` 就是它。
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            t = t.replacingOccurrences(of: "```json", with: "")
                 .replacingOccurrences(of: "```", with: "")
                 .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let a = t.firstIndex(of: "{"), let b = t.lastIndex(of: "}"), a < b else {
            // 🚨 用 `t` 不是 `raw`（低-3）：`t` 已经剥掉了 ``` 围栏。
            //    用 `raw` 的话，「有围栏、无花括号」那种返回会**带着反引号上屏**。
            return numberPoints(t)
        }
        let slice = String(t[a...b])
        guard let d = slice.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let items = o["items"] as? [Any], !items.isEmpty else {
            // 🚨🚨 **解析失败时绝不能把花括号原样交给他。**
            //    走到这儿说明文本里确实有 `{…}`，只是结构跟预期不同 ——
            //    这时候 `numberPoints` 会原样返回，于是 JSON 上屏。
            //    兜底：**把引号里的内容捞出来**（键名和 null/数字不会被捞到），
            //    捞得到就用捞到的，捞不到才退回原文。
            return salvageFromJSONish(t) ?? numberPoints(t)
        }
        let lead = ((o["lead"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // 🚨 `items` 里也可能是对象（`{"text": "..."}`）而不是纯字符串 ——
        //    只认字符串的话又会掉进上面那个"解析成功但取不到内容"的坑。
        let texts = items.compactMap { el -> String? in
            if let s = el as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let m = el as? [String: Any] {
                for k in ["text", "item", "content", "value"] {
                    if let s = m[k] as? String {
                        return s.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            return nil
        }.filter { !$0.isEmpty }
        if texts.isEmpty { return salvageFromJSONish(t) ?? numberPoints(t) }
        // 🚨🚨 **第三个格子 `ask`**（1.1 2026-09-05 加，engine.py 是唯一真值）。
        //
        //    起因是 Kevin 亲自指出的层级错乱：整理出来的前 3 点是「我的情况分三期」，
        //    第 4 点却是「请你先读 PDF、按模板帮我写说明」。他的原话：
        //    「**第四点是我要让它做的兜底和补充，跟前三点根本不是一个层级**」。
        //    items 里的条目彼此并列，而「请你做某事」是**对听者的请求** ——
        //    编成第 4 条就把两个层级压平了。
        //
        // 🚨 光改提示词治不了：模型原来**只有 lead / items 两个格子可放**，
        //    那句话除了塞进 items 无处可去。所以是协议加字段，不是措辞问题。
        //
        // 🚨🚨 **不接这个字段 = 静默丢内容**：老客户端拿到 `ask` 不认识，
        //    那句话直接消失，而且不报任何错。
        //    渲染规矩：**items 之后、单独一段、不参与编号、不带任何前缀符号**。
        let ask = ((o["ask"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 只有一条就写成一句话，不编号（他要的是"多条才 1、2、3"）
        if texts.count == 1 {
            let one = (lead.isEmpty ? texts[0] : lead + "。" + texts[0])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ask.isEmpty ? one : one + NL + NL + ask
        }
        var lines: [String] = []
        if !lead.isEmpty { lines.append(lead + "：") }
        for (i, x) in texts.enumerated() { lines.append("\(i + 1). " + x) }
        var out = lines.joined(separator: NL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // 🚨 空行隔开，让它在视觉上**明确不属于那串编号**。
        if !ask.isEmpty { out += NL + NL + ask }
        return out.isEmpty ? numberPoints(t) : out
    }

    /// **最后一道：看起来像 JSON 但解析不出来时，把人话捞出来。**
    ///
    /// 🚨 Kevin 2026-08-31 看到的就是没有这一道的后果：
    ///    「产出的文字里还残留很多代码（lead、null、items）」。
    ///    **他要的是一段中文，任何情况下都不该看到花括号和字段名。**
    ///
    /// 做法：捞出所有引号里的串，扔掉**键名**（后面紧跟冒号的那些）和空串。
    /// 捞不到任何东西就返回 nil，由调用方决定怎么退。
    static func salvageFromJSONish(_ s: String) -> String? {
        guard s.contains("{"), s.contains("\"") else { return nil }
        var out: [String] = []
        var buf = ""
        var inStr = false
        var esc = false
        var pendingIsKey = false
        var chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inStr {
                if esc { buf.append(c); esc = false }
                else if c == "\\" { esc = true }
                else if c == "\"" {
                    inStr = false
                    // 后面第一个非空白字符是冒号 → 这是键名，丢掉
                    var j = i + 1
                    // 🚨 `\t` 和 `\r` 也是空白。上一版只跳空格和换行，
                    //    于是 `{"lead"\t: null}` 里的 `lead` 不被认成键名，
                    //    直接当正文捞出来上屏 —— 正是他抱怨的那几个词。
                    while j < chars.count,
                          chars[j] == " " || chars[j] == "\n"
                          || chars[j] == "\t" || chars[j] == "\r" { j += 1 }
                    pendingIsKey = (j < chars.count && chars[j] == ":")
                    let v = buf.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !pendingIsKey, !v.isEmpty { out.append(v) }
                    buf = ""
                } else { buf.append(c) }
            } else if c == "\"" {
                inStr = true; buf = ""
            }
            i += 1
        }
        guard !out.isEmpty else { return nil }
        if out.count == 1 { return out[0] }
        return out.enumerated().map { "\($0.offset + 1). " + $0.element }
            .joined(separator: "\n")
    }

    /// 没有 JSON 时的兜底编号。**保守：宁可不动，也不许拆错。**
    /// · 已经分行 / 已经有编号 → 原样不动
    /// · 不足 3 句 → 原样不动（他要的是"多条才编号"）
    static func numberPoints(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return s }
        if t.contains("\n") { return s }
        if t.range(of: "(^|\\s)[1-9][.、]", options: .regularExpression) != nil { return s }
        var items: [String] = []
        var cur = ""
        for ch in t {
            cur.append(ch)
            if "。！？!?".contains(ch) {
                let q = cur.trimmingCharacters(in: .whitespacesAndNewlines)
                if !q.isEmpty { items.append(q) }
                cur = ""
            }
        }
        let tail = cur.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { items.append(tail) }
        if items.count < 3 { return s }
        return items.enumerated().map { "\($0.offset + 1). " + $0.element }
            .joined(separator: "\n")
    }

    /// 🚨 模型偶尔把 ZH 块吐两遍（实测）：<<<OUT>>>…<<<ZH>>>中文<<<ZH>>>中文
    ///    键盘只要英文那半截。
    static func splitEn(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let a = s.range(of: "<<<OUT>>>"), let b = s.range(of: "<<<ZH>>>"),
              a.upperBound <= b.lowerBound else { return s }
        return String(s[a.upperBound..<b.lowerBound])
            .replacingOccurrences(of: "<<<OUT>>>", with: "")
            .replacingOccurrences(of: "<<<ZH>>>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 🚨 提示词里禁了破折号，但模型照样吐（实测），所以代码里兜死。
    static func postprocess(_ input: String) -> String {
        var s = input
        s = s.replacingOccurrences(of: " — ", with: "; ")
        s = s.replacingOccurrences(of: "—", with: "; ")
        s = s.replacingOccurrences(of: " – ", with: "; ")

        var out = ""
        let chars = Array(s)
        for (i, ch) in chars.enumerated() {
            if ch == "–" {
                let p = i > 0 ? chars[i - 1] : " "
                let n = i + 1 < chars.count ? chars[i + 1] : " "
                out += (p.isNumber && n.isNumber) ? "-" : ", "
            } else {
                out.append(ch)
            }
        }
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        return out.replacingOccurrences(of: " ;", with: ";")
                  .replacingOccurrences(of: " ,", with: ",")
                  .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// **整理档排版的自测。** 由 `gate_all_selftests.py` 自动发现并运行。
    ///
    /// 🚨 判据一律是「**他会不会看到花括号/字段名**」，
    ///    不是"函数有没有被调用"——后者昨天刚绿过一次，而主路径根本没接。
    ///
    /// - Returns: 失败说明；全过返回 nil。
    static func selfTest() -> String? {
        var bad: [String] = []
        func no(_ name: String, _ out: String) {
            // 上屏内容里绝不许出现这些
            // 🚨🚨 禁词用**裸词**，不带引号。上一版查的是 `"\"items\""`，
            //    而 salvage 的输出是**剥了引号**的 —— 那两项在 salvage 路径上
            //    结构性抓不到，是**永远不会失败的检查**。
            for w in ["{", "}", "items", "lead", "null"] where out.contains(w) {
                bad.append(name + "：上屏里出现了 " + w + " —— " + String(out.prefix(60)))
            }
        }

        // ① 正常 JSON：多条要编号
        let a = renderPoints("{\"lead\":\"本周进度\",\"items\":[\"资料没齐\",\"周三再看\",\"发票要催\"]}", fallback: "【原话】")
        no("正常JSON", a)
        if !a.contains("1. ") || !a.contains("3. ") { bad.append("正常JSON：没编号 -> " + a) }

        // ② 带 ``` 围栏（模型很常见）
        let b = renderPoints("```json\n{\"lead\":null,\"items\":[\"甲\",\"乙\",\"丙\"]}\n```", fallback: "【原话】")
        no("带围栏", b)
        if !b.contains("1. ") { bad.append("带围栏：没解析出来 -> " + b) }

        // ③ items 是对象数组
        let c = renderPoints("{\"lead\":\"\",\"items\":[{\"text\":\"甲\"},{\"text\":\"乙\"}]}", fallback: "【原话】")
        no("对象数组", c)
        if !c.contains("甲") || !c.contains("乙") { bad.append("对象数组：内容丢了 -> " + c) }

        // ④ 🚨 结构不对的 JSON —— 这一条正是他撞到的：解析失败也**不许**原样上屏
        let d = renderPoints("{\"lead\": null, \"items\": {\"a\": \"下周一开会\", \"b\": \"李总资料没齐\"}}", fallback: "【原话】")
        no("结构不对", d)
        if !d.contains("下周一开会") { bad.append("结构不对：内容没捞出来 -> " + d) }

        // ⑤ 只有一条不编号
        let e = renderPoints("{\"lead\":\"\",\"items\":[\"就一句话\"]}", fallback: "【原话】")
        no("单条", e)
        if e.contains("1. ") { bad.append("单条：不该编号 -> " + e) }

        // ⑥ 阴性对照：普通中文原样不动（证明它不会乱动正常文本）
        let f = renderPoints("这是一句普通的话。", fallback: "【原话】")
        if f != "这是一句普通的话。" { bad.append("阴性对照：把正常文本改了 -> " + f) }

        // ⑦ 阴性对照②：捞不到东西时返回 nil，不硬凑
        if salvageFromJSONish("没有大括号也没有引号") != nil {
            bad.append("阴性对照②：不像 JSON 的文本也被当成 JSON 捞了")
        }

        // ⑧⑨⑩ 🚨 **来自真实链路的样本**（2026-08-31 打线上 /api/llm 取回）。
        //    上面那几条是我编的形状 ——「坏样本和判据同源」那一族：
        //    数据是我自己塞的，至少要有几条来自真实链路。
        //    实测整理档 **3/3 都吐 JSON**，也就是说没有这道闸时
        //    iOS 上「整理」是 100% 坏的，不是偶发。
        let r1 = renderPoints("{\"lead\": \"下周一开会讨论审计进度\", \"items\": [\"李总那边的资料还没准备好，可能要拖到周三。\", \"建议先把能做的部分先做了。\", \"提醒财务尽快处理发票。\"]}", fallback: "【原话】")
        no("真实链路1", r1)
        if !r1.contains("1. ") || !r1.contains("3. ") { bad.append("真实链路1：没编号 -> " + r1) }
        if !r1.contains("下周一开会讨论审计进度") { bad.append("真实链路1：lead 丢了 -> " + r1) }

        // 🚨 这一条就是他亲眼看到的 `"lead": null`
        let r2 = renderPoints("{\"lead\": null, \"items\": [\"今天先这样吧。\"]}", fallback: "【原话】")
        no("真实链路2(lead=null)", r2)
        if r2 != "今天先这样吧。" { bad.append("真实链路2：单条该原样出 -> " + r2) }

        let r3 = renderPoints("{\"lead\": \"供应商谈判结果\", \"items\": [\"付款期从 30 天延至 60 天。\", \"下月涨价 5%，可以再谈。\"]}", fallback: "【原话】")
        no("真实链路3", r3)
        if !r3.contains("1. ") || !r3.contains("2. ") { bad.append("真实链路3：没编号 -> " + r3) }

        // ⑪⑫⑬ 🚨 **交叉审查点名的三档 —— 上一版十条样本一条都没走到这里。**
        //    「闸门只查我造的样本」那一族：禁词表写对了，但那个分支从没被触发过。
        let e1 = renderPoints("{\"lead\": null, \"items\": []}", fallback: "【原话】")   // 模型"没什么可列"时的常见返回
        no("空items", e1)
        let e2 = renderPoints("{}", fallback: "【原话】")
        no("空对象", e2)
        let e3 = renderPoints("{\"lead\"\t: null, \"items\"\t: [\"甲\",\"乙\"]}", fallback: "【原话】")
        no("键名后带Tab", e3)
        if !e3.contains("甲") { bad.append("键名后带Tab：正文丢了 -> " + e3) }

        // ⑭ 🚨🚨 **反向控制：我们自己的提示语一个字都不许上屏。**
        //
        //    本文件抬头（`renderPoints` 的注释）写着「配套反向控制见 selfTest()」——
        //    **而它根本不存在**（2026-09-04 查出）。也就是说「那句文案够不着这一层」
        //    这条规矩当时**没有任何检查守着**：谁把 `L.err_zh_unreadable` 加回来，
        //    十三条样本一条都不会响。
        //    **注释声称有检查 ≠ 真有检查** —— 这比没有检查更糟，因为它让人以为查过了。
        //
        //    这条洞的真实后果（0 → 2.2 转来那条）：`Backend` 把 `renderPoints`
        //    的返回值当 `.success` 交出去，于是**我们的提示语被 commit 进他正在写的
        //    文档里** —— 他以为那是译文。安卓/PC 都修过，iOS 是最后一个。
        for s in [L.err_zh_unreadable, L.err_empty] where !s.isEmpty {
            for (name, out) in [("空items", e1), ("空对象", e2), ("正常", a)]
            where out.contains(s) {
                bad.append("🚨 " + name + "：把我们的提示语当译文交出去了 -> "
                           + String(out.prefix(60)))
            }
        }
        // ⑮ 🚨 **排不出来时必须退回他的原话** —— 他说的字一个都不能丢。
        //    只查"没有提示语"是不够的：返回空串同样满足那一条，
        //    而空串上屏＝他说的话凭空消失（比看到一句提示语更糟）。
        if e1 != "【原话】" {
            bad.append("空items：没退回原话 -> " + String(e1.prefix(60)))
        }
        if e2 != "【原话】" {
            bad.append("空对象：没退回原话 -> " + String(e2.prefix(60)))
        }

                return bad.isEmpty ? nil : bad.joined(separator: "; ")
    }
}
