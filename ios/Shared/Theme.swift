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
    /// **渐变紫**（Kevin 2026-09-04：「iOS 输入法中，麦克风底色及翻译、工作等 tab 的
    /// 紫色不够渐变，需调整为渐变紫色」）。
    ///
    /// 🚨 **用现有的两个紫，不新造色值**（他说过「不要自己设计…你审美我不放心」）：
    ///    上 `accent` `#7C5CE6` → 下 `accentDown` `#5F41B8`，都是 Skin/Theme 里已有的。
    /// 🚨 做成**可拉伸的 1×64 竖向渐变图**，用 `setBackgroundImage` 铺 —— 不用
    ///    `CAGradientLayer`：那要手动跟着 frame 变，按钮一改尺寸就露馅；
    ///    resizable image 由 UIKit 自己拉伸，任何尺寸都对。
    /// 🚨 **单一配置点**：所有紫色块都从这儿取，别在各处各画一个渐变。
    static let purpleGrad: UIImage? = {
        let h: CGFloat = 64
        let r = UIGraphicsImageRenderer(size: CGSize(width: 1, height: h))
        let img = r.image { ctx in
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let g = CGGradient(colorsSpace: cs,
                                     colors: [accent.cgColor,
                                              accentDown.cgColor] as CFArray,
                                     locations: [0, 1]) else { return }
            ctx.cgContext.drawLinearGradient(
                g, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: h),
                options: [])
        }
        return img.resizableImage(withCapInsets: .zero, resizingMode: .stretch)
    }()

    /// 说话记录/详情里**按档位给译文上色**（2.1 定，Kevin 09-03 看图点头）。
    /// 🚨 跟安卓一致：结构化英文 = `Skin.OK`，整理中文 = `Skin.ACCENT_HI`。别另挑色。
    static let modeEnGreen = hex(0x6EE7B7)   // 结构化英文档
    static let modeZhPurple = hex(0xB98BE8)  // 整理中文档
    // <<<PALETTE-END>>>

    // ─────────────────────────────────────────────────────────────
    // 🚨🚨 以下是 **iOS 专用、不进安卓同步** 的键盘配色层。
    //    必须放在 `<<<PALETTE-END>>>` **之后** —— 上面那段是
    //    `D:\_build\sync_theme_ios.py` 从安卓 `Theme.java` 生成的，
    //    写在里面下次同步就被覆盖掉（09-03 我就这么放错过一次）。
    // ─────────────────────────────────────────────────────────────

    /// **系统「下巴」的实测色（浅色宿主）**。
    /// 🚨 2026-09-03 从 Kevin 真机截图逐像素量的：#D0D3DA。
    ///    早先写的 #1B1B1D 是在**模拟器**上量**系统自带键盘**得的，量错了对象。
    /// 🚨 这条带子公开接口改不了，跟**宿主 App 的外观**走
    ///    （Kevin：Typeless、腾讯输入法都一样，苹果的限制）。
    static let chinLight = hex(0xD0D3DA)

    /// 深色宿主下的下巴色。🚨 **这个还没实测**，按 iOS 深色键盘常见带估的。
    ///    拿到深色宿主截图后用同一套量法换掉，结构不用动。
    static let chinDark = hex(0x2C2C2E)

    /// 下巴上系统自己那两个图标的颜色（地球、麦克风），从截图量的：
    /// 地球最暗 100 像素均值 (70,75,81)、麦克风 (73,77,83) → #464B51。
    static let chinGlyph = hex(0x464B51)

    // MARK: - 浅紫雾面（Kevin 2026-09-03 选的，Grok 方案二）
    //
    // 🚨 **编号有两套，别再搞混**：他说的「方案三」＝我发给他的对比图里**第三张**，
    //    也就是 Grok 正文里的「方案 2 浅紫雾面」。我第一版按 Grok 的编号做了他的
    //    方案 3（浅色宿主纯灰平涂），被他当场更正。以后给他编号一律用图上那个号。
    //
    // Grok 对前几版的诊断（他的原话「这三个都很丑」的成因）：
    //   丑的**是结构不是某一档 hex** ——「上半深紫 + 下半浅键」是两套语言
    //   挤在 250pt 里，看着像主题褪色。所以要**选边**：浅色宿主整面就是浅的，
    //   起点就浅，没有从 #0B1230 泄下来的脏渐变。
    // 跟纯灰那版的差别：面板带一点品牌色相（很淡的冷紫雾），紫身份还在。

    /// 当前宿主是不是浅色外观。**由键盘在 `viewDidLoad` / 外观变化时写入**。
    /// 🚨 不要在这里自己去读 `UIScreen.main.traitCollection` ——
    ///    键盘要的是**宿主 App**（微信）的外观，不是系统设置。
    static var hostIsLight = false

    static var chin: UIColor { hostIsLight ? chinLight : chinDark }

    /// 普通按键（两行功能键）的填充。
    static var kbKey: UIColor { hostIsLight ? hex(0xFFFFFF) : key }
    /// 普通按键上的字。浅色 #1C1C1E on #FFFFFF = 17.01:1。
    static var kbKeyText: UIColor { hostIsLight ? hex(0x1C1C1E) : text }
    /// 底排三个键（打字/朗读/删除）的填充。
    /// 浅色下比白键略紫一点，仍是浅色家族；深色下用实色，别叠半透明白
    /// （叠出来跟面板糊在一起）。
    static var kbBottomKey: UIColor {
        hostIsLight ? hex(0xC9C4DC) : hex(0x3A3650)
    }
    /// 底排的字/图标。浅色 #1C1C1E on #C9C4DC = 10.06:1；深色 #EBEBF5 on #3A3650 ≈ 9:1。
    static var kbBottomText: UIColor { hostIsLight ? hex(0x1C1C1E) : text }
    /// 提示文字。🚨 浅色下**不要**用系统灰 #6E6E73（压在 #D0D3DA 上只有 4.06，不过线），
    ///    也不要用浅紫灰 #6B6578（压在 #E4E0F2 上只有 4.32，同样不过）。
    ///    直接复用下巴图标色 #464B51（5.87–6.08），跟系统的地球/麦克风同一级，
    ///    接缝两侧的文字也就统一了。
    static var kbHint: UIColor { hostIsLight ? chinGlyph : dim }
    /// 按下态。
    static var kbKeyDown: UIColor { hostIsLight ? hex(0xC0BBD4) : keyDown }

    // MARK: - 手写板（Kevin 2026-09-03：「手写也不要黑色啦，用白色底就好了」）
    //
    // 🚨🚨 这三个色只管**用户看到的画布**。
    //    **喂给模型的那张 96×96 是另外渲染的**（`HandwritePad` 里那个
    //    `UIGraphicsImageRenderer` 自己 fill 黑底、笔色 `modelInk = 160/255`），
    //    跟这里完全无关。那条「纯白会让准确率从 95% 掉到 28%」的实测
    //    管的是模型那张图 —— **别把它套到这三个色上**，也别为了"一致"
    //    去把模型那张图改成白底。

    /// **重试角标的琥珀色**（角标那个圆的**填充**）。🚨 Kevin 09-03 指定 `#F0B429`，
    /// **不用红** —— 红是"出错了"，琥珀是"等你一下"。这不是我挑的色，别改成 `danger`。
    static let amber = hex(0xF0B429)

    /// 角标里那个 `!` 的颜色。🚨 **深墨不是白**（2026-09-03 Kevin 骂"看不清"后按对比度改）：
    /// 白 `!` 压琥珀填充只有 **1.86:1**（实测），深墨压琥珀 **9.13:1**。填充色是固定的
    /// 琥珀，所以这里不随宿主变。
    static let amberInk = hex(0x1C1C1E)

    /// 「没传上去·再点一下」那行**提示字**的颜色。
    /// 🚨🚨 **不能用 `amber` 当字色**（2026-09-03 Kevin 原话「黄色的字根本看不清」）：
    ///    琥珀字压**浅色宿主**键盘底（`kbPanel` 浅=`#F4F2FA`）只有 **1.68:1**，废。
    ///    深色宿主保持 `#F0B429`（压深底 9.78:1）。**改前后都量过，不是拍脑袋。**
    /// 🚨🚨 第一版用 `#A15C00`（隔离 4.68）**还是被骂看不清** —— 抽真机渲染像素量：
    ///    只有 **3.59:1**。两个原因：真实背景是更浅的 `#E3E3EA`（不是我以为的 kbPanel），
    ///    小字抗锯齿又把笔画调淡。**这就是"只信 hex 号会骗人、必须量渲染后的像素"。**
    ///    改用 `#6B3F00`（隔离 7.04），留足抗锯齿余量，渲染后才稳过 4.5。仍是暖琥珀棕。
    static var kbHintWarn: UIColor { hostIsLight ? hex(0x6B3F00) : amber }

    /// **shift 大写锁定态**的底和箭头。
    /// 🚨 浅色宿主下普通键就是 `#FFFFFF`，所以锁定态**不能也用白底** ——
    ///    那样三态里有两态长得一样，他看不出大写锁没锁。
    ///    浅色用近黑底白箭头（跟白色普通键、紫色 shift 态都拉开）；
    ///    深色沿用原来的白底紫箭头（那边普通键是半透明白，白底本来就够显眼）。
    static var kbShiftLock: UIColor { hostIsLight ? hex(0x1C1C1E) : hex(0xFFFFFF) }
    static var kbShiftLockInk: UIColor { hostIsLight ? hex(0xFFFFFF) : accent }

    /// 手写画布的底。
    static var kbInkCanvas: UIColor { hostIsLight ? hex(0xFFFFFF) : hex(0x000000) }
    /// 米字格虚线。要看得见但不抢笔画。
    static var kbInkGrid: UIColor { hostIsLight ? hex(0xD3D6DE) : hex(0x2A313B) }
    /// 笔画颜色。浅底就得用深笔，否则白底白字什么都看不见。
    static var kbInk: UIColor { hostIsLight ? hex(0x1C1C1E) : hex(0xFFFFFF) }

    /// 浮层面板（语言选择、历史）的底。浅色宿主下比面板更亮一档，
    /// 免得浮层跟浅紫面板糊在一起分不出层次。
    static var kbPanel: UIColor { hostIsLight ? hex(0xF4F2FA) : bg }


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

        // ── 浅色宿主：浅紫雾面 ──────────────────────────────────────
        // 🚨 关键是**起点就浅**，不是从深紫泄下来。跟被否掉的 B/C 的差别就在这：
        //    那两版上半仍是 #0B1230 深紫，半深半浅才是「丑」的成因。
        //    这里顶到底 #E4E0F2 → #D8D6E4 → #D0D3DA，对下巴的对比从约 1.20
        //    收到 1.00 —— 肉眼不是接缝，是一层很淡的冷紫雾。
        // 🚨 **浅色下不铺径向柔光**：白光压在浅底上看不见，只会把面板整体提亮发灰。
        if hostIsLight {
            let mist = CAGradientLayer()
            mist.frame = bounds
            mist.colors = [hex(0xE4E0F2).cgColor,
                           hex(0xD8D6E4).cgColor,
                           chinLight.cgColor]
            mist.locations = [0, 0.55, 1]
            mist.startPoint = CGPoint(x: 0.5, y: 0)
            mist.endPoint = CGPoint(x: 0.5, y: 1)
            root.addSublayer(mist)
            return root
        }

        // ── 深色宿主：保持现网深紫（跟安卓同一张脸）────────────────────
        let lin = CAGradientLayer()
        lin.frame = bounds
        // 深色宿主：#16122A → #1C1830 → 对齐深色下巴 #2C2C2E。
        // 🚨 `chinDark` 是**估的、没实测过**（iOS 深色键盘常见带）。
        //    拿到深色宿主的真机截图后用同一套逐像素量法换掉它，结构不用动。
        lin.colors = [hex(0x16122A).cgColor,
                      hex(0x1C1830).cgColor,
                      chinDark.cgColor]
        lin.locations = [0, 0.70, 1]
        lin.startPoint = CGPoint(x: 0.5, y: 0)
        lin.endPoint = CGPoint(x: 0.5, y: 1)
        root.addSublayer(lin)

        // 径向柔光只在深色下有意义（浅色底上白光看不见，还会发灰）
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

    /// **给圆钮装麦克风图标的唯一出口。`side` 传按钮直径，别自己再乘系数。**
    ///
    /// 🚨🚨 Kevin 2026-09-05：「button 里面的话筒有点太小了，跟面对面那个不是
    ///    一个 size」。查出来是**同一个 0.6 被乘了两遍**：`micGlyph` 内部本来
    ///    就乘 0.60，随手那两处又在外面写了 `micBarHeight * 0.6`
    ///    → 图标 27.4pt，而面对面/键盘是 45.6 / 52.8。
    ///
    ///    三个界面各写各的 `setImage(Theme.micGlyph(…))`，**同一条规矩三份实现**，
    ///    漂了也没人报错 —— 图标小一圈编译不会红、测试也不会红。
    ///    所以收成这一个出口，并且**在这里挡住"又乘了一次"**：
    ///    真实的按钮直径是 60（面对面紧凑）/ 76（随手、面对面常规）/ 88（键盘），
    ///    传进来小于 60 的一定是被谁乘过了。
    static func setMicGlyph(_ b: UIButton, side: CGFloat) {
        assert(side >= 60, "🚨 micGlyph 的 side 要传按钮直径（60/76/88），"
               + "收到 \(side) —— 是不是在外面又乘了一次系数？")
        b.setImage(micGlyph(side), for: .normal)
    }

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
