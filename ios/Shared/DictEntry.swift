import Foundation

/// **查词的一条结果。**
///
/// 🚨 **最多 3 条义项，截断在这里做**（2.1 规格）：
///    「单个词没上下文，模型会吐十条义项，按使用频率排序砍到 3 条 ——
///     超过 3 条他就不看了，等于没查」。
///    坏样本：查 `take`（几十个义项）→ 仍然只出 3 条。
///    **常用词上看不出这个错**，所以截断必须有单独的判据。
struct DictSense {
    /// 英文释义 —— **在上**。它教的是"怎么用"。
    let en: String
    /// 中文对译 —— 在下。用来确认理解。
    let zh: String
    /// `formal` / `informal` 之类的用法标注；没有就空。
    /// 🚨 有标注的那条**降一级**显示（Grok ⑤：偏义和常用义同等对待，扫描成本高）。
    let register: String
}

struct DictEntry {
    let word: String
    let phonetic: String
    /// 词性，作**一次**小标题（Grok ②：`adj.` 重复三次是噪音）。
    let pos: String
    let senses: [DictSense]
    let exampleEn: String
    let exampleZh: String
    let collocations: [String]

    /// 🚨 **截断的唯一出口。** 放在模型这一层而不是渲染层：
    ///    渲染层截的话，缓存里存的还是十条，换个入口渲染就漏了。
    static let maxSenses = 3

    func trimmed() -> DictEntry {
        guard senses.count > DictEntry.maxSenses else { return self }
        return DictEntry(word: word, phonetic: phonetic, pos: pos,
                         senses: Array(senses.prefix(DictEntry.maxSenses)),
                         exampleEn: exampleEn, exampleZh: exampleZh,
                         collocations: collocations)
    }
}

/// **查过的词：本地缓存 + 最近列表。**
///
/// 🚨 2.1 判据 6：**同一个词查第二次不许再打后端**
///    ——「他会反复查同一批词，这正是要放进单词本的那批」。
///    判据是**没有网络请求**（看日志/抓包），不是"感觉快了点"。
enum DictStore {
    private static var cache: [String: DictEntry] = [:]
    private static var recentKeys: [String] = []
    private static let maxRecent = 12

    /// 归一化：大小写和首尾空白不该算两个词。
    static func key(_ w: String) -> String {
        w.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func cached(_ w: String) -> DictEntry? { cache[key(w)] }

    static func put(_ e: DictEntry) {
        let k = key(e.word)
        cache[k] = e
        recentKeys.removeAll { $0 == k }
        recentKeys.insert(k, at: 0)
        if recentKeys.count > maxRecent { recentKeys.removeLast() }
    }

    /// **真发出去的查词请求数。** 判据 6 靠它，不靠"感觉快了点"。
    ///
    /// 🚨 这个计数**只在 `Backend.lookup` 真要发请求那一处** +1。
    ///    放调用方的话会漏（调用方有搜索框回车、点最近查过、语音三处），
    ///    而漏掉的表现是"缓存看起来生效了" —— 正好是错的方向。
    private(set) static var netCount = 0
    static func bumpNetCount() { netCount += 1 }

    static func recent() -> [String] {
        recentKeys.compactMap { cache[$0]?.word }
    }
}
