import Foundation

/// 反向翻译的目标语言。
///
/// 🚨🚨 **这是安卓 `Reverse.java` 的逐条翻译，不是重新设计。**
///    `gate_pure_logic.py` 读安卓当真值比对。
///
/// Kevin 2026-08-26 要的：旅游时**对方说外语，我要看懂**。
///   · 正向 = 我说话 → 译成我选的目标语言（`lang`，给对方看）
///   · 反向 = 对方说话 → 译成**我的语言**（给我看）
///
/// 「我的语言」＝**界面语言**：一个人把界面设成什么语言，
/// 那就是他读起来最省力的语言，不用再让他单独选一次。
///
/// 🚨 整条链**不需要动后端**（2026-08-26 实测，`probe_asr_english.py`）：
///   · 后端 ASR 走火山 `bigmodel`、没传语言参数，实测两段英文**逐字**转出，
///     中文对照组同时转出汉字 —— 所以不是碰巧。
///   · `engine.LANGS` 里 `zh` / `zht` 本来就在，
///     语义就是"说任何语言、译成中文"。
enum Reverse {

    /// 界面语言 → 反向翻译的目标语言码（`engine.LANGS` 里的键）。
    /// - Parameter uiLang: `Lang.current` 的值：`zh` / `hant` / `en`
    static func target(for uiLang: String?) -> String {
        guard let u = uiLang else { return "zh" }
        if u == "en" { return "en" }
        if u == "hant" { return "zht" }
        // 🚨 兜底给简体中文，不是英文 —— 认不出的多半是某种中文变体。
        return "zh"
    }

    /// 面对面翻译：**这句话是谁说的**（安卓 `Reverse.isMine`）。
    ///
    /// ```
    /// 有汉字 -> 是【我】说的中文 -> 译成对方的语言
    /// 没汉字 -> 是【对方】说的   -> 译成我的界面语言
    /// ```
    ///
    /// 🚨🚨 **判据是「有没有一个汉字」，不是「汉字占多少比例」。这是设计，不是偷懒。**
    ///    他天天说「OK 那我们 confirm 一下 timeline」——**按占比会判成英文，整段翻反**。
    ///    中英夹杂是他的常态，所以**只要出现一个汉字就算他在说中文**。
    ///    改成占比之前先想清楚这一句会变成什么样。
    ///
    /// 🚨 只认**汉字**，不认全角标点：「，。！？」这些在中英夹杂里两边都会出现，
    ///    拿它们当证据会把纯英文句子误判成中文。
    ///
    /// - Returns: true = 我说的（中文）；false = 对方说的
    static func isMine(_ text: String?) -> Bool {
        // 认不出就当我说的：翻错方向不如不翻。
        guard let t = text else { return true }
        for u in t.unicodeScalars where isHan(u) { return true }
        return false
    }

    /// 是不是汉字（CJK 统一表意文字，含扩展 A 和兼容区）。
    /// 🚨 跟安卓 `Reverse.isHan` **同三段**，别自己加减区段。
    static func isHan(_ u: Unicode.Scalar) -> Bool {
        let v = u.value
        return (v >= 0x4E00 && v <= 0x9FFF)      // 基本区
            || (v >= 0x3400 && v <= 0x4DBF)      // 扩展 A
            || (v >= 0xF900 && v <= 0xFAFF)      // 兼容表意文字
    }

    /// 这一句该译成什么语言（安卓 `targetFor(text, uiLang, mine)`）。
    /// - Parameters:
    ///   - text: 听到的这句话
    ///   - uiLang: 我的界面语言（`zh` / `hant` / `en`）
    ///   - mine: 我说话时的目标语言码（设置里那个）
    static func target(text: String?, uiLang: String?, mine: String?) -> String {
        // 我说的 -> 译给对方；对方说的 -> 译回我的界面语言
        isMine(text) ? (mine ?? "en") : target(for: uiLang)
    }

    // MARK: - 自测

    /// 跟安卓 `selfTest()` 一一对应。返回 nil = 全过。
    static func selfTest() -> String? {
        if target(for: "zh") != "zh" { return "简体界面该反向到 zh" }
        if target(for: "hant") != "zht" { return "繁体界面该反向到 zht（不是 zh）" }
        if target(for: "en") != "en" { return "英文界面该反向到 en" }
        if target(for: nil) != "zh" { return "nil 该兜底到 zh（不崩）" }
        if target(for: "") != "zh" { return "空串该兜底到 zh" }
        if target(for: "ja") != "zh" { return "认不出的语言该兜底到 zh" }
        // 🚨 三个真实界面语言必须**互不相同** —— 全返回同一个值的实现
        //    也能过上面每一条，但那是错的。
        if target(for: "zh") == target(for: "en") { return "zh 和 en 不该同档" }
        if target(for: "zh") == target(for: "hant") { return "zh 和 hant 不该同档" }
        if target(for: "en") == target(for: "hant") { return "en 和 hant 不该同档" }

        // ---- 方向判定。**坏样本是这一组的要害**（对齐安卓 selfTest）----
        if !isMine("我们明天开个会") { return "纯中文该判我说的" }
        if isMine("Let's sync tomorrow") { return "纯英文该判对方说的" }
        // 🚨 中英夹杂：**按占比会判错的那两句**，必须判成中文
        if !isMine("这个 deadline 要 push 一下") { return "夹杂句该判中文（deadline/push）" }
        if !isMine("OK 那我们 confirm 一下 timeline") {
            return "🚨 只有两个汉字也该判中文 —— 按占比必错"
        }
        // 🚨 全角标点不算证据：纯英文配中文标点仍是对方说的
        if isMine("Sure，OK。") { return "全角标点不该把英文判成中文" }
        if !isMine(nil) { return "nil 该兜底成我说的（翻错方向不如不翻）" }
        if isMine("") { return "空串没有汉字，判对方（调用方自己拦空）" }

        // ---- 三种界面语言各验一遍 ----
        //    🚨 只在中文界面下测的话，"判反"那一类结构上测不出来。
        if target(text: "我说中文", uiLang: "zh", mine: "en") != "en" {
            return "中文界面·我说 -> 目标 en"
        }
        if target(text: "Hello there", uiLang: "zh", mine: "en") != "zh" {
            return "中文界面·对方说 -> 回 zh"
        }
        if target(text: "Hello there", uiLang: "hant", mine: "en") != "zht" {
            return "繁体界面·对方说 -> 回 zht（不是 zh）"
        }
        if target(text: "Hello there", uiLang: "en", mine: "zh") != "en" {
            return "英文界面·对方说 -> 回 en"
        }
        if target(text: "我说中文", uiLang: "en", mine: "zh") != "zh" {
            return "英文界面·我说 -> 目标 zh"
        }

        // 🚨🚨 已知限制（M1，交叉审查 2026-09-03，2.1 排优先级中低）：
        //    **目标语言含汉字时方向判反。** 「有一个汉字＝我说中文」这个前提，
        //    在对方说的语言也含汉字时不成立 —— 对方说日语「私は日本人です」含
        //    `私/日本人`（U+4E00–9FFF）→ isMine 判成"我说的中文" → 译成英文而非中文。
        //    **中英场景完全正常**（Kevin 主用中→英），只在日/繁/粤目标触发。
        //    这里**钉住当前行为**：一旦 isMine 对日语的判定变了（= 有人修了 M1），
        //    这条会红，逼修的人**连这条一起更新**，不让它静默改变。
        if !isMine("私は日本人です") {
            return "M1 已知限制变了：日语含汉字现在不判 mine 了 —— 修 M1 时连这条断言一起更新"
        }
        return nil
    }
}
