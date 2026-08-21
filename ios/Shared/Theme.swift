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

    static let bg      = hex(0x15181D)   // 最外层底
    static let panel   = hex(0x1E232B)   // 卡片/面板
    static let key     = hex(0x2A313B)   // 按键
    static let keyDown = hex(0x3A424E)

    static let text    = hex(0xECEFF4)
    static let dim     = hex(0x8A94A3)
    static let accent  = hex(0x4FA6C7)   // 低饱和青蓝
    static let danger  = hex(0xC9615C)   // 录音中（不刺眼的砖红）

    /// 待命态的麦克风图形 —— **就是 App 图标 G3 里那一个**（Assets 里的 `mic`）。
    /// 🚨 Kevin 2026-08-21：「小麦克风有点太卡通了…直接拿 T icon 下面那个麦克风用，
    ///    保持 App 的 UI 和 Icon 风格一致」。所以不用 emoji 🎤，用抠出来的原件。
    /// `size` 传按钮边长，图形占 60%（麦克风是竖长条，52% 时视觉上偏细）。
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
    /// 🚨 原来用 emoji「■」，在 120pt 的按钮里只占 ~20%，Kevin 说「太小了」。
    ///    改成自己画：边长 = 按钮的 40%，微圆角。
    static func stopGlyph(_ size: CGFloat) -> UIImage {
        let side = size * 0.40
        let r = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return r.image { ctx in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side),
                         cornerRadius: side * 0.12).fill()
            _ = ctx
        }.withRenderingMode(.alwaysOriginal)
    }
}
