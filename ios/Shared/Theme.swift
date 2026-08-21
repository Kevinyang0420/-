import UIKit

/// 配色的**单一配置点**（跟安卓 `Theme.java` 一一对应，两端同一套色值）。
///
/// 🚨 Kevin 2026-08-21：「UI 过于丑了（黑色底配蓝色选中框）」。
///    重做方向：不用纯黑+高饱和蓝，改深炭灰三层递进 + 低饱和青蓝强调色。
///    颜色只在这里定义，别在各处再写 UIColor(red:...) —— 要改一次改完。
enum Theme {
    private static func hex(_ v: UInt32) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    // 🚨🚨 跟安卓 Theme.java 逐条对齐，色值**取自 Grok 的 G1 设计稿**
    //    （D:\_build\sample_grok_palette.py）。三条规则照做，别自由发挥：
    //      ① 选中态不是强调色，只是更浅一档的灰（keyDown vs key）
    //      ② 同一排 chip 全部同色
    //      ③ 青色整屏只出现一处（说话长条）
    static let bg      = hex(0x18181C)   // 最外层底
    static let panel   = hex(0x202428)   // 卡片/面板
    // 🚨 Kevin 2026-08-21：「灰色药丸再加深一点，现在不是很分得清楚」。
    //    未选压暗、选中提亮，相对亮度差从 20 拉到 45（安卓侧 build_apk.py 有闸门守着）。
    static let key     = hex(0x1B1E25)   // 按键 / chip 未选 / Tab 轨道
    static let keyDown = hex(0x454B57)   // 按下 / **选中态**

    static let text    = hex(0xECEFF4)
    static let dim     = hex(0x8A94A3)
    /// 唯一的强调色，只许用在说话长条上。
    static let accent  = hex(0x486C78)
    static let danger  = hex(0x8C4A46)   // 录音中（同样压暗，跟 G1 一个调子）

    /// 待命态的麦克风图形 —— **就是 App 图标 G3 里那一个**（Assets 里的 `mic`）。
    /// 🚨 Kevin 2026-08-21：「小麦克风有点太卡通了…直接拿 T icon 下面那个麦克风用，
    ///    保持 App 的 UI 和 Icon 风格一致」。所以不用 emoji 🎤，用抠出来的原件。
    /// 说话键的高度。🚨 Kevin 2026-08-21：说话键改成 Typeless 那样的**长条**，
    /// 不是圆圈（「又很长、很占位置」）。圆圈 120pt 见方，长条只要 54。
    static let micBarHeight: CGFloat = 54

    /// `size` 传图形框边长，麦克风占 60%（它是竖长条，52% 时视觉上偏细）。
    static func micGlyph(_ size: CGFloat) -> UIImage? {
        guard let src = UIImage(named: "mic") else { return nil }
        let side = size * 0.60
        let r = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        let img = r.image { _ in
            src.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        return img.withRenderingMode(.alwaysTemplate)
    }

    /// 录音态的停止方块。
    /// 🚨 原来用 emoji「■」，在按钮里只占 ~20%，Kevin 说「太小了」。
    ///    改成自己画。size 传图形框边长，方块占它的 2/3（≈长条高的 40%）。
    static func stopGlyph(_ size: CGFloat) -> UIImage {
        let side = size * 0.67
        let r = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return r.image { ctx in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side),
                         cornerRadius: side * 0.12).fill()
            _ = ctx
        }.withRenderingMode(.alwaysOriginal)
    }
}
