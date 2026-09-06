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
    /// **这一条义项自己的词性**（`v.` / `n.` …）。旧结构没有，就是空。
    ///
    /// 🚨 Kevin 2026-09-06 报「commute 只给了动词，名词没写上来」——
    ///    后端三条的 pos 都是对的（v./n./v.），是渲染丢的：
    ///    整卡只显示**第一条**的词性，名词那条就摆在 `v.` 标题底下，看不出来。
    ///    词性是**义项级**的，不是整卡级的。
    var pos: String = ""
}

struct DictEntry {
    let word: String
    let phonetic: String
    /// 词性，作**一次**小标题（Grok ②：`adj.` 重复三次是噪音）。
    let pos: String
    let senses: [DictSense]
    /// **全部例句**（英, 中）。
    ///
    /// 🚨 2026-09-06 之前这里是**单数**两个字段，而解析层 `arr.first`
    ///    只取第一条 —— 后端给多条，界面只显示一条，收藏进单词本也只存得下一条。
    ///    Kevin：「这个单词**没有例句，什么都没了**呀」。
    var examples: [(String, String)] = []

    /// 兼容老调用点：第一条例句。**新代码请直接用 `examples`。**
    var exampleEn: String { examples.first?.0 ?? "" }
    var exampleZh: String { examples.first?.1 ?? "" }
    let collocations: [String]
    /// 后端返回的**原始 JSON**。
    ///
    /// 🚨 句子卡（`kind:"sentence"`）的字段是 meaning/breakdown/alternatives/keys，
    ///    跟词卡完全不同。往 `DictEntry` 里再塞四个字段，等于把词卡的结构
    ///    撑成两用 —— 以后每加一种卡都要再撑一次。
    ///    原样留一份，让 `CardSections` 去认 `kind` 并取自己那几段。
    var raw: String = ""

    init(word: String, phonetic: String, pos: String, senses: [DictSense],
         examples: [(String, String)], collocations: [String],
         // 🚨 有默认值 —— 便利入口和测试夹具不必都传。
         //    真实解析（`DictParse`）必须传，句子卡全靠它。
         raw: String = "") {
        self.word = word
        self.phonetic = phonetic
        self.pos = pos
        self.senses = senses
        self.examples = examples
        self.collocations = collocations
        self.raw = raw
    }

    /// 只有一条例句时的便利写法 —— **假数据和老调用点用**。
    /// 🚨 真实解析走上面那个（收全），别拿这个入口去喂后端数据，
    ///    那等于把「只留一条」这个 bug 换个地方再犯一次。
    init(word: String, phonetic: String, pos: String, senses: [DictSense],
         exampleEn: String, exampleZh: String, collocations: [String]) {
        let ex = (exampleEn.isEmpty && exampleZh.isEmpty)
            ? [] : [(exampleEn, exampleZh)]
        self.init(word: word, phonetic: phonetic, pos: pos, senses: senses,
                  examples: ex, collocations: collocations)
    }

    /// **拿去显示的音标** —— 已经剥掉两边的斜杠。
    ///
    /// 🚨🚨 Kevin 2026-09-06 报 `//rɪˈzɪliənt//`。根因在**契约**：
    ///    `LOOKUP_PROMPT` 写的是 `"phonetic": "IPA in slashes"`（自带斜杠），
    ///    而四个渲染点各自又包了一层 `/…/`。
    ///    **不是谁忘了 strip，是契约和所有使用者的默认假设正好相反。**
    ///
    /// 🚨 1.1 已经改了契约 + 服务端出口 strip，**但那只管新查的词** ——
    ///    **他单词本里已存的旧卡片存的是带斜杠的老数据**，
    ///    不在渲染前再剥一次，那些卡片永远显示 `//…//`。
    ///    **判据要拿已存的旧卡片验；只验新查的词，这半漏了也是绿的。**
    ///
    /// 🚨 放模型这一层、不放各渲染点 —— 跟下面 `trimmed()` 同一个理由：
    ///    渲染层各剥各的，换个入口就漏一个。
    var phoneticForDisplay: String {
        phonetic.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
    }

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
