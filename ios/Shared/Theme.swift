import UIKit

/// 配色的**单一配置点**（跟安卓 `Theme.java` 一一对应，两端同一套色值）。
///
/// 🚨 Kevin 2026-08-21：「UI 过于丑了（黑色底配蓝色选中框）」。
///    重做方向：不用纯黑+高饱和蓝，改深炭灰三层递进 + 低饱和青蓝强调色。
///    颜色只在这里定义，别在各处再写 UIColor(red:...) —— 要改一次改完。
enum Theme {
    /// 半透明色：`a` 是 0–255 的不透明度。
    /// 🚨 键盘按键 2026-08-22 改成半透明玻璃，色值带 alpha，
    ///    用原来那个 hex() 会把 alpha 丢掉、变成实心块。
    private static func hexA(_ v: UInt32, _ a: UInt32) -> UIColor {
        hex(v).withAlphaComponent(CGFloat(a) / 255)
    }

    private static func hex(_ v: UInt32) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    // 🚨🚨 色值 2026-08-22 换成**紫色变体 A**（Kevin 从四版里圈的那个），
    //    来源不是我调的，是从可灵参考图上量出来的
    //    （`D:\_build\sample_ref.py`，取样点先画图确认过再信数字）。
    //    三条规则照旧，别自由发挥：
    //      ① 选中态不是强调色，只是更亮一档（keyDown vs key）
    //      ② 同一排 chip 全部同色
    //      ③ **强调色整屏只出现一处**（麦克风）
    // <<<PALETTE-GEN>>>
    // 🚨🚨 下面这段是**从安卓 `Theme.java` 生成的**（`D:\_build\sync_theme_ios.py`），
    //    不要手改 —— 改配色请改安卓那边的单一配置点，再跑一次同步脚本。
    //    以前这里靠注释写「跟安卓逐条对齐」来维持，那等于有第二配置点，迟早走散。
    static let bg = hex(0x141033)   // 安卓 BG
    static let bgTop = hex(0x0B1230)   // 安卓 BG_TOP
    static let bgBot = hex(0x231843)   // 安卓 BG_BOT
    static let panel = hexA(0xFFFFFF, 0x14)   // 安卓 PANEL = #14FFFFFF
    static let key = hexA(0xFFFFFF, 0x16)   // 安卓 KEY = #16FFFFFF
    static let keyDown = hexA(0xFFFFFF, 0x38)   // 安卓 KEY_DN = #38FFFFFF
    static let text = hex(0xF2EFFA)   // 安卓 TEXT
    static let dim = hex(0xA79FC0)   // 安卓 DIM
    static let accent = hex(0x7C5CE6)   // 安卓 ACCENT
    static let accentDown = hex(0x5F41B8)   // 安卓 ACCENT_DN
    static let danger = hex(0xA8456B)   // 安卓 DANGER
    // <<<PALETTE-END>>>

    /// 键盘/页面的底：**线性渐变 + 一枚径向柔光**，跟安卓 `Theme.keyboardBg()` 同构。
    ///
    /// 🚨 只有线性的话上下色差被压得很小，肉眼看不出渐变 ——
    ///    半透明按键透上来的就是一片均匀的紫，等于白做。
    ///    加径向之后同一排按键从左到右有明暗差，"透"才看得出来。
    /// 🚨 返回的是 CALayer，调用方要在 `layoutSubviews` 里更新 frame，
    ///    否则转屏/键盘高度变化时渐变不跟着走（那种 bug 只在真机转屏才看得见）。
    static func keyboardBackground(_ bounds: CGRect) -> CALayer {
        let root = CALayer()
        root.frame = bounds

        let lin = CAGradientLayer()
        lin.frame = bounds
        lin.colors = [bgTop.cgColor, bg.cgColor, bgBot.cgColor]
        lin.locations = [0, 0.5, 1]
        lin.startPoint = CGPoint(x: 0.5, y: 0)
        lin.endPoint = CGPoint(x: 0.5, y: 1)
        root.addSublayer(lin)

        let glow = CAGradientLayer()
        glow.type = .radial
        glow.frame = bounds
        glow.colors = [UIColor(white: 1, alpha: 0.15).cgColor,
                       UIColor(white: 1, alpha: 0).cgColor]
        glow.startPoint = CGPoint(x: 0.28, y: 0.18)
        glow.endPoint = CGPoint(x: 1.15, y: 1.05)
        root.addSublayer(glow)
        return root
    }

    /// 待命态的麦克风图形 —— **就是 App 图标 G3 里那一个**（Assets 里的 `mic`）。
    /// 🚨 Kevin 2026-08-21：「小麦克风有点太卡通了…直接拿 T icon 下面那个麦克风用，
    ///    保持 App 的 UI 和 Icon 风格一致」。所以不用 emoji 🎤，用抠出来的原件。
    // 🚨 间距/圆角跟安卓 Theme.java 的 PAD/GAP/R_KEY/R_CARD 一一对应。
    //    Kevin 2026-08-21：「它这个看起来挺舒服的，不会那么拥挤。你那里太拥挤了」。
    static let pad: CGFloat = 18
    static let gap: CGFloat = 12
    static let rKey: CGFloat = 12
    static let rCard: CGFloat = 16

    /// 给控件加投影 + 一圈微亮上缘。
    /// 🚨 Kevin：「它的每一个都有一个小阴影，显得有立体感，更 high class」。
    ///    只有阴影没有那道边会显得"浮着"，两者一起才是那个质感。
    ///    iOS 这边不像安卓要操心父容器裁剪，但 `clipsToBounds` 打开会一样把阴影切掉。
    static func elevate(_ v: UIView, _ elev: CGFloat = 3, rim: Bool = true) {
        v.clipsToBounds = false
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.55
        v.layer.shadowRadius = elev
        v.layer.shadowOffset = CGSize(width: 0, height: elev * 0.6)
        if rim {
            v.layer.borderWidth = 1
            v.layer.borderColor = UIColor(white: 1, alpha: 0.08).cgColor
        }
    }

    /// 说话键的直径。
    /// 🚨 Kevin 2026-08-21 改过两次，以**最后这次**为准：先是「不要搞成圆圈嘛，
    ///    又很长、很占位置…参考 Typeless 做成长方框」，后来把那行说明删掉之后又说
    ///    「不需要留长了，还是用回原来那个圆圈的形状，这样整个输入法都显得干净一点」。
    ///    当初改长条的前提（说明行占着一整行、圆圈会被底排压住）已经不成立。
    static let micBarHeight: CGFloat = 76

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

    /// 朗读键的小喇叭 —— **自己画的单色图形**，不是 emoji。
    ///
    /// 🚨 Kevin 2026-08-22：「那个朗读的小图标（小喇叭）跟这个紫色色调有点冲」。
    ///    🔊 是彩色 emoji，由系统 emoji 字体渲染，`tintColor` 管不到它，
    ///    在任何主题下都是那块蓝+橙。安卓当天换成了 PNG 图标；
    ///    iOS 这边不加资源（要动 Assets.xcassets 和推送清单，
    ///    任一处漏了都是静默失败，而这台机器验不了 iOS），改成直接画。
    ///    形状跟安卓那个 ic_speak 一致：方块箱体 + 梯形 + 两道弧。
    static func speakGlyph(_ size: CGFloat) -> UIImage {
        let r = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
        return r.image { _ in
            UIColor.white.setFill()
            UIColor.white.setStroke()
            let s = size
            let body = UIBezierPath()
            body.move(to: CGPoint(x: s * 0.13, y: s * 0.38))
            body.addLine(to: CGPoint(x: s * 0.34, y: s * 0.38))
            body.addLine(to: CGPoint(x: s * 0.55, y: s * 0.20))
            body.addLine(to: CGPoint(x: s * 0.55, y: s * 0.80))
            body.addLine(to: CGPoint(x: s * 0.34, y: s * 0.62))
            body.addLine(to: CGPoint(x: s * 0.13, y: s * 0.62))
            body.close()
            body.fill()
            let lw = max(1.2, s * 0.055)
            for rr in [s * 0.20, s * 0.31] {
                let arc = UIBezierPath(
                    arcCenter: CGPoint(x: s * 0.55, y: s * 0.50),
                    radius: rr, startAngle: -.pi / 3, endAngle: .pi / 3,
                    clockwise: true)
                arc.lineWidth = lw
                arc.lineCapStyle = .round
                arc.stroke()
            }
        }.withRenderingMode(.alwaysTemplate)
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


// MARK: - 波形图标（「回语音」那个键）

extension Theme {
    /// 键盘候选栏左上角那个**波形**图标。照抄安卓 `WaveIcon.java`。
    ///
    /// 🚨 不用喇叭、不写字（Kevin 2026-08-23：「语音也不要用这个喇叭，
    ///    很丑，太 low 了…Typeless 的语音符号是个波浪形的符号。不需要写字」）。
    /// 🚨 一个图标同时取代「返回」和「语音」两个键 ——
    ///    他说「点返回和点语音都是回到同一个地方，重复了」。
    static func waveIcon(color: UIColor,
                         barW: CGFloat = 2.5, gap: CGFloat = 2.5,
                         size: CGSize = CGSize(width: 26, height: 18))
        -> UIImage {
        // 六根竖条的相对高度（0~1），中间高两边低 —— 就是"说话"那个形状
        let hs: [CGFloat] = [0.22, 0.62, 1.00, 0.74, 0.42, 0.22]
        let r = UIGraphicsImageRenderer(size: size)
        return r.image { ctx in
            color.setFill()
            let total = CGFloat(hs.count) * barW
                + CGFloat(hs.count - 1) * gap
            var x = (size.width - total) / 2
            let cy = size.height / 2
            for h in hs {
                let half = size.height * h / 2
                let rect = CGRect(x: x, y: cy - half,
                                  width: barW, height: half * 2)
                UIBezierPath(roundedRect: rect, cornerRadius: barW / 2).fill()
                x += barW + gap
            }
        }.withRenderingMode(.alwaysOriginal)
    }
}
