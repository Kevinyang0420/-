import Foundation

/// **把语音转出来的文本收敛成"要查的词"。**
///
/// Kevin 2026-09-05：「查词这个功能也支持语音，**可以通过拼写去查词**」。
/// 2.1 规格：**麦克风只有一个键**，说单词和拼字母走同一个键 ——
/// 「他不该在按之前就知道自己要用哪种」。所以判断在这里做，不做成两个模式。
///
/// 🚨🚨 **这是我们已知的薄弱处，不是想当然能过的**：
///    今天早上他说「选**乙**」，我们自己的转写听成了「**E**」。
///    单字母/拼读序列正是 ASR 链路最容易错的地方。
///    2.1 原话：「不是不做的理由，是**必须先验**的理由」。
///    → 所以这一层只做**能确定的那部分**，做不到的**如实暴露**，不假装。
enum SpellFold {

    /// 分隔符：ASR 会把 `K-U-C-Y-N` 转成各种样子 ——
    /// `K U C Y N` / `K、U、C、Y、N` / `KUCYN` / `k u c y n`。
    /// 🚨 **全部按码点写死，不写转义**（今天被工具链吃过转义好几次）。
    private static let seps: Set<Character> = Set(
        [32, 9, 10, 13, 45, 44, 46].map { Character(UnicodeScalar(UInt8($0))) }
        + ["、", "，", "。", "·"])

    /// 看起来像"在拼字母"吗？
    ///
    /// 判据：切开之后**至少 3 段、且每段都是单个英文字母**。
    /// - 至少 3 段：`I T` 这种两段的更可能是真词或缩写，别乱拼。
    /// - 每段单字母：只要有一段是完整单词，那就是在说话，不是在拼。
    static func looksSpelled(_ s: String) -> Bool {
        let parts = s.split(whereSeparator: { seps.contains($0) })
                     .map { String($0) }
                     .filter { !$0.isEmpty }
        guard parts.count >= 3 else { return false }
        for p in parts {
            guard p.count == 1, let c = p.unicodeScalars.first,
                  (c.value >= 65 && c.value <= 90) || (c.value >= 97 && c.value <= 122)
            else { return false }
        }
        return true
    }

    /// 收敛：像拼字母就拼起来（大写），否则原样返回（只去首尾空白）。
    static func fold(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksSpelled(t) else { return t }
        return String(t.filter { !seps.contains($0) }).uppercased()
    }
}
