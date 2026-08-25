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
        return nil
    }
}
