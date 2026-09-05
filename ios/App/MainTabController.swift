import UIKit

/// 主 App 的**四 Tab 骨架**：首页 / 历史 / 常用词 / 设置。
///
/// 权威：Kevin 2026-09-04「主 App 四 Tab 改版」+ 09-04「iOS 首页换成安卓那一套」。
/// 对应安卓 `SettingsActivity.tabBar()`（那边是自己画的 56dp 文字条 +
/// `startActivity` 跳转；iOS 用 `UITabBarController`，见下面「为什么不照抄画法」）。
///
/// ## 四格是哪四格（09-04 需求变更点，别用旧的）
/// | # | Tab | 去哪 | 变更 |
/// |---|---|---|---|
/// | 1 | 首页 | `HomeViewController` | — |
/// | 2 | 历史 | `HistoryListViewController` | 原来是首页上一条长条 |
/// | 3 | 常用词 | `VocabViewController` | **升成 Tab**（原来在设置里） |
/// | 4 | 设置 | `PrefsViewController` | 原来是右上角齿轮 |
///
/// 🚨 撤掉的：「我的」不再是 Tab（账户挪进设置页）、「单词本」不再是 Tab
///    （Kevin：「单词本不是最 key 的…所以单词本放设置里」）。
///
/// ## 为什么不照抄安卓那条自己画的文字栏
/// 安卓那条是 11sp 纯文字、无图标、选中只换色。iOS 上纯文字的 tab bar
/// **看起来像坏了**（系统给 tab item 的文字留的位置在图标下方，没图标时
/// 文字会贴着底边）。所以这里用系统 `UITabBarController` + SF Symbols，
/// 颜色仍然用 `Skin.accent` / `Skin.dim` —— **结构照抄，控件用各端原生的**。
/// 🚨 图标选型**没有他点过头**，出图给他看之后再定；这一版先按语义最直白的选。
///
/// ## 🚨 空 Tab 是红线
/// 四个 Tab 每一个都必须点进去有东西。常用词屏（`VocabViewController`）
/// 就是为了解锁这一条才先做的 —— 在它做出来之前这个文件不许被接上去。
final class MainTabController: UITabBarController {

    /// Tab 闪白探针（只在 `TRANSLESS_TABPROBE=1` 时启用）
    private let flashProbe = TabFlashProbe()

    override func viewDidLoad() {
        super.viewDidLoad()

        let home = nav(HomeViewController(), L.tab_home, "house")
        // 🚨 首页**自己隐藏导航栏**（它有自己的顶栏），其余三个要留着标题栏。
        home.setNavigationBarHidden(true, animated: false)
        home.interactivePopGestureRecognizer?.delegate = nil

        // 🚨🚨 **五个 Tab，中间那个是「面对面翻译」并做成凸起**（Kevin 2026-09-04 选 B）。
        //
        //    背景：首页换成安卓那套版式之后，「面对面翻译」**丢了入口** ——
        //    安卓首页上本来就没有这一条，而 iOS 原来那列长条被整个换掉了。
        //    在他拍板之前我临时挂在「长按随手翻译」上，那是隐藏手势、等于没上线。
        //    他看了 A（随手翻译上面加一条）/ B（五 Tab 中间凸起）两版之后选了 B。
        //
        // 🚨 **中间那格必须是索引 2**（五个里的正中间）—— 凸起靠的是
        //    `centerButton` 覆盖在那一格上，位置算的就是 `第2格的中心`。
        //    以后要加 Tab 必须保持奇数个、且面对面在正中，否则凸起会偏。
        viewControllers = [
            home,
            nav(HistoryListViewController(), L.tab_history, "clock"),
            // 中间这一格：**只出文字标签，不出图标** —— 凸起圆钮盖住了图标的位置，
            // 但标签在圆钮下方露出来，跟其它四格的文字对齐（2.1 09-04 定：
            // 「标签『面对面』用 accent」）。
            // 🚨 **这一格必须存在**：`selectedIndex = 2` 要有东西可选，
            //    而且五格等分才能让凸起落在正中间。
            nav(FaceToFaceViewController(), L.tab_f2f, nil),
            nav(VocabViewController(), L.tab_vocab, "text.book.closed"),
            nav(PrefsViewController(), L.tab_settings, "gearshape"),
        ]

        // 配色：选中 ACCENT、未选中 DIM（跟安卓 `tabItem` 的两态一致）。
        // 🚨 iOS 15 起 `UITabBar` 的背景要走 appearance，直接设 `barTintColor`
        //    在滚动到底时会被系统换成透明的，表现是"划到底 Tab 栏突然变色"。
        let ap = UITabBarAppearance()
        ap.configureWithOpaqueBackground()
        // 底色取渐变最深的那一段，跟页面底部接得上（安卓那条是透明 + 白 16% 描边，
        // iOS 这边 tab bar 压在内容上，透明会让文字糊在背景图上）。
        ap.backgroundColor = Skin.bg3
        ap.shadowColor = Skin.glassStroke
        ap.stackedLayoutAppearance.normal.iconColor = Skin.dim
        ap.stackedLayoutAppearance.normal.titleTextAttributes =
            [.foregroundColor: Skin.dim]
        ap.stackedLayoutAppearance.selected.iconColor = Skin.accent
        ap.stackedLayoutAppearance.selected.titleTextAttributes =
            [.foregroundColor: Skin.accent]
        tabBar.standardAppearance = ap
        tabBar.scrollEdgeAppearance = ap

        // 🚨 中间那格的标签**永远是 accent 紫**（2.1 09-04 定），
        //    不跟着"选中/未选中"变灰 —— 它下面顶着一颗紫圆钮，
        //    标签变灰会显得那颗钮是"没启用"的。
        //    只改这一格：`UITabBarItem` 自己的 appearance 优先级高于 tabBar 的。
        // 🚨🚨 **`TRANSLESS_TRANSPARENT_ON` 是这条缺陷的实验开关**（2026-09-05）：
        //      `mid`（默认／不设）＝ 现状，透明外观在中间那格
        //      `none`            ＝ **整个拿掉**，看 0.36 会不会消失（决定性正向实验）
        //      `vocab`           ＝ 挪到「常用词」，看它会不会跟着跑（反向控制）
        //    2.1 提的假设是 `configureWithTransparentBackground()` 连不透明深色底
        //    一起丢了。我先自己那条「主 App 没声明深色」的假设 ——
        //    **已用 A/B 证伪**：声明生效了（--expect 过），读数一点没变（0.19→0.36）。
        let transparentOn = ProcessInfo.processInfo
            .environment["TRANSLESS_TRANSPARENT_ON"] ?? "mid"
        if transparentOn == "mid", let mid = viewControllers?[2].tabBarItem {
            let a = UITabBarAppearance()
            a.configureWithTransparentBackground()
            for st in [a.stackedLayoutAppearance.normal,
                       a.stackedLayoutAppearance.selected] {
                st.titleTextAttributes = [.foregroundColor: Skin.accent]
            }
            mid.standardAppearance = a
            mid.scrollEdgeAppearance = a
        }
        // 🚨 **候选修法开关（`TRANSLESS_TABFIX`）—— 现在默认不开。**
        //    做成开关是为了：测量一旦坐实 portal 就是那个白，
        //    **同一轮就能 A/B**，不用再等一次构建。
        //    🚨 但**不许先改了再说**：目前 portal 只是"机制信号"，
        //    还没证明它盖住 tab 栏且内容是浅的。没坐实就改 = 又一次瞎猜。
        //      `opaque`   ＝ 关掉半透明，让栏自己就是不透明深色
        //      `noeffect` ＝ 把外观里的毛玻璃效果去掉（液态玻璃材质是这一层）
        switch ProcessInfo.processInfo.environment["TRANSLESS_TABFIX"] ?? "" {
        case "opaque":
            tabBar.isTranslucent = false
        case "noeffect":
            let a2 = UITabBarAppearance()
            a2.configureWithOpaqueBackground()
            a2.backgroundEffect = nil          // 去掉毛玻璃
            a2.backgroundColor = Skin.bg3
            a2.shadowColor = Skin.glassStroke
            a2.stackedLayoutAppearance = ap.stackedLayoutAppearance
            tabBar.standardAppearance = a2
            tabBar.scrollEdgeAppearance = a2
        default:
            break
        }
        buildCenterButton()

        // 🚨 只在 `TRANSLESS_TABPROBE=1` 时挂探针（逐帧取 tab 栏底色），
        //    用来查「点设置时闪一下白」。平时一行都不跑。
        if ProcessInfo.processInfo.environment["TRANSLESS_TABPROBE"] == "1" {
            delegate = self
            // 隐形读数标签：闸门靠它把数拿到测试进程里
            let l = UILabel()
            l.accessibilityIdentifier = "app.tabprobe"
            l.isAccessibilityElement = true
            l.text = "0"
            l.textColor = .clear
            l.font = .systemFont(ofSize: 9)
            l.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(l)
            NSLayoutConstraint.activate([
                l.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                l.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            ])
            flashProbe.readout = l
        }
        // 🚨 **反向控制开关**：把那份透明外观挪到「常用词」那一格。
        //    闪白**跟着跑过去** ⇒ 2.1 的假设成立；跟不过去 ⇒ 假设错了，别按它改。
        //    没有反向控制的话，"改完不闪了"也可能是别的原因（或者本来就抓不到）。
        if transparentOn == "vocab", let v = viewControllers?[3].tabBarItem {
            let a = UITabBarAppearance()
            a.configureWithTransparentBackground()
            v.standardAppearance = a
            v.scrollEdgeAppearance = a
        }
    }

    // MARK: - 中间那个凸起按钮

    /// 凸起直径。
    /// 🚨 **不自己定数**：跟语音面板那个录音圆钮同一个 88（`micSize`），
    ///    两处圆的大小一致，他在两屏之间切不会觉得"大小不一样"。
    // 🚨 这两个**不是 private** —— 别的屏要按它算"底部要留出多少"。
    //    凸起是盖在**所有** Tab 页上的，它往上凸出 `bumpLift`，
    //    谁把控件贴到底就会被它压住（09-04 面对面的录音钮就被压了，
    //    端到端截图上一眼看出来）。**单一配置点：改这里，各屏自动跟。**
    static let bumpSize: CGFloat = 56
    /// 往上凸出多少（超出 tab bar 顶边的部分）。
    static let bumpLift: CGFloat = 18
    /// 别的屏底部至少要留出这么多，才不会被凸起压住。
    static var bottomClearance: CGFloat { bumpLift + 12 }

    private let centerButton = CircleButton(type: .custom)

    private func buildCenterButton() {
        // 🚨🚨 **两个小人，不是箭头**（Kevin 2026-09-04 当场骂回来的）。
        //
        //    原话：「面对面那个地方，为什么原来放两个小人挺好的，
        //    现在搞个箭头是有啥意思？又他妈瞎鸡巴改」。
        //
        //    经过：我先做的是 `person.2.fill`（他看过的那版），
        //    然后 2.1 说「安卓用 ⇄、两端统一、Kevin 拍板 B 时看的图就是箭头」，
        //    我就换了。**换错了。**
        //
        // 🚨 教训：**他看过并且没说不好的东西，别因为别人一句话去改。**
        //    2.1 说"他拍板时看的图是箭头"——那是转述，而他本人现在当面说
        //    「原来两个小人挺好的」。**当事人现在的话 > 别人转述他过去的话。**
        //    要改回箭头，得他自己开口。
        centerButton.setImage(
            UIImage(systemName: "person.2.fill",
                    withConfiguration: UIImage.SymbolConfiguration(
                        pointSize: 22, weight: .semibold)),
            for: .normal)
        centerButton.tintColor = .white
        // 🚨 渐变紫走 `Theme.purpleGrad`（**单一配置点**）—— Kevin 09-04 要的
        //    「紫色不够渐变」那条改的就是它，这里跟着走，不另画一个渐变。
        centerButton.setBackgroundImage(Theme.purpleGrad, for: .normal)
        centerButton.layer.cornerRadius = Self.bumpSize / 2
        centerButton.clipsToBounds = true
        // 🚨 描边用 tab bar 的底色，让凸起和栏面之间有一圈"挖空"感 ——
        //    不描的话渐变紫直接贴着深紫底，凸起看不出来。
        centerButton.layer.borderWidth = 3
        centerButton.layer.borderColor = Skin.bg3.cgColor
        centerButton.accessibilityLabel = L.f2f_title
        centerButton.accessibilityIdentifier = "tab.center.f2f"
        centerButton.addTarget(self, action: #selector(tapCenter),
                               for: .touchUpInside)
        // 🚨🚨 **不在这里建约束**（2026-09-04 实撞崩溃）：
        //    `viewDidLoad` 里 `centerButton` 还没加进视图树，跟 `tabBar`
        //    **没有共同祖先**，`activate` 当场抛
        //    `NSGenericException ... they have no common ancestor`，App 起不来。
        //
        // 🚨 而且这条**编译是过的**，只有真跑起来才炸 ——
        //    我差点拿「BUILD SUCCEEDED」当交付，是**截图截到了模拟器桌面**
        //    （App 根本没起来）才发现。**编过 ≠ 跑得起来。**
        //
        //    改成不用约束、在 `viewDidLayoutSubviews` 里按 `tabBar` 的实际
        //    frame 摆 —— tab bar 的高度本来就要等系统布完才知道。
        centerButton.frame = CGRect(x: 0, y: 0,
                                    width: Self.bumpSize, height: Self.bumpSize)
        view.addSubview(centerButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 锚在 tab bar 的**顶边中点**上：tab bar 高度在不同机型（有没有 Home 键）
        // 上不一样，按屏幕底算会在小屏压住图标、在大屏飘起来。
        centerButton.center = CGPoint(x: tabBar.frame.midX,
                                      y: tabBar.frame.minY
                                         + Self.bumpSize / 2 - Self.bumpLift)
        view.bringSubviewToFront(centerButton)
    }

    @objc private func tapCenter() { selectedIndex = 2 }

    // 🚨🚨 **这里曾经有一个 `loadView()` 覆写和一个自定义根视图，已删** ——
    //    连着两次把 App 弄坏，记下来免得下一个人（或我自己）再加回去：
    //
    //    ① 第一版：想给凸起按钮扩大命中区，把 `hitTest` 写在**控制器**上 ——
    //       `hitTest` 是 `UIView` 的方法，编译直接报
    //       `does not override any method from its superclass`。
    //    ② 第二版：改成覆写 `loadView()` 换一个自定义根视图来接 `hitTest` ——
    //       **`UITabBarController` 要自己管那个根视图**，换掉之后整个控制器废掉，
    //       表现是**纯白屏**（进程活着、日志无异常、`BUILD SUCCEEDED`）。
    //       这一版还被我装进了他手机。
    //
    // 🚨 而这个覆写**从一开始就不需要**：凸起按钮是加在**全屏的 `view`** 上的，
    //    它的 frame 本来就完整落在 `view` 的 bounds 里，触摸正常派发。
    //    「超出父视图 bounds 就点不到」只有在按钮是 **tabBar 的子视图** 时才成立 ——
    //    我把一个不成立的前提套了上去，然后为它写了两版修法。
    //    **动手之前先确认那个问题真的存在。**

    /// - Parameter symbol: 传 nil = 这一格不画图标也不画文字
    ///   （给中间那个被凸起按钮盖住的占位格用）。
    private func nav(_ vc: UIViewController, _ title: String,
                     _ symbol: String?) -> UINavigationController {
        let n = UINavigationController(rootViewController: vc)
        n.tabBarItem = UITabBarItem(
            title: title,
            image: symbol.flatMap { UIImage(systemName: $0) },
            selectedImage: nil)
        return n
    }
}

// MARK: - Tab 闪白探针（只在 TRANSLESS_TABPROBE=1 时接上）

extension MainTabController: UITabBarControllerDelegate {
    /// 🚨🚨 **采样必须从 `shouldSelect` 开始，不是 `didSelect`。**
    ///    第一版挂在 `didSelect` —— 那是**切换完成之后**才触发的，
    ///    而他说的闪白发生在切换过程中：
    ///    「我点『设置』的时候，下面的 tab 面板会切成白色，然后很快又会变成黑色」。
    ///    窗口开晚了就什么都测不到，而读数会长得像"一切正常"
    ///    （实测那一版：每格都是 0.19 → 0.36 然后保持，没有回落，
    ///     跟"闪一下再变回来"完全不是一个形状）。
    ///    **观测窗口跟事件错位 ＝ 等于没观测。**
    func tabBarController(_ tabBarController: UITabBarController,
                          shouldSelect viewController: UIViewController) -> Bool {
        let i = viewControllers?.firstIndex(of: viewController) ?? -1
        NSLog("TABPROBE 将切到第 %d 格，开始逐帧采样（切换前）", i)
        flashProbe.start(on: tabBar, seconds: 1.6)
        return true
    }
}
