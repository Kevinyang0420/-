import Foundation

/// **单词本自动归类：词 / 词组 / 句子。**
///
/// Kevin 2026-09-05：「按照翻译的东西（词、词组、句子等）去 organize，方便人去回看」
/// 拍板「这还用问吗？**肯定是自动啊**」。
///
/// 判据照 2.1 规格（**先用简单可解释的，别上模型**）：
///   · 词    ＝ 1 个词
///   · 词组  ＝ 2–4 个词，且**不含句末标点**
///   · 句子  ＝ ≥5 个词，**或**含句末标点（`. ? !` 及中文 `。？！`）
///
/// 🚨 **在展示时算，不写死进存储** —— 以后改判据不用迁移数据。
///
/// 🚨 **放 Shared 而不是写在那一屏里**：单词本页和（将来的）记录页分页都要用它，
///    抄第二份必漂。这摊活已经在"同一规则两处实现"上栽过好几次
///    （话筒比例三处、语言表手抄、分段标题两屏各写）。
enum WordKind {

    enum Kind: Int {
        case word = 0, phrase = 1, sentence = 2
    }

    /// 句末标点 —— **中英都要**。只写 ASCII 的话中文句子会被判成词组。
    private static let enders: Set<Character> = [".", "?", "!", "。", "？", "！"]

    /// 数词：按空白切。
    ///
    /// 🚨 **不用 `.whitespacesAndNewlines`**：它含全角空格等，
    ///    跟安卓 Java 的 `\s` **不是同一个集合** —— 同一条在两端会数出不同的词数，
    ///    而两边各自的自测都会通过（`WordId` 里已经栽过这个坑，注释写着呢）。
    ///    这里按 ASCII 空白写死，跟 `WordId.norm` 同口径。
    // 🚨 **全部按码点写死，一个反斜杠都不用**：空格32 制表9 换行10 回车13 垂直制表11 换页12。
    // 全部按码点写死: 空格32 制表9 换行10 回车13 垂直制表11 换页12。
    // 这样写没有任何转义字符, 工具链吃不掉。
    // (上一版把控制字符写成转义, 被展开成真的制表符和换行,
    //  连这段注释自己都被拦腰断成没有前缀的一行, 当场编不过。)
    private static let spaces: Set<Character> = Set(
        [32, 9, 10, 13, 11, 12].map { Character(UnicodeScalar(UInt8($0))) })

    static func words(_ s: String) -> Int {
        var n = 0
        var inWord = false
        for ch in s {
            if spaces.contains(ch) {
                inWord = false
            } else if !inWord {
                inWord = true
                n += 1
            }
        }
        return n
    }

    static func of(_ en: String) -> Kind {
        let t = en.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return .word }
        let hasEnder = t.contains { enders.contains($0) }
        let n = words(t)
        if hasEnder { return .sentence }
        if n <= 1 { return .word }
        if n <= 4 { return .phrase }
        return .sentence
    }

    // 🚨 **段标题不在这里**（原来有个 `title(_:)` 用了文案表 `L`）。
    //    这个类型被编进测试包做纯逻辑测试，那里没有 `L` —— 报的是
    //    `cannot find 'L' in scope`。
    //    但真正的教训不是"补个依赖"：**判据属于逻辑、文案属于界面**，
    //    混在一起的结果就是纯逻辑不再纯。标题挪到 `HistoryListViewController`。

    /// 分组。**空的那一段整段不出现** —— 这是 2.1 点名的坏样本
    /// （灌 3 条词 + 3 条句子，「词组」整段必须不出现）：
    /// 标题写死的实现在数据少时看不出来，只有这样灌才会现形。
    static func group<T>(_ items: [T], en: (T) -> String) -> [(kind: Kind, items: [T])] {
        var buckets: [Kind: [T]] = [:]
        for it in items {
            buckets[of(en(it)), default: []].append(it)
        }
        return [Kind.word, .phrase, .sentence].compactMap { k in
            guard let v = buckets[k], !v.isEmpty else { return nil }
            return (k, v)
        }
    }
}
