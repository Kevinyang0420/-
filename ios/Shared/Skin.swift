// 🚨🚨 这个文件是**生成的**，别手改。
//    改配色/排版请改安卓的 Skin.java，然后跑：
//        py D:\_build\sync_skin_ios.py
//
//    为什么是生成的：Kevin 2026-08-25 说「怎么还是黑色底的呢」——
//    iOS 主 App 一直直接刷键盘的底色，而安卓早换成三段渐变了。
//    键盘那 11 个色值没漂，因为它有生成器；主 App 这套漂了，
//    因为它只有一句「注释说要同步」。**注释挡不住走散。**

import UIKit

enum Skin {

    // ---- 颜色（从 Skin.java 生成，AARRGGBB）----
    /// Skin.java BG_1 = 0xFF0F1B4F
    static let bg1 = UIColor(red: 0x0F/255.0, green: 0x1B/255.0,
                           blue: 0x4F/255.0, alpha: 0xFF/255.0)
    /// Skin.java BG_2 = 0xFF2A1358
    static let bg2 = UIColor(red: 0x2A/255.0, green: 0x13/255.0,
                           blue: 0x58/255.0, alpha: 0xFF/255.0)
    /// Skin.java BG_3 = 0xFF431661
    static let bg3 = UIColor(red: 0x43/255.0, green: 0x16/255.0,
                           blue: 0x61/255.0, alpha: 0xFF/255.0)
    /// Skin.java ACCENT = 0xFF8B5CF6
    static let accent = UIColor(red: 0x8B/255.0, green: 0x5C/255.0,
                           blue: 0xF6/255.0, alpha: 0xFF/255.0)
    /// Skin.java ACCENT_2 = 0xFF6D3FB0
    static let accent2 = UIColor(red: 0x6D/255.0, green: 0x3F/255.0,
                           blue: 0xB0/255.0, alpha: 0xFF/255.0)
    /// Skin.java ACCENT_HI = 0xFFB98BE8
    static let accentHi = UIColor(red: 0xB9/255.0, green: 0x8B/255.0,
                           blue: 0xE8/255.0, alpha: 0xFF/255.0)
    /// Skin.java TEXT = 0xFFF4F1FB
    static let text = UIColor(red: 0xF4/255.0, green: 0xF1/255.0,
                           blue: 0xFB/255.0, alpha: 0xFF/255.0)
    /// Skin.java DIM = 0xFFA99DC6
    static let dim = UIColor(red: 0xA9/255.0, green: 0x9D/255.0,
                           blue: 0xC6/255.0, alpha: 0xFF/255.0)
    /// Skin.java OK = 0xFF6EE7B7
    static let ok = UIColor(red: 0x6E/255.0, green: 0xE7/255.0,
                           blue: 0xB7/255.0, alpha: 0xFF/255.0)
    /// Skin.java SLOGAN_ZH_COLOR = 0xFFD4CDE8
    static let sloganZh = UIColor(red: 0xD4/255.0, green: 0xCD/255.0,
                           blue: 0xE8/255.0, alpha: 0xFF/255.0)

    // ---- 排版（sp 与 pt 按 1:1）----
    /// Skin.java BRAND_SP = 28f
    static let brandSize: CGFloat = 28
    /// Skin.java SLOGAN_ZH_SP = 14f
    static let sloganZhSize: CGFloat = 14
    /// Skin.java SLOGAN_EN_SP = 11f
    static let sloganEnSize: CGFloat = 11

    // ---- 字距：安卓是 em 的倍数，iOS kerning 是绝对点数 ----
    /// BRAND_TRACK(0.03) × BRAND_SP(28) = 0.84 pt
    static let brandKern: CGFloat = 0.84
    /// SLOGAN_ZH_TRACK(0.06) × SLOGAN_ZH_SP(14) = 0.84 pt
    static let sloganZhKern: CGFloat = 0.84
    /// SLOGAN_EN_TRACK(0.12) × SLOGAN_EN_SP(11) = 1.32 pt
    static let sloganEnKern: CGFloat = 1.32

    // ---- 主界面背景：三段渐变（对应安卓 Skin.screenBg）----
    /// 🚨 iOS 主 App 原来直接刷 Theme.bg（键盘底色），
    ///    那正是他看到的「黑色底」。这里换成跟安卓同一套渐变。
    static func screenBg(_ bounds: CGRect) -> CAGradientLayer {
        let g = CAGradientLayer()
        g.frame = bounds
        g.colors = [bg1.cgColor, bg2.cgColor, bg3.cgColor]
        g.locations = [0.0, 0.55, 1.0]
        g.startPoint = CGPoint(x: 0.5, y: 0.0)
        g.endPoint = CGPoint(x: 0.5, y: 1.0)
        return g
    }
}


// MARK: - 说明性文字的颜色

extension Skin {
    /// 说明性文字（设置页副标题、英文 slogan、引导页说明）。
    ///
    /// 🚨 **不直接改 `Skin.dim`**：那是全局色，键盘、诊断页、一堆地方都在用，
    ///    动它等于一次改几十处且都没验过。这里只给"说明性文字"用。
    ///    Grok 评审：「设置页副标题对比度过低（尤其在深色紫底上），可读性边缘」。
    ///    Kevin 2026-08-25 看过对比图：「看着差不多，那就直接用他的改了吧」。
    static let sub = UIColor(red: 0xC3 / 255.0, green: 0xBD / 255.0,
                             blue: 0xD6 / 255.0, alpha: 1)
}
