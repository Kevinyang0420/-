import UIKit
import AVFoundation

/// 「面对面翻译」屏 —— **语言切换 A 定稿**（Kevin 2026-09-04：「就用这一稿」）。
///
/// 规格：`_规格_面对面语言切换_A定稿_20260904.md`，定稿图 `D:\_tmp_ui\f2f_langA.png`。
/// 这是对已实现的「面对面乙」的改动（乙的结构保留：一整面输出、绝不上下对开）。
///
/// ## A 定稿改了什么（跟乙比）
/// | | 乙 | **A 定稿** |
/// |---|---|---|
/// | 底部 | 朗读钮 + 「按一下说话」键 | **语言条 + 一颗录音圆钮**（贴底） |
/// | 朗读 | 独立按钮 | 🚨 **点译文大字**（不单独设钮） |
/// | 方向 | ⇄ 中文→English 只读条 | **[中文▴] (⇄) [English▴]**，可各选任意语言 |
/// | 说话提示 | 「按一下说话」 | 🚨 **去掉**（Kevin：多余，都知道点那个说话） |
///
/// ## 三条铁律（他反复强调）
/// 1. 🚨 **绝不重叠** —— 译文大字独占中上黄金区，语言条/录音钮各占各的竖向空间。
/// 2. 🚨 **录音钮用键盘那颗真按钮**：`CircleButton` + `Theme.micGlyph` + `Theme.accent`，
///    **不自创、不改样式**（这里是直接复用那两个组件，不是照着画一个像的）。
/// 3. 🚨 **语言项取 `Backend.langs`**（随手翻译那份，单一来源），别另写一张表。
///
/// ## 方向仍然自动判（乙 §5，没变）
/// 说的话里**有一个汉字就算我在说中文** → 译成**右边**那个语言；没汉字 = 对方说的 →
/// 译回**左边**那个语言。判定在 `Reverse.isMine`（跟安卓拉齐，`gate_pure_logic` 看着）。
final class FaceToFaceViewController: UIViewController {

    // MARK: - 尺寸（竖/横两套）

    private struct Metrics {
        let bigSize: CGFloat
        let bigLine: CGFloat
        let bigMaxLines: Int
        let ctxCount: Int
        let micSide: CGFloat
        static let portrait = Metrics(bigSize: 30, bigLine: 40, bigMaxLines: 6,
                                      ctxCount: 2, micSide: 76)
        static let landscape = Metrics(bigSize: 24, bigLine: 32, bigMaxLines: 3,
                                       ctxCount: 1, micSide: 60)
    }
    private var m: Metrics = .portrait

    private static let topBarH: CGFloat = 48
    private static let langBarH: CGFloat = 34
    private static let langBtnW: CGFloat = 112     // 🚨 Kevin：小一点、"别像眼睛"，别再放大
    private static let textInset: CGFloat = 16

    // MARK: - 状态

    private enum Phase { case idle, listening, thinking }
    private var phase: Phase = .idle

    private var utterances: [String] = []
    private var latest: String { utterances.last ?? "" }

    /// 左=我说的语言，右=对方的语言。默认 中文 ↔ English（规格）。
    private var leftLang = "zh"
    private var rightLang = "en"

    private lazy var voice = Voice()
    private var voiceUsed = false
    private var elapsedTimer: Timer?
    /// 有没有跟 `KbVoiceHost` 借过麦克风（M4：`reclaimMic` 必须跟 `yieldMic` 配对，
    /// 进屏一句没说就返回时别凭空 reclaim，免得点亮状态栏麦克风灯）。
    private var didYieldMic = false
    private var epoch = 0

    // MARK: - 视图

    private let ctxStack = UIStackView()
    private let bigLabel = UILabel()
    /// 「＋ 单词本」—— 2.1 规格第 4 条：**面对面两端原来完全没接**，
    /// 而「遇到生词最多的恰恰是面对面场景」。
    private let keepBtn = UIButton(type: .system)
    private var lastZh = ""
    private var lastOut = ""
    private let emptyStack = UIStackView()
    private let leftBtn = UIButton(type: .system)
    private let swapBtn = UIButton(type: .system)
    private let rightBtn = UIButton(type: .system)
    /// 🚨 键盘那颗真录音钮（同一个类 + 同一个图标 + 同一个色），不是照着画的。
    private let micBtn = CircleButton(type: .system)
    /// 录音时圆钮里的波形 —— **跟键盘那颗完全同一套**（同一个 `WaveView` 类、
    /// 同样 66%×46% 的比例、同样 `setActive` + `push` 的接法）。
    ///
    /// 🚨🚨 2026-09-04 Kevin：「点一下键盘那个 button 也应该有所变化吧，
    ///    变成一个波浪线什么的，就跟我们平时键盘语音一样。现在这个点一下
    ///    跟没点一样，后台明明已经开始录了，但根本看不出来。
    ///    这个东西做得太不 human 了」。
    ///
    ///    **他说得对**：正在录音却看不出来，是最基本的反馈缺失。
    ///    键盘那颗按下去有波形，这颗什么都没有 —— 同一个产品里
    ///    同一个动作两种反馈，本来就该一致。
    /// 🚨 **照搬不自创**：直接用键盘那个类，不另画一个"像波形的东西"。
    private let waveView = WaveView(frame: .zero)

    /// 进入「处理中」的时刻，用来在圆钮里数秒。
    /// 🚨🚨 **一个静止的「…」跟死了没区别**（键盘那边 2526 行原话，安卓
    ///    `startBusyTick` 同款）。Kevin 2026-09-04 报的就是这条：
    ///    「点完红色的波浪线之后，它没有像键盘那样出现秒数倒计时，
    ///     而是直接显示了一个省略号，让人不知道它 load 得怎么样」。
    ///    **会动＝活着，停住＝真挂了** —— 这是他判断"要不要再等"的唯一依据。
    /// 处理中那档的刷新器。🚨 只在 `.thinking` 期间活着，别常驻。
    private let busyTicker = BusyTicker()
    private var micWH: [NSLayoutConstraint] = []
    /// 语言下拉浮层（临时层，选完即收）。
    private var dropdown: UIView?

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        // 🚨🚨 **只设导航栏标题，别用 `title =`**（2026-09-04 端到端截图抓到）。
        //    `UIViewController.title` 会**同时**写进 `tabBarItem.title` ——
        //    于是我在 `MainTabController` 里设的短标签「面对面」被这一行
        //    覆盖成全称「面对面翻译」，那一格把左右两格挤窄了。
        //    Tab 那格只有五分之一屏宽，必须用短标签。
        navigationItem.title = L.f2f_title
        UI.paintBg(self)
        m = view.bounds.width > view.bounds.height ? .landscape : .portrait
        buildUI()
        render()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || isBeingDismissed { teardown() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
        // M10：`viewDidLoad` 时 bounds 还不是最终尺寸，而 `viewWillTransition` 只在旋转时触发
        //      —— 手机本来就横着推进来会拿到 portrait 尺寸。这里按真实 bounds 重判。
        let want: Metrics = view.bounds.width > view.bounds.height ? .landscape : .portrait
        if want.bigSize != m.bigSize {
            m = want
            applyMetrics()
            render()
        }
    }

    override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        m = size.width > size.height ? .landscape : .portrait
        applyMetrics()
        coordinator.animate(alongsideTransition: { _ in
            self.hideDropdown()          // 转屏时浮层收掉，免得锚错位置
            self.render()
        })
    }

    // MARK: - 搭 UI（锚点式，各块各占各的竖向空间，绝不重叠）

    private func buildUI() {
        let guide = view.safeAreaLayoutGuide
        let pad = Theme.pad

        // ── 录音圆钮：贴底、水平居中。**键盘那颗**（CircleButton + micGlyph + accent）──
        micBtn.translatesAutoresizingMaskIntoConstraints = false
        // 🚨 渐变紫（Kevin 09-04）。规格说这颗**就是键盘那颗**，键盘改了这里必须跟，
        //    否则同一颗按钮两个样子 —— 那正是"同一规矩两处实现"的形态。
        micBtn.backgroundColor = .clear
        micBtn.setBackgroundImage(Theme.purpleGrad, for: .normal)
        micBtn.tintColor = .white
        micBtn.setTitle("", for: .normal)
        Theme.setMicGlyph(micBtn, side: m.micSide)
        micBtn.accessibilityIdentifier = "transless.f2f.mic"
        micBtn.addTarget(self, action: #selector(tapMic), for: .touchUpInside)
        view.addSubview(micBtn)
        // 波形贴在圆钮里 —— 比例照抄键盘那颗（66% 宽 × 46% 高，都相对**宽度**算，
        // 这样圆钮尺寸变（横竖屏 76/60）时波形跟着等比缩，不会走形。
        waveView.translatesAutoresizingMaskIntoConstraints = false
        waveView.isUserInteractionEnabled = false   // 别挡住按钮的点击
        micBtn.addSubview(waveView)
        NSLayoutConstraint.activate([
            waveView.centerXAnchor.constraint(equalTo: micBtn.centerXAnchor),
            waveView.centerYAnchor.constraint(equalTo: micBtn.centerYAnchor),
            waveView.widthAnchor.constraint(equalTo: micBtn.widthAnchor,
                                            multiplier: 0.66),
            waveView.heightAnchor.constraint(equalTo: micBtn.widthAnchor,
                                             multiplier: 0.46),
        ])
        let mw = micBtn.widthAnchor.constraint(equalToConstant: m.micSide)
        let mh = micBtn.heightAnchor.constraint(equalToConstant: m.micSide)
        micWH = [mw, mh]

        // ── 语言条：[左语言▴] (⇄) [右语言▴]，水平居中，元件间距 12 ──────────
        styleLangButton(leftBtn)
        styleLangButton(rightBtn)
        leftBtn.addTarget(self, action: #selector(tapLeftLang), for: .touchUpInside)
        // 🚨 给自动化一个**稳定的抓手**：文案会跟着选中的语言变
        //    （「英文」→「日语」），按文案找必漂。
        leftBtn.accessibilityIdentifier = "f2f.lang.left"
        rightBtn.accessibilityIdentifier = "f2f.lang.right"
        rightBtn.addTarget(self, action: #selector(tapRightLang), for: .touchUpInside)

        swapBtn.translatesAutoresizingMaskIntoConstraints = false
        swapBtn.backgroundColor = Theme.accent.withAlphaComponent(60.0 / 255.0)
        swapBtn.layer.cornerRadius = Self.langBarH / 2
        swapBtn.layer.borderWidth = 1
        swapBtn.layer.borderColor = Theme.accent.cgColor
        swapBtn.tintColor = .white
        swapBtn.setImage(UIImage(systemName: "arrow.left.arrow.right",
                                 withConfiguration: UIImage.SymbolConfiguration(
                                    pointSize: 15, weight: .semibold)), for: .normal)
        swapBtn.addTarget(self, action: #selector(tapSwap), for: .touchUpInside)

        let langBar = UIStackView(arrangedSubviews: [leftBtn, swapBtn, rightBtn])
        langBar.axis = .horizontal
        langBar.alignment = .center
        langBar.spacing = 12
        langBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(langBar)

        // ── 文字面（顶 = 顶栏底；底 = 语言条顶）—— 译文大字的黄金区 ─────────
        let textArea = UILayoutGuide()
        view.addLayoutGuide(textArea)

        ctxStack.axis = .vertical
        ctxStack.spacing = 6
        ctxStack.alignment = .fill
        ctxStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(ctxStack)

        bigLabel.numberOfLines = m.bigMaxLines
        bigLabel.lineBreakMode = .byTruncatingTail
        bigLabel.textColor = Theme.text
        bigLabel.textAlignment = .center          // 🚨 A 定稿图：大字水平居中
        bigLabel.translatesAutoresizingMaskIntoConstraints = false
        // 🚨 朗读 = 点译文大字（A 定稿：不单独设朗读钮）
        bigLabel.isUserInteractionEnabled = true
        bigLabel.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(tapSpeak)))
        view.addSubview(bigLabel)

        keepBtn.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        keepBtn.contentEdgeInsets = UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
        keepBtn.layer.cornerRadius = 14
        keepBtn.translatesAutoresizingMaskIntoConstraints = false
        keepBtn.accessibilityIdentifier = "f2f.add.wordbook"
        keepBtn.addTarget(self, action: #selector(tapKeep), for: .touchUpInside)
        keepBtn.isHidden = true          // 没有结果时不出现
        view.addSubview(keepBtn)

        let e1 = UILabel()
        e1.text = L.f2f_place
        e1.font = .systemFont(ofSize: 16)
        e1.textColor = Theme.dim
        e1.textAlignment = .center
        e1.numberOfLines = 0
        let e2 = UILabel()
        e2.text = L.f2f_take_turns
        e2.font = .systemFont(ofSize: 13)
        e2.textColor = Theme.dim.withAlphaComponent(0.62)
        e2.textAlignment = .center
        e2.numberOfLines = 0
        emptyStack.axis = .vertical
        emptyStack.spacing = 10
        emptyStack.alignment = .center
        emptyStack.addArrangedSubview(e1)
        emptyStack.addArrangedSubview(e2)
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStack)

        NSLayoutConstraint.activate([
            // 录音钮贴底居中
            micBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            // 🚨🚨 **给底部那颗凸起圆钮让位**（2026-09-04 端到端截图抓到）。
            //    凸起是盖在**所有 Tab 页**上的，它往上凸出 `bumpLift`，
            //    而这里原来只留 12 —— 两颗圆当场上下叠在一起。
            //    这类"两个独立组件在屏幕上打架"**只有真截图才看得见**，
            //    读代码永远发现不了：两边各自都是对的。
            // 🚨 用 `MainTabController.bottomClearance` 算，**不另写一个数** ——
            //    凸起的尺寸/凸出量以后改，这里自动跟着走。
            micBtn.bottomAnchor.constraint(
                equalTo: guide.bottomAnchor,
                constant: -MainTabController.bottomClearance),
            mw, mh,

            // 语言条在录音钮上方，各占各的空间（绝不重叠）
            langBar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            langBar.bottomAnchor.constraint(equalTo: micBtn.topAnchor, constant: -16),
            langBar.heightAnchor.constraint(equalToConstant: Self.langBarH),
            leftBtn.widthAnchor.constraint(equalToConstant: Self.langBtnW),
            leftBtn.heightAnchor.constraint(equalToConstant: Self.langBarH),
            rightBtn.widthAnchor.constraint(equalToConstant: Self.langBtnW),
            rightBtn.heightAnchor.constraint(equalToConstant: Self.langBarH),
            swapBtn.widthAnchor.constraint(equalToConstant: Self.langBarH),
            swapBtn.heightAnchor.constraint(equalToConstant: Self.langBarH),

            // 文字面：顶栏底 → 语言条顶
            textArea.topAnchor.constraint(equalTo: guide.topAnchor, constant: Self.topBarH),
            textArea.bottomAnchor.constraint(equalTo: langBar.topAnchor, constant: -12),
            textArea.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: pad),
            textArea.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -pad),

            // 上文贴文字面顶（不参与居中）
            ctxStack.topAnchor.constraint(equalTo: textArea.topAnchor, constant: Self.textInset),
            ctxStack.leadingAnchor.constraint(equalTo: textArea.leadingAnchor),
            ctxStack.trailingAnchor.constraint(equalTo: textArea.trailingAnchor),

            // 🚨 译文大字：整块垂直居中于黄金区（乙 §3 的硬约束，A 定稿沿用）
            bigLabel.centerYAnchor.constraint(equalTo: textArea.centerYAnchor),
            bigLabel.leadingAnchor.constraint(equalTo: textArea.leadingAnchor),
            bigLabel.trailingAnchor.constraint(equalTo: textArea.trailingAnchor),

            keepBtn.topAnchor.constraint(equalTo: bigLabel.bottomAnchor, constant: 10),
            keepBtn.centerXAnchor.constraint(equalTo: textArea.centerXAnchor),

            emptyStack.centerYAnchor.constraint(equalTo: textArea.centerYAnchor),
            emptyStack.centerXAnchor.constraint(equalTo: textArea.centerXAnchor),
            emptyStack.leadingAnchor.constraint(greaterThanOrEqualTo: textArea.leadingAnchor),
            emptyStack.trailingAnchor.constraint(lessThanOrEqualTo: textArea.trailingAnchor),
        ])
        applyMetrics()
    }

    /// 语言钮：玻璃底 + 描边 + 14pt 字 + 右侧向上小三角（示意下拉向上弹）。
    private func styleLangButton(_ b: UIButton) {
        b.translatesAutoresizingMaskIntoConstraints = false
        b.backgroundColor = UIColor.white.withAlphaComponent(26.0 / 255.0)
        b.layer.cornerRadius = 16
        b.layer.borderWidth = 1
        b.layer.borderColor = UIColor.white.withAlphaComponent(41.0 / 255.0).cgColor
        b.setTitleColor(Theme.text, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 14)
        b.contentHorizontalAlignment = .left
        b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 10)
        // 三角放右侧
        let tri = UILabel()
        tri.text = "▴"
        tri.font = .systemFont(ofSize: 12)
        tri.textColor = Theme.dim
        tri.translatesAutoresizingMaskIntoConstraints = false
        tri.isUserInteractionEnabled = false
        b.addSubview(tri)
        NSLayoutConstraint.activate([
            tri.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -10),
            tri.centerYAnchor.constraint(equalTo: b.centerYAnchor),
        ])
    }

    private func applyMetrics() {
        bigLabel.numberOfLines = m.bigMaxLines
        micWH.forEach { $0.constant = m.micSide }
        // 🚨 **不在这里 `setImage`** —— 那是改按钮长相的**第二个**出口，
        //    录音中一旦被调到（换机型、字号变化、旋转都会触发），
        //    麦克风图标就会重新盖回波形上。这类"同一规则两处实现"
        //    必然漂：走唯一出口 `renderMic()`，它自己按相位决定画什么。
        renderMic()
    }

    // MARK: - 渲染

    private func render() {
        let empty = utterances.isEmpty
        emptyStack.isHidden = !empty
        bigLabel.isHidden = empty
        ctxStack.isHidden = empty

        ctxStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if !empty && utterances.count > 1 {
            let show = Array(utterances.dropLast().suffix(m.ctxCount))
            for (i, t) in show.enumerated() {
                let l = UILabel()
                l.text = t
                l.font = .systemFont(ofSize: 14)
                l.numberOfLines = 1
                l.textAlignment = .center
                l.lineBreakMode = .byTruncatingTail
                // 离大字近的稍亮，远的更淡（都很淡，不许抢大字）
                let fromBottom = show.count - 1 - i
                l.textColor = Theme.dim.withAlphaComponent(fromBottom == 0 ? 0.55 : 0.35)
                ctxStack.addArrangedSubview(l)
            }
        }

        if !empty {
            let p = NSMutableParagraphStyle()
            p.minimumLineHeight = m.bigLine
            p.maximumLineHeight = m.bigLine
            p.alignment = .center
            bigLabel.attributedText = NSAttributedString(
                string: latest,
                attributes: [.font: UIFont.systemFont(ofSize: m.bigSize, weight: .bold),
                             .foregroundColor: Theme.text,
                             .paragraphStyle: p])
        }

        renderLangBar()
        renderMic()
    }

    private func renderLangBar() {
        leftBtn.setTitle(Backend.langLabel(leftLang), for: .normal)
        rightBtn.setTitle(Backend.langLabel(rightLang), for: .normal)
    }

    /// 三态画法 **逐行照抄键盘那颗**（`KeyboardViewController.setPhase`）。
    ///
    /// 🚨🚨 **这是标准答案，不许在这里重新设计。** Kevin 2026-09-04 直接
    ///    把键盘录音中的截图发过来当参照：紫圆 → **红圆 + 波形、没有麦克风图标**。
    ///    他要的就是「跟平时键盘语音一样」，两屏必须长一样。
    ///
    /// 🚨 上一版栽在两点，都写在这儿免得再犯：
    ///
    ///    ① **`micBtn.imageView?.alpha = 0` 藏不掉图标。** UIButton 在自己
    ///       重绘（状态变化、布局、tint 更新）时会把 `imageView` 的属性复原，
    ///       于是波形和麦克风图标**叠在一起糊成一团** —— 他截图上就是这个。
    ///       正解是把**图标本身**换掉：`setImage(nil, for: .normal)`。
    ///       判据：改属性 vs 改内容 —— **属性会被系统覆盖，内容不会。**
    ///
    ///    ② **换纯色必须先清掉渐变底图。** `setBackgroundImage` 画在
    ///       `backgroundColor` **之上**，不清的话录音中还是紫的、红不了
    ///       （键盘那边 2440-2444 行有一模一样的注释，是同一个坑）。
    private func renderMic() {
        micBtn.isEnabled = true       // 三态都可点（处理中点一下=取消，不静默）
        micBtn.alpha = 1.0            // 🚨 不再用整体透明度表达状态：
                                      //    "稍暗一档"在深紫底上根本看不出来，
                                      //    等于没有反馈 —— 换色才看得见。
        micBtn.setTitle("", for: .normal)
        switch phase {
        case .idle:
            Theme.setMicGlyph(micBtn, side: m.micSide)
            micBtn.backgroundColor = .clear
            micBtn.setBackgroundImage(Theme.purpleGrad, for: .normal)
        case .listening:
            // 圆里**只放波形**，不放麦克风、也不放停止方块
            // （键盘那边 Kevin 已经否过方块：「像个肚脐眼一样」）。
            micBtn.setImage(nil, for: .normal)
            micBtn.setBackgroundImage(nil, for: .normal)   // 先清渐变，否则红不了
            micBtn.backgroundColor = Theme.danger
        case .thinking:
            micBtn.setImage(nil, for: .normal)
            // 秒数由共用的 `busyTicker` 刷（Shared/BusyTicker.swift）
            micBtn.setBackgroundImage(nil, for: .normal)
            micBtn.backgroundColor = Theme.kbKeyDown
        }
        // 🚨 **波形只在「在听」时出现** —— 挂在这个咽喉上而不是散在
        //    起录/停录/取消/失败各处：那样漏一处就会出现
        //    「已经不录了、波形还在动」，比没有反馈更误导。
        //    `renderMic()` 是三个相位唯一的渲染出口，挂这里三态自动都对。
        waveView.setActive(phase == .listening)
        busyTicker.sync(busy: phase == .thinking, on: micBtn)
    }

    // 🚨 原来这里有一份 `retickBusy()`，已并入 `Shared/BusyTicker.swift`
    //    —— 随手那一屏当时没有对应实现，两边就此漂开（一边数秒、一边不数）。

    // MARK: - 加入单词本

    /// 🚨 状态判定**用 `WordBookCore.idOf` 这唯一一个 id 算法** ——
    ///    随手翻译的 `inBook()`、说话记录的 `inBook(_:)` 都是它。
    ///    三处各写一套的话，同一条在三屏会给出三种"加没加过"。
    private func paintKeep() {
        let has = WordBookCore.usable(lastOut)
        keepBtn.isHidden = !has
        guard has else { return }
        let id = WordBookCore.idOf(lastZh, lastOut)
        let added = WordBook.list().contains { $0.id == id }
        keepBtn.setTitle(added ? L.wb_added : L.wb_add, for: .normal)
        keepBtn.setTitleColor(added ? Theme.dim : .white, for: .normal)
        keepBtn.backgroundColor = added
            ? UIColor.white.withAlphaComponent(0.10)
            : Theme.accent.withAlphaComponent(0.55)
    }

    @objc private func tapKeep() {
        guard WordBookCore.usable(lastOut) else { return }
        let id = WordBookCore.idOf(lastZh, lastOut)
        if WordBook.list().contains(where: { $0.id == id }) {
            WordBook.remove(id: id)          // 再点是移除，不是重复添加
        } else {
            // 参数形状照抄 `AppDelegate:4772`，不凭印象写。
            _ = WordBook.add(zh: lastZh, en: lastOut, span: "full",
                             tone: "", today: Srs.todayString())
        }
        // 🚨 重画前先读盘：显示的状态要来自存储，不是本地布尔取反 ——
        //    写失败时界面照样变的话，他会以为收进去了。
        paintKeep()
    }

    // MARK: - 语言切换

    @objc private func tapSwap() {
        hideDropdown()
        swap(&leftLang, &rightLang)
        renderLangBar()
        UIView.animate(withDuration: 0.22) {
            self.swapBtn.transform = self.swapBtn.transform.rotated(by: .pi)
        }
    }

    @objc private func tapLeftLang() { showDropdown(for: leftBtn, isLeft: true) }
    @objc private func tapRightLang() { showDropdown(for: rightBtn, isLeft: false) }

    /// 语言下拉：**向上弹**，锚在被点钮的上沿；临时层，选完即收。
    /// 🚨 语言项取 `Backend.langs`（随手翻译那份，单一来源），不另写一张表。
    private func showDropdown(for anchor: UIButton, isLeft: Bool) {
        if dropdown != nil { hideDropdown(); return }
        let cur = isLeft ? leftLang : rightLang

        let panel = UIView()
        panel.backgroundColor = Theme.panel
        panel.layer.cornerRadius = 18
        panel.layer.borderWidth = 0.6
        panel.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        panel.translatesAutoresizingMaskIntoConstraints = false

        let col = UIStackView()
        col.axis = .vertical
        col.translatesAutoresizingMaskIntoConstraints = false
        // 🚨🚨 **套一层滚动**（2026-09-05）。原来 `col` 是直接贴在面板上的，
        //    9 门时刚好放得下，Kevin 要扩到 23+ 门之后**超出屏幕的部分点不到** ——
        //    而且这个面板是往上弹的，溢出方向正好顶到状态栏。
        //    这一处 2.1 的清单里没有；三个选择器各写各的，所以只查一处会漏。
        //
        // 🚨🚨 **浮层里的滚动跟贴死在安全区上的滚动，是两种东西。**
        //    历史列表/详情那两处也是 `contentLayoutGuide`，但它们四边等式贴死在
        //    安全区上 —— 高度**由外层定死**，不需要内容来撑，所以套滚动没事。
        //    这个面板是**浮层**：高度没有任何外部来源，只能靠内容撑。
        //    套滚动 = 把唯一那条高度来源剪断。
        //    （2026-09-05 扫全簿三处命中同一形状，只有这一处真坏 ——
        //      **扫描定位形状，不下判决**；拿扫描结果当结论会去"修"两个没坏的。）
        //
        // 🚨 **一句话判据（下次往任何浮层里加东西之前先问）**：
        //    「顶部只有不等式」的浮层，高度**只能靠内容撑**；
        //    而内容撑不撑得起来，取决于放进去的是什么 ——
        //      `UILabel` / `UIStackView` **有**固有高度 ✅
        //      `UIScrollView` **没有**（它的 contentLayoutGuide 只管内容尺寸）❌
        //    我昨晚干的正是：往一个靠内容撑的浮层里，塞了个没有固有高度的东西。
        //    （同屏另一处浮层 `l` 是 UILabel，所以它一直好好的。）
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = true
        scroll.addSubview(col)
        panel.addSubview(scroll)

        // 🚨 顺序走共用的 `LangRecents`（最近用过置顶），别在这里另排一份。
        let sec = LangRecents.sections(all: Backend.langsForUI.map { $0.code })
        // 🚨🚨 **两段必须有标题。** 不加的话用户看到的是
        //    「英文…英文」「日语…日语」重复出现而**没有任何解释** ——
        //    随手那屏用的是系统 `UIMenu`，标题它自己会画；
        //    这个面板是自绘的，**同一条规矩两种实现，标题这一半漏了**。
        //
        // 🚨 我第一版闸门只查「看得见几门语言」，12 门也照样绿 ——
        //    **判据缺了「分段看不看得懂」这一整个维度**，
        //    是看截图才发现的，不是闸门抓的。
        // 🚨 分段逻辑**逐行照抄 `LangMenu.swift:66-75`**：
        //    「最近用过」有内容才加，「全部语言」**无条件加**。
        //    我第一版写成「只有 recent 非空才加全部语言标题」——
        //    没有最近记录时整个列表就没标题了，**两屏又走散**。
        //    这种地方不许凭印象写，去把那一份读出来照抄。
        // 🚨🚨 **方案丙**（Kevin 2026-09-05 拍板）：「最近用过」是**快捷区**，
        //    做成横滑 chips（描边不填充、更扁），**不再是跟下面同构的列表行**。
        //    「全部语言」保持完整不删。
        //
        // 🚨 判据是**两段一眼看上去不是同一种东西**，不是"我改成了 chips"。
        //    改完退一步看：还像两截同样的列表，就没达到目的。
        if !sec.recent.isEmpty {
            col.addArrangedSubview(sectionHeader(L.lang_recent))
            if let chips = LangChips.row(codes: sec.recent, current: cur,
                                         onPick: { [weak self] code in
                                             self?.pickLangCode(code, isLeft: isLeft)
                                         }) {
                col.addArrangedSubview(chips)
            }
        }
        col.addArrangedSubview(sectionHeader(L.lang_all))
        for code in sec.allIncludingRecent {
            col.addArrangedSubview(langRow(title: Backend.langLabel(code), code: code,
                                           checked: code == cur, isLeft: isLeft))
        }
        // 🚨 **不再有「更多语言…」那一项**（Kevin 2026-09-05 当场砍掉）：
        //    「既然没有的话，还写着干嘛呢？」—— 它点下去只弹一句"现在先支持这 9 种"，
        //    而语言表早就 31 门了。**一个只会说自己没有的入口，没有存在的理由。**

        view.addSubview(panel)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: panel.topAnchor, constant: 4),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -4),
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            col.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            col.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            col.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            col.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            // 🚨 内容宽度跟着可视宽度，否则会横着滚
            col.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            panel.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            panel.leadingAnchor.constraint(equalTo: anchor.leadingAnchor),
            // 🚨 向上弹：锚在被点钮的**上沿**
            panel.bottomAnchor.constraint(equalTo: anchor.topAnchor, constant: -8),
            panel.topAnchor.constraint(greaterThanOrEqualTo:
                                        view.safeAreaLayoutGuide.topAnchor, constant: 8),
        ])

        // 🚨🚨 **把高度链接回来** —— 这就是 Kevin 2026-09-05 报的
        //    「点了之后是个扁的，看不到语言」。
        //
        //    我上一版给面板套了滚动来治"23 门滚不到底"，**却把撑高度的那条链剪断了**：
        //    加滚动之前 `col` 直接贴在面板上，是 stack 的固有高度把面板撑开的；
        //    套上滚动之后 `col` 钉在 `scroll.contentLayoutGuide` 上，
        //    而**内容布局指南只定内容尺寸、不给滚动视图自身高度**。
        //    于是面板只剩 `bottom=锚点上沿` 和 `top>=安全区+8`（不等式，不定高）——
        //    Auto Layout 取最小解，高度≈0。
        //
        //    🚨 **编译不报、约束不冲突、日志没有一个字**，只有点开看才知道。
        //       "我修好了滚动"和"面板还撑得开"是两件事，我只验了前一件。
        //
        //    修法：让滚动"想要"内容那么高（750 优先级），
        //    顶到安全区时由上面那条 required 的不等式压回来，超出部分靠滚。
        let hFit = scroll.heightAnchor.constraint(equalTo: col.heightAnchor)
        hFit.priority = .defaultHigh
        hFit.isActive = true

        dropdown = panel
    }

    /// 分段小标题 —— 跟随手那屏系统菜单的观感对齐（灰、小一号、不可点）。
    private func sectionHeader(_ text: String) -> UIView {
        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let t = UILabel()
        t.text = text
        t.font = .systemFont(ofSize: 12, weight: .semibold)
        t.textColor = Theme.dim
        t.translatesAutoresizingMaskIntoConstraints = false
        t.accessibilityIdentifier = "f2f.lang.section"
        row.addSubview(t)
        NSLayoutConstraint.activate([
            t.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            t.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -4),
        ])
        return row
    }

    private func langRow(title: String, code: String,
                         checked: Bool, isLeft: Bool) -> UIView {
        let row = UIControl()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let t = UILabel()
        t.text = title
        t.font = .systemFont(ofSize: 15)
        t.textColor = Theme.text
        t.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(t)
        let ck = UILabel()
        ck.text = checked ? "✓" : ""
        ck.font = .systemFont(ofSize: 15, weight: .semibold)
        ck.textColor = Theme.accent
        ck.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(ck)
        NSLayoutConstraint.activate([
            t.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            t.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            ck.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            ck.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            t.trailingAnchor.constraint(lessThanOrEqualTo: ck.leadingAnchor, constant: -8),
        ])
        let pick = LangPick(target: self, action: #selector(pickLang(_:)))
        pick.code = code
        pick.isLeft = isLeft
        row.addGestureRecognizer(pick)
        return row
    }

    @objc private func pickLang(_ g: LangPick) {
        guard let code = g.code else { return }
        pickLangCode(code, isLeft: g.isLeft)
    }

    /// **选中一门语言的唯一出口** —— 列表行和「最近用过」chips 都走它。
    ///
    /// 🚨 抽出来的理由跟键盘那屏一样：方案丙给了这一屏**两条选中路径**。
    ///    两条各写一遍必然有一条漏掉"记最近用过"或"两边不许同语言"，
    ///    **而那种漏不报错**，只会表现成"从 chips 选就没记住"。
    func pickLangCode(_ code: String, isLeft: Bool) {
        hideDropdown()
        guard !code.isEmpty else { return }
        // 🚨 记一次"最近用过"，走 `LangRecents.use` 这个唯一写入口 ——
        //    三个选择器各记各的话，"最近用过"在三个界面会给出三种顺序。
        LangRecents.use(code)
        // 🚨 两边不许选成同一种（那样翻了等于没翻）——撞了就跟对面对调。
        if isLeft {
            if code == rightLang { rightLang = leftLang }
            leftLang = code
        } else {
            if code == leftLang { leftLang = rightLang }
            rightLang = code
        }
        renderLangBar()
    }

    private func hideDropdown() {
        dropdown?.removeFromSuperview()
        dropdown = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        hideDropdown()          // 点空白处收掉浮层
    }

    // MARK: - 朗读（点译文大字）

    @objc private func tapSpeak() {
        hideDropdown()
        // 🚨🚨 **每一步都留痕**（2026-09-04 加）。Kevin：「我点那个大字，
        //    它也说不出来话」—— 而这条路原来**一句日志都没有**：
        //    没文字、相位不对、后端失败、音频会话被待机占着，
        //    四种都长成"点了不出声"，分不开。跟录音钮那条同一个毛病。
        KbBridge.note("面对面·点大字朗读：相位=\(phase) 在播=\(Speaker.isPlaying)"
                      + " 文字长度=\(latest.count)")
        if Speaker.isPlaying { Speaker.stop(); return }
        // H1：录音/处理中不许朗读 —— 否则 TTS 会被正在录的麦克风录进去。
        guard phase == .idle else {
            KbBridge.note("面对面·朗读被挡：相位不是 idle（\(phase)）")
            return
        }
        let t = latest
        guard !t.isEmpty else {
            KbBridge.note("面对面·朗读被挡：还没有译文可读")
            return
        }
        // 🚨 **待机占着音频会话时先让开** —— 否则 TTS 起不来，
        //    表现就是"点了没声音"。跟起录前 `yieldMic()` 是同一个道理，
        //    而这条路原来**漏了**（起录让、朗读不让）。
        KbVoiceHost.shared.yieldMic()
        Backend.speak(text: t) { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch r {
                case .success(let mp3):
                    KbBridge.note("面对面·朗读：拿到音频 \(mp3.count) 字节，开播")
                    Speaker.play(mp3) { _ in }
                case .failure(let f):
                    // 🚨 失败要**说出来**，不能静默 —— 他分不出"没反应"和"失败了"。
                    KbBridge.note("面对面·朗读失败：\(f)")
                    self.toast(f.userText)
                }
            }
        }
    }

    // MARK: - 录音（点一下开始，再点一下停）

    @objc private func tapMic() {
        hideDropdown()
        switch phase {
        case .idle: startListening()
        case .listening:
            elapsedTimer?.invalidate(); elapsedTimer = nil
            phase = .thinking
            renderMic()
            if voice.running { voice.stop() }
        case .thinking:
            epoch += 1
            if voice.running { voice.stop() }
            elapsedTimer?.invalidate(); elapsedTimer = nil
            if didYieldMic { KbVoiceHost.shared.reclaimMic(); didYieldMic = false }
            phase = .idle
            renderMic()
        }
    }

    private func startListening() {
        // 🚨🚨 **每一步都留痕**（2026-09-04 加）。Kevin 报「点录音钮根本没反应」，
        //    而这条路径原来**从头到尾一句日志都没有** —— 权限没给、
        //    保活占着会话、引擎起不来，三种都长成"点了没反应"，分不开。
        //    **没有痕迹的失败等于没法查**，只能靠猜，而猜要他再试一次。
        // 🚨 权限**只从 `Voice.micPermission()` 取**（唯一咽喉）。
        //    原来这里直接读 `AVAudioSession.recordPermission` —— 那个在 iOS 17
        //    起已废弃，读出来的值跟 `.undetermined`/`.denied` 都比不上，
        //    两个分支都不成立、直接往下走，卡在更里面而外面没有任何反馈，
        //    表现就是他报的「点了根本没反应」。
        let perm = Voice.micPermission()
        KbBridge.note("面对面·按了录音钮：phase=\(phase) 权限=\(perm)")
        if perm == .undetermined {
            Voice.requestMic { ok in
                DispatchQueue.main.async { if ok { self.startListening() } }
            }
            return
        }
        if perm == .denied {
            navigationController?.pushViewController(SetupViewController(), animated: true)
            return
        }
        Speaker.stop()                       // 起录前停朗读，别把 TTS 录进去
        // 🚨 让出麦克风。`yieldMic()` 里有个提前返回（`holdIsPlayRec` 为真时
        //    **不停保活**）—— 那种情况下静音保活还占着音频会话，
        //    `voice.start` 可能起不来，而且原来一句痕迹都没有。
        KbVoiceHost.shared.yieldMic()
        KbBridge.note("面对面·让麦：待机=\(KbVoiceHost.shared.standby)"
                      + " 保活模式=\(KbVoiceHost.holdIsPlayRec)")
        didYieldMic = true

        epoch += 1
        let recEpoch = epoch
        phase = .listening
        renderMic()

        voiceUsed = true
        // 🚨 **波形必须真的跟着音量动** —— 只把它显示出来、不喂数据，
        //    那是个假反馈（画着一条不动的线），比没有更糟：
        //    他会以为在录，而实际上分不出录没录到。
        //    数据源跟键盘那颗完全一样：`Voice.onLevel`。
        voice.onLevel = { [weak self] v in
            DispatchQueue.main.async { self?.waveView.push(v) }
        }
        // 🚨 起录**结果**也要留痕。09-04 实测：日志停在「让麦」那一行之后
        //    什么都没有 —— 分不清是引擎起来了在等他说话、还是起录当场失败了。
        //    `Voice.start` 失败是**同步回 onWav(.failure)** 的，不抛异常，
        //    所以"没有下文"这件事本身不说明任何问题，必须自己打点。
        KbBridge.note("面对面·起录：调 voice.start（相位已置 listening、波形已开）")
        voice.start(onPartial: { _ in }, onWav: { [weak self] result in
            DispatchQueue.main.async {
                KbVoiceHost.shared.reclaimMic()
                guard let self = self else { return }
                self.didYieldMic = false
                guard recEpoch == self.epoch else { return }
                self.elapsedTimer?.invalidate(); self.elapsedTimer = nil
                switch result {
                case .failure(let f):
                    // 🚨 失败要**说出来**（他分不出"没反应"和"失败了"）。
                    KbBridge.note("面对面·起录失败：\(f)")
                    self.phase = .idle; self.renderMic(); self.toast(f.userText)
                case .success(let wav):
                    KbBridge.note("面对面·录到 \(wav.count) 字节")
                    guard wav.count > 44 else { self.phase = .idle; self.renderMic(); return }
                    self.phase = .thinking
                    self.renderMic()
                    self.transcribeAndTranslate(wav, ep: recEpoch)
                }
            }
        })
    }

    /// 这段 wav 说了多久（毫秒）。
    ///
    /// 🚨 **从字节数算，不用计时器**（照抄安卓 `FaceToFaceActivity`）：
    ///    16kHz / 16bit / 单声道 = 每毫秒 32 字节。计时器算的是"我按住了多久"，
    ///    包含起录前的准备和停录后的收尾；字节数算的是**真正录进去多少**。
    /// 🚨 减掉 44 字节的 WAV 头 —— 不减的话每句都多算 1 毫秒多，
    ///    2000 条下来是实打实的偏差。
    private func wavMs(_ wav: Data) -> Int {
        let bytes = max(0, wav.count - 44)
        return bytes * 1000 / (16_000 * 2)
    }

    private func transcribeAndTranslate(_ wav: Data, ep: Int) {
        Backend.transcribe(wav: wav) { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard ep == self.epoch else { return }
                switch r {
                case .failure(let f):
                    self.phase = .idle; self.renderMic(); self.toast(f.userText)
                case .success(let zh):
                    // M7：空转写别当一句话（省一次 polish 的调用和计费）
                    guard !zh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        self.phase = .idle; self.renderMic(); return
                    }
                    // 🚨 方向：有汉字＝我说的 → 译成**右边**语言；没汉字＝对方说的 → 译回**左边**语言。
                    let mine = Reverse.isMine(zh)
                    let target = mine ? self.rightLang : self.leftLang
                    Backend.polish(text: zh, tone: "", mode: .en, lang: target) {
                        [weak self] r2 in
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            guard ep == self.epoch else { return }
                            self.phase = .idle
                            switch r2 {
                            case .success(let out):
                                guard !out.trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty else { self.renderMic(); return }
                                // 🚨🚨 2026-09-04 补：**面对面说的话原来一条都没进说话记录**
                                //    （安卓 `FaceToFaceActivity` 早就调了 `History.add`，
                                //     iOS 这一屏漏了）。后果两层：
                                //      ① 「说话记录」Tab 里看不见面对面说过的话；
                                //      ② KPI ③④ 少算这一整条入口。
                                // 🚨 `mode` 传 `"en"`：面对面**只有翻译档**，
                                //    没有整理/逐字这两档（跟安卓 `Api.MODE_EN` 一致）。
                                // 🚨 `lang` 传**这一句真正译成了什么**（`target`），
                                //    不是固定的右边语言 —— 对方说英文时译回的是左边。
                                History.add(mode: "en", tone: "", zh: zh, out: out,
                                            durMs: self.wavMs(wav), lang: target)
                                self.utterances.append(out)
                                // 🚨 记住这一对，「＋单词本」要用。
                                //    存 `zh`/`out` 而不是从 `utterances` 反推 ——
                                //    那里只有英文，收进单词本要中英成对
                                //    （`idOf(zh, en)` 两个一起算，见 WordBookCore 注释）。
                                self.lastZh = zh
                                self.lastOut = out
                                self.paintKeep()
                                self.render()
                            case .failure(let f):
                                self.renderMic(); self.toast(f.userText)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 收尾

    private func teardown() {
        epoch += 1
        if voiceUsed, voice.running { voice.stop() }
        elapsedTimer?.invalidate(); elapsedTimer = nil
        if didYieldMic { KbVoiceHost.shared.reclaimMic(); didYieldMic = false }
        Speaker.stop()
    }

    // MARK: - 小工具

    private func toast(_ text: String) {
        let l = PaddingLabel()
        l.text = text
        l.font = .systemFont(ofSize: 14)
        l.textColor = .white
        l.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        l.numberOfLines = 0
        l.textAlignment = .center
        l.layer.cornerRadius = 10
        l.layer.masksToBounds = true
        l.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            l.bottomAnchor.constraint(equalTo: micBtn.topAnchor, constant: -60),
            l.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            l.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
        l.alpha = 0
        UIView.animate(withDuration: 0.2, animations: { l.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.3, delay: 2.2, options: [],
                           animations: { l.alpha = 0 },
                           completion: { _ in l.removeFromSuperview() })
        }
    }
}

/// 带语言码的点击识别器（免给每行挂 tag）。
private final class LangPick: UITapGestureRecognizer {
    var code: String?
    var isLeft = false
}

/// 带内边距的 label，只给 f2f 的 toast 用。
private final class PaddingLabel: UILabel {
    private let inset = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: inset))
    }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + inset.left + inset.right,
                      height: s.height + inset.top + inset.bottom)
    }
}
