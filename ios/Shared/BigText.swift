import Foundation

/// 大字展示的字号计算。
///
/// 🚨🚨 **这是安卓 `BigText.java` 的逐条翻译，不是重新设计。**
///    分档表、宽度判据、最小字号，全部一一对应。
///    `gate_bigtext_parity.py` 读安卓当真值比对。
///
/// 🚨 宽度判据是**东亚宽度表**，不是「码点大不大」。
///    安卓那版第一稿写的是 `c < 0x2E80 ? 1 : 2`，
///    等于把 é ñ ü 俄语 希腊语 阿拉伯语全当成汉字宽度 ——
///    而 Transless 的目标语言里就有这些。**这边不要退回那种写法。**
enum BigText {

    /// 宽度分档 → 字号（pt）。**从小到大排，第一个够用的就选它。**
    /// 🚨 安卓那边单位是 sp、这边是 pt —— 两者在标准字体缩放下数值一致，
    ///    所以**表里的数字必须一模一样**，不要在这里"换算"。
    private static let table: [(Int, CGFloat)] = [
        (24, 56),      // 一句短话（≈12 个汉字）
        (60, 42),
        (120, 32),
        (240, 24),
    ]
    /// 比表里最大档还长时用这个。
    static let minSize: CGFloat = 18

    /// 一段文字占多少「宽度单位」：**东亚宽字符算 2，其余算 1**。
    static func widthUnits(_ s: String?) -> Int {
        guard let s = s else { return 0 }
        var w = 0
        // 🚨 按 **UTF-16 码元**数，跟安卓 `charAt` 一致。
        //    用 `s.unicodeScalars` 或 `Character` 的话，
        //    组合重音的 "café" 会被数成 4 而安卓数成 5 —— 两端就分叉了。
        for u in s.utf16 {
            w += isWide(u) ? 2 : 1
        }
        return w
    }

    /// 这个字符占两格吗（东亚宽度 Wide / Fullwidth）。区间跟安卓 `isWide` 一致。
    private static func isWide(_ c: UInt16) -> Bool {
        return (c >= 0x1100 && c <= 0x115F)      // 韩文字母
            || (c >= 0x2E80 && c <= 0x303E)      // CJK 部首、标点
            || (c >= 0x3041 && c <= 0x33FF)      // 假名、注音、CJK 兼容
            || (c >= 0x3400 && c <= 0x4DBF)      // CJK 扩展 A
            || (c >= 0x4E00 && c <= 0x9FFF)      // CJK 统一汉字
            || (c >= 0xA000 && c <= 0xA4CF)      // 彝文
            || (c >= 0xAC00 && c <= 0xD7A3)      // 韩文音节
            || (c >= 0xF900 && c <= 0xFAFF)      // CJK 兼容汉字
            || (c >= 0xFE30 && c <= 0xFE6F)      // CJK 兼容标点
            || (c >= 0xFF00 && c <= 0xFF60)      // 全角
            || (c >= 0xFFE0 && c <= 0xFFE6)
    }

    /// 按文字长度选字号。
    static func size(_ s: String?) -> CGFloat {
        let w = widthUnits(s)
        for (limit, sz) in table where w <= limit { return sz }
        return minSize
    }

    // MARK: - 自测

    /// 六组跟安卓 `selfTest()` 一一对应。返回 nil = 全过。
    static func selfTest() -> String? {
        // ① 中文更宽
        if widthUnits("你好世界") != 8 {
            return "「你好世界」该是 8 宽，实际 \(widthUnits("你好世界"))"
        }
        if widthUnits("hello wo") != 8 {
            return "「hello wo」该是 8 宽，实际 \(widthUnits("hello wo"))"
        }
        if widthUnits("你好世界") <= widthUnits("hello") {
            return "4 个汉字该比 hello 宽"
        }

        // ①.5 🚨 **非 ASCII 的窄字符也要算 1**（法语/西班牙语/俄语/阿拉伯语）
        let narrow = ["cafe\u{0301}", "caf\u{00e9}", "espa\u{00f1}ol",
                      "\u{00fc}ber", "\u{041f}\u{0440}\u{0438}\u{0432}\u{0435}\u{0442}",
                      "\u{03b1}\u{03b2}\u{03b3}",
                      "\u{0645}\u{0631}\u{062d}\u{0628}\u{0627}"]
        for t in narrow {
            if widthUnits(t) != t.utf16.count {
                return "「\(t)」每个字符该算 1 宽，实际 \(widthUnits(t)) / \(t.utf16.count)"
            }
        }
        for t in ["\u{4e2d}", "\u{3042}", "\u{ac00}", "\u{ff01}"] {
            if widthUnits(t) != 2 {
                return "「\(t)」该算 2 宽，实际 \(widthUnits(t))"
            }
        }

        // ② 越长字号越小（单调不增）
        var s = ""
        var prev = CGFloat.greatestFiniteMagnitude
        for i in 0..<300 {
            s += "a"
            let sz = size(s)
            if sz > prev { return "字号在第 \(i) 个字符处变大了：\(prev) -> \(sz)" }
            prev = sz
        }
        if prev != minSize { return "300 个字符该落到最小档 \(minSize)，实际 \(prev)" }

        // ③ 分界点两侧 —— 专抓 `<` 写成 `<=` 那种差一位的错
        if size(String(repeating: "a", count: 24)) != 56 { return "24 宽该是 56" }
        if size(String(repeating: "a", count: 25)) != 42 { return "25 宽该掉到 42" }
        if size(String(repeating: "a", count: 60)) != 42 { return "60 宽该是 42" }
        if size(String(repeating: "a", count: 61)) != 32 { return "61 宽该掉到 32" }

        // ④ 空 / nil 不崩，且给最大字号
        if size("") != 56 { return "空串该给最大字号" }
        if size(nil) != 56 { return "nil 该给最大字号（不崩）" }

        return nil
    }
}
