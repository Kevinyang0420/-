import UIKit

// Transless 同传输入法 · iOS 键盘扩展
//
// 交互目标（Kevin 2026-08-20 明确的）：**按一下开始说，再按一下停**，然后自动出英文。
// 参照 Typeless 的单按钮形态：界面上只有一个大按钮是主角。
//
// 🚨 上一版做错的地方：
//   1. 界面塞了四个语气标签 + 麦克风 + 三个底部按钮，他不知道该按哪个
//   2. 停下来之后什么反应都没有，他不知道发生了什么
// 现在：一个大按钮独占中间；按一下开始、再按一下停；停了之后**自动**转写→整理→
// 翻译→上屏，全程不用他再点第二个按钮。每一步界面上都写着现在在干嘛。
//
// 🚨 别再加「静音自动收音」：他说口水话时中间会停顿思考，1.8 秒的自动截断会把他打断。
//    下面那个 8 秒只是防呆（忘了关就别一直录着），不是交互主路径。

final class KeyboardViewController: UIInputViewController {
    /// 渐变底。🚨 必须在 viewDidLayoutSubviews 里更新 frame ——
    ///    不更新的话转屏或键盘高度变化时渐变不跟着走，
    ///    表现成「下半截是黑的」，而且只在真机转屏才看得见。
    private var bgLayer: CALayer?


    private enum Phase {
        case idle, listening, thinking
    }

    private let tones = Prompts.all
    private let toneLabels = Prompts.all.map(Prompts.label)
    private var tone = Prompts.normalize(UserDefaults.standard.string(forKey: "vime.tone"))

    private let hintLabel = UILabel()

    /// 录音失败时的**完整现场**。
    ///
    /// 🚨 `hintLabel` 是 `numberOfLines = 1`，塞多行进去**只会显示第一行** ——
    ///    557 就是这么把唯一的诊断线索弄丢的：我为了"修截断"改成换行排，
    ///    结果 Kevin 看到的从 `2003329396 输入 4800…` 变成了
    ///    只剩 `录音引擎：2003329396`。
    ///    **"信息变少"最常见的原因不是系统状态变了，是我们自己把它吃掉了。**
    private var diagView: UITextView?

    /// 🚨 **白下巴定性用的一条 2px 亮线**，贴在我们键盘容器的**最底边**。
    ///
    /// Kevin 报「紫色键盘到 Send 那行就结束，下面还有一条浅灰带，
    /// 里面左边地球、右边麦克风」。**那条带子是谁的我们一直不知道**，
    /// 而这决定了修法完全不同：
    ///   · 线**在灰带上方** → 我们的容器到此为止 → **灰带不是我们的**
    ///     （多半是宿主 App 或系统的输入栏）→ 我们改不了也不该改
    ///   · 线**在灰带下方或看不到** → 灰带在我们容器里 → **是我们的**
    ///
    /// **一次真机、一个二元答案**，比反复问"还在不在"强。
    /// 🚨 临时诊断件，定性之后删掉。
    private let bottomProbe = UIView()
    private let heardLabel = UILabel()
    /// 跑在 App 内的预览页里（不是真扩展）。预览壳会把它设成 true。
    /// 🚨 只影响「完全访问」那条警告 —— 那是扩展独有的概念，
    ///    在 App 进程里恒为 false，不屏蔽就永远挂着。
    var previewMode = false

    private let micButton = UIButton(type: .system)
    /// 麦克风的**偏好**尺寸（priority 999）—— 宽高相等那条才是硬的。
    /// 见 `micButton` 那段注释：写死两个常量不保证是正圆。
    private var micSize: NSLayoutConstraint!
    private let toneButton = UIButton(type: .system)
    private let fallbackButton = UIButton(type: .system)
    /// 打字键盘（字母/符号）。**懒建**：没点 Type 之前不占内存 ——
    /// 键盘扩展的内存上限很紧（约 60MB），建了不用是浪费。
    // ---- 语音面板的控件（照搬安卓 `buildVoicePanel()` 的结构）----
    private let tabTranslate = UIButton(type: .system)
    private let tabTranscribe = UIButton(type: .system)
    private let langButton = UIButton(type: .system)
    private let histButton = UIButton(type: .system)
    private let modeZhButton = UIButton(type: .system)
    private let modeRawButton = UIButton(type: .system)
    private let typeButton = UIButton(type: .system)
    private let speakButton = UIButton(type: .system)
    private let sendButton = UIButton(type: .system)
    private lazy var toneButtons: [UIButton] =
        Prompts.all.map { _ in UIButton(type: .system) }
    /// 语言那格的等宽约束 —— 隐藏它时要一起关掉（见 `paintMode`）。
    private var langWidthC: NSLayoutConstraint?
    private var toneRow: UIStackView?
    private var transRow: UIStackView?
    private var historyPanel: UIView?

    /// 当前档位。**跟主 App 用同一个 key**（`vime.mode`），
    /// 否则在键盘里切了档、回 App 一看还是老的。
    private var mode: Backend.Mode =
        Backend.Mode(rawValue: UserDefaults.standard
            .string(forKey: "vime.mode") ?? "en") ?? .en
    private var lang: String =
        UserDefaults.standard.string(forKey: "vime.lang") ?? "en"
    /// 最后一次上屏的结果 —— 「朗读」要用。
    private var lastOut = ""

    /// 🚨 只为**预览页**能切到打字键盘各档（截图/量高度）。
    ///    正式界面里没有任何地方从外部碰它。
    var typingView: TypingKeyboardView?   // 截图/预览用：放开可见性
    private var voiceRoot: UIStackView?
    private var heightC: NSLayoutConstraint?
    /// 第一次显示时要不要直接进打字键盘。见 `viewDidLoad` 里的说明。
    private var needsInitialTyping = false
    /// 没开「允许完全访问」时挂的那条提示。开了就是 nil。
    private var fullAccessWarning: UILabel?

    // 🚨 懒加载，不在扩展启动瞬间创建。
    //    Voice() 里会 init AVAudioEngine + SFSpeechRecognizer —— 键盘扩展的启动预算
    //    只有几十 MB / 极短的看门狗时限，启动路径上任何重活都可能被系统直接杀掉，
    //    表现就是「选了键盘却弹回上一个」且没有明显报错。录音引擎等第一次按麦克风再建。
    private var phase: Phase = .idle
    /// 进入 thinking 的时刻 —— 用来判"是不是卡死了"。
    private var thinkingSince = Date()

    // MARK: - 界面

    override func viewDidLoad() {
        super.viewDidLoad()
        // 🚨 用户可能只用键盘、从没打开过 App —— 这里也保一次。
        DeviceId.ensure()
        // 🚨 底改成渐变（跟安卓一致）。平涂 Theme.bg 时，
        //    半透明按键透上来的是一片均匀的紫 —— Kevin 说的"太紫了"就是这么来的。
        //
        // 🚨🚨 **`backgroundColor` 不能是 `.clear`** —— 这就是那条
        //    反复被点名的「白下巴」（Kevin 2026-08-26：「底部『白下巴』问题
        //    还是没解决，留白太长了，这个强调过很多次，务必处理」）。
        //
        //    机制：`home indicator` 那条安全区**不在我们的 `view.bounds` 里**，
        //    渐变 CALayer 铺的是 bounds，铺不到那儿；系统用**键盘视图的
        //    `backgroundColor`** 去填那一条。设成 `.clear` 就露出系统默认浅色
        //    —— 那条浅色就是他看到的"白下巴"。
        //
        //    所以背景色设成渐变**最底下那一档**（`Theme.bgBot`），
        //    跟渐变的末端接上，视觉上是连续的。
        //    🚨 渐变层仍然照铺 —— 背景色只负责安全区那一条，
        //       正文区域还是渐变，不会变回"一片均匀的紫"。
        view.backgroundColor = Theme.bgBot
        bgLayer = Theme.keyboardBackground(view.bounds)
        view.layer.insertSublayer(bgLayer!, at: 0)

        // 🚨🚨 「允许完全访问」的提示**不在这里建**（2026-08-26 修）。
        //    原来在 viewDidLoad 里判 `hasFullAccess`，两个致命问题：
        //      ① 这个属性在 viewDidLoad 时**本来就不可靠** ——
        //         扩展刚起来时常读到 false，哪怕用户早就开了
        //      ② 建出来之后**全文件没有任何移除逻辑**，
        //         于是那行红字一旦出现就永远挂在键盘顶上
        //    Kevin 2026-08-26 真机撞到：「为什么这个红字会显示出来？」
        //    → 搬到 `viewWillAppear`，**每次弹键盘都重判**，有权限就摘掉。

        // 🚨🚨 起手是**语音面板**，不是打字键盘 —— 这才是跟安卓一致。
        //    安卓 `VoiceImeService.onStartInputView()` 里明明白白写着
        //    `showTyping(false)`：每次弹出键盘都回到语音面板。
        //    上一版这里写 `needsInitialTyping = true`，注释还说"跟安卓一致"
        //    —— **那句注释是错的**，谁都没去对一眼安卓代码。
        //    （Kevin 2026-08-26 真机截图对比后发现两端差一大截。）
        needsInitialTyping = false

        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = Theme.dim
        hintLabel.textAlignment = .center
        // 🚨🚨 **这一行被压扁过**（2026-08-28 在模拟器上抓到，发包前）。
        //    现象：「先打开 Transless，点一下「键盘语音」再回来说话」
        //    只剩上下各半截，读不了。
        //    根因跟麦克风变橄榄形**同型**：`root` 那个竖直 stack 的总高被
        //    `heightC` 卡死，撑不下时 UIKit 会打断某条约束 —— 这次断的是
        //    这个 label 的固有高度。
        //    **它是新架构里唯一告诉用户"该去开待机"的地方**，压扁了等于没有。
        //
        //    修法两条：
        //      ① 竖直方向**不许被压缩**（优先级 required）。麦克风那边是
        //         999，所以撑不下时先缩麦克风 —— 麦克风本来就设计成会缩的。
        //      ② 允许两行：这句话在窄屏上一行放不下，
        //         1 行会截成「先打开 Trans…」，那跟压扁一样读不了。
        hintLabel.numberOfLines = 2
        hintLabel.setContentCompressionResistancePriority(.required,
                                                          for: .vertical)
        hintLabel.text = ""

        heardLabel.font = .systemFont(ofSize: 15)
        heardLabel.textColor = Theme.text
        heardLabel.textAlignment = .center
        heardLabel.numberOfLines = 2

        // 一个大按钮，占绝对主位
        micButton.setTitle("", for: .normal)
        micButton.setImage(Theme.micGlyph(88), for: .normal)
        micButton.tintColor = .white
        micButton.titleLabel?.font = .systemFont(ofSize: 34)
        micButton.backgroundColor = Theme.accent
        micButton.addTarget(self, action: #selector(tapMic), for: .touchUpInside)
        micButton.translatesAutoresizingMaskIntoConstraints = false
        // 🚨🚨 **麦克风变成橄榄形**（Kevin 2026-08-28：「麦克风怎么变成了一个
        //    橄榄形？」）。根因不是我把尺寸写错了 —— 宽高本来都写的 88：
        //      · `root` 那个竖直 stack 的总高被 `heightC` 卡死；
        //      · 内容撑不下时 UIKit 会**打断某一条必需约束**，
        //        实际被打断的是**高度**那条（宽度那条留着）→ 扁了；
        //      · 而 `cornerRadius` 写死 44 **不会跟着变**，
        //        于是一个 88×70 的方块套着 44 的圆角 = 橄榄。
        //    **写死两个常量 ≠ 保证是正圆。**
        //
        //    修法三条，缺一不可：
        //      ① 宽高相等做成**硬约束**（永远成立，压缩时也成立）
        //      ② 尺寸只是**偏好**（priority 999），撑不下时让它变小而不是变扁
        //      ③ 圆角在 `viewDidLayoutSubviews` 里按**实际高度**算，不写死
        micSize = micButton.widthAnchor.constraint(equalToConstant: 88)
        micSize.priority = .init(999)
        micSize.isActive = true
        micButton.heightAnchor.constraint(
            equalTo: micButton.widthAnchor).isActive = true

        let micWrap = UIView()
        micWrap.addSubview(micButton)
        micButton.centerXAnchor.constraint(equalTo: micWrap.centerXAnchor).isActive = true
        micButton.topAnchor.constraint(equalTo: micWrap.topAnchor).isActive = true
        micButton.bottomAnchor.constraint(equalTo: micWrap.bottomAnchor).isActive = true

        // ---------------------------------------------------------------
        // 顶排：[翻译] [English ▾] (logo) [转写] [历史]
        // 🚨 **照搬安卓 `buildVoicePanel()`**，不是重新设计。
        //    安卓那边四格等宽 + logo 固定宽插正中间，顺序是
        //    「翻译·语言 | logo | 转写·历史」—— 语言是**翻译的参数**，
        //    所以挨着翻译放（Kevin 2026-08-22 专门调过这个顺序）。
        // ---------------------------------------------------------------
        tabTranslate.setTitle(L.kb_translate, for: .normal)
        tabTranscribe.setTitle(L.kb_transcribe, for: .normal)
        langButton.setTitle(langTitle() + " ▾", for: .normal)
        histButton.setTitle(L.kb_history, for: .normal)
        for b in [tabTranslate, langButton, tabTranscribe, histButton] {
            b.titleLabel?.font = .systemFont(ofSize: 13)
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.7
            b.layer.cornerRadius = 8
            b.backgroundColor = Theme.key
            b.setTitleColor(Theme.dim, for: .normal)
        }
        tabTranslate.addTarget(self, action: #selector(pickTranslate),
                               for: .touchUpInside)
        tabTranscribe.addTarget(self, action: #selector(pickTranscribe),
                                for: .touchUpInside)
        langButton.addTarget(self, action: #selector(cycleLang),
                             for: .touchUpInside)
        histButton.addTarget(self, action: #selector(showHistory),
                             for: .touchUpInside)

        let logo = UIImageView(image: UIImage(named: "logo"))
        logo.contentMode = .scaleAspectFit
        logo.alpha = 0.55
        logo.translatesAutoresizingMaskIntoConstraints = false
        // 🚨 只给宽度、不给高度时，`logo` 会被拉成**跟整行一样高的窄条** ——
        //    Kevin 2026-08-28 看到的那个夹在「英文」和「转写」中间的
        //    「T 一样的小方块」就是它。26 宽 × 44 高，怎么看怎么怪。
        //    给它**跟宽度相等的高度并居中**，才是一个正方的小标记。
        logo.widthAnchor.constraint(equalToConstant: 26).isActive = true
        logo.heightAnchor.constraint(
            equalTo: logo.widthAnchor).isActive = true
        // 🚨 **套一个容器**，不是给整排 `alignment = .center`。
        //    整排居中会让四个按钮**也缩成内容高**（那是把问题换个地方，
        //    按钮会从饱满的胶囊变成一条细边）。
        //    容器填满行高、logo 在里面居中 —— 只动 logo 一个。
        let logoBox = UIView()
        logoBox.addSubview(logo)
        logo.centerXAnchor.constraint(
            equalTo: logoBox.centerXAnchor).isActive = true
        logo.centerYAnchor.constraint(
            equalTo: logoBox.centerYAnchor).isActive = true
        logoBox.widthAnchor.constraint(equalToConstant: 26).isActive = true

        let top = UIStackView(arrangedSubviews:
            [tabTranslate, langButton, logoBox, tabTranscribe, histButton])
        top.axis = .horizontal
        top.spacing = 6
        top.distribution = .fill
        // 四个格子等宽，logo 固定 —— 跟安卓一样让 logo 落在正中心
        //
        // 🚨🚨 `langButton` 那条等宽**必须存下来、隐藏时关掉**。
        //    UIStackView 里隐藏一个 arrangedSubview 会把它的尺寸压成 0，
        //    而"等于 tabTranslate 宽"这条约束还生效 —— 两边打架，
        //    整排布局在切到「转写」那一下崩掉（交叉审查 H3）。
        //    另外两个（转写/历史）不会隐藏，所以直接 active 就行。
        for b in [tabTranscribe, histButton] {
            b.widthAnchor.constraint(equalTo: tabTranslate.widthAnchor)
                .isActive = true
        }
        let langW = langButton.widthAnchor.constraint(
            equalTo: tabTranslate.widthAnchor)
        langW.isActive = true
        langWidthC = langW
        top.heightAnchor.constraint(equalToConstant: 34).isActive = true

        // ---------------------------------------------------------------
        // 第二排：翻译档 → 语气三档；转写档 → 整理/逐字
        // 🚨 两排装在**同一个固定高度的容器**里，切档时键盘高度不跳。
        //    安卓那边正是为这个才加的 `subWrap`（Kevin 2026-08-21：
        //    「点翻译是一个高度，点转写它又长高了一点」）。
        // ---------------------------------------------------------------
        for (i, b) in toneButtons.enumerated() {
            b.setTitle(Prompts.label(Prompts.all[i]), for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 13)
            b.layer.cornerRadius = 8
            b.tag = i
            b.addTarget(self, action: #selector(pickTone(_:)),
                        for: .touchUpInside)
        }
        let toneRow = UIStackView(arrangedSubviews: toneButtons)
        toneRow.axis = .horizontal
        toneRow.spacing = 6
        toneRow.distribution = .fillEqually

        modeZhButton.setTitle(L.kb_polish, for: .normal)
        modeRawButton.setTitle(L.kb_verbatim, for: .normal)
        for b in [modeZhButton, modeRawButton] {
            b.titleLabel?.font = .systemFont(ofSize: 13)
            b.layer.cornerRadius = 8
        }
        modeZhButton.addTarget(self, action: #selector(pickPolish),
                               for: .touchUpInside)
        modeRawButton.addTarget(self, action: #selector(pickVerbatim),
                                for: .touchUpInside)
        let transRow = UIStackView(arrangedSubviews:
            [modeZhButton, modeRawButton])
        transRow.axis = .horizontal
        transRow.spacing = 6
        transRow.distribution = .fillEqually

        let subWrap = UIView()
        subWrap.translatesAutoresizingMaskIntoConstraints = false
        subWrap.heightAnchor.constraint(equalToConstant: 32).isActive = true
        for r in [toneRow, transRow] {
            r.translatesAutoresizingMaskIntoConstraints = false
            subWrap.addSubview(r)
            NSLayoutConstraint.activate([
                r.leadingAnchor.constraint(equalTo: subWrap.leadingAnchor),
                r.trailingAnchor.constraint(equalTo: subWrap.trailingAnchor),
                r.topAnchor.constraint(equalTo: subWrap.topAnchor),
                r.bottomAnchor.constraint(equalTo: subWrap.bottomAnchor),
            ])
        }
        self.toneRow = toneRow
        self.transRow = transRow

        // ---------------------------------------------------------------
        // 底排：[🌐] [⌨ 打字] [🔊 朗读] [⌫] [发送]
        // 🚨 安卓是四格 [打字][朗读][⌫][发送]；iOS 多一个 `🌐` ——
        //    那是**平台必需**的（切回系统键盘的唯一入口，安卓由系统提供）。
        //    这是两端唯一允许的差异，别顺手删掉。
        // ---------------------------------------------------------------
        // 🚨 **不用 emoji 当图标**：emoji 由系统按彩色渲染，
        //    在深色键盘上是一颗突兀的蓝绿地球（Kevin：「很丑」）。
        //    下面这套参数是 **Grok 评审给的**，不是我自己挑的
        //    （Kevin：「你不要自己设计了…UI 的东西你问 Grok」）：
        //      符号 globe/keyboard/speaker.wave.2/delete.left
        //      字重 .medium · 尺寸 22pt · 颜色 white α0.85 · .alwaysTemplate
        let globe = smallButton("")
        globe.setImage(Self.kbIcon("globe"), for: .normal)
        globe.tintColor = Self.iconTint
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)),
                        for: .allTouchEvents)

        // 🚨 文案里**不再带 emoji**：`L.kb_type` 原来是「⌨  打字」，
        //    那个 ⌨ 在 iOS 上是彩色 emoji，跟旁边的 SF Symbol 风格打架。
        //    图标改用 `setImage`，文字只留「打字」。
        typeButton.setTitle(L.kb_type_plain, for: .normal)
        typeButton.setImage(Self.kbIcon("keyboard"), for: .normal)
        speakButton.setTitle(L.kb_speak, for: .normal)
        speakButton.setImage(Self.kbIcon("speaker.wave.2"), for: .normal)
        sendButton.setTitle(L.kb_send, for: .normal)   // 发送保持纯文字
        for b in [typeButton, speakButton, sendButton] {
            b.titleLabel?.font = .systemFont(ofSize: 13)
            b.layer.cornerRadius = 8
            b.backgroundColor = Theme.key
            b.setTitleColor(Theme.text, for: .normal)
        }
        // 图标在左、文字在右，间距 6pt（Grok 给的值）
        for b in [typeButton, speakButton] {
            b.tintColor = Self.iconTint
            b.configuration = nil
            b.imageEdgeInsets = UIEdgeInsets(top: 0, left: -3, bottom: 0, right: 3)
            b.titleEdgeInsets = UIEdgeInsets(top: 0, left: 3, bottom: 0, right: -3)
        }
        // 发送是主操作，用强调色（跟安卓一致）
        sendButton.backgroundColor = Theme.accent
        sendButton.setTitleColor(.white, for: .normal)
        speakButton.isEnabled = false        // 没内容可念时不给点
        typeButton.addTarget(self, action: #selector(showTyping),
                             for: .touchUpInside)
        speakButton.addTarget(self, action: #selector(tapSpeak),
                              for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(tapSend),
                             for: .touchUpInside)

        // 同上：⌫ 那个 emoji 在深色底上是蓝色的，跟整块配色打架。
        let del = smallButton("")
        del.setImage(Self.kbIcon("delete.left"), for: .normal)
        del.tintColor = Self.iconTint
        del.addTarget(self, action: #selector(backspace), for: .touchUpInside)

        let bottom = UIStackView(arrangedSubviews:
            [globe, typeButton, speakButton, del, sendButton])
        bottom.axis = .horizontal
        // Grok：键间距统一 8pt；五个键统一高度 44pt（iOS 最小可点区域）
        bottom.spacing = 8
        globe.widthAnchor.constraint(equalToConstant: 46).isActive = true
        del.widthAnchor.constraint(equalToConstant: 46).isActive = true
        for b in [globe, del] {
            b.backgroundColor = Theme.key
            b.layer.cornerRadius = 8
        }
        // 🚨 三个文字键**等宽**。不加这条的话 UIStackView 的 `.fill`
        //    会按 hugging 优先级分配剩余空间，「打字」被拉得老长
        //    （截图里那格宽得离谱），跟安卓四格均分完全不是一回事。
        speakButton.widthAnchor.constraint(
            equalTo: typeButton.widthAnchor).isActive = true
        sendButton.widthAnchor.constraint(
            equalTo: typeButton.widthAnchor).isActive = true
        bottom.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let root = UIStackView(arrangedSubviews:
            [top, subWrap, hintLabel, micWrap, bottom])
        root.axis = .vertical
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        voiceRoot = root
        // 🚨 高度要能改：打字键盘比语音面板高。存下这个约束，切换时改 constant。
        // 🚨 初始高度 = **同一个常量**。原来写死 300，而语音面板
        //    切一轮回来是 250、打字键盘是 242 —— 一个高度三个数。
        let hc = view.heightAnchor.constraint(
            equalToConstant: Layout.panelH)
        heightC = hc
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            // 🚨🚨 **bottom 必须约束**，否则 root 的高度由内容决定，
            //    键盘下面留一条空白 —— Kevin 2026-08-26：「你现在这个下巴
            //    这么大，根本就没有铺上」。原来只有 top + 固定 height，
            //    内容自然撑不满那 250/300。
            root.bottomAnchor.constraint(equalTo: view.bottomAnchor,
                                         constant: -6),
            hc,
        ])

        // 🚨 白下巴定性线（**临时诊断件**）。见 `bottomProbe` 的注释：
        //    这条 2px 荧光绿贴在我们容器的最底边，一次真机就能给出
        //    "那条灰带是不是我们的"这个二元答案。
        //    荧光绿是故意的 —— 配色里没有这个颜色，不会跟任何东西混。
        bottomProbe.backgroundColor = UIColor(red: 0, green: 1, blue: 0.35,
                                              alpha: 1)
        bottomProbe.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomProbe)
        NSLayoutConstraint.activate([
            bottomProbe.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomProbe.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomProbe.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomProbe.heightAnchor.constraint(equalToConstant: 2),
        ])

        paintMode()

        // 🚨 `TRANSLESS_KB_DIAG=1` 时**直接造一次录音失败**，把诊断面板摆出来。
        //    这是为了在**模拟器上验"诊断能不能完整显示"** —— 那一条不需要
        //    真麦克风，而我们已经因为"没先验可见性"浪费了 Kevin 一次真机测试
        //    （557 那版我为了修截断改成换行排，而 `hintLabel.numberOfLines = 1`
        //     把后面几段全吃掉，他只看到 `录音引擎：2003329396`）。
        //    **先验通诊断本身，再让他试。**
        if ProcessInfo.processInfo.environment["TRANSLESS_KB_DIAG"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self = self else { return }
                let fake = Voice.Failure(
                    stage: .engine,
                    detail: "2003329396\ncom.apple.coreaudio.avfaudio\n"
                        + "输入 48000Hz/1ch\n"
                        + Voice.context(rung: 0))
                self.setPhase(.idle, hint: L.kb_rec_failed_tap)
                self.showDiag("\(fake)\n\n" + Voice.diagnostics())
            }
        }
    }

    // MARK: - 每次弹出键盘都重判「完全访问」

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshFullAccessWarning()
    }

    // 🚨🚨 `hasFullAccess` **在扩展刚起来时会读到 false**，哪怕用户早就开了。
    //    Kevin 2026-08-26：「我已经确认我加了这个权限了，但是它还是会
    //    一直出来」。所以判据必须**多个时机各判一次** ——
    //    只判一次的那一次很可能恰好是不准的那一次。
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshFullAccessWarning()
        // 再延迟补一次：扩展的权限状态偶尔要过一拍才准。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refreshFullAccessWarning()
        }
        if needsInitialTyping {
            needsInitialTyping = false
            showTyping()
        }
    }

    /// 宿主输入框内容变了 —— 这时候扩展肯定已经完全就绪，
    /// `hasFullAccess` 在这里最可信。
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshFullAccessWarning()
    }

    /// 「允许完全访问」的提示：**每次弹键盘都重判**，有权限就摘掉。
    ///
    /// 🚨 不能只判一次：`hasFullAccess` 在 `viewDidLoad` 时不可靠，
    ///    而且用户可能中途去设置里开了 —— 开完回来红字还挂着的话，
    ///    他会以为没生效（Kevin 2026-08-26 真机撞到）。
    private func refreshFullAccessWarning() {
        // 🚨 预览壳里**永远不显示这条**。预览跑在主 App 进程里，
        //    `hasFullAccess` 恒为 false（那是**扩展**才有的概念），
        //    于是这条红条在预览页上永远挂着 —— Kevin 2026-08-28 看到的
        //    就是这个，而它跟他手机上真键盘的状态毫无关系。
        //    **一个恒真的警告等于没有警告**，只会让人以为功能坏了。
        if previewMode {
            fullAccessWarning?.removeFromSuperview()
            fullAccessWarning = nil
            return
        }
        if hasFullAccess {
            fullAccessWarning?.removeFromSuperview()
            fullAccessWarning = nil
            return
        }
        if fullAccessWarning != nil { return }
        // 🚨 **不再是一行裸红字**（Kevin：「上面还有那条红字」「很碍眼」）。
        //    Grok 给的方案：淡红底的「轻警告条」+ 橙色警示图标，
        //    保留警示感但不刺眼。数值照抄，没有自己调。
        let warn = PaddedLabel()
        warn.text = "  " + L.kb_need_full_short
        warn.font = .systemFont(ofSize: 12)
        warn.textColor = UIColor(red: 1, green: 0.847, blue: 0.847, alpha: 1)
        warn.numberOfLines = 1
        warn.adjustsFontSizeToFitWidth = true
        warn.minimumScaleFactor = 0.85
        warn.textAlignment = .center
        warn.backgroundColor = UIColor(red: 1, green: 0.3, blue: 0.3,
                                       alpha: 0.12)
        warn.layer.cornerRadius = 8
        warn.layer.masksToBounds = true
        warn.heightAnchor.constraint(equalToConstant: 32).isActive = true
        // 🚨🚨 **插进 root 当第一行**，不要绝对定位。
        //    绝对定位（贴 top 或 bottom）会**压住按钮** ——
        //    贴底压着「打字/朗读/⌫/发送」，贴顶压着「翻译/英文/转写/历史」。
        //    进了 stack 就自己占一行，谁都不挡。
        voiceRoot?.insertArrangedSubview(warn, at: 0)
        fullAccessWarning = warn
    }



    // MARK: - 语音面板 / 打字键盘 切换

    /// 切到打字键盘。**懒建**，第一次点才创建。
    @objc func showTyping() {   // 截图/预览用：放开可见性
        if typingView == nil {
            let t = TypingKeyboardView()
            t.translatesAutoresizingMaskIntoConstraints = false
            t.onText = { [weak self] s in
                guard let p = self?.textDocumentProxy else { return }
                // 🚨 先撤掉 marked text 再插入。拼音缓冲走的是 marked text，
                //    而 `insertText` 在**有 marked text 时**的行为 UIKit 没承诺
                //    —— 宿主可能替换、也可能让「marked 的 nihao」和
                //    「插入的 你好」叠在一起。安卓那边没这个问题：
                //    `commitText` 的语义就是替换 composing。
                //    ⚠️ 未在真实宿主实测（预览页没有宿主输入框，模拟器切键盘
                //       扩展要点 🌐，脚本点不了）。这是按 UIKit 稳妥写法加的，
                //       代价为零；等能在 Safari 里真跑一次再确认。
                p.unmarkText()
                p.insertText(s)
            }
            t.onDelete = { [weak self] in
                self?.textDocumentProxy.deleteBackward()
            }
            t.onSwitchToVoice = { [weak self] in self?.showVoice() }
            // 退格要读光标前的文字（长按连删、按词删），把输入连接给它。
            t.proxyProvider = { [weak self] in self?.textDocumentProxy }
            t.onHeightChange = { [weak self] h in
                guard let s = self, s.voiceRoot?.isHidden == true else { return }
                s.heightC?.constant = h
            }
            // 拼音缓冲 -> 输入框的 marked text（安卓的 setComposingText）。
            // 🚨 空串要 `unmarkText()`，直接 setMarkedText("") 在有些宿主 App
            //    里会留下一个空的标记段，光标行为变怪。
            t.onComposing = { [weak self] s in
                guard let p = self?.textDocumentProxy else { return }
                if s.isEmpty {
                    p.unmarkText()
                } else {
                    p.setMarkedText(s, selectedRange: NSRange(location: s.count,
                                                              length: 0))
                }
            }
            view.addSubview(t)
            NSLayoutConstraint.activate([
                t.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                t.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                t.topAnchor.constraint(equalTo: view.topAnchor),
                t.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            typingView = t
        }
        typingView?.isHidden = false
        voiceRoot?.isHidden = true
        // 🚨 高度由键盘自己按当前档位算（手写档比字母档高一截）。
        //    以前这里写死 280，手写档的底排就被挤扁了。
        heightC?.constant = typingView?.preferredHeight
            ?? Layout.panelH
    }

    @objc private func showVoice() {
        typingView?.isHidden = true
        voiceRoot?.isHidden = false
        // 🚨 语音面板跟打字键盘**同高**（除手写外都一样高）。
        heightC?.constant = Layout.panelH
    }

    // MARK: - 顶排/第二排的行为（照搬安卓）

    @objc private func pickTranslate() { setMode(.en) }

    /// 从翻译切过来时落在「整理」；已经在转写档就保持原来那一档。
    /// 🚨 跟安卓 `tabTranscribe.onClick` 一字不差 —— 别自己改成"总是落整理"。
    @objc private func pickTranscribe() { setMode(mode == .raw ? .raw : .zh) }

    @objc private func pickPolish() { setMode(.zh) }
    @objc private func pickVerbatim() { setMode(.raw) }

    private func setMode(_ m: Backend.Mode) {
        mode = m
        UserDefaults.standard.set(m.rawValue, forKey: "vime.mode")
        paintMode()
    }

    @objc private func pickTone(_ b: UIButton) {
        guard b.tag < Prompts.all.count else { return }
        tone = Prompts.all[b.tag]
        UserDefaults.standard.set(tone, forKey: "vime.tone")
        paintMode()
    }

    /// 语言在支持的清单里循环。
    /// 🚨 清单**从 `Backend.langs` 取**，不在这里再抄一份 ——
    ///    安卓那边为这个栽过（手写的清单漏了新加的语言，同型第三次）。
    @objc private func cycleLang() {
        let all = Backend.langs.map { $0.code }
        let i = all.firstIndex(of: lang) ?? 0
        lang = all[(i + 1) % all.count]
        UserDefaults.standard.set(lang, forKey: "vime.lang")
        langButton.setTitle(langTitle() + " ▾", for: .normal)
    }

    private func langTitle() -> String { Backend.langLabel(lang) }

    /// 按当前档位刷新两排的高亮和显隐。跟安卓 `paintTones()` + `setMode()` 一致。
    private func paintMode() {
        let isTranslate = (mode == .en)
        tabTranslate.backgroundColor = isTranslate ? Theme.accent : Theme.key
        tabTranslate.setTitleColor(isTranslate ? .white : Theme.dim,
                                   for: .normal)
        tabTranscribe.backgroundColor = isTranslate ? Theme.key : Theme.accent
        tabTranscribe.setTitleColor(isTranslate ? Theme.dim : .white,
                                    for: .normal)
        // 🚨 语言只在翻译档有意义 —— 转写是「听到什么写什么」，跟目标语言无关。
        //    安卓那边也是这么藏的。
        langButton.isHidden = !isTranslate
        // 🚨 跟着一起关，见上面那条注释：隐藏 + 等宽约束同时在会打架。
        langWidthC?.isActive = isTranslate
        toneRow?.isHidden = !isTranslate
        transRow?.isHidden = isTranslate
        for (i, b) in toneButtons.enumerated() {
            let on = (Prompts.all[i] == tone)
            b.backgroundColor = on ? Theme.accent : Theme.key
            b.setTitleColor(on ? .white : Theme.dim, for: .normal)
        }
        modeZhButton.backgroundColor = (mode == .zh) ? Theme.accent : Theme.key
        modeZhButton.setTitleColor(mode == .zh ? .white : Theme.dim,
                                   for: .normal)
        modeRawButton.backgroundColor = (mode == .raw) ? Theme.accent : Theme.key
        modeRawButton.setTitleColor(mode == .raw ? .white : Theme.dim,
                                    for: .normal)
    }

    // MARK: - 底排

    /// 朗读最后一次上屏的结果。没有内容时按钮本来就是禁用的。
    ///
    /// 🚨 走主 App 同一条路：`Backend.speak` 拿 mp3 → `Speaker.play`。
    ///    我第一版凭印象写了 `Speaker.speak(_:lang:)` 和 `Backend.tts`
    ///    —— **两个都不存在**。这是今晚第三次凭印象写 API 了，
    ///    以后引用任何跨文件的方法先 grep 一遍再写。
    @objc private func tapSpeak() {
        if Speaker.isPlaying {
            Speaker.stop()
            speakButton.setTitle(L.kb_speak, for: .normal)
            return
        }
        let t = lastOut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        speakButton.setTitle("…", for: .normal)
        Backend.speak(text: t) { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch r {
                case .failure:
                    self.speakButton.setTitle(L.kb_speak, for: .normal)
                case .success(let mp3):
                    Speaker.play(mp3) { [weak self] _ in
                        DispatchQueue.main.async {
                            self?.speakButton.setTitle(L.kb_speak, for: .normal)
                        }
                    }
                }
            }
        }
    }

    /// 「发送」：把宿主输入框里的内容提交。
    ///
    /// 🚨 iOS **没有安卓那个 `sendDefaultEditorAction`** —— 扩展只能通过
    ///    `textDocumentProxy` 插入字符。对多数聊天 App 来说插入换行
    ///    就是发送；对不吃换行的，用户还得自己按一下。
    ///    这是平台限制，不是偷懒；写在这里免得下次有人以为是 bug。
    @objc private func tapSend() {
        textDocumentProxy.insertText("\n")
    }

    // MARK: - 历史

    /// 当前铺出来的那几条 —— 「收藏」按钮靠 `tag` 回来找它。
    private var historyRows: [History.Item] = []

    private func paintKeep(_ b: UIButton, _ got: Bool) {
        b.setTitle(got ? L.kb_kept : L.kb_keep, for: .normal)
        b.setTitleColor(got ? Theme.dim : Theme.accent, for: .normal)
        b.isEnabled = !got
    }

    /// 把这一条收进单词本。
    ///
    /// 🚨 **按真实返回值改按钮**，不是先宣布成功。安卓那边犯过：
    ///    无条件写「已收」，而 `add` 可能返回 empty / 失败，
    ///    用户以为收了，本子里没有。
    @objc private func keepHistory(_ sender: UIButton) {
        let i = sender.tag
        guard i >= 0, i < historyRows.count else { return }
        let it = historyRows[i]
        let r = WordBook.add(zh: it.zh, en: it.out, span: "full",
                             tone: it.tone, today: Srs.todayString())
        let ok = (r == "added" || r == "added_evicted" || r == "same")
        paintKeep(sender, ok)
        // 🚨 键盘里弹不了 UIAlertController（没有可present的层级），
        //    所以结果只能落在按钮和这行提示上。失败必须说出来。
        hintLabel.text = (r == "same") ? L.wb_dupe
            : (ok ? L.wb_saved : L.wb_save_failed)
    }

    @objc private func showHistory() {
        if historyPanel != nil { hideHistory(); return }
        let items = History.list()
        let panel = UIView()
        panel.backgroundColor = Theme.bg
        panel.translatesAutoresizingMaskIntoConstraints = false

        let back = UIButton(type: .system)
        back.setTitle("‹ " + L.kb_history, for: .normal)
        back.titleLabel?.font = .systemFont(ofSize: 15)
        back.setTitleColor(Theme.text, for: .normal)
        back.addTarget(self, action: #selector(hideHistory),
                       for: .touchUpInside)

        let list = UIStackView()
        list.axis = .vertical
        list.spacing = 6
        if items.isEmpty {
            let e = UILabel()
            e.text = L.kb_history_none
            e.font = .systemFont(ofSize: 13)
            e.textColor = Theme.dim
            e.textAlignment = .center
            list.addArrangedSubview(e)
        } else {
            // 🚨 只铺前 8 条。键盘扩展内存紧（~60MB），
            //    50 条全建出来没必要 —— 要翻更多去 App 里看。
            historyRows = Array(items.prefix(8))
            for (i, it) in historyRows.enumerated() {
                let b = UIButton(type: .system)
                b.contentHorizontalAlignment = .left
                b.titleLabel?.font = .systemFont(ofSize: 13)
                b.titleLabel?.lineBreakMode = .byTruncatingTail
                b.setTitle(History.label(it) + "  " + it.out, for: .normal)
                b.setTitleColor(Theme.text, for: .normal)
                b.accessibilityValue = it.out
                b.addTarget(self, action: #selector(insertHistory(_:)),
                            for: .touchUpInside)

                // 🚨🚨 **收藏入口就放在这里** —— Kevin 2026-08-28 原话：
                //    「历史记录里可以留个入口，支持把我说过的这些翻译
                //     同步到我的单词本里」。
                let keep = UIButton(type: .system)
                keep.tag = i
                keep.titleLabel?.font = .systemFont(ofSize: 13)
                // 🚨 按钮自带约 16dp 横向内边距，不清掉就会把「收藏」挤成「收…」
                //    —— 安卓那边「Delete」被截成「Delet」就是这一条。
                keep.contentEdgeInsets = UIEdgeInsets(top: 2, left: 6,
                                                      bottom: 2, right: 6)
                keep.setContentHuggingPriority(.required, for: .horizontal)
                keep.setContentCompressionResistancePriority(.required,
                                                             for: .horizontal)
                paintKeep(keep, WordBook.list().contains {
                    $0.id == WordBookCore.idOf(it.zh, it.out)
                })
                keep.addTarget(self, action: #selector(keepHistory(_:)),
                               for: .touchUpInside)

                let row = UIStackView(arrangedSubviews: [b, keep])
                row.axis = .horizontal
                row.spacing = 8
                list.addArrangedSubview(row)
            }
        }
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        list.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(list)
        panel.addSubview(back)
        panel.addSubview(scroll)
        back.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.topAnchor.constraint(equalTo: view.topAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            back.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            back.leadingAnchor.constraint(equalTo: panel.leadingAnchor,
                                          constant: 12),
            scroll.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor,
                                            constant: 12),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor,
                                             constant: -12),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor,
                                           constant: -8),
            list.topAnchor.constraint(equalTo: scroll.topAnchor),
            list.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            list.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])
        historyPanel = panel
    }

    @objc private func hideHistory() {
        historyPanel?.removeFromSuperview()
        historyPanel = nil
    }

    @objc private func insertHistory(_ b: UIButton) {
        if let t = b.accessibilityValue, !t.isEmpty {
            textDocumentProxy.insertText(t)
        }
        hideHistory()
    }

    // MARK: - 图标统一（参数来自 Grok 评审，别自己改）

    /// 底排图标的统一色：白 α0.85。**不用系统灰** —— Grok 指名这一条，
    /// 系统灰在深色紫底上发冷、跟旁边带文字的键不是一个观感。
    static let iconTint = UIColor.white.withAlphaComponent(0.85)

    /// 统一规格的 SF Symbol：22pt / .medium / alwaysTemplate。
    static func kbIcon(_ name: String) -> UIImage? {
        let cfg = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        return UIImage(systemName: name, withConfiguration: cfg)?
            .withRenderingMode(.alwaysTemplate)
    }

    private func smallButton(_ t: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(t, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 17)
        b.backgroundColor = Theme.key
        b.layer.cornerRadius = 8
        return b
    }

    private func toneTitle() -> String {
        toneLabels[tones.firstIndex(of: tone) ?? 0]
    }

    @objc private func cycleTone() {
        let i = tones.firstIndex(of: tone) ?? 0
        tone = tones[(i + 1) % tones.count]
        UserDefaults.standard.set(tone, forKey: "vime.tone")
        toneButton.setTitle(toneTitle(), for: .normal)
    }

    @objc private func backspace() { textDocumentProxy.deleteBackward() }

    /// 把录音失败的现场完整摆出来：多行、可选中复制、不截断。
    ///
    /// 🚨 用 `UITextView` 而不是 `UILabel`：
    ///    · 能滚动 —— 内容比键盘高时不会被裁掉
    ///    · 能选中复制 —— 他不用再截图，直接粘过来
    ///    `UILabel` 两样都做不到，而这正是前两轮丢信息的原因。
    private func showDiag(_ text: String) {
        diagView?.removeFromSuperview()
        let tv = UITextView()
        tv.text = text
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.textColor = Theme.text
        // 🚨🚨 **不透明 + 铺满 + 置顶**，三样缺一不可。
        //    第一版我用了 `black.withAlphaComponent(0.4)` 并留了边距，
        //    在模拟器上一看：**键盘按钮从半透明底下透上来跟文字叠在一起**，
        //    而且最后几行被底排按钮盖住 —— 「当前路由」那行根本读不到。
        //    这跟 557 那次是同一个毛病的第二种形态：
        //    **诊断"生成了"不等于"读得到"。**
        //    幸好这次先在模拟器上验了，没再浪费他一次真机。
        tv.backgroundColor = UIColor(red: 0.04, green: 0.03, blue: 0.09,
                                     alpha: 1)          // 不透明
        tv.isEditable = false
        tv.isSelectable = true          // 让他能直接复制
        tv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tv)
        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tv.topAnchor.constraint(equalTo: view.topAnchor),
            tv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        // 🚨 **置顶**：`addSubview` 只保证加在当前最上层，
        //    而底排按钮是更晚才布局的，不显式提到最前会被它们盖住。
        view.bringSubviewToFront(tv)
        diagView = tv
        tv.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(hideDiag)))
    }

    @objc private func hideDiag() {
        diagView?.removeFromSuperview()
        diagView = nil
    }

    private func setPhase(_ p: Phase, hint: String) {
        if p == .thinking && phase != .thinking { thinkingSince = Date() }
        phase = p
        hintLabel.text = hint
        switch p {
        case .idle:
            micButton.setTitle("", for: .normal)
            micButton.setImage(Theme.micGlyph(88), for: .normal)
            micButton.tintColor = .white
            micButton.backgroundColor = Theme.accent
            micButton.isEnabled = true
        case .listening:
            micButton.setTitle("", for: .normal)
            micButton.setImage(Theme.stopGlyph(88), for: .normal)
            micButton.backgroundColor = Theme.danger
            micButton.isEnabled = true
        case .thinking:
            micButton.setImage(nil, for: .normal)
            micButton.setTitle("…", for: .normal)
            micButton.setTitleColor(.white, for: .normal)
            micButton.backgroundColor = Theme.keyDown
            micButton.isEnabled = false
        }
    }

    // MARK: - 录音（说完自动收）

    /// 这一轮遥控的命令序号；`-1` = 没有在进行的。
    private var remoteSeq = -1
    /// 已经读到过的结果时间戳，用来只认更新的那条。
    private var lastResAt: TimeInterval = 0
    private var pollTimer: Timer?

    @objc private func tapMic() {
        if phase == .listening { stopListening(); return }
        // 🚨🚨 thinking 必须有出口（交叉审查 H4，安卓修过同型的）。
        //    后端挂了/回调没来时，`phase` 会永远停在 thinking，
        //    麦克风从此点不动 —— 用户只能杀掉宿主 App 才恢复。
        //    超过 90 秒还在 thinking 就当它死了，放行重来。
        if phase == .thinking {
            if Date().timeIntervalSince(thinkingSince) > 90 {
                setPhase(.idle, hint: "")
            } else {
                return
            }
        }

        // 🚨🚨 **键盘扩展自己录不了音，这是 iOS 的硬限制，不是我们的 bug。**
        //    苹果技术问答 QA1872：「App extensions in iOS 8 are not allowed to
        //    record audio」，并点名 `AVAudioEngine startAndReturnError:`（用了
        //    inputNode 时）会返错 —— 那正是 `Voice.start()` 走的路。
        //    系统日志里的判词是
        //    `CMSUtility_IsAllowedToStartRecording: ... was NOT allowed to start
        //     recording **because it is an extension**`（论坛 thread 742601，
        //    2023-12，现代 iOS 上仍然如此）。
        //    **系统查的是「调用方是不是扩展」**，跟音频会话怎么配、Full Access
        //    开没开、麦克风权限给没给全都无关。
        //    2026-08-28 之前那三次真机失败（`2003329396` =
        //    `AVAudioSessionErrorCodeUnspecified`）都是这一条，
        //    「引擎在会话激活前创建」那个假设是错的。
        //    → 所以录音交给主 App，键盘退化成遥控器。见 `KbBridge`。
        guard KbBridge.available else {
            setPhase(.idle, hint: L.kb_rec_failed_tap)
            showDiag(bridgeMissingDiag())
            return
        }
        guard KbBridge.hostAlive else {
            setPhase(.idle, hint: L.kb_need_standby)
            return
        }

        heardLabel.text = ""
        setPhase(.listening, hint: "")
        lastResAt = 0
        // 🚨 语气/模式/语言必须**跟着命令送过去**。
        //    原来这里的注释写着「模式跟 App 共用同一个 UserDefaults 键，
        //    两处切换互通」——**那是错的**：键盘扩展有自己独立的偏好域，
        //    `UserDefaults.standard` 两边从来不是同一份。让主 App 读它自己的，
        //    就会出现「在键盘里选了邮件语气，出来的却是随意」，
        //    而键盘上那个按钮还亮着。
        remoteSeq = KbBridge.send("start", args: [
            "tone": tone,
            "mode": UserDefaults.standard.string(forKey: "vime.mode") ?? "en",
            "lang": UserDefaults.standard.string(forKey: "vime.lang") ?? "en",
        ])
        startPolling()
    }

    private func stopListening() {
        setPhase(.thinking, hint: "")
        KbBridge.send("stop")
    }

    // MARK: - 遥控：等主 App 把结果递回来

    /// 🚨 Darwin 通知只降延迟、**不作唯一路径** —— 进程被挂起时它会丢，
    ///    只靠它的表现是「有时候能用」，那种间歇性故障比彻底坏掉还难查。
    ///    所以这里是**轮询**，通知那条以后可以加，加了也只是让它更快。
    private func startPolling() {
        pollTimer?.invalidate()
        let deadline = Date().addingTimeInterval(120)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) {
            [weak self] t in
            guard let self = self else { t.invalidate(); return }
            if self.remoteSeq < 0 { t.invalidate(); return }
            // 宿主中途被系统关掉：说清楚，别让他对着一个死掉的宿主干等
            if !KbBridge.hostAlive {
                t.invalidate()
                self.remoteSeq = -1
                self.setPhase(.idle, hint: L.kb_host_gone)
                return
            }
            if Date() > deadline {
                t.invalidate()
                self.remoteSeq = -1
                self.setPhase(.idle, hint: L.kb_host_slow)
                return
            }
            guard let r = KbBridge.takeResult(seq: self.remoteSeq,
                                              after: self.lastResAt) else { return }
            self.lastResAt = r.at
            switch r.kind {
            case "partial":
                self.heardLabel.text = r.body
            case "error":
                t.invalidate()
                self.remoteSeq = -1
                // 🚨🚨 **长的现场走全屏面板，别塞进 hintLabel**（2026-08-28 第二次栽）。
                //    `hintLabel` 是 `numberOfLines = 2`，主 App 回来的诊断是十几行 ——
                //    塞进去只显示前两行，Kevin 报的就是「什么什么看不见了」。
                //    557 那次一模一样（当时是 numberOfLines = 1）。
                //    **诊断自己瞎掉，会让下一轮又白费他一次。**
                if r.body.contains("\n") || r.body.count > 24 {
                    self.setPhase(.idle, hint: L.kb_rec_failed_tap)
                    self.showDiag(r.body)
                } else {
                    self.setPhase(.idle, hint: r.body)
                }
            case "text":
                t.invalidate()
                self.remoteSeq = -1
                self.deliver(r.body)
            default:
                break
            }
        }
    }

    /// 主 App 交回来的最终结果：`{"zh": 听到的, "out": 出稿}`。
    ///
    /// 🚨 **先落历史再上屏**，顺序不许倒 —— 照搬 `send()` 里那条：
    ///    上屏可能失败（输入框失焦、宿主换了），而后端已经算完、钱也花了。
    private func deliver(_ json: String) {
        guard let d = json.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: String],
              let out = o["out"], !out.isEmpty else {
            setPhase(.idle, hint: L.kb_host_slow)
            return
        }
        let zh = o["zh"] ?? ""
        let mode = UserDefaults.standard.string(forKey: "vime.mode") ?? "en"
        History.add(mode: mode, tone: tone, zh: zh, out: out)
        lastOut = out
        speakButton.isEnabled = true
        heardLabel.text = ""
        textDocumentProxy.insertText(out)
        setPhase(.idle, hint: "")
    }

    /// 共享容器都拿不到时的现场。**这条是配置问题，不是运行时故障**，
    /// 所以报的东西也不一样：报的是「谁没配好」，不是音频会话那一堆。
    private func bridgeMissingDiag() -> String {
        return """
        === 键盘语音没接通 ===
        共享容器  拿不到（App Group 未生效）
        组名      \(KbBridge.group)

        这是**打包配置**的问题，不是你手机的问题：
        主 App 和键盘要挂在同一个 App Group 上才能互相递话。
        把这一屏发给开发，不用做别的。
        """
    }

    // MARK: - 兜底：翻译光标前已有的中文

    @objc private func translatePending() {
        if phase != .idle { return }
        let t = (textDocumentProxy.documentContextBeforeInput ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            hintLabel.text = L.kb_nothing_before
            return
        }
        heardLabel.text = t
        send(t, replaceChars: t.count)
    }

    // MARK: - 统一出口

    private func send(_ zh: String, replaceChars: Int) {
        guard !Secrets.pass.isEmpty else {
            setPhase(.idle, hint: L.kb_no_pass)
            return
        }
        setPhase(.thinking, hint: "")
        // 模式跟 App 共用同一个 UserDefaults 键，两处切换互通
        let mode = Backend.Mode(
            rawValue: UserDefaults.standard.string(forKey: "vime.mode") ?? "en") ?? .en
        let lang = UserDefaults.standard.string(forKey: "vime.lang") ?? "en"
        Backend.polish(text: zh, tone: tone, mode: mode, lang: lang) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let en):
                    // 🚨🚨 **先落历史 + 存 lastOut，再上屏** —— 顺序不许倒。
                    //    照搬安卓那条血泪注释（他们 2026-08-23 交叉审查 H4）：
                    //    上屏那一步可能失败（输入框失焦、宿主换了），
                    //    而后端已经算完、钱也花了。先落历史，
                    //    至少还留着"去历史里再点一次"这条退路。
                    //
                    //    🚨 这两行今天被交叉审查抓出来是**完全漏掉的**：
                    //    我加了 `History` 类和「朗读」按钮，却没有任何地方
                    //    调 `History.add()`、也没给 `lastOut` 赋值 ——
                    //    两个新功能都是空壳（历史永远空、朗读永远没内容）。
                    History.add(mode: mode.rawValue, tone: self.tone,
                                zh: zh, out: en)
                    self.lastOut = en
                    self.speakButton.isEnabled = true
                    for _ in 0..<replaceChars { self.textDocumentProxy.deleteBackward() }
                    self.textDocumentProxy.insertText(en)
                    self.heardLabel.text = ""
                    self.setPhase(.idle, hint: "")
                case .failure(let err):
                    // 失败绝不动输入框，他说的话还在
                    self.setPhase(.idle, hint: "失败：\(err)")
                }
            }
        }
    }

    deinit {
        // 🚨 键盘被销毁时**必须撤单**：否则主 App 还在替一个已经不存在的键盘
        //    录音，麦克风指示灯一直亮着，而没有任何人会来收结果。
        pollTimer?.invalidate()
        if remoteSeq >= 0 { KbBridge.send("cancel") }
    }

    /// 🚨 渐变底的 frame 必须跟着 bounds 走。
    ///    不更新的话，转屏或键盘高度变化（切数字层/候选条出现）时
    ///    渐变停在旧尺寸，下半截露出透明底 —— 只在真机上才看得见。
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 🚨 圆角按**实际高度**算，不写死 —— 布局压缩时尺寸会变，
        //    写死的圆角会让它变成橄榄形。
        micButton.layer.cornerRadius = micButton.bounds.height / 2
        bgLayer?.frame = view.bounds
        bgLayer?.sublayers?.forEach { $0.frame = view.bounds }
    }
}

/// 键盘上带内边距的 label（轻警告条用）。
private final class PaddedLabel: UILabel {
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: UIEdgeInsets(top: 0, left: 16,
                                                       bottom: 0, right: 16)))
    }
}
