import Foundation

/// 查词结果的**纯解析** —— 不碰网络、不碰存储、不碰界面。
///
/// 🚨 从 `Backend` 抽出来的理由是**判据跑不动**：UI 测试是独立进程，
///    `Backend` 拖着网络和 `Secrets`，编不进测试包 ——
///    于是「换了 JSON 结构之后老缓存还解不解得出」这条**根本没法验**。
///    （`LangRank` / `WordCard` / `SpellFold` 同一套路。）
///
/// 🚨 **两种结构都要认**（2026-09-06 iOS 改用 `engine.LOOKUP_PROMPT` 之后）：
/// ```
/// engine ->  senses[{pos,en,zh,register}] / examples[{en,zh}] / phonetic "juː"
/// ```
/// 🚨 **新契约的音标不带斜杠**（`engine.LOOKUP_PROMPT` 明写
///    "IPA WITHOUT slashes"，服务端出口还无条件 strip 一遍）。
///    渲染时由 `phoneticForDisplay` 统一剥+包 —— **存量旧卡片带斜杠**，
///    所以解析这一层两种都要认，测试夹具里那些 "/juː/" 是**存量形状，别改**。
/// ```
/// 旧的   ->  senses[{en,zh,register}] / pos / example_en / example_zh
/// ```
/// 旧的**不能删**：缓存里存着按旧结构存下来的条目，只认新的会让
/// 「以前查过的词打不开了」—— 而那不像换提示词引起的，会把人带去查缓存。
enum DictParse {

    static func entry(word: String, raw: String) -> DictEntry? {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a = t.firstIndex(of: "{"), let b = t.lastIndex(of: "}") {
            t = String(t[a...b])
        }
        guard let d = t.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
        else { return nil }
        let raws = o["senses"] as? [[String: Any]] ?? []
        let ss = raws.map {
            DictSense(en: ($0["en"] as? String) ?? "",
                      zh: ($0["zh"] as? String) ?? "",
                      register: ($0["register"] as? String) ?? "",
                      pos: ($0["pos"] as? String) ?? "")
        }
        guard !ss.isEmpty else { return nil }

        // 🚨 **两种结构都要认**（2026-09-06 换 engine 那份提示词之后）：
        //    engine  ->  "examples": [{"en":…, "zh":…}]      数组
        //    旧的    ->  "example_en" / "example_zh"          两个平铺字段
        //    🚨 旧结构**不能删** —— 缓存里存着按旧结构存下来的条目，
        //       只认新的会让老缓存整条解不出（表现是"以前查过的词打不开了"）。
        var exEn = (o["example_en"] as? String) ?? ""
        var exZh = (o["example_zh"] as? String) ?? ""
        if exEn.isEmpty, let arr = o["examples"] as? [[String: Any]],
           let first = arr.first {
            exEn = (first["en"] as? String) ?? ""
            exZh = (first["zh"] as? String) ?? ""
        }

        // 🚨🚨 **不许拿第一条义项的词性当整卡词性。**
        //    engine 把 `pos` 放在**每条 sense 里**，旧结构才是顶层一个。
        //    原来这里有个 fallback「顶层没有就取第一条的」——
        //    commute 第一条是 `v.`，于是整卡标成 `v.`，
        //    而第二条明明是 `n.`（通勤路程），被摆在动词标题底下 →
        //    **Kevin 看到的就是「名词没写上来」**。
        //    词性是**义项级**的；整卡级的那个只对旧结构有意义，
        //    留着 fallback 就是这个错的来源（1.1 建议直接删，同意）。
        let pos = (o["pos"] as? String) ?? ""

        // 🚨 engine 要求音标**带斜杠**（"IPA in slashes"），而界面自己会补
        //    `/…/`（`DictViewController:344` 附近）—— 不剥的话显示成 `//juː//`。
        //    也可能是 `null`，那时上面的 `as? String` 已经回空串。
        var ph = (o["phonetic"] as? String) ?? ""
        ph = ph.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))

        return DictEntry(word: (o["word"] as? String) ?? word,
                         phonetic: ph,
                         pos: pos,
                         senses: ss,
                         exampleEn: exEn,
                         exampleZh: exZh,
                         collocations: (o["collocations"] as? [String]) ?? [])
    }
}
