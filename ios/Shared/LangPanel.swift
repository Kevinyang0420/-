import UIKit

/// **选语言的自绘面板** —— 「最近用过」横滑 chips ＋「全部语言」竖排列表。
///
/// Kevin 2026-09-05 晚拍板「要改」：随手翻译那屏原来用系统 `UIMenu`，
/// 上下两段**长得一模一样**（都是一行行文字，只有一条细线隔开），
/// 所以同一门语言出现两次时看着像重复 —— 而这正是他早上实拍报障的那个观感。
///
/// 🚨🚨 **这个文件是把面对面那屏已经跑通的面板提出来的，不是新写第三套。**
///    那一套里踩过的坑都在，别在别处重写：
///    ① **横滑那行的高度链**：`UIScrollView` 自身没有固有高度
///       （`contentLayoutGuide` 只定内容尺寸），不接 `heightAnchor`
///       整行会塌成 0 —— 2026-09-05 上午面对面那个面板就这么变成
///       「一条扁的、看不到语言」，Kevin 当场报障。
///    ② **两段必须不同类**：chips 描边不填充、更扁；列表行是纯文字 + 行首勾。
///       判据是"一眼看上去不是同一种东西"，不是"我用了 chips 这个控件"。
///    ③ **勾只画一次**：同一门语言在两段都出现时，只有 chips 那个高亮，
///       列表行不再重复打勾（`LangChips` 用描边变色表达选中）。
enum LangPanel {

    /// 造一个可以直接盖到界面上的面板。
    ///
    /// - Parameters:
    ///   - current: 当前选中的语言码
    ///   - onPick: 选了哪个（面板由调用方负责移除）
    static func make(current: String,
                     onPick: @escaping (String) -> Void) -> UIView {
        let panel = UIView()
        // 🚨 UITest 要能指着它问「你还在不在」。
        //    没这个标识的话，判据只能挂在截图上 —— 那种判据不会自己红。
        //    键盘和主 App 共用这个 make，一处加、两屏都有。
        panel.accessibilityIdentifier = "lang.panel"
        // 🚨🚨 **照抄语气那个下拉框，不是重新设计**（Kevin 2026-09-06 01:40）：
        //    「翻译的下拉框跟语气的下拉框、目标语言的下拉框不是一个，
        //      能不能统一都用语气的这个下拉框，看上去高级一点」
        //    「目标语言下拉框都没对齐…**而且太透明了，会跟下面的字重合**」
        //
        // 🚨 **根因是我今晚改出来的**：语气那个是**系统 `UIMenu`**
        //    （`AppDelegate:3574 toneButton.menu = toneMenu()`），
        //    而语言选择器今晚从 `UIMenu` 换成了这个自绘面板（方案丙）——
        //    换了实现却没把外观带过来，于是同屏出现两种下拉框。
        //
        // 🚨 下面这些数**是从语气面板的截图上逐像素量出来的**，不是我挑的：
        //    面板内部 RGB (33,29,70)，纵向 std 只有 0.3–1.7；
        //    而它盖住的页面背景是 (29,23,84)、std 0.8–2.5 ——
        //    **面板的蓝通道稳在 70、不跟着背景走 ⇒ 它是不透明的。**
        //    描边 RGB (68,54,161)。
        //    量法记一句：第一版我容差给到 14，而两者蓝通道只差 14 ——
        //    **判据分辨不了这两个对象**，页面背景也被当成面板了。
        panel.backgroundColor = UIColor(red: 33/255.0, green: 29/255.0,
                                        blue: 70/255.0, alpha: 1)
        panel.layer.cornerRadius = 18
        // 🚨 系统菜单用的是**连续曲率**（圆角那条尾巴明显比正圆长：
        //    量出来 y=+13pt 处实体还内缩 7pt）。只调半径追不上这个形状。
        panel.layer.cornerCurve = .continuous
        panel.layer.borderWidth = 1
        panel.layer.borderColor = UIColor(red: 68/255.0, green: 54/255.0,
                                          blue: 161/255.0, alpha: 1).cgColor
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.accessibilityIdentifier = "lang.panel"
        // 🚨🚨 **必须裁剪** —— 不加这一条，滚动等于没做。
        //
        //    `hFit`（滚动想要内容那么高）是 750，会被调用方
        //    `bottom ≤ 麦克风上方` 那条 required 压回来 —— **滚动视图确实被限高了**。
        //    但**面板默认不裁剪子视图**，于是超出的那些行照样画在面板外面，
        //    实测最后一门语言落在 `y=1580`（屏幕才 852pt 高）。
        //
        //    表现是：**看起来"东西都在"，实际够不着** ——
        //    前五条判据（有 chips / 列表几行 / 勾几个）全绿，
        //    因为那些元素**存在**，只是**在屏幕外**。
        //    是第六条 `isHittable` 抓到的。**「在」和「用得了」是两件事。**
        panel.clipsToBounds = true

        let col = UIStackView()
        col.axis = .vertical
        col.spacing = 2
        col.translatesAutoresizingMaskIntoConstraints = false

        // 🚨 套滚动：31 门语言放不下，而且**不套的话超出屏幕的部分点不到**。
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = true
        scroll.addSubview(col)
        panel.addSubview(scroll)

        let sec = LangRecents.sections(all: Backend.langsForUI.map { $0.code })

        // ── 「最近用过」：横滑 chips ──────────────────────────
        if !sec.recent.isEmpty {
            col.addArrangedSubview(header(L.lang_recent))
            if let chips = LangChips.row(codes: sec.recent, current: current,
                                         onPick: onPick) {
                col.addArrangedSubview(chips)
            }
        }

        // ── 「全部语言」：完整不删（Kevin 定的）──────────────
        col.addArrangedSubview(header(L.lang_all))
        for code in sec.allIncludingRecent {
            col.addArrangedSubview(row(code: code, onPick: onPick))
        }

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -6),
            // 🚨 他原话：「最近那里**贴着边框**，很丑」。语气那个有内边距，这个没有。
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor,
                                            constant: 14),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor,
                                             constant: -14),
            col.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            col.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            col.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            col.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            // 🚨 内容宽度跟着可视宽度，否则会横着滚
            col.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])

        // 🚨🚨 **把高度链接上** —— 我在这个文件顶上写了这条警告，
        //    然后在同一个文件里原样犯了一次。
        //
        //    `UIScrollView` **自身没有固有高度**（`contentLayoutGuide`
        //    只定内容尺寸）。调用方只给了 `top` 和 `bottom ≤ 安全区`
        //    这种不等式 —— 没有任何东西告诉它"应该多高"，
        //    Auto Layout 取最小解 → **面板塌成 0**，里面的东西一个都查不到。
        //
        //    这正是 2026-09-05 上午面对面那屏「点了之后是个扁的，
        //    看不到语言」的同一个坑。**写在注释里没用，要写进约束里。**
        //
        //    修法：让滚动"想要"内容那么高（750 优先级），
        //    顶到调用方给的上限时由 required 的不等式压回来，超出靠滚。
        let hFit = scroll.heightAnchor.constraint(equalTo: col.heightAnchor)
        hFit.priority = .defaultHigh
        hFit.isActive = true
        return panel
    }

    // MARK: - 两段的两种长相（差别要一眼看得出来）

    private static func header(_ t: String) -> UILabel {
        let l = UILabel()
        l.text = t
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        l.textColor = Theme.dim
        l.accessibilityIdentifier = "lang.section"
        l.translatesAutoresizingMaskIntoConstraints = false
        l.heightAnchor.constraint(equalToConstant: 26).isActive = true
        return l
    }

    /// 「全部语言」的一行 —— 纯文字，**不打勾**。
    ///
    /// 🚨 勾归 chips 那一段（`LangChips` 用描边变色表达选中）。
    ///    两处都打勾正是 Kevin 实拍报的那个「两个中文都有勾」。
    private static func row(code: String,
                            onPick: @escaping (String) -> Void) -> UIView {
        let b = UIButton(type: .system)
        b.setTitle(Backend.langLabel(code), for: .normal)
        b.contentHorizontalAlignment = .left
        b.titleLabel?.font = .systemFont(ofSize: 16)
        b.setTitleColor(Theme.text, for: .normal)
        b.accessibilityIdentifier = "lang.row." + code
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let t = ChipTap(target: ChipTap.box, action: #selector(ChipTap.noop))
        t.code = code
        t.onPick = onPick
        b.addGestureRecognizer(t)
        return b
    }
}
