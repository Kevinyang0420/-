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
}
