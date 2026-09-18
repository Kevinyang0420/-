import Foundation
import UIKit

/// 繁体候选区该用的字体 —— **港式字形**，不是系统默认那套。
///
/// 规格：`_规格_速成输入法调研_20260918.md`§4.3。
///
/// 🚨 存在的理由：`CandidateBar.swift` 现在全是 `.systemFont(ofSize:)`，
///    不带任何字体/语言标记，香港用户和台湾用户看到的候选字**用的是同一套字形**——
///    而 iOS 的汉字统一（Han unification）在没有显式指定的情况下，哪种地区的写法
///    胜出取决于系统当前的字体级联，不受 App 自己声明的语言偏好控制。
///
/// ✅✅ **09-18 已在真机验证**（2.1 给的线索）：`PingFang HK` 和 `PingFang TC`
///    是苹果系统里**两个真实存在、彼此独立**的字体家族（`fontNames(forFamilyName:)`
///    各自能拿到 6 个字重：Regular/Ultralight/Thin/Light/Medium/Semibold），
///    抽样 16 个常用字用 `CTFontGetGlyphsForCharacters` 比对，**5 个字拿到不同的
///    glyph ID**——不是同一张字形表的两个别名，是真的会画出不同的字。
///    这条验证了「指定这个字体大概率就是缺的那一步」——**显式指定是有意义的**，
///    不是空操作。
///
/// 🚨 **这只是候选区将来接上时用的工具函数，现在还没有任何调用点**——
///    跟 `EavesdropConsent`/`EavesdropTranscript` 一样先把可验证的那一小块做实。
///    ① 速成候选区（`_规格_速成输入法调研_20260918.md`）UI 还没做，做的时候接。
///    ② **现有 `CandidateBar.swift` 的拼音/五笔候选栏还没有改**——那是已经上线的
///       功能，繁体候选是不是也该换成港式字形是产品决定，不是这条注释能替 2.1 拍板的，
///       改之前要单独确认，不能顺手带过去。
enum HantFont {

    /// 字体家族名固定为 `PingFang HK`——**别写死具体字重的 PostScript 名**，
    /// 那样每加一个新字重就要维护一遍映射表；用 `UIFontDescriptor` 做的话，
    /// 系统会自己在这个家族里挑最接近的字重。
    private static let familyName = "PingFang HK"

    /// 拿港式字形的字体；**这个家族在当前系统上不存在就退回默认系统字体**——
    /// 防御性写法，不是预期会触发（`PingFang HK` iOS 9 起就是内建字体），
    /// 但字体资源理论上可能因为系统版本/设备而缺失，缺失时候选区不能整个画不出字。
    static func font(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let desc = UIFontDescriptor(fontAttributes: [
            .family: familyName,
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        let f = UIFont(descriptor: desc, size: size)
        // 🚨 系统找不到这个家族时，`UIFont(descriptor:size:)` 不会返回 nil——
        //    它会退到某个默认字体，但那个默认字体的家族名不会是 `PingFang HK` 系列。
        //    用这个当"没找到"的判据，而不是判 nil。
        guard f.familyName.hasPrefix("PingFang HK") else {
            return .systemFont(ofSize: size, weight: weight)
        }
        return f
    }

    // ------------------------------------------------------------ 自测

    /// 由 `gate_all_selftests.py` 自动发现并运行。
    ///
    /// 🚨 这个自测**在真机/模拟器上跑才有意义**（`PingFang HK` 是否存在是系统资源，
    ///    Mac 上的独立 harness 不一定装了 iOS 系统字体）——照 `EavesdropTranscript`
    ///    那次的教训，这条只保证"逻辑没崩"，不保证"这台机器上真的有这个字体"。
    static func selfTest() -> String? {
        var bad: [String] = []
        let f = font(ofSize: 24)
        // ① 拿到的字体大小必须是要求的那个——退回默认字体时也一样，不该跑偏
        if abs(f.pointSize - 24) > 0.01 {
            bad.append("字号不对 -> \(f.pointSize)")
        }
        // ② 家族名只能是「PingFang HK 系列」或「系统默认」这两种可能，不该是别的东西
        if !f.familyName.hasPrefix("PingFang HK") && !f.familyName.contains("SF") {
            bad.append("退回字体不是预期里的任何一种 -> \(f.familyName)")
        }
        return bad.isEmpty ? nil : bad.joined(separator: "; ")
    }
}
