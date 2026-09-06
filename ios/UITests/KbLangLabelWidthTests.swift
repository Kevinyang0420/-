import XCTest

/// **键盘那颗语言 chip 换成「中文 → English」形态，宽度放不放得下。**
///
/// 2.1 09-07 判：iOS 键盘只显示 `English ▾`，安卓键盘是 `中文 → English ▾`
/// （`VoiceImeService:1673 dirLabel()`，口径是 2.1 08-28 定的），
/// **有现成答案就照抄，不新设计**。
/// 但他自己也说了：方向标签比现状长得多，**先量再判**。
///
/// 🚨 **这一条只出数，不改 UI。** 量完给 2.1：
///    · 都放得下 → 直接抄（照抄已有形态不算设计）
///    · 有溢出   → 那是版面取舍，他拿数据去送 Grok
///
/// 🚨 量的是**排版宽度**（`NSString.size(withAttributes:)`），不是字符数。
///    字符数在中日文和德文之间完全没有可比性 —— 「中文」两个字比
///    `Chinesisch` 十个字母还窄。**数字符会得出完全相反的结论。**
final class KbLangLabelWidthTests: XCTestCase {

    /// 键盘那颗 chip 的字号（`KeyboardViewController` 里 langButton 用的）。
    private let font = UIFont.systemFont(ofSize: 14)

    private func w(_ s: String) -> CGFloat {
        return ceil((s as NSString).size(withAttributes: [.font: font]).width)
    }

    /// 🚨 **方向标签的宽度跟界面语言无关** —— 表里存的就是各语言的**自称**
    ///    （`GenLangs.langs` 的 `label`），中文永远显示「中文」、德语永远
    ///    `Deutsch`，不随界面语言变。所以量的是**全部语言两两组合的最坏值**，
    ///    比只量 7 门界面语言更有说服力。
    /// 🚨 直接读 `GenLangs`，**不手抄一份** —— 手抄的语言表这摊活栽过。
    func testMeasureDirectionLabelWidth() {
        let all = GenLangs.langs
        XCTAssertFalse(all.isEmpty, "🚨 语言表是空的")

        // 现状：只有目标语言名 + ▾
        var nowMax: (String, CGFloat) = ("", 0)
        for l in all {
            let t = l.label + " ▾"
            if w(t) > nowMax.1 { nowMax = (t, w(t)) }
        }
        // 提议：源 → 目标 + ▾（照抄安卓 dirLabel 的形态）
        var dirMax: (String, CGFloat) = ("", 0)
        for a in all {
            for b in all where a.code != b.code {
                let t = a.label + " → " + b.label + " ▾"
                let x = w(t)
                if x > dirMax.1 { dirMax = (t, x) }
            }
        }
        // 中文用户最常见的那一组，单列 —— 最坏值是理论上限，
        // 而他实际每天看到的是这一条。
        let zh = all.first { $0.code == "zh" }?.label ?? "中文"
        let en = all.first { $0.code == "en" }?.label ?? "English"
        let common = zh + " → " + en + " ▾"

        let half = UIScreen.main.bounds.width / 2
        var lines: [String] = []
        lines.append(String(format: "现状最宽    %5.0f pt   %@", nowMax.1, nowMax.0))
        lines.append(String(format: "方向最宽    %5.0f pt   %@", dirMax.1, dirMax.0))
        lines.append(String(format: "常见一组    %5.0f pt   %@", w(common), common))
        lines.append(String(format: "倍数（最坏）%.2fx",
                            dirMax.1 / max(nowMax.1, 1)))
        lines.append(String(format: "倍数（常见）%.2fx",
                            w(common) / max(nowMax.1, 1)))
        lines.append(String(format: "参考线 屏宽一半 %.0f pt", half))
        lines.append("🚨 参考线不是真实可用宽度：那一行还有「翻译/转写」两个档位钮"
                     + "和一个图标，chip 只分到剩下的。**我只出数，放不放得下由版面定。**")
        let report = lines.joined(separator: "\n")

        let a = XCTAttachment(string: report)
        a.name = "键盘语言标签宽度"
        a.lifetime = .keepAlways
        add(a)
        for l in lines { print("KBWIDTH " + l) }

        // 唯一的硬断言：量到了东西。**不断言放得下** —— 那是版面的事。
        XCTAssertGreaterThan(dirMax.1, nowMax.1,
                             "🚨 方向标签不可能比现状还窄 —— 量错了")
    }
}
