#if canImport(ActivityKit)
import ActivityKit
#endif
import AVFoundation
import UIKit
import ObjectiveC
import os   // os_unfair_lock（M3：渲染线程写、主线程读的两个计数）

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

    /// 🚨🚨 **告诉系统这个键盘支持听写。这是苹果工程师亲口列的录音前提之一。**
    ///
    /// 依据：developer.apple.com/forums/thread/775077，**Apple Engineer 回复原文**
    /// `[核期:2026-08-28 适用:提问 2025-02、末次回复 2025-09]`：
    ///
    /// > 「Are you [configuring open access] and **[indicating dictation support]**?
    /// >   If you are already doing the above and are still getting a `!rec` error,
    /// >   then please use Feedback Assistant to submit a bug report…」
    ///
    /// **苹果的口径是「可以录，但要满足条件」，不是「不许录」** ——
    /// 这跟我们一整晚拿 QA1872（2014 年、iOS 8、通篇没提键盘）推出来的前提相反。
    ///
    /// 三个条件我们**只缺这一个**：
    ///   ① Open Access 配置 ✅
    ///   ② **indicate dictation support** ← 🚨 **全工程原来一处都没有**
    ///   ③ `RequestsOpenAccess = true` ✅（`project.yml`）
    ///
    /// 🚨 **别因此就宣布"根因找到了"** —— 它只是把一个**已知缺失的必要条件**补上。
    ///    成不成看实测：真按一次键盘麦克风，面包屑会记下 `tryLocalRecord` 的结果。
    ///    （在此之前，扩展直录一直是 `2003329396`。）
    override var hasDictationKey: Bool {
        get { true }
        set { }
    }

    /// 渐变底。🚨 必须在 viewDidLayoutSubviews 里更新 frame ——
    ///    不更新的话转屏或键盘高度变化时渐变不跟着走，
    ///    表现成「下半截是黑的」，而且只在真机转屏才看得见。
    private var bgLayer: CALayer?


    private enum Phase {
        case idle, listening, thinking
    }

    private let tones = Prompts.all
    private let toneLabels = Prompts.all.map(Prompts.label)
    private var tone = Prompts.normalize(KbBridge.prefs.string(forKey: "vime.tone"))

    private let hintLabel = UILabel()

    /// 录音失败时的**完整现场**。
    ///
    /// 🚨 `hintLabel` 是 `numberOfLines = 1`，塞多行进去**只会显示第一行** ——
    ///    557 就是这么把唯一的诊断线索弄丢的：我为了"修截断"改成换行排，
    ///    结果 Kevin 看到的从 `2003329396 输入 4800…` 变成了
    ///    只剩 `录音引擎：2003329396`。
    ///    **"信息变少"最常见的原因不是系统状态变了，是我们自己把它吃掉了。**
    private var diagView: UITextView?
    /// 诊断面板的关闭按钮。**跟面板分开存**，见 `hideDiag`。
    private var diagClose: UIButton?

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

    private let micButton = CircleButton(type: .system)
    /// 录音中的波形，画在圆圈**里面**（安卓 2026-08-22 已定案，照抄）。
    private let waveView = WaveView(frame: .zero)
    /// 波形刷新 + 处理中秒数，都挂在它上面。
    private var uiTick: Timer?
    /// 进入 .thinking 的时刻，用来写「3s」。
    private var busySince = Date()
    /// 按下麦克风的时刻，末尾倒计时用。
    private var listenSince = Date()
    /// 波形诊断的上次留痕时刻（一秒一条，别刷爆）。
    private var lastWaveNote = Date.distantPast
    private var kbRecorder: AVAudioRecorder?

    /// **正在飞的那次「后台架引擎」**（可取消）。
    ///
    /// 🚨🚨 原来这里是个裸 `Bool`，交叉审查（20260901_0136 中-1 / 低-1）指出两个毛病：
    ///    ① `viewDidAppear` 的兜底清闸**分不清「卡住的旧标记」和「正在飞的这一次」** ——
    ///       键盘切走再切回只要 0.5 秒，而窗口有 1.2 秒，清掉之后再按一次
    ///       就会有**两个后台架并发**，两个回调各发一次 `start` 给宿主。
    ///    ② 轮询用的是自引用的局部函数 `tick()`：**没有取消手柄**，还漏一份上下文。
    ///    → 换成实例持有的 `DispatchWorkItem`：能取消、无自引用，
    ///      「在不在飞」由它是不是 nil 决定，**只有一个真值**。
    private var bgArmWork: DispatchWorkItem?
    /// **「1.5 秒宿主不应答就改走 arm」那条兜底**（可取消）。
    ///
    /// 🚨🚨 原来是裸 `asyncAfter`，**没有取消手柄**：按下麦克风后 1.5 秒内
    ///    键盘被收起或切走，`teardown` 重置相位那条带 `remoteSeq < 0` 前置，
    ///    所以 phase 仍是 `.listening` → 定时器照跑 → `markWantRec()` + 拉主 App
    ///    → **他没在用键盘，Transless 自己被拉起来**，还留下一张条子。
    ///    （交叉审查 20260901_0252 低-2）
    private var fallbackWork: DispatchWorkItem?
    /// 这次后台架是什么时候起飞的（兜底清闸要靠它区分"卡住"和"正在飞"）。
    private var bgArmStartedAt: Date?
    private var bgArmInFlight: Bool { bgArmWork != nil }
    private var kbCapture: AVCaptureSession?
    private var kbSink: AltAudioSink?
    /// 不跳转那条路上，宿主到底应答过没有。**没应答就要回退到跳转。**
    private var hostAnswered = false
    /// 🚨 等宿主结果的时限。**说话期间为 nil（不设限）**，按了停止才开始计时。
    ///    原来 `startPolling()` 写死 `now + 120`：任何超过两分钟的录音，键盘都会在第 120 秒
    ///    自己切回 idle、提示「等太久了」并忘掉这次录音，而主 App 其实还在录
    ///    （2026-09-02 探针实测能录满 200 秒）。上限不在录音，在键盘等得不耐烦。
    private var pollDeadline: Date?
    /// 等结果期间心跳停了只记一次痕迹，别 0.4 秒刷一条。
    private var hostBeatStaleNoted = false
    private var listenStartedAt = Date()
    /// 上一句说了多久（毫秒）。0 = 还没量过。只进本地历史，**不上传**。
    private var lastSpokeMs = 0
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
    /// 语言下拉浮层。开着时非 nil —— 跟 `historyPanel` 同一套路数。
    private var langPanel: UIView?
    /// 形状告警的节流时刻（中-5）。
    private var lastShapeNote = Date.distantPast
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
        Backend.Mode(rawValue: KbBridge.prefs
            .string(forKey: "vime.mode") ?? "en") ?? .en
    private var lang: String =
        KbBridge.prefs.string(forKey: "vime.lang") ?? "en"
    /// 最后一次上屏的结果 —— 「朗读」要用。
    private var lastOut = ""

    /// 🚨 只为**预览页**能切到打字键盘各档（截图/量高度）。
    ///    正式界面里没有任何地方从外部碰它。
    var typingView: TypingKeyboardView?   // 截图/预览用：放开可见性
    private var voiceRoot: UIStackView?
    private var heightC: NSLayoutConstraint?
    /// 录音圆按钮整体上抬多少 pt（Kevin 09-03 选）：0=现状 · 8=两条功能行之间居中 · 23=面板几何正中。
    private static let micLift: CGFloat = 8

    /// 麦克风右上角那枚琥珀叹号。有存货没传上去时亮。
    private let retryBadge = UILabel()
    /// 角标亮时圆钮下面那行「没传上去 · 再点一下」。
    private let retryHint = UILabel()
    /// 🚨 圆钮的竖向约束存下来 —— 失败态要把它往上让 10，
    ///    **平时必须回到居中**（不许永久上移）。
    private var micTopC: NSLayoutConstraint?
    private var micBotC: NSLayoutConstraint?
    /// 失败态圆钮往上让多少。他定的 10。
    private static let micRetryLift: CGFloat = 10
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
        // 🚨🚨 **键盘一起来就把老位置的历史搬进 App Group**（2026-09-04 补）。
        //
        //    原来 `migrateToGroup()` **只在 `History.list()` 里调**，而键盘的
        //    `list()` 只有他**点开键盘上的历史面板**才跑。后果：
        //    键盘自己容器里那些旧记录（H1 修好之前写的）一直躺在那儿，
        //    主 App 的「说话记录」永远看不见 —— 而**每个进程的老位置是它自己的**，
        //    主 App 那边的迁移搬不动键盘这份。
        //    表现就是"我以前用键盘说的话都没了"，而他不会知道是升级弄的。
        //
        // 🚨 顺带这也是 H1 的**正面证据**来源：这一句会让 `fileURL` 在键盘进程里
        //    解析一次，从而写下「History 落点[键盘扩展]：<路径>」那条日志。
        //    没有它的话，"没看到回落告警"什么都证明不了（缺失 ≠ 0）。
        // 🚨 便宜：一次 `containerURL` + 一次 `fileExists`，老位置没文件就立刻返回。
        // 🚨🚨 **挪到后台线程**（2026-09-04 紧急改）。Kevin 报「键盘用不了了，
        //    一直是语音界面，点打字按钮没反应」，而设备日志在他切键盘之后
        //    **一条都没有** —— 扩展进程压根没起来。
        //
        //    这一行原来是**同步**跑在 `viewDidLoad` 第一句：它要
        //    `containerURL` + 建目录 + 可能整份合并搬迁历史（2000 条）。
        //    键盘扩展的启动预算极小，在这里做磁盘 IO 会把整个扩展拖死 ——
        //    表现就是键盘起不来、点什么都没反应。
        //
        // 🚨 **迁移不该挡在启动路径上**：它是"顺手把旧数据搬过来"，
        //    早一秒晚一秒没区别，但它卡住的代价是**键盘整个不能用**。
        //    放后台、低优先级，起不来也不影响他打字。
        DispatchQueue.global(qos: .utility).async {
            History.migrateFromOldContainer()
        }
        // 🚨 白边修法 v2（2026-09-02 09:2x）：v1 在 viewWillAppear 里开 allowsSelfSizing 太晚 ——
        //    真机序列 932→478 那两帧发生在 willAppear 之前，宿主读到的仍是 478。
        //    "按内容自定尺寸"必须在视图刚建好、系统还没给默认高度之前就打开。
        inputView?.allowsSelfSizing = true
        // 🚨 白边修法 v3：v2 序列仍是 didLoad 0 → 932 → willAppear 932 → 478 → 露面 478 → 250，
        //    且 `window` 高度同步在变 —— 是**系统在给远程窗口定尺寸**，约束要到 didAppear 之后才赢。
        //    远程视图控制器的初始窗口尺寸看的是 `preferredContentSize`，所以在这儿就把它定成 250，
        //    并把初始 frame 也压成 250（宿主 keyboardWillShow 读的是动画起点那一帧）。
        logKbFrame("didLoad")
        // 🚨🚨 **白下巴的解药**（2026-08-28 实测，不是推断）。
        //    Kevin 反复问「这个白下巴真的没法改颜色了吗」。
        //    我们原来的结论是「那是系统的 UIKeyboardDockView，公开 API 改不了色」——
        //    **前半句对，后半句的含义错了。**
        //
        //    ⛔️ 2026-09-03 **这段结论已被真机证伪，别再照它推理。**
        //    原文写的是「模拟器实测：浅色外观 RGB(223,224,230)、深色外观 RGB(27,27,29)，
        //    所以声明深色外观那条带子就会跟着变深」。
        //    量错了对象：量的是**模拟器里系统自带的键盘**，不是**真机上我们自己的键盘**。
        //    Kevin 09-03 在微信里的截图逐像素量：这一行已经生效，
        //    而那条带子仍然是 **#D0D3DA 浅灰**，纹丝不动。
        //    → 那条带子跟的是**宿主 App 的外观**，我们的 override 管不着它。
        //    Kevin 原话：「其他输入法、腾讯输入法也都是这样，下面底边都是改不了的，
        //    这是苹果的限制。所以我才说，你这个要改成渐变色嘛。」
        //    这一行**仍然要留着** —— 它管的是我们自己视图里的系统控件（选择器、光标等），
        //    只是**不要再指望它能染下巴**。
        //
        //    我们全套配色本来就是深色（`Theme.kbPanel` 是深的），
        //    所以这里声明深色外观 —— 不是挑了个颜色，是让系统那条带子
        //    跟我们已有的主题一致。
        //    🚨 配色决定权仍在 2.1：要是以后做浅色主题，这一行要跟着改。
        // 🚨🚨 **方案三（Kevin 2026-09-03 选的）：配色跟着宿主外观分叉。**
        //    原来这里写死 `.dark`，理由是「声明深色，系统那条下巴就跟着变深」——
        //    **那条理由已被他的真机截图证伪**：这一行生效着，下巴照样是 #D0D3DA 浅灰。
        //    下巴跟的是**宿主 App**（微信）的外观，我们的 override 管不着它。
        //    既然管不着，就反过来**跟着它走**：宿主浅色 → 我们整面也浅。
        // 🚨 这一行必须在建任何控件**之前** —— 下面所有 `Theme.kb*` 都是
        //    读 `hostIsLight` 的计算属性，设晚了控件就按上一次的外观建好了。
        let hostLight = (traitCollection.userInterfaceStyle == .light)
        Theme.hostIsLight = hostLight
        overrideUserInterfaceStyle = hostLight ? .light : .dark
        KbBridge.note("外观：宿主=" + (hostLight ? "浅色" : "深色") + "，面板走"
                      + (hostLight ? "浅色（方案三·系统同构）" : "深色（现网深紫）"))
        // 🚨 用户可能只用键盘、从没打开过 App —— 这里也保一次。
        DeviceId.ensure()
        // 🚨 底改成渐变（跟安卓一致）。平涂 Theme.kbPanel 时，
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
        // 🚨 安全区那条由 `backgroundColor` 填，设成实测的下巴色 #D0D3DA，
        //    跟渐变末端和系统那条灰带三者一致 —— 这是方案②（Kevin 09-03 选的）。
        view.backgroundColor = Theme.chin
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
        hintLabel.textColor = Theme.kbHint
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
        heardLabel.textColor = Theme.kbKeyText
        heardLabel.textAlignment = .center
        heardLabel.numberOfLines = 2

        // 一个大按钮，占绝对主位
        micButton.setTitle("", for: .normal)
        Theme.setMicGlyph(micButton, side: 88)
        micButton.tintColor = .white
        micButton.titleLabel?.font = .systemFont(ofSize: 34)
        // 🚨 渐变紫（Kevin 09-04）：底色清掉、改铺渐变图，别两套底叠着
        micButton.backgroundColor = .clear
        micButton.setBackgroundImage(Theme.purpleGrad, for: .normal)
        micButton.addTarget(self, action: #selector(tapMic), for: .touchUpInside)
        // 🚨 给 UI 测试用的标识 —— 有了它我自己就能在真机上点这个键，
        //    不用再让 Kevin 当我的手和眼睛。
        micButton.accessibilityIdentifier = "transless.mic"
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
        // 🚨 中-6：**下限是硬约束。** 只有"宽高相等"时，撑不下会一路缩到接近 0
        //    （正方形，所以形状探针也抓不到）。44pt 是苹果的最小可点尺寸。
        micButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        micButton.heightAnchor.constraint(
            equalTo: micButton.widthAnchor).isActive = true

        let micWrap = UIView()
        // 🚨 尺寸 66% x 46% 照抄安卓 `ws = MIC_CIRCLE_DP*0.66f` / 高 `*0.46f`。
        //    圆的直径这边是 88（见下面那条 widthAnchor）。
        waveView.translatesAutoresizingMaskIntoConstraints = false
        micButton.addSubview(waveView)
        NSLayoutConstraint.activate([
            waveView.centerXAnchor.constraint(equalTo: micButton.centerXAnchor),
            waveView.centerYAnchor.constraint(equalTo: micButton.centerYAnchor),
            waveView.widthAnchor.constraint(
                equalTo: micButton.widthAnchor, multiplier: 0.66),
            waveView.heightAnchor.constraint(
                equalTo: micButton.widthAnchor, multiplier: 0.46),
        ])
        micWrap.addSubview(micButton)
        micButton.centerXAnchor.constraint(equalTo: micWrap.centerXAnchor).isActive = true
        // 🚨 2026-09-03 Kevin：「录音圆按钮位置有点没居中，稍微沉下来了一点」——量出来确实低。
        //    竖排是 顶栏34 + 档位32 + 提示 + 已听到 + 圆按钮 + 底排44（间距 8），
        //    圆按钮上方占 98pt、下方只占 52pt → 圆心落在 148，而面板中心是 125，**低 23pt**。
        //    `micLift` 就是往上抬多少：0＝维持现状；8＝在「档位行↔底排」之间居中（推荐，改动最小）；
        //    23＝圆心正好压在面板几何中心。**等他挑，挑完只改这一个数。**
        // 🚨 存下来：失败态要整体上让 10，**平时回到原位**。
        //    2.1 上一版把它永久上移，平时就不居中了 —— Kevin 当场点名
        //    「你能不能站在一个整体去考虑问题，不要只是头痛医头、脚痛医脚」。
        let mTop = micButton.topAnchor.constraint(
            equalTo: micWrap.topAnchor, constant: -Self.micLift)
        let mBot = micButton.bottomAnchor.constraint(
            equalTo: micWrap.bottomAnchor, constant: -Self.micLift)
        mTop.isActive = true
        mBot.isActive = true
        micTopC = mTop
        micBotC = mBot

        // ── 重试角标：贴在圆钮右上角 ──────────────────────────────
        // 🚨 **琥珀不是红**（他指定 #F0B429）：红＝出错了，琥珀＝等你一下。
        retryBadge.text = "!"
        retryBadge.font = .systemFont(ofSize: 15, weight: .bold)
        retryBadge.textColor = Theme.amberInk   // 🚨 深墨不是白：白压琥珀 1.86:1 看不清
        retryBadge.textAlignment = .center
        retryBadge.backgroundColor = Theme.amber
        retryBadge.layer.cornerRadius = 11
        retryBadge.layer.masksToBounds = true
        retryBadge.isHidden = true
        retryBadge.translatesAutoresizingMaskIntoConstraints = false
        micWrap.addSubview(retryBadge)

        // ── 提示行：圆钮下面一行 ─────────────────────────────────
        // 🚨🚨 **面板高度两态必须完全一样** —— 这行**不进竖直 stack**，
        //    而是浮在 `micWrap` 里，所以它出现/消失都不会让面板长个。
        //    面板一长就会把宿主 App 的内容顶跑（他明确点名）。
        retryHint.text = L.kb_retry_hint
        retryHint.font = .systemFont(ofSize: 13, weight: .medium)   // 🚨 加粗一档：小字抗锯齿会掉对比度
        retryHint.textColor = Theme.kbHintWarn   // 🚨 浅色宿主用深琥珀，琥珀字压浅底 1.68:1 看不清
        retryHint.textAlignment = .center
        retryHint.isHidden = true
        retryHint.translatesAutoresizingMaskIntoConstraints = false
        micWrap.addSubview(retryHint)

        NSLayoutConstraint.activate([
            retryBadge.widthAnchor.constraint(equalToConstant: 22),
            retryBadge.heightAnchor.constraint(equalToConstant: 22),
            retryBadge.centerXAnchor.constraint(
                equalTo: micButton.trailingAnchor, constant: -8),
            retryBadge.centerYAnchor.constraint(
                equalTo: micButton.topAnchor, constant: 8),

            retryHint.centerXAnchor.constraint(equalTo: micWrap.centerXAnchor),
            retryHint.topAnchor.constraint(
                equalTo: micButton.bottomAnchor, constant: 4),
            retryHint.leadingAnchor.constraint(
                greaterThanOrEqualTo: micWrap.leadingAnchor),
            retryHint.trailingAnchor.constraint(
                lessThanOrEqualTo: micWrap.trailingAnchor),
        ])

        // 长按 400ms = 丢掉这条存货（他定的）
        let hold = UILongPressGestureRecognizer(
            target: self, action: #selector(dropPendingAudio(_:)))
        hold.minimumPressDuration = 0.4
        micButton.addGestureRecognizer(hold)

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
            b.backgroundColor = Theme.kbKey
            b.setTitleColor(Theme.kbHint, for: .normal)
        }
        tabTranslate.addTarget(self, action: #selector(pickTranslate),
                               for: .touchUpInside)
        tabTranscribe.addTarget(self, action: #selector(pickTranscribe),
                                for: .touchUpInside)
        // 🚨 Kevin 2026-08-31：「语言…只是点点点的嘛，这个肯定要下拉框啊」。
        //    9 种语言点到粤语要 8 下，而且每一下都真的改了设置。
        langButton.addTarget(self, action: #selector(showLangPicker),
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
        // 🚨 2026-09-03 Kevin：「下面那一排不要用白色了，换个颜色，
        //    跟它自带的白下巴底下的字体颜色、条纹颜色保持统一」。
        //    底排坐在渐变最浅的那一段上，用 `keyOnChin` + `textOnChin`
        //    （深字色是从他截图里量系统那两个图标得的 #464B51，不是我挑的）。
        //    发送键在下面单独覆盖成强调色，不受这里影响。
        // 🚨 **给四个键加稳定标识** —— 量尺时「删除」按文案**找不到**
        //    （它是纯图标键、没有文字），只能从相邻键的坐标反推出 46。
        //    自动化按文案找是那种"今天能用、换个语言就坏"的定位方式。
        typeButton.accessibilityIdentifier = "kb.bottom.type"
        speakButton.accessibilityIdentifier = "kb.bottom.speak"
        sendButton.accessibilityIdentifier = "kb.bottom.send"

        for b in [typeButton, speakButton, sendButton] {
            b.titleLabel?.font = .systemFont(ofSize: 13)
            b.layer.cornerRadius = 8
            b.backgroundColor = Theme.kbBottomKey
            b.setTitleColor(Theme.kbBottomText, for: .normal)
        }
        // 图标在左、文字在右，间距 6pt（Grok 给的值）
        for b in [typeButton, speakButton] {
            // 🚨 图标跟着文字走，否则字变深了图标还是浅色 —— 一半糊一半清楚。
            b.tintColor = Theme.kbBottomText
            b.configuration = nil
            b.imageEdgeInsets = UIEdgeInsets(top: 0, left: -3, bottom: 0, right: 3)
            b.titleEdgeInsets = UIEdgeInsets(top: 0, left: 3, bottom: 0, right: -3)
        }
        // 发送是主操作，用强调色（跟安卓一致）
        sendButton.backgroundColor = .clear
        sendButton.setBackgroundImage(Theme.purpleGrad, for: .normal)
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
        // 🚨 纯图标键、没有文字 —— 量尺用例按文案找它**找不到**，
        //    只能从相邻两键的坐标反推。给它标识，自动化才量得到。
        del.accessibilityIdentifier = "kb.bottom.delete"
        del.setImage(Self.kbIcon("delete.left"), for: .normal)
        // 🚨 删除键也在底排，跟旁边三个一起换 —— 漏掉它就是「四个键三种颜色」。
        del.backgroundColor = Theme.kbBottomKey
        del.tintColor = Theme.kbBottomText
        // 🚨🚨 **走 `Backspace.attach`，不要自己绑单次点击。**
        //    Kevin 2026-08-29：「删除键只能一个一个字母去删，既不能选中一块删除，
        //    也不能连删、快删。**这个在安卓当时那个版本也出现过，为什么又犯同样的错？**」
        //    —— 因为 `Backspace`（首删 → 延时 → 连删 → 超过阈值整词删）**早就写好了**，
        //    打字键盘那边用了它，**唯独这个语音面板的删除键自己绑了 `touchUpInside`**。
        //    规矩没写错，是**没落到这个出口上** —— 跟安卓那次同型，也跟今天其它几处同型。
        // 🚨 顺带解掉「选中一块删不掉」：`deleteBackward()` 在有选区时删的就是整个选区，
        //    原来一次点击只调一次、又没有连删，所以看起来像"删不动"。
        Backspace.attach(del) { [weak self] in self?.textDocumentProxy }

        // 🚨 2026-09-03 Kevin：「地球图标和系统的重复了，不需要在我们这边再设一个」→ 去掉。
        //    `globe` 变量保留但不入栈（handleInputModeList 仍可被系统调用），删控件不删能力。
        let bottom = UIStackView(arrangedSubviews:
            [typeButton, speakButton, del, sendButton])
        bottom.axis = .horizontal
        // Grok：键间距统一 8pt；五个键统一高度 44pt（iOS 最小可点区域）
        // 🚨🚨 **底排四个键的尺寸集中在这里**（Kevin 2026-09-05 13:23 报障：
        //    「发送按钮太大，删除按钮太小，经常点错…下方四个格子的大小需要重新排列」）。
        //
        //    实测现状（屏宽 440）：打字 117 / 朗读 117 / **删除 46** / 发送 117
        //    → **发送是删除的 2.5 倍，而且两者紧挨着**，他说的"经常点错"跟这个对得上。
        //
        // 🚨 **尺寸抽成命名常量、集中在这一处** —— 他还没拍板选哪版，
        //    抽出来之后无论他选甲/乙/丙，都是**改这几个数字**，不用重排结构。
        //    （原来是"删除写死 46、另三个等宽平分"，那种写法改任何一版都要动约束。）
        // 🚨 **现在这几个值＝现状，一个像素没动** —— 他没点头之前不许自己改尺寸。
        // 🚨🚨 **当前是方案乙**（2026-09-05 16:5x 先落地，**Kevin 尚未回字母**）。
        //    他的规矩是「不许自己定尺寸，先出方案给他过目」—— 方案图已经在他面前，
        //    这里先实现是为了**他回一个字母就能立刻出包**，不是替他定了。
        //    他选甲或丙，改下面三个数字即可，结构不用动。
        //
        //      现状：删除 46 / 间距 8 / 送前间距 8   ← 发送:删除 = 2.5 倍
        //      甲：  删除 92 / 间距 8 / 送前间距 8
        //      乙：  删除 88 / 间距 8 / **送前间距 20**  ← 现在这版
        //      丙：  删除 99 / 间距 8 / 送前间距 8（四格均分）
        //
        // 🚨 乙比甲多的那一条**才是直接治「经常点错」的** ——
        //    他说的是误触，缩小发送只治一半，**两键之间拉开距离才治另一半**。
        let kDelW: CGFloat = 88
        let kGapNormal: CGFloat = 8
        let kGapBeforeSend: CGFloat = 20

        bottom.spacing = kGapNormal
        del.widthAnchor.constraint(equalToConstant: kDelW).isActive = true
        // 🚨 单独调「删除↔发送」的间距要用 `setCustomSpacing`：
        //    `bottom.spacing` 是**整行统一**的，改它会把三个间隙一起改宽。
        bottom.setCustomSpacing(kGapBeforeSend, after: del)
        for b in [del] {
            b.backgroundColor = Theme.kbKey
            b.layer.cornerRadius = 8
        }
        // 🚨 三个文字键**等宽**。不加这条的话 UIStackView 的 `.fill`
        //    会按 hugging 优先级分配剩余空间，「打字」被拉得老长
        //    （截图里那格宽得离谱），跟安卓四格均分完全不是一回事。
        // 🚨 **方案乙：朗读和发送缩到跟删除一样宽，打字吃掉剩余**。
        //    原来是「三个文字键等宽」→ 实测各 117，而删除只有 46。
        //    现在改成「朗读 = 发送 = 删除」，三个都是 kDelW；
        //    打字不设宽度，由 stack 把剩余给它（实测会落在 117 附近）。
        // 🚨 **他的三条方向**：发送↓（117→88）、删除↑（46→88）、朗读↓（117→88）。
        //    方向一条都没反。
        speakButton.widthAnchor.constraint(
            equalToConstant: kDelW).isActive = true
        sendButton.widthAnchor.constraint(
            equalToConstant: kDelW).isActive = true
        bottom.heightAnchor.constraint(equalToConstant: 44).isActive = true

        // 🚨🚨 H4：`heardLabel` 原来**从来没被加进视图树** ——
        //    声明了、配置了、三处往里写字，但十处 addSubview 一处都不是它。
        //    表现：识别出来的中文、宿主回来的 partial，**全程不可见**。
        //    主 App 那边（`AppDelegate`）是加进去的，只有键盘漏了。
        let root = UIStackView(arrangedSubviews:
            [top, subWrap, hintLabel, heardLabel, micWrap, bottom])
        root.axis = .vertical
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        voiceRoot = root
        // 🚨 高度要能改：打字键盘比语音面板高。存下这个约束，切换时改 constant。
        // 🚨 初始高度 = **同一个常量**。原来写死 300，而语音面板
        //    切一轮回来是 250、打字键盘是 242 —— 一个高度三个数。
        // 🚨 白边 v7（2026-09-02 10:0x）：高度约束**不再压在系统的 inputView(view) 上**，
        //    改挂在我们自己的内容视图 root 上，并开 allowsSelfSizing 让系统按内容算尺寸。
        //    怀疑：直接约束 inputView 会跟系统自己那条必需约束打架，系统先按临时默认(478/500)起动画，
        //    宿主 keyboardWillShow 读到的就是那一帧；Typeless 只比我们高一点却没白边，
        //    说明宿主一开始读到的就是它的真实高度 —— 它多半没碰 inputView。
        // 🚨 白边 v7 已撤（2026-09-02 12:3x）：约束挂 root + allowsSelfSizing 之后，露面不再落回 250，
        //    键盘停在系统给的 452/472 上、内容只有 236，随后 iOS 直接换成了系统拼音键盘（跑器截图实锤）。
        //    恢复成约束挂在 view 上的 250（v1 之前那版）。
        let hc = view.heightAnchor.constraint(
            equalToConstant: Layout.panelH)
        // 🚨 白边修法（2026-09-02 09:1x，真机序列 932→478→露面478→250）：
        //    键盘上屏那一刻是系统默认的 478，之后才落到我们要的 250；
        //    宿主按 478 让位、我们只画 250 → 上方空出 ~228pt 的白。
        //    苹果给自定义键盘的规矩：高度约束**优先级 999**（跟系统那条不硬碰）。
        // ⛔️ 后半句原文写着「并在 viewWillAppear 里强制排一次」——
        //    **代码里没有那一步**，注释描述了一个不存在的机制（2026-09-03 查出）。
        //    真正的强制排版在下面 `forceHeightIfV8()`，而且**默认关着**。
        hc.priority = UILayoutPriority(999)
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

        // 🚨🚨 白下巴定性线（**临时诊断件**）。
        //    **默认不出现** —— 只有 `TRANSLESS_KB_DIAG=1` 时才画。
        //
        //    2026-08-28：它原来是**无条件**加进视图的，也就是说
        //    **Kevin 装的每一个包，键盘底部都会有一条 2pt 亮绿线**。
        //    他今天已经因为白下巴问过「我怎么才能让你聪明点」——
        //    再看到底部多一条绿线，他不会认为那是把尺，
        //    **他会认为我们又加了个毛病**。
        //
        //    🚨 还有第二个害处：它让 `gate_keyboard_chin` **永远处在假阳性状态**
        //    （量到 6px 非键盘色 = 3 倍屏上的这条线），那道闸门再也说不出真话。
        //    **一个临时诊断件长期挡在闸门前面，等于又造了一道永远失真的检查。**
        //
        //    🚨 这是「测量干扰被测对象」那一族 —— 今天第五次。
        if ProcessInfo.processInfo.environment["TRANSLESS_KB_DIAG"] == "1" {
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
        }

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
                self.setPhase(.idle, hint: KbBridge.hasRetryAudio() ? L.kb_rec_failed_retry : L.kb_rec_failed_tap)
                self.showDiag("\(fake)\n\n" + Voice.diagnostics())
            }
        }
        // 🚨 白边修法 v4（2026-09-02 09:2x）：v3 在 viewDidLoad 开头定尺寸，那时约束还没建，
        //    系统查到内容尺寸为 0 → 退回默认 478 → 宿主按 478 让位。
        //    所以在**约束全部建好之后**再定一次并强制排版，让系统第一次问尺寸时就是 250。
        logKbFrame("didLoad末")
        // 🚨 载入时刷一次角标（2026-09-03 补）：`refreshRetryBadge` 原来只在
        //    `setPhase` 里调，而正常启动**不一定**走到 setPhase → 重开键盘时
        //    如果上一次有"没传上去的存货"，角标要等某次相位切换才亮。
        //    存货是持久的（App Group），一弹出来就该看得见 → 这里补一刀。
        refreshRetryBadge()
    }

    // MARK: - 每次弹出键盘都重判「完全访问」

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 2026-09-03（2.1 铁律第三个字段）：tone 原来只在启动读一次、从不重读——主 App 改了语气，键盘永远拿旧的。
        //    露面时重读一次，显示与发送同源（发送用的也是这个内存 tone）。mode/lang 已各自收口。
        let toneNow = Prompts.normalize(KbBridge.prefs.string(forKey: "vime.tone"))
        if toneNow != tone { KbBridge.note("语气已在别处改过：键盘=" + tone + " 偏好=" + toneNow + " → 跟偏好"); tone = toneNow; paintMode() }
        // 🚨 白边修法：宿主在这之后立刻读键盘高度，所以现在就把 250 排出来
        logKbFrame("willAppear")
        forceHeightIfV8("willAppear")
        refreshFullAccessWarning()
        // 🚨 **`viewWillAppear` 不取稿**：这时输入连接可能还没建立，
        //    插入会被静默丢弃。取稿统一放在 `viewDidAppear`。
        // 🚨🚨 **说实话（审查 M-2）**：顺序是「先落历史 → 再插 → 再抬序号」，
        //    **不是"插成功了才抬"** —— `insertText` 返回 `Void`，
        //    根本没有"成功"这个信号可读。所以插入落空时稿子会作废，
        //    **唯一的补救是它已经进了 `History`**。
        //    别在这儿写一句声称有防护、实际没有的注释：
        //    下一个人会照它做判断。
    }

    // 🚨🚨 `hasFullAccess` **在扩展刚起来时会读到 false**，哪怕用户早就开了。
    //    Kevin 2026-08-26：「我已经确认我加了这个权限了，但是它还是会
    //    一直出来」。所以判据必须**多个时机各判一次** ——
    //    只判一次的那一次很可能恰好是不准的那一次。
    /// **白边 v8** —— 让「露面」那一刻就等于 250。🚨 **默认关着。**
    ///
    /// 根因（真机痕迹坐实）：露面那一刻 `view=445/452/467/478`，而约束只要 250。
    /// 宿主按 445 让位、我们只画 250 → 上面空出约 195px 的白。
    /// v1–v7 全在调下沿那个 250，**没有一版拦住 445 这个上沿**。
    ///
    /// 🚨 **v7 是怎么坏的**（不能重演）：它把约束改挂到 root 并开 `allowsSelfSizing`，
    ///    结果露面后停在 452/472 不落回 250，**iOS 直接弃用我们的键盘、换成系统拼音**。
    ///    所以 v8 **不动约束的挂载点和优先级**，只在这一拍主动把值按下去并强排一次。
    ///
    /// 🚨 **开关文件 `whiteedge_v8`，默认没有＝关**。出问题删掉那个文件即回滚，
    ///    不用重装。判据见 `_白边v8_回滚判据_20260903.md` 的 A/B/C 三条 ——
    ///    **B（键盘还在不在屏幕上）只能靠截图判**，光看高度日志会漏掉 v7 那种死法。
    private func forceHeightIfV8(_ where_: String) {
        guard KbBridge.flag("whiteedge_v8") else { return }
        let target = typingView?.isHidden == false
            ? (typingView?.preferredHeight ?? Layout.panelH) : Layout.panelH
        heightC?.constant = target
        // 🚨 `preferredContentSize` 是**远程视图控制器定初始窗口尺寸**看的那个，
        //    宿主 `keyboardWillShow` 读的就是动画起点那一帧 —— 光改约束够不着它。
        preferredContentSize = CGSize(width: view.bounds.width, height: target)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        KbBridge.note("白边v8｜" + where_ + " 强制排版 → 目标 "
                      + String(Int(target)) + "｜此刻 view=" + String(Int(view.bounds.height)))
    }

    /// **角标状态的唯一出口。** 别在别处直接改 `retryBadge.isHidden`。
    ///
    /// 🚨 **面板高度两态完全一样**：提示行浮在 `micWrap` 里、不进竖直 stack，
    ///    所以显示/隐藏都不会让面板长个（他点名：一长就把宿主的内容顶跑）。
    /// 🚨 **平时圆钮居中，失败时圆+字当一整块居中**（圆往上让 10）——
    ///    不许永久上移。
    private func refreshRetryBadge() {
        // 🚨 调试开关 `kb_force_retry`：强制点亮角标，**只为我自己截图验收 UI**
        //    （两态高度一样 / 失败整块居中 / 琥珀不用红 / Speak 不变灰）。
        //    真机 devicectl 不能截图、键盘扩展 UI 又要真失败一次才亮，
        //    没这个开关我就只能等 Kevin 失败一次才看得到对不对。
        //    环境变量 `TRANSLESS_KB_FORCE_RETRY=1`（模拟器可注入）或
        //    App Group `flags.txt` 里写 `kb_force_retry` 都能开；平时两者都没有=关。
        // 🚨🚨 **env 变量这一路原来根本没接**（2026-09-03 修）：注释白纸黑字写着
        //    「环境变量能开」，但下面只查了 `KbBridge.flag`（那个只读 App Group），
        //    而 App Group 在模拟器里失效 → 模拟器上这个开关**永远打不开**，
        //    我想截图验收角标就卡在这。这正是"注释承诺了、代码没实现"的假开关。
        //    真机上用户设不了 env（只有 simctl/Xcode 启动能注入），泄不了也误触不了。
        let forceEnv = ProcessInfo.processInfo
            .environment["TRANSLESS_KB_FORCE_RETRY"] == "1"
        let on = KbBridge.hasRetryAudio() || KbBridge.flag("kb_force_retry") || forceEnv
        retryBadge.isHidden = !on
        retryHint.isHidden = !on
        micTopC?.constant = -Self.micLift - (on ? Self.micRetryLift : 0)
        micBotC?.constant = -Self.micLift - (on ? Self.micRetryLift : 0)
        // 🚨 **角标亮时 Speak 不准变灰**（他亲口）——
        //    那是他"我要说新的一句"的唯一出口，灰掉就等于又把他堵死了。
        if on {
            speakButton.isEnabled = true
            speakButton.alpha = 1.0
        }
        view.layoutIfNeeded()
    }

    /// 长按 400ms：丢掉这条存货。他定的。
    @objc private func dropPendingAudio(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, KbBridge.hasRetryAudio() else { return }
        KbBridge.setHasRetryAudio(false)
        KbBridge.clearPendingAudio()
        KbBridge.send("drop", args: [:])
        KbBridge.note("键盘：长按丢掉了那条没传上去的")
        refreshRetryBadge()
        setPhase(.idle, hint: "")
    }

    private var pendingWatch: Timer?


    /// **按需在键盘进程里试一次录音**（`com.kevin.transless.debug.kbmic`）。
    ///
    /// 🚨 这是为了推翻/坐实「键盘扩展不能录音」那条结论。
    ///    上一次得出它的时候**主 App 正握着麦克风输入**，
    ///    那个实验的前置条件根本不干净。
    ///    判据是**录到的字节数**，不是错误码。
    private func armKbMicProbe() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, obs, _, _, _ in
                guard let obs = obs else { return }
                let me = Unmanaged<KeyboardViewController>
                    .fromOpaque(obs).takeUnretainedValue()
                DispatchQueue.main.async { me.runKbMicProbe() }
            },
            "com.kevin.transless.debug.kbmic" as CFString,
            nil, .deliverImmediately)
    }

    private func runKbMicProbe() {
        // 🚨 顺带把宿主身份探测也跑一遍 —— 这条通道我能主动触发，
        //    不必等他按麦克风。SecTask 那一族成不成，一次就知道。
        // 🚨🚨🚨 **收回开关后面（2026-08-31 19:2x）—— 它把他的键盘搞崩了。**
        //    Kevin：「为什么我说完话之后，键盘设置就变成了默认输入法（简体拼音）？」
        //    **扩展一崩，iOS 就自动切回系统键盘** —— 那就是这个症状。
        //    这段做 ObjC 运行时枚举 + dlsym + RunningBoard 调用，
        //    几小时前加 csops 时已经把键盘搞崩过一次，我摘了 csops
        //    **却把整段留在了每次按麦克风都跑的路径上**。
        //    它是诊断件，不是产品功能 —— 默认不跑。
        if KbBridge.flag("probehost") { probeHostApp() }
        KbBridge.note("键盘麦克风实验：开始（宿主活着=" + String(KbBridge.hostAlive)
                      + "｜引擎架着=" + String(KbBridge.hostArmed())
                      + "｜完全访问=" + String(hasFullAccess) + "）")
        recordWithRecorder(seconds: 2) { data, err in
            let n = data?.count ?? 0
            KbBridge.note("键盘麦克风实验·AVAudioRecorder：" + String(n) + " 字节"
                          + (err.map { "｜错误 " + $0 } ?? "｜没报错"))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.probeCaptureStack()
        }
    }

    /// **让宿主 App 回到前台** —— `NSExtensionContext.completeRequest`。
    ///
    /// 🚨 这条语义上正好是「做完事，回到宿主」（分享扩展就靠它），
    ///    而且是**公开 API** —— 我今天挖的 15 条里一条都没碰过它。
    ///    Kevin：「它必须能自己跳回原 APP」。
    ///
    /// 🚨 挂在**主 App 架好之后**发来的通知上：那一刻宿主还活着、
    ///    键盘扩展也还在，正是能"回去"的时机。
    private func armReturnChannel() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, obs, _, _, _ in
                guard let obs = obs else { return }
                let me = Unmanaged<KeyboardViewController>
                    .fromOpaque(obs).takeUnretainedValue()
                DispatchQueue.main.async {
                    guard let ctx = me.extensionContext else {
                        KbBridge.note("回宿主：没有 extensionContext"); return
                    }
                    KbBridge.note("回宿主：调 completeRequest —— 看他落在哪个 App")
                    ctx.completeRequest(returningItems: nil) { ok in
                        KbBridge.note("回宿主：completeRequest 回调 ok=" + String(ok))
                    }
                }
            },
            "com.kevin.transless.backtohost" as CFString,
            nil, .deliverImmediately)
    }

    /// **扒开 `extensionContext`，看 iOS 26 有没有留下宿主身份的字段。**
    ///
    /// 🚨 为什么值得做：Apple DTS 说**没有公开 API** 能认出宿主 —— 这句话是对的，
    ///    但它没说**私有字段也不存在**。而现有全部证据都指向"必须知道宿主是谁"：
    ///      · Typeless 返回时主 App 进程号**一直没变**（17430 稳着）→ 它不是结束自己；
    ///      · `suspend` / `exit(0)` / `terminate` 全部实测落桌面 → 不是那三条；
    ///      · 它能从**淘宝、小红书**回去，而这两个**不在**它声明的 50 个 scheme 里
    ///        → 也不是"照声明表挨个 canOpenURL 猜"。
    ///    → 只剩 `open(宿主的 scheme)`。而 `open()` **不需要声明**（只有 `canOpenURL` 需要），
    ///      所以它缺的只有"宿主是谁"这一个信息。**这个探针就是去找它。**
    ///
    /// 🚨 **只读名字，不乱 `valueForKey`**：对不存在的键取值会抛 ObjC 异常，
    ///    Swift 接不住 —— 那会变成在他手机上崩键盘。只对**对象类型（编码 `@`）**
    ///    且名字里带 host/bundle/pid/app 的 ivar 用 `object_getIvar` 读，这条是安全的。
    /// **宿主是谁 —— 直接问系统，不猜。**
    ///
    /// 🚨🚨🚨 iOS 26 的 `UIInputViewController` 上有 `_hostApplicationBundleIdentifier`
    ///    （2026-09-02 类级扒表扒出来的，同族还有 `_hostProcessIdentifier` /
    ///    `_hostAuditToken`，`_UIViewServiceViewControllerOperator` 上另有 ivar `_hostBundleID`）。
    ///    Apple DTS 说「**没有公开 API** 能认出宿主」—— 那句话是对的，
    ///    **但它没说私有的不存在**，而我把它读成了"这件事做不到"，白绕三天。
    ///    → 教训：**「没有公开 API」≠「做不到」**，官方否定只覆盖它自己的那个范围。
    ///
    /// 🚨 这是私有 API：上架审核有被拒风险（他这台是开发签名的自用包，先跑通再谈）。
    ///    所以一律 `responds(to:)` 先问、拿不到就**安静退回猜的那条**，绝不硬调。
    /// **第二条独立路径：从审计令牌里挖出宿主 PID，再把 PID 翻成路径。**
    ///
    /// 🚨 为什么要第二条：`_hostApplicationBundleIdentifier` 在"宿主＝自家容器"这个样本上
    ///    返回的是常量字符串 `"<null>"`（不是 nil，是 Apple 塞的占位符）。
    ///    那一枪打在自家宿主上，**判不了第三方宿主时是什么行为** —— 与其等一次按压
    ///    只换一个答案，不如让同一次按压同时验两条路。
    ///
    /// 🚨 `proc_pidpath` 是 **公开的 BSD API**（`<libproc.h>`），不是私有 selector；
    ///    但沙盒可能不让读别的进程 —— 读不到就老老实实返回 nil，别装作成功。
    /// 🚨 `audit_token_t` 是 8 个 uint32，**PID 在下标 5**（`val[5]`）。
    /// **最后一条没试过的取法：找到 `_UIViewServiceViewControllerOperator` 实例，读它的 `_hostBundleID` ivar。**
    ///
    /// 🚨 前面四条判死的都是**别的对象**：`self`（UIInputViewController）上的方法、
    ///    `extensionContext` 上的方法、审计令牌、XPC 连接描述。
    ///    而类级扒表显示，**只有 `_UIViewServiceViewControllerOperator` 这个类
    ///    真的有一个叫 `_hostBundleID` 的 ivar** —— 我却从没拿到过它的**实例**。
    ///    「扒过这个类」≠「读过这个对象」。
    ///
    /// 🚨 只走**对象型 ivar**（编码以 `@` 开头），`object_getIvar` 对它们是安全的；
    ///    深度 2、节点上限 400，避免在他键盘弹出的关键路径上耗时。
    /// 🚨 不用 `value(forKey:)`（装不下结构体会抛异常打崩键盘，今晚已栽过）。
    private func findOperatorHost() -> String? {
        var seen = Set<ObjectIdentifier>()
        var queue: [(AnyObject, Int)] = []
        if let c = self.extensionContext { queue.append((c as AnyObject, 0)) }
        queue.append((self, 0))
        var visited = 0
        while !queue.isEmpty, visited < 400 {
            let (obj, depth) = queue.removeFirst()
            visited += 1
            let oid = ObjectIdentifier(obj)
            if seen.contains(oid) { continue }
            seen.insert(oid)
            let clsName = String(describing: type(of: obj))
            if clsName.contains("ViewServiceViewControllerOperator") {
                var c: AnyClass? = type(of: obj)
                while let k = c {
                    var n: UInt32 = 0
                    if let ivars = class_copyIvarList(k, &n) {
                        for i in 0..<Int(n) {
                            guard let np = ivar_getName(ivars[i]) else { continue }
                            if String(cString: np) == "_hostBundleID" {
                                let v = object_getIvar(obj, ivars[i])
                                free(ivars)
                                let got = (v as? String) ?? String(describing: v)
                                KbBridge.note("operator._hostBundleID = " + got)
                                // 🚨🚨 **`<null>` 不是包名，是苹果的占位符** ——
                                //    上一版这里直接 return 了它，于是
                                //    `rememberHost("<null>")` 把假宿主存进共享区，
                                //    回程会拿它去查表（查不到→退回猜，不致命但是**假数据**）。
                                //    过滤规则跟上面那四个选择器**必须一致**：
                                //    非空、不是 `<null>`、且含点号才算包名。
                                //    （同一个规则两处实现 = 必漂，这次就漂了。）
                                if let str = v as? String,
                                   !str.isEmpty, str != "<null>", str.contains(".") {
                                    return str
                                }
                                return nil
                            }
                        }
                        free(ivars)
                    }
                    c = class_getSuperclass(k)
                }
            }
            guard depth < 2 else { continue }
            var c2: AnyClass? = type(of: obj)
            var lv = 0
            while let k = c2, lv < 3 {
                lv += 1
                var n: UInt32 = 0
                if let ivars = class_copyIvarList(k, &n) {
                    for i in 0..<Int(n) {
                        let enc = ivar_getTypeEncoding(ivars[i]).map { String(cString: $0) } ?? ""
                        guard enc.hasPrefix("@") else { continue }
                        if let child = object_getIvar(obj, ivars[i]) as AnyObject? {
                            queue.append((child, depth + 1))
                        }
                    }
                    free(ivars)
                }
                c2 = class_getSuperclass(k)
            }
        }
        KbBridge.note("operator 搜索：走了 " + String(visited)
                      + " 个对象，没找到带 _hostBundleID 的 operator")
        return nil
    }

    func hostByAuditToken() -> String? {
        guard let ctx = self.extensionContext else {
            KbBridge.note("宿主探针 ▸ extensionContext 是 nil"); return nil
        }
        let obj = ctx as AnyObject
        let sel = NSSelectorFromString("_extensionHostAuditToken")
        guard obj.responds(to: sel) else {
            KbBridge.note("宿主探针 ▸ 审计令牌：不响应"); return nil
        }
        // 🚨🚨🚨 **不能用 `value(forKey:)`，也不能用 `perform`。**
        //    这个方法返回的是 `audit_token_t` —— 一个 **32 字节的 C 结构体**。
        //    KVC 装不下结构体，`valueForKey:` 会抛异常；而键盘扩展里的 ObjC 异常
        //    Swift 接不住 → **进程当场崩掉**。表现就是：前面几条日志都在，
        //    从这一句开始一条都没有，看起来像"代码没被执行"。
        //    （我为此查了三轮"为什么不执行"，真相是它执行了然后死了。
        //     教训：**日志断在某一句 ≠ 没走到那一句**，也可能是走到了就没命了。）
        //    正解：拿 IMP 按真实签名直接调，结构体返回由 arm64 的 sret 规则处理。
        typealias TokFn = @convention(c) (AnyObject, Selector) -> audit_token_t
        guard let m = class_getInstanceMethod(type(of: obj), sel) else {
            KbBridge.note("宿主探针 ▸ 审计令牌：拿不到方法"); return nil
        }
        let f = unsafeBitCast(method_getImplementation(m), to: TokFn.self)
        let tok = f(obj, sel)
        // 🚨🚨🚨 **只把 SecTask 这一小段搬过来，不搬 `probeHostApp()` 整个。**
        //    那个函数 2026-08-31 **把他的键盘搞崩过** —— 扩展一崩 iOS 就切回简体拼音，
        //    正是他当时报的症状。它做 ObjC 运行时枚举 + dlsym + RunningBoard 调用，
        //    而我要的只是其中三个 dlsym 符号。**要哪一段就搬哪一段，别为了省事开整个开关。**
        //
        //    台账记着 `SecTaskCopySigningIdentifier` / `SecTaskCopyValueForEntitlement`
        //    都返回 nil —— **但没记那是在哪种宿主下测的**，而在今晚之前我只造得出
        //    "自家容器当宿主"这一种样本。现在用 `sms:` 能随时把键盘送进第三方 App，
        //    所以这个结论要重测一次。**结论存着、样本可能一直不对**，是同族的坑。
        typealias SecCreateFn = @convention(c) (CFAllocator?, audit_token_t) -> Unmanaged<AnyObject>?
        typealias SecIdFn = @convention(c) (AnyObject, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFString>?
        typealias SecEntFn = @convention(c) (AnyObject, CFString, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFTypeRef>?
        if let hSec = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW)
                      ?? dlopen(nil, RTLD_NOW),
           let symC = dlsym(hSec, "SecTaskCreateWithAuditToken") {
            let create = unsafeBitCast(symC, to: SecCreateFn.self)
            if let taskRef = create(nil, tok) {
                let task = taskRef.takeRetainedValue()
                var got: String? = nil
                if let symI = dlsym(hSec, "SecTaskCopySigningIdentifier") {
                    var e: Unmanaged<CFError>?
                    if let idRef = unsafeBitCast(symI, to: SecIdFn.self)(task, &e) {
                        got = idRef.takeRetainedValue() as String
                    }
                }
                if got == nil, let symE = dlsym(hSec, "SecTaskCopyValueForEntitlement") {
                    let ent = unsafeBitCast(symE, to: SecEntFn.self)
                    var e2: Unmanaged<CFError>?
                    if let v = ent(task, "application-identifier" as CFString, &e2),
                       let str = v.takeRetainedValue() as? String {
                        // 形如 `TEAMID.com.tencent.xin` —— 去掉队伍号前缀
                        got = str.contains(".") ? String(str.drop(while: { $0 != "." }).dropFirst()) : str
                    }
                }
                if let g = got, g.contains(".") {
                    KbBridge.note("🎉 签名标识：宿主 = " + g)
                    KbBridge.rememberHost(g)
                } else {
                    // 已判死，不再刷屏
                }
            } else {
                KbBridge.note("签名标识：SecTaskCreateWithAuditToken 返回 nil")
            }
        }
        let pid = Int32(bitPattern: tok.val.5)
        // 🚨 **回程准度：先量再修**（2026-09-02 07:5x，不改任何行为，只记证据）。
        //    认宿主五条全判死，但**宿主 PID 是拿得到的**。于是有一个可测的信号：
        //    回程猜对了 → 他会在**同一个 App** 里接着打字 → 键盘再露面时 PID 不变；
        //    猜错了 → 他得手动切回去 → PID 会不同、或者间隔明显更长。
        //    这条日志就是为了几天后回答：**这个信号到底靠不靠谱**。
        //    🚨 只记不判 —— 现在就拿它做决策是拿没验过的指标下结论。
        KbBridge.logReturnAccuracy(hostPid: Int(pid))
        if !KeyboardViewController.didLogSel {
            KbBridge.note("宿主探针 ▸ 审计令牌里的宿主 PID = " + String(pid))
        }
        if pid > 0 { KbBridge.rememberHostPid(pid) }
        // 令牌本体也存（32 字节）：主 App 拿它去问 LaunchServices「这是谁」
        let tokData = withUnsafeBytes(of: tok) { Data($0) }   // tok 是 let，用非 inout 版本
        KbBridge.rememberHostToken(tokData)
        return nil
    }

    func hostBundleIDNow() -> String? {
        var best: String? = nil
        for name in ["_hostApplicationBundleIdentifier", "_hostBundleID",
                     "hostBundleID", "_hostApplicationBundleID"] {
            let sel = NSSelectorFromString(name)
            if !self.responds(to: sel) {
                KbBridge.note("宿主探针 ▸ " + name + "：不响应")
                continue
            }
            let raw = self.perform(sel)?.takeUnretainedValue()
            let desc = raw == nil ? "nil" : String(describing: raw!)
            let cast = (raw as? String)
            // 🚨 啰嗦的原始值**每个进程只打一次**：痕迹是 200 行的环形缓冲，
            //    每次键盘露面都打 4 行，会把真正要等的那一条（他在微信里按的那次）挤掉。
            // 🚨 2026-09-02 13:0x：改回每次都打（要在真微信/eMPF 宿主下抓干净值）
            if true {
                KbBridge.note("宿主探针 ▸ " + name + "：原始=" + desc
                              + "｜类型=" + (raw == nil ? "-" : String(describing: type(of: raw!)))
                              + "｜转字符串=" + (cast ?? "失败"))
            }
            // 🚨 `<null>` 是 NSNull 的描述，不是 bundle id —— 明确排掉，
            //    否则它会一路走到 open() 变成一个开不了的 URL，然后我又要去查"为什么没回去"。
            if let c = cast, !c.isEmpty, c != "<null>", c.contains(".") { best = best ?? c }
        }
        // 🚨🚨🚨 **这里原来有一行 `perform(_hostProcessIdentifier)`，是它把键盘打崩的。**
        //    那个方法返回 **`int`**，而 `perform` 一律按"返回对象指针"处理 ——
        //    拿到的是把整数当指针的野值，`String(describing:)` 一碰就死。
        //    表现：日志永远断在同一句，看起来像"后面的代码没被执行"，
        //    于是我一连查了三轮**后面那段**，真凶却在**前面一行**。
        //    → 教训：**日志断点 ≠ 故障点**。断点只说明"到这儿为止还活着"，
        //      下一句可能是没走到，也可能是走到了就没命了。
        //    返回非对象（int/结构体）的 selector **一律走 IMP + 真实签名**，
        //    绝不用 `perform` / `value(forKey:)`。PID 从审计令牌拿，够了。
        KeyboardViewController.didLogSel = true
        if best == nil { _ = hostByAuditToken() }
        if best == nil { best = findOperatorHost() }
        // 🚨 **唯一出口再挡一次**：无论上面哪条路拿到的，都必须长得像包名。
        //    "同一个规则散在几处" 是今晚反复出现的病根 —— 这里做最后一道闸。
        if let b = best, !b.isEmpty, b != "<null>", b.contains(".") {
            KbBridge.rememberHost(b)
            KbBridge.note("🎉 宿主是谁：" + b + "（第三方宿主也问得到！）")
        } else if best != nil {
            KbBridge.note("宿主取到的是占位符（" + (best ?? "") + "），不当数据用")
            best = nil
        }
        return best
    }

    /// 🚨🚨 **系统给多高就用多高 —— 照 Typeless 做**（2026-09-02 09:4x，Kevin 亲测它在 eMPF 没白边）。
    ///    真机序列：露面那一帧是系统给的默认高度（信息 478、别的 App 452），
    ///    我们之前硬要 250、露面后再缩 → 宿主按大的让位、我们画小的 → 白边就是缩出来的那一截。
    ///    四种"提前把 250 定下来"的办法全试过，系统一律先按自己的默认起动画。
    ///    → 不抢了：露面时读到系统给的高度就认下来，各档统一用它，之后不再变尺寸。
    static var adoptedH: CGFloat = 0
    private var lastFrameH = -1
    private func logKbFrame(_ why: String) {
        // 🚨 高度一变就记（不按时间节流）：第一版按 2 秒节流只抓到一帧 `view=932`，
        //    分不清是「先 932 再回 250」还是「一直 932」—— 这两种是两个不同的 bug。
        let vh = Int(view.bounds.height)
        guard vh != lastFrameH || why != "重排" else { return }
        lastFrameH = vh
        let wh = Int(view.window?.bounds.height ?? -1)
        let iv = Int(inputView?.bounds.height ?? -1)
        KbBridge.note("键盘高度｜" + why + "｜view=" + String(vh) + "｜inputView=" + String(iv)
                      + "｜window=" + String(wh) + "｜约束=" + String(Int(heightC?.constant ?? -1))
                      + "｜相位=" + String(describing: phase))
    }

    /// **键盘自己的 RBS 句柄 → hostProcess → bundle**（读自己的句柄不需要权限）+ 扒宿主代理协议。
    private static var didHostProc = false
    private func probeHostProcessViaRBS() {
        guard !KeyboardViewController.didHostProc else { return }
        KeyboardViewController.didHostProc = true
        if let hc: AnyClass = NSClassFromString("RBSProcessHandle") {
            // 实例方法里带 host/parent 的
            var names: [String] = []
            var n: UInt32 = 0
            if let ms = class_copyMethodList(hc, &n) {
                for i in 0..<Int(n) {
                    let nm = NSStringFromSelector(method_getName(ms[i])); let l = nm.lowercased()
                    if l.contains("host") || l.contains("parent") || l.contains("bundle") || l.contains("identity") { names.append(nm) }
                }
                free(ms)
            }
            KbBridge.note("HP RBSProcessHandle ▸ " + names.prefix(20).joined(separator: " ｜ "))
            let cur = NSSelectorFromString("currentProcess")
            if let m = class_getClassMethod(hc, cur) {
                typealias F0 = @convention(c) (AnyClass, Selector) -> AnyObject?
                if let me = unsafeBitCast(method_getImplementation(m), to: F0.self)(hc, cur) {
                    let myBid = ((me.value(forKey: "bundle") as AnyObject?)?.value(forKey: "identifier") as? String) ?? "(nil)"
                    KbBridge.note("HP currentProcess.bundle.identifier = " + myBid)
                    for key in ["hostProcess", "parentProcess", "hostProcessHandle"] {
                        let sel = NSSelectorFromString(key)
                        guard me.responds(to: sel) else { KbBridge.note("HP 不响应 " + key); continue }
                        if let hp = me.perform(sel)?.takeUnretainedValue() {
                            let bid = ((hp.value(forKey: "bundle") as AnyObject?)?.value(forKey: "identifier") as? String) ?? "(nil)"
                            let pid = (hp.value(forKey: "pid") as? Int) ?? -1
                            KbBridge.note("HP ✅ " + key + " → pid " + String(pid) + "｜bundle = " + bid)
                        } else { KbBridge.note("HP " + key + " 返回 nil") }
                    }
                } else { KbBridge.note("HP currentProcess 返回 nil") }
            // identity：RBSProcessIdentity（类方法签名里带 host: —— 扩展的 identity 里可能存着宿主）
            if let m = class_getClassMethod(hc, cur) {
                typealias F0 = @convention(c) (AnyClass, Selector) -> AnyObject?
                if let me = unsafeBitCast(method_getImplementation(m), to: F0.self)(hc, cur),
                   let idn = me.value(forKey: "identity") as AnyObject? {
                    let ic: AnyClass = type(of: idn)
                    var names: [String] = []
                    var n2: UInt32 = 0
                    if let ms = class_copyMethodList(ic, &n2) {
                        for i in 0..<Int(n2) {
                            let nm = NSStringFromSelector(method_getName(ms[i])); let l = nm.lowercased()
                            if l.contains("host") || l.contains("embed") || l.contains("container") || l.contains("parent") || l.contains("bundle") || l.contains("app") { names.append(nm) }
                        }
                        free(ms)
                    }
                    KbBridge.note("HP identity " + String(describing: ic) + " ▸ " + names.prefix(30).joined(separator: " ｜ "))
                    KbBridge.note("HP identity 描述：" + String(describing: idn).prefix(300).description)
                    for key in ["hostIdentity", "hostProcessIdentity", "host", "embeddedApplicationIdentifier", "containerIdentity", "parentIdentity"] {
                        let sel = NSSelectorFromString(key)
                        guard idn.responds(to: sel) else { continue }
                        if let v = idn.perform(sel)?.takeUnretainedValue() {
                            KbBridge.note("HP identity." + key + " = " + String(describing: v).prefix(200).description)
                        } else { KbBridge.note("HP identity." + key + " = nil") }
                    }
                }
            }
            } else { KbBridge.note("HP 没有 +currentProcess") }
        }
        // 🚨 扒协议表那段已删（2026-09-02 12:12 它让键盘 SIGSEGV：返回的不是 Protocol 对象）
    }

    private static var didLogSel = false
    private static var didProbeCtx = true   // 🚨 扒表已有定论，默认不跑（20 行/次会冲掉环形缓冲）
    private func probeExtensionContext() {
        // 🚨🚨 **宿主身份每次都要取**：键盘扩展是**常驻进程**，
        //    原来那个"只跑一次"的静态闩会把它锁死 —— 00:56 跑过一次之后，
        //    我后面每一次触发都什么都没发生，而日志里看起来就像"探针没写对"。
        //    同族错误：**把「进程生命周期」当成「一次交互」**。
        _ = hostBundleIDNow()
        // probeHostProcessViaRBS() 已摘（IMP 直调 currentProcess 返回对象 → over-release 崩键盘）
        guard !KeyboardViewController.didProbeCtx else { return }
        KeyboardViewController.didProbeCtx = true
        guard let ctx = self.extensionContext else {
            KbBridge.note("扒开 extensionContext：它是 nil（键盘没有扩展上下文）")
            return
        }
        let obj = ctx as AnyObject
        var cls: AnyClass? = type(of: obj)
        KbBridge.note("扒开 extensionContext：类 = " + String(describing: cls))
        // 🚨 XPC 代理对象的描述里常带连接名/包名 —— 最后一个便宜的路子。
        //    只读描述，不调它的任何方法（调远程方法会跨进程，风险高）。
        for k in ["_extensionHostProxy", "_auxiliaryConnection", "_connection"] {
            let sl = NSSelectorFromString(k)
            guard obj.responds(to: sl) else { continue }
            let v = obj.perform(sl)?.takeUnretainedValue()
            if false { KbBridge.note("代理描述 ▸ " + k + " = "
                          + String(describing: v).prefix(220).description) }
        }
        if let h = hostBundleIDNow() {
            KbBridge.note("宿主是谁：问到了 → " + h)
        } else {
            KbBridge.note("宿主是谁：🚨 问不到（选择器不响应或返回空）")
        }
        var hits: [String] = []
        var depth = 0
        while let c = cls, depth < 6 {
            depth += 1
            var n: UInt32 = 0
            if let ivars = class_copyIvarList(c, &n) {
                for i in 0..<Int(n) {
                    let iv = ivars[i]
                    guard let np = ivar_getName(iv) else { continue }
                    let name = String(cString: np)
                    let enc = ivar_getTypeEncoding(iv).map { String(cString: $0) } ?? "?"
                    let low = name.lowercased()
                    let interesting = low.contains("host") || low.contains("bundle")
                        || low.contains("pid") || low.contains("app")
                    if interesting {
                        var line = name + "（" + enc + "）"
                        if enc.hasPrefix("@") {
                            let v = object_getIvar(obj, iv)
                            line += " = " + String(describing: v)
                        }
                        hits.append(line)
                    }
                }
                free(ivars)
            }
            var pn: UInt32 = 0
            if let props = class_copyPropertyList(c, &pn) {
                for i in 0..<Int(pn) {
                    let name = String(cString: property_getName(props[i]))
                    let low = name.lowercased()
                    if low.contains("host") || low.contains("bundle") || low.contains("pid") {
                        hits.append("属性 " + name)
                    }
                }
                free(props)
            }
            var mn: UInt32 = 0
            if let ms = class_copyMethodList(c, &mn) {
                for i in 0..<Int(mn) {
                    let name = NSStringFromSelector(method_getName(ms[i]))
                    let low = name.lowercased()
                    if low.contains("host") || low.contains("bundleid") || low.contains("pid") {
                        hits.append("方法 " + name)
                    }
                }
                free(ms)
            }
            cls = class_getSuperclass(c)
        }
        if hits.isEmpty {
            KbBridge.note("扒开 extensionContext：整条继承链里【没有】host/bundle/pid 相关字段")
        } else {
            for h in hits.prefix(14) { KbBridge.note("扒开 extensionContext ▸ " + h) }
            KbBridge.note("扒开 extensionContext：共 " + String(hits.count) + " 条")
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        // 🚨🚨 v5「系统给多高就用多高」已作废（2026-09-02 09:53，Kevin：短信里铺满整屏）。
        //    露面前那一帧**不是系统的键盘高度**，是个乱值：同一台机十分钟内给了
        //    452/478/500/681/706/707/910/935。认它＝把键盘做成随机高度。
        //    Typeless「不管怎样都是半个屏」= 它是**固定**高度，不是跟系统要的。
        // 🚨 白边埋点（2026-09-02，Kevin：回到 eMPF 后键盘上方一大片空白）。
        //    要分清是宿主让位过多还是我们上报的高度有问题，得先知道自己此刻多高。
        logKbFrame("露面")
        probeExtensionContext()
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
        // 🚨🚨 **回填那半段。** 用户从主 App 切回来，键盘重新出现的这一刻，
        //    就是唯一能把稿子送进输入框的时机 —— 主 App 自己碰不到微信的输入框。
        //    这里**不用序号配对**：跳转架构下键盘根本没发过命令，
        //    而且切回来时它很可能已经是一个新实例，序号早重置了。
        //    → 跟「起录条子」同一个形状：放一份、谁先回来谁取走、取走即作废。
        // 🚨🚨 **无条件留一条痕迹** —— 这是判断「自动切回落到哪」的唯一自动判据：
        //    落回微信 → 输入框还在 → 键盘会重新出现 → 这条痕迹出现；
        //    落到桌面 → 桌面没有输入框 → 键盘不会出现 → 这条痕迹不出现。
        //    **他按一次，两种结果我都分得出来，不用再追问他。**
        // 🚨 不能挂在 `restoreRecordingPhase` 里面 —— 那条有 guard，
        //    不在录音时就不写了，正好把「落到哪」这个问题的另一半吃掉。
        // 🚨🚨 **给自己造一个「切到下一个输入法」的开关。**
        //    Kevin：「你就看 Typeless 是怎么做的」。而我一直切不到它的键盘
        //    （地球键坐标点不准，长按也弹不出列表）。
        //    但**我们自己的键盘可以调系统 API 主动切走** ——
        //    `advanceToNextInputMode()`。开关一开，我们的键盘一露面就切下一个，
        //    这样我就能一步步切到 Typeless，然后去拍它按下麦克风时的行为。
        //    🚨 只在 `flags.txt` 写了 `switchaway` 时才动，正常使用碰不到。
        if KbBridge.flag("switchaway") {
            KbBridge.note("切换开关：主动切到下一个输入法")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.advanceToNextInputMode()
            }
        }
        // 🚨 告诉宿主"我还在用"—— 它靠这个决定还要不要占着麦克风。
        // 🚨🚨 **已拆除**：它用 `Unmanaged.passUnretained(self)` 注册了
        //    Darwin 观察者却**从不注销** —— 键盘扩展随时被销毁重建，
        //    VC 一没，下次通知就是**野指针**，扩展当场挂。
        //    键盘崩 = 他被切回系统键盘。**实验通道不许留在产品路径上。**
        // armKbMicProbe()
        armReturnChannel()   // 🚨 主 App 架好后靠它把他送回宿主
        // 🚨 **两条从没试过的取宿主途径 —— 只读字典，不做运行时枚举**
        //    （前两次把他键盘搞崩，就是因为枚举 ivar + dlsym；这两条不碰那些）。
        if !KbBridge.probedEnvOnce {
            KbBridge.probedEnvOnce = true
            let env = ProcessInfo.processInfo.environment
            let hits = env.filter { k, v in
                let s = (k + "=" + v).lowercased()
                return s.contains("bundle") || s.contains("host")
                    || s.contains("xpc") || s.contains("container")
                    || s.contains(".app")
            }
            KbBridge.note("环境变量探宿主（共 " + String(env.count) + " 项，命中 "
                          + String(hits.count) + "）："
                          + hits.map { $0.key + "=" + String($0.value.suffix(60)) }
                              .prefix(6).joined(separator: " ｜ "))
            // 🚨 场景那半去掉了：`UIApplication.shared` 在**扩展里不可用**
            //    （编译期就报 'shared' is unavailable in application extensions）。
            //    这本身也是条信息 —— 键盘扩展连 `UIApplication` 都碰不到，
            //    所以"从键盘直接把某个 App 拉到前台"结构上就不成立。
        }
        KbBridge.markKeyboardSeen()
        // 🚨 回来了就清掉离场记号，否则宿主的宽限从上次离场算起，
        //    他人已经回来、还在说，那一单却会被"他走了太久"收掉。
        KbBridge.clearKeyboardGone()
        KbBridge.note("键盘出现｜宿主在录=" + String(KbBridge.recordingSince() != nil))
        // 🚨 保险：万一在飞的那次卡住，麦克风按钮会**永久锁死**
        //    （"一次失败把功能永久关掉"是最难被发现的那种坏法）。
        // 🚨🚨 但**不能无脑清**：键盘切走再切回只要 0.5 秒，而后台架的窗口有 1.2 秒，
        //    无脑清会把「正在飞的这一次」也放行，于是再按一下就有**两个并发**、
        //    两个回调各给宿主发一次 `start`（交叉审查 中-1）。
        //    → 判据加时间维度：只有**超过 3 秒还在飞**才判为卡住。
        if let t = bgArmStartedAt, Date().timeIntervalSince(t) > 3 {
            cancelBgArm("超过 3 秒还在飞，判为卡住")
        }
        // 🚨🚨 **没测过的条件：键盘正在前台显示时，后台的宿主能不能架起麦克风。**
        //    我之前所有「后台架引擎」的实验，**键盘都不在场** —— 而键盘在场时
        //    我们这一整套（宿主 + 扩展）在系统眼里是"正在被使用"，
        //    iOS 对音频输入的放行条件很可能不一样。
        //    **前置条件不同的实验，不能拿旧结论套。**（今天栽过四次）
        //    宿主活着但没架 → 让它现在就试一次，成不成都留痕。
        if KbBridge.hostAlive, !KbBridge.hostArmed() {
            KbBridge.note("键盘在前台且宿主没架 → 让它现在试着架（这个条件没测过）")
            _ = KbBridge.send("prearm", args: [:])
        }
        // 🚨 **免手点的音频探针**（只在 `flags.txt` 里写了 `probeaudio` 时跑）。
        //    他睡了、手机锁着，XCUITest 起不来（`Timed out while enabling
        //    automation mode`）。而键盘只在弹出时才活 —— 用探针 App 自动聚焦
        //    文本框把键盘拉出来，键盘一出现就自己跑，**不需要任何人点屏幕**。
        //    🚨 默认关着：它会占用麦克风 2.5 秒，绝不能在他正常打字时乱抢。
        if KbBridge.flag("probeaudio") {
            KbBridge.note("键盘音频探针：开跑（flags 里有 probeaudio）")
            // 🚨🚨 **探针一律收进 `probeaudio` 开关（2026-08-30）。**
            //    它们每次都要抢 2.5 秒麦克风 —— 而现在宿主正靠那只麦克风
            //    在后台录音，**探针会把刚打通的链路打断**，
            //    还平白给他多等 1–2 秒。
            //    结论已经出了（Apple 官方文档：自定义键盘无法访问麦克风），
            //    这几条留着只为将来复现，不该在产品路径上跑。
            if KbBridge.flag("probeaudio") {
                // 🚨 已关死：这两条各抢 2.5 秒麦克风，还会打断正在跑的录音。
                _ = 0
            }
        }
        takePendingIfAny()
        startPendingWatch()
        restoreRecordingPhase()
        // 🚨 顺序重要：先恢复相位（可能把 phase 设成 .listening），
        //    再决定要不要重启轮询；`autoStartIfHeMeantTo` 只在 `.idle` 时才动，
        //    所以放最后不会跟恢复出来的录音态打架。
        resumePollingIfNeeded()
        autoStartIfHeMeantTo()
    }

    /// 🚨🚨 **他 2026-08-29 报的「录音键看不出在录」就是这里。**
    ///    录音、转写、回填全是通的，只有状态丢了 ——
    ///    因为键盘扩展在切走时被系统销毁，**回来是个新实例，相位重置成待命**。
    ///    → 相位从**共享区**恢复，不靠实例内存。
    ///    （同一个函数上面那段注释早就写着「切回来很可能是新实例」，
    ///      但只用在了稿子上、没用在状态上 —— 道理写对了，范围没覆盖到。）
    /// **切回来之后把轮询接回去。**
    ///
    /// 🚨🚨 2026-08-31 交叉审查 高-4：上一轮只做了「切走不撤单」这一半，
    ///    可 `teardown` 照样把 `pollTimer` 停了 —— 切回来按停止时，
    ///    宿主把稿子写进回执槽，**没有任何人来读**，界面停在「…」上秒数一直涨。
    ///    **这正是他报的症状，上一轮只修掉了一半。**
    ///
    /// 两种情况都要管：
    ///  · 同一实例回来：`remoteSeq` 还在，只是定时器没了 → 重启
    ///  · 新实例回来（键盘扩展随时被销毁重建）：`remoteSeq == -1`，
    ///    从**共享区**把序号捞回来 —— 实例内存里的东西活不过一次重建。
    private func resumePollingIfNeeded() {
        guard pollTimer == nil else { return }
        if remoteSeq < 0 {
            // 宿主还在录 or 刚录完还没取走 → 那一单还没了结，把序号接回来
            guard KbBridge.recordingSince(maxAge: 180) != nil else { return }
            let seq = KbBridge.currentSeq
            guard seq > 0 else { return }
            remoteSeq = seq
            KbBridge.note("键盘：新实例回来，从共享区接回序号 " + String(seq))
        }
        KbBridge.note("键盘：切回来了，重启轮询（seq=" + String(remoteSeq) + "）")
        startPolling()
    }

    private func restoreRecordingPhase() {
        guard let since = KbBridge.recordingSince() else { return }
        guard phase == .idle else { return }
        // 🚨🚨 **单号也要接回来**（Kevin 2026-09-04 那条的另一半）。
        //
        //    这个函数原来只恢复了**界面**和**计时**，没恢复 `remoteSeq`。
        //    以前不暴露，是因为切走时键盘会撤单、根本没有"在飞的单"；
        //    这一版改成销毁也不撤单之后，就露出来了：
        //    界面回到「在听」、宿主也真的在录，**但他按停止没有任何反应**
        //    —— 「还在录却停不下来」比「停掉」更糟，他只能干等超时。
        //
        // 🚨 单号必须从**共享区**取：切到别的 App 会让 iOS 销毁键盘扩展，
        //    回来是个**全新进程**，`remoteSeq` 恒为 -1，进程内存里什么都不剩。
        // 🚨 取不到就**不猜**（猜错会去停别人的单），只记一笔。
        if remoteSeq < 0 {
            let sq = KbBridge.recordingSeq()
            if sq >= 0 {
                remoteSeq = sq
                KbBridge.note("键盘：接回在飞的那一单 seq=" + String(sq))
            } else {
                KbBridge.note("🚨 键盘：宿主在录但共享区没有单号 —— 接不回来，"
                              + "他按停止会没反应（多半是旧版本留下的半份状态）")
            }
        }
        KbBridge.note("键盘：宿主正在录，恢复成录音态")
        setPhase(.listening, hint: "")
        // 🚨 计时要用**宿主真正起录的时刻**，不是键盘出现的时刻 ——
        //    否则末尾倒计时会晚一大截，他会在毫不知情时被自动停。
        listenSince = since
    }

    /// 有没有主 App 留下的东西（失败原因 / 稿子）；有就给他看。
    ///
    /// 🚨 去重状态在**共享区**（`doneSeq`），不在实例内存 ——
    ///    键盘扩展**随时会被系统销毁重建**，实例里的标记跟着没，
    ///    换个实例就把同一句英文再插一遍。（第三轮审查）
    private func takePendingIfAny() {
        // 失败先看；它跟稿子各有各的序号，**互不影响，也不 return**。
        if let f = KbBridge.peekFailure() {
            KbBridge.markFailShown(seq: f.seq)
            KbBridge.note("键盘取到失败原因，弹给他看")
            // 🚨 状态要自洽：把相位打回 `.idle` 就该把这一单也收干净，
            //    否则「idle 相位 + 活着的 seq + 活着的轮询」三者矛盾，
            //    还会让 1.5 秒兜底的相位闸变成"该跳的时候不跳"
            //    （交叉审查 20260901_0252 低-1）。
            if remoteSeq >= 0 {
                pollTimer?.invalidate(); pollTimer = nil
                remoteSeq = -1
            }
            setPhase(.idle, hint: L.kb_jump_failed)
            showDiag(f.why)
        }
        guard let p = KbBridge.peekPending() else { return }
        KbBridge.note("键盘取到出稿，上屏（" + String(p.out.count) + " 字）")
        // 🚨🚨 **出稿之后这一单就结束了，单号要清掉。**（2026-09-04 实测抓到）
        //
        //    上面那条**失败**分支早就清了（"状态要自洽"），
        //    而**成功**这条没清 —— 同一条规矩两个出口，只落地了一个。
        //    以前不暴露：键盘被销毁时会撤单，`remoteSeq` 跟着进程一起没了。
        //    这一版改成销毁不撤单之后就现形了 —— 他手机 17:10 的痕迹：
        //      17:09:53 键盘取到出稿，上屏（58 字）      ← 这一单已经完了
        //      17:10:01 键盘被销毁，录音继续（seq=853），不撤单  ← 还拿着旧单号
        //    后果目前只是**痕迹说假话**（"录音继续"其实没有在录），
        //    但这种"状态量只写不清"的漏日后一定会变成真 bug，而且是间歇性的。
        if remoteSeq >= 0 {
            pollTimer?.invalidate(); pollTimer = nil
            remoteSeq = -1
        }
        deliverLocal(zh: p.zh, out: p.out)
        // 🚨 抬的是**我刚投的这一份**的序号，不是"当前最新那份" ——
        //    否则主 App 在这中间又出一份新稿会被一起抬掉、静默蒸发。
        //    （第四轮审查 高-1）
        KbBridge.markDelivered(seq: p.seq)
    }

    private func startPendingWatch() {
        pendingWatch?.invalidate()
        var left = 90.0
        pendingWatch = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) {
            [weak self] t in
            guard let self = self else { t.invalidate(); return }
            left -= 0.4
            if left <= 0 { t.invalidate(); self.pendingWatch = nil; return }
            // 🚨 **命中了也不停表。** 上一版一命中就 `invalidate` ——
            //    万一那次没投成（或后面又来一份稿），**就再也没人来取了**，
            //    比原来的 bug 更贵。（第三轮审查 高-2）
            //    去重靠共享区的 `doneSeq`，重复调用是幂等的，不怕多跑。
            if KbBridge.hasPending() { self.takePendingIfAny() }
        }
    }

    /// 宿主输入框内容变了 —— 这时候扩展肯定已经完全就绪，
    /// `hasFullAccess` 在这里最可信。
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        refreshFullAccessWarning()
        // 🚨🚨 **光标被挪走 / 宿主自己改了文字 → 我们的 composing 记账立刻作废。**
        //
        //    他在输入框里点一下别的位置、选中一段、或宿主自动补全改了内容，
        //    我们记的「屏幕上挂着 niha」就不再对应真实位置了。
        //    这时候 `clearShownComposing()` 会在**新光标处**连删 4 下 ——
        //    **删掉他别的字**。这是这套「自己记账」策略唯一的硬风险，
        //    必须在这儿掐掉。
        //
        // 🚨 只清记账、**不动文档**（同 `teardown`）：那段拼音就留在原地当普通文字。
        //    宁可留一段没转换的拼音，也不许删错东西。
        // 🚨 判据：`documentContextBeforeInput` 的结尾**不再是**我们记的那一段，
        //    就说明位置已经变了。拿不到上下文（没有完全访问权限）时一律作废 ——
        //    **不确定就不删**。
        guard !shownComposing.isEmpty else { return }
        let before = textDocumentProxy.documentContextBeforeInput
        if before?.hasSuffix(shownComposing) != true {
            shownComposing = ""
            typingView?.dropComposingBuffer()
        }
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
        // 🚨 提交审核前清单 F1：**关掉「允许完全访问」时键盘还得能用** ——
        //    缺这条会被苹果直接拒。而这条警告条一挂上就多占一行，
        //    历史上它**绝对定位时压住过按钮**（贴底压「打字/朗读/⌫/发送」，
        //    贴顶压「翻译/英文/转写/历史」）。
        //    → `TRANSLESS_FORCE_WARN=1` 在**模拟器**里把它强制显示出来截图核对，
        //    **不去动 Kevin 手机上的系统开关**（那是他的设置，我不碰）。
        let forceWarn = ProcessInfo.processInfo.environment["TRANSLESS_FORCE_WARN"] == "1"
        if !forceWarn {
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
            // 🚨🚨🚨 **上屏策略 2026-09-04 整个换掉**（Kevin 报的两条 P0：
            //    「选词后第一个字出不来」「连打断」）。
            //
            //    旧策略：composing 和 commit **都用 `setMarkedText`**，
            //    commit 时 `setMarkedText(候选)` + `unmarkText()`。
            //    它假设**宿主会把第三方键盘的 marked 段当成可替换的待选区**。
            //    这个假设**从来没在真宿主验过** —— 下面原来那段注释里我自己
            //    写着「⚠️ 未在真实宿主实测」，然后就这么发出去了。
            //
            //    真机上（尤其微信这类宿主）常把 marked text **即时定稿成正文**。
            //    一旦 "ceshi" 已经落成正文，`setMarkedText("测")` 就变成
            //    **在它后面新插一段**，`unmarkText` 一定稿 → 文档变成 `ceshi测`
            //    —— 他看到的「拼音先出来、字跟在后面 / 第一个字没出来」就是这个。
            //    连打同根：每个字母都 setMarkedText(越来越长的拼音)，
            //    宿主不维持 marked 段就会重复插入，越打越乱。
            //
            // 🚨 新策略：**不再依赖宿主怎么对待 marked text**。
            //    我们自己记住「屏幕上现在挂着多长的 composing」（`shownComposing`），
            //    要变的时候**按长度 `deleteBackward` 抹掉**、再 `insertText` 新内容。
            //    `deleteBackward`/`insertText` 是 `UIKeyInput` 的基本操作，
            //    所有宿主都必须实现 —— 这是确定性的，不用赌。
            //    代价：输入框里的拼音不再有"下划线待选"的系统外观（变成普通文字），
            //    但**能正确工作** > 好看。安卓那边 `commitText` 本来就是确定性的。
            //
            // 🚨 判据（必须真机真宿主，harness 绿不算）：微信里打 `ceshi` 选「测」
            //    → 文档里应当**只有「测」**，不是 `ceshi测`。
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
                // 🚨🚨 2026-09-03 Kevin：「选了字，但是拼音也被选进来了，
                //    写完之后拼音和字都连在了一起」。根因就是下面这两行原来的顺序。
                //
                //    `unmarkText()` 的语义是**把当前 marked text 定稿**，不是「丢弃」。
                //    原来先 unmark 再 insert，等于每选一个字，
                //    缓冲里那串还没转换的拼音先被当成**字面文字**提交进输入框，
                //    然后才插入选中的那个字 —— 拼音和字就这么连在一起了。
                //
                //    正确顺序是**先用要上屏的内容替换掉 composition，再定稿**：
                //    `setMarkedText` 会替换当前 marked 段（没有 marked 段时就在光标处插入），
                //    然后 `unmarkText()` 把这一段变成正式文字。
                //    没有 composition 时这两行等价于一次普通插入，所以
                //    标点、数字、英文字母走同一条路也安全。
                //
                //    🚨 安卓那边没有这个坑：`ic.commitText(s, 1)` 的 contract
                //       本来就是「替换待选区」。这是 iOS 独有的一处。
                // 先把屏幕上那段 composing 抹掉，再插入要上屏的内容。
                self?.clearShownComposing()
                p.insertText(s)
            }
            t.onDelete = { [weak self] in
                // 🚨 走到这里说明拼音缓冲已经空了（`backspaceEatsBuffer` 先问过），
                //    所以这一下就是真删文档。但**屏幕上可能还挂着 composing**
                //    （比如缓冲刚好被吃空的那一下），先抹干净再删，
                //    否则会删到 composing 的最后一个字符、状态又和屏幕分家。
                self?.clearShownComposing()
                self?.textDocumentProxy.deleteBackward()
            }
            t.onSwitchToVoice = { [weak self] in self?.showVoice() }
            // 退格要读光标前的文字（长按连删、按词删），把输入连接给它。
            t.proxyProvider = { [weak self] in self?.textDocumentProxy }
            t.onHeightChange = { [weak self] h in
                guard let s = self, s.voiceRoot?.isHidden == true else { return }
                s.heightC?.constant = h
            }
            // 拼音缓冲 -> 输入框（安卓的 setComposingText）。
            // 🚨 见上面 `onText` 那段：**不再用 marked text**，改成
            //    「按已显示长度删干净 + 插入新串」，宿主怎么处理 marked 段都不影响。
            t.onComposing = { [weak self] s in
                self?.showComposing(s)
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

    // MARK: - composing 记账（拼音在宿主输入框里的那一段）
    //
    // 🚨🚨 **屏幕上现在挂着多长的 composing，只有这一个变量记账。**
    //    2026-09-04 之前是靠 `setMarkedText`/`unmarkText` 让宿主自己维护，
    //    而**宿主怎么对待第三方键盘的 marked 段是没有保证的**
    //    （微信会即时定稿成正文）—— 那正是「选词后第一个字出不来」
    //    和「连打断」的根因。现在改成我们自己数、自己删。
    //
    // 🚨 用 `count`（Character 数）而不是 utf16：`deleteBackward()` 删的是
    //    **一个可见字符**（grapheme cluster），不是一个 UTF-16 码元。
    //    拼音是纯 ASCII 两者一样，但这条以后要是用来挂中文就会分叉，
    //    写清楚免得下一个人改错。
    private var shownComposing = ""

    /// 把输入框里那段 composing 换成 `s`（空串 = 抹掉）。
    ///
    /// 🚨 **幂等**：`s` 跟现在显示的一样就什么都不做 ——
    ///    不然每次 `refreshCandidates()` 都会「删一遍再插一遍」，
    ///    在慢宿主上会看到闪烁，也白白多两次跨进程调用。
    private func showComposing(_ s: String) {
        guard s != shownComposing else { return }
        clearShownComposing()
        if !s.isEmpty {
            textDocumentProxy.insertText(s)
            shownComposing = s
        }
    }

    /// 抹掉输入框里那段 composing。**记账和实际删除必须同进同退。**
    private func clearShownComposing() {
        guard !shownComposing.isEmpty else { return }
        for _ in 0..<shownComposing.count { textDocumentProxy.deleteBackward() }
        shownComposing = ""
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
        KbBridge.prefs.set(m.rawValue, forKey: "vime.mode")
        paintMode()
    }

    /// 2026-09-03 Kevin「整理跟没整理一样」：发命令时原来读偏好 `vime.mode`，而高亮用的是内存 `mode`
    ///    （只在键盘启动时读一次）；主 App 也会写这个偏好（它自己的档位按钮、反向时强制 .en）——
    ///    于是可能【高亮是整理、发出去是逐字】。改成**发高亮的那个**；两者不一致时留痕（这就是证据）。
    /// 🚨 铁律（2.1 裁定）：**屏幕上显示的和实际发出去的，必须来自同一次读取 —— mode / lang / tone 三个都算。**
    ///    留痕只是诊断不是根治——两个写入者（键盘/主 App）还在；根治是把写入收成一处。
    /// 2026-09-03（2.1 查出）：`lang` 与 `mode` 同型——显示用内存 `lang`、发送重读偏好 `vime.lang`。同一修法。
    private func sentLang() -> String {
        let pref = KbBridge.prefs.string(forKey: "vime.lang") ?? "en"
        if pref != lang {
            KbBridge.note("目标语言不一致：显示=" + lang + " 偏好=" + pref + " → 按显示发，并把偏好改回来")
            KbBridge.prefs.set(lang, forKey: "vime.lang")
        }
        return lang
    }
    private func sentMode() -> String {
        let pref = KbBridge.prefs.string(forKey: "vime.mode") ?? "en"
        if pref != mode.rawValue {
            KbBridge.note("档位不一致：高亮=" + mode.rawValue + " 偏好=" + pref + " → 按高亮发，并把偏好改回来")
            KbBridge.prefs.set(mode.rawValue, forKey: "vime.mode")
        }
        return mode.rawValue
    }

    @objc private func pickTone(_ b: UIButton) {
        guard b.tag < Prompts.all.count else { return }
        tone = Prompts.all[b.tag]
        KbBridge.prefs.set(tone, forKey: "vime.tone")
        paintMode()
    }

    /// **语言下拉列表。** 复用 `showHistory` 那套浮层，不新造面板。
    ///
    /// 🚨 清单从 `Backend.langs` 取，**这里不抄第二份** ——
    ///    `cycleLang` 的注释里就写着「安卓那边为这个栽过（手写的清单漏了新加的语言）」。
    /// 🚨 当前项要有勾，否则他不知道现在是哪个（点点点那版至少按钮上写着）。
    @objc private func showLangPicker() {
        if langPanel != nil { hideLangPicker(); return }
        let panel = UIView()
        panel.backgroundColor = Theme.kbPanel
        panel.translatesAutoresizingMaskIntoConstraints = false

        let back = UIButton(type: .system)
        back.setTitle("‹ " + L.kb_lang_pick, for: .normal)
        back.titleLabel?.font = .systemFont(ofSize: 15)
        back.setTitleColor(Theme.kbKeyText, for: .normal)
        back.addTarget(self, action: #selector(hideLangPicker), for: .touchUpInside)
        back.translatesAutoresizingMaskIntoConstraints = false

        let list = UIStackView()
        list.axis = .vertical
        list.spacing = 4
        list.translatesAutoresizingMaskIntoConstraints = false
        // 🚨 顺序走共用的 `LangRecents`（最近用过置顶）。这个面板本来就套着
        //    `UIScrollView`，23 门滚得动 —— 三处里只有它原本就不会溢出。
        let sec = LangRecents.sections(all: Backend.langsForUI.map { $0.code })

        // 🚨🚨 **方案丙**（Kevin 2026-09-05 13:0x：「语言列表选丙」）——
        //    **这一屏就是他实拍报障的那一屏**（`Kevin实拍_iOS输入法选语言重复_1156.jpg`）。
        //
        //    原来是 `for code in sec.recent + sec.rest` —— **把两段拼平**，
        //    于是他那台 3 门语言渲染出 5 行（中文×2、英文×2），
        //    而两段长得一模一样，重复就被读成 bug。
        //
        //    丙：**「最近用过」做成横滑 chips**（描边不填充、更扁），
        //    「全部语言」保持**完整不删**。两段一眼看上去不是同一种东西，
        //    同一个名字出现两次就不再读作错。
        if let chips = LangChips.row(codes: sec.recent, current: lang,
                                     onPick: { [weak self] code in
                                         self?.applyLang(code)
                                     }) {
            // 🚨 **chips 上面要有「最近用过」小标题** —— 面对面那屏有，这屏原来没有。
            //    出图自查时发现的：光有 chips，用户不知道那一排是什么。
            //    **两屏走散正是今天这个 bug 的成因**，不能在修它的时候又制造一次。
            let head = UILabel()
            head.text = L.lang_recent
            head.font = .systemFont(ofSize: 12, weight: .semibold)
            head.textColor = Theme.kbHint
            head.accessibilityIdentifier = "kb.lang.recent.title"
            list.addArrangedSubview(head)
            list.addArrangedSubview(chips)

            // 「全部语言」也给个标题，两段各自说清自己是什么
            let all = UILabel()
            all.text = L.lang_all
            all.font = .systemFont(ofSize: 12, weight: .semibold)
            all.textColor = Theme.kbHint
            all.accessibilityIdentifier = "kb.lang.all.title"
            list.addArrangedSubview(all)
        }

        for code in sec.allIncludingRecent {
            let b = UIButton(type: .system)
            b.contentHorizontalAlignment = .left
            b.titleLabel?.font = .systemFont(ofSize: 15)
            b.setTitle((code == lang ? "✓  " : "     ") + Backend.langLabel(code),
                       for: .normal)
            b.setTitleColor(code == lang ? Theme.accent : Theme.kbKeyText, for: .normal)
            b.accessibilityValue = code
            b.accessibilityIdentifier = "transless.lang." + code
            b.heightAnchor.constraint(equalToConstant: 34).isActive = true
            b.addTarget(self, action: #selector(pickLang(_:)), for: .touchUpInside)
            list.addArrangedSubview(b)
        }

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(list)
        panel.addSubview(back)
        panel.addSubview(scroll)
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.topAnchor.constraint(equalTo: view.topAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            back.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            back.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            scroll.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 4),
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -8),
            list.topAnchor.constraint(equalTo: scroll.topAnchor),
            list.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            list.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])
        langPanel = panel
    }

    @objc private func hideLangPicker() {
        langPanel?.removeFromSuperview()
        langPanel = nil
    }

    @objc private func pickLang(_ b: UIButton) {
        // 🚨 认 `accessibilityValue`（语言 code），**不认标题文字** ——
        //    标题带勾和空格，而且会随界面语言变；按文字匹配是那种
        //    "今天能用、换个语言就坏"的判据。
        if let code = b.accessibilityValue, !code.isEmpty {
            applyLang(code)
        }
        hideLangPicker()
    }

    /// **选中一门语言的唯一出口** —— 列表行和「最近用过」chips 都走它。
    ///
    /// 🚨 抽出来是因为方案丙给了这一屏**两条选中路径**（chips 和列表）。
    ///    两条各写一遍的话，必然有一条忘了写偏好、或者忘了记「最近用过」——
    ///    而那种漏**不会报错**，只会表现成"从 chips 选的语言下次就不见了"。
    func applyLang(_ code: String) {
        guard !code.isEmpty else { return }
        lang = code
        KbBridge.prefs.set(lang, forKey: "vime.lang")
        LangRecents.use(code)          // 唯一写入口，三个选择器共用
        langButton.setTitle(langTitle() + " ▾", for: .normal)
        hideLangPicker()
    }

    private func langTitle() -> String { Backend.langLabel(lang) }

    /// 按当前档位刷新两排的高亮和显隐。跟安卓 `paintTones()` + `setMode()` 一致。
    /// 选中态铺**渐变紫**、未选中回普通键底（Kevin 09-04：紫色不够渐变）。
    /// 🚨 单一实现：所有 tab/语气/子档都走这里，别每处各写一遍开关。
    /// 🚨 铺渐变时把 `backgroundColor` 清掉 —— 两套底叠着会在圆角边缘露出实心紫。
    private func paintPurple(_ b: UIButton, on: Bool) {
        if on {
            b.backgroundColor = .clear
            b.setBackgroundImage(Theme.purpleGrad, for: .normal)
        } else {
            b.setBackgroundImage(nil, for: .normal)
            b.backgroundColor = Theme.kbKey
        }
    }

    private func paintMode() {
        let isTranslate = (mode == .en)
        paintPurple(tabTranslate, on: isTranslate)
        tabTranslate.setTitleColor(isTranslate ? .white : Theme.kbHint,
                                   for: .normal)
        paintPurple(tabTranscribe, on: !isTranslate)
        tabTranscribe.setTitleColor(isTranslate ? Theme.kbHint : .white,
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
            paintPurple(b, on: on)
            b.setTitleColor(on ? .white : Theme.kbHint, for: .normal)
        }
        paintPurple(modeZhButton, on: mode == .zh)
        modeZhButton.setTitleColor(mode == .zh ? .white : Theme.kbHint,
                                   for: .normal)
        paintPurple(modeRawButton, on: mode == .raw)
        modeRawButton.setTitleColor(mode == .raw ? .white : Theme.kbHint,
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
            paintSpeakButton()
            return
        }
        speakText(lastOut)
    }

    /// **朗读任意一段文字** —— 底排的 🔊 和历史行里的 🔊 走**同一条链**。
    ///
    /// 🚨 Kevin 2026-08-31：「历史的那些记录没法朗读，这一点还是没有完全对齐安卓版」。
    /// 🚨 抽成一个函数、不复制第二份：同一规矩两处实现必漂，今天已栽过五次。
    private func speakText(_ raw: String) {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        // 🚨 中-4：飞行期间禁用，否则他会以为没反应再点一下，
        //    发出第二个付费 /api/tts，两个响应先后回来 → 标题说「朗读」而音频在响。
        speakBusy = true
        paintSpeakButton()
        Backend.speak(text: t) { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // 🚨 **每一条出口都要复位**，包括下面那条被丢弃的 ——
                //    漏一条就是一个永远转不回来的「…」。
                self.speakBusy = false
                switch r {
                // 🚨🚨 M-C：这里原来【什么都不说】——
                //    他点 🔊 看到「…」然后变回 🔊，跟**完全没反应**分不开。
                //    2.1 的规矩：每个状态都要跟"没反应"分得开。
                // 🚨 只写提示行、**不动 phase** —— 录音中改 phase 会把停止键
                //    变回开始键（主 App 那边的 H-B 就是这么栽的）。
                case .failure(let f):
                    self.paintSpeakButton()
                    KbBridge.note("失败·键盘朗读：" + String("\(f)".prefix(120)))
                    // 🚨 低-1：**非待命一律不上屏**。沿高-1 那条路
                    //    （点 🔊 → 开录 → TTS 失败回来），提示行会被这句盖住
                    //    并卡整段录音 —— `retickUI` 只刷 micButton，不刷它。
                    guard self.phase == .idle else { return }
                    self.hintLabel.text = f.ttsText
                case .success(let mp3):
                    // 🚨🚨 高-1：**不看 phase 就播 = 把 TTS 播进热麦克风。**
                    //    主 App 上一轮为这件事加了同形的闸，**键盘这条一个字都没加**
                    //    —— 同一条规则的第二个出口，又漏了。
                    //    TTS 飞行时 🔊 是禁的，但**麦克风没禁**：他完全可以在
                    //    等 TTS 的时候开录音，回来就把 Andrew 的声音录进这一句。
                    guard self.phase == .idle else {
                        KbBridge.note("朗读结果到达时已不在待命（阶段=\(self.phase)），丢弃")
                        self.paintSpeakButton()
                        return
                    }
                    // 🚨 **必须在 `play` 之后刷**：`Speaker.isPlaying` 读的是
                    //    `player?.isPlaying`，在 `play()` 返回之前恒为 false ——
                    //    上一版我把 `paintSpeakButton()` 写在 `play` 之前，
                    //    注释还写着"开播了，标题变「停」"，**跟实际正好相反**。
                    //    （今天第 N 次「注释断言了一个代码没有的状态」。）
                    Speaker.play(mp3) { [weak self] err in
                        DispatchQueue.main.async {
                            self?.paintSpeakButton()      // 播完了 → 标题回「朗读」
                            // 播放失败也不许静默（本机的事，跟额度无关 → 通用句）
                            if let err = err {
                                KbBridge.note("失败·键盘朗读播放："
                                              + String("\(err)".prefix(120)))
                                self?.hintLabel.text = L.err_tts_failed
                            }
                        }
                    }
                    // 🚨 `play()` 已经返回，这时 `isPlaying` 才是真的 —— 刷成「停」。
                    self.paintSpeakButton()
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
        b.setTitleColor(got ? Theme.kbHint : Theme.accent, for: .normal)
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
        // 🚨 只取 8 条：历史现在留 2000（09-03 对齐安卓/PC），
        //    面板本来就只铺 8 行，别为了铺 8 行把 2000 个 Item 都建出来。
        let items = History.list(limit: 8)
        let panel = UIView()
        panel.backgroundColor = Theme.kbPanel
        panel.translatesAutoresizingMaskIntoConstraints = false

        let back = UIButton(type: .system)
        back.setTitle("‹ " + L.kb_history, for: .normal)
        back.titleLabel?.font = .systemFont(ofSize: 15)
        back.setTitleColor(Theme.kbKeyText, for: .normal)
        back.addTarget(self, action: #selector(hideHistory),
                       for: .touchUpInside)

        let list = UIStackView()
        list.axis = .vertical
        list.spacing = 6
        if items.isEmpty {
            let e = UILabel()
            e.text = L.kb_history_none
            e.font = .systemFont(ofSize: 13)
            e.textColor = Theme.kbHint
            e.textAlignment = .center
            list.addArrangedSubview(e)
        } else {
            // 🚨 只铺前 8 条。键盘扩展内存紧（~60MB）——
            //    现在总共留 2000 条，更不能全建出来。要翻更多去 App 里看。
            historyRows = Array(items.prefix(8))
            for (i, it) in historyRows.enumerated() {
                let b = UIButton(type: .system)
                b.contentHorizontalAlignment = .left
                b.titleLabel?.font = .systemFont(ofSize: 13)
                b.titleLabel?.lineBreakMode = .byTruncatingTail
                b.setTitle(History.label(it) + "  " + it.out, for: .normal)
                b.setTitleColor(Theme.kbKeyText, for: .normal)
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

                // 🚨 每行一个 🔊 —— 对齐安卓。**只朗读、不插入**：
                //    两个动作分开，免得他只想听一下却把文字插进了聊天框。
                let sp = UIButton(type: .system)
                sp.setTitle("🔊", for: .normal)
                sp.titleLabel?.font = .systemFont(ofSize: 16)
                sp.accessibilityValue = it.out
                sp.accessibilityIdentifier = "transless.hist.speak"
                sp.setContentHuggingPriority(.required, for: .horizontal)
                sp.setContentCompressionResistancePriority(.required,
                                                           for: .horizontal)
                sp.addTarget(self, action: #selector(speakHistoryRow(_:)),
                             for: .touchUpInside)

                let row = UIStackView(arrangedSubviews: [b, sp, keep])
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

    /// 历史行里的 🔊 —— **只朗读，不插入**。
    @objc private func speakHistoryRow(_ b: UIButton) {
        guard let t = b.accessibilityValue, !t.isEmpty else { return }
        KbBridge.note("历史朗读：" + String(t.prefix(30)))
        speakText(t)
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
        b.backgroundColor = Theme.kbKey
        b.layer.cornerRadius = 8
        return b
    }

    private func toneTitle() -> String {
        toneLabels[tones.firstIndex(of: tone) ?? 0]
    }

    @objc private func cycleTone() {
        let i = tones.firstIndex(of: tone) ?? 0
        tone = tones[(i + 1) % tones.count]
        KbBridge.prefs.set(tone, forKey: "vime.tone")
        toneButton.setTitle(toneTitle(), for: .normal)
    }

    // 🚨 `backspace()` 已删（2026-08-29）：它是「点一下删一个」的老实现，
    //    唯一的绑定点已改走 `Backspace.attach`（长按连删 + 整词删）。
    //    **留着它就等于留了一条随时会被重新绑上的旁路** ——
    //    删除键这个坑安卓犯过一次、iOS 又犯一次，就是因为存在第二个出口。

    /// 把录音失败的现场完整摆出来：多行、可选中复制、不截断。
    ///
    /// 🚨 用 `UITextView` 而不是 `UILabel`：
    ///    · 能滚动 —— 内容比键盘高时不会被裁掉
    ///    · 能选中复制 —— 他不用再截图，直接粘过来
    ///    `UILabel` 两样都做不到，而这正是前两轮丢信息的原因。
    /// 🚨🚨 **诊断面板默认不给他看（2026-08-31）。**
    ///
    ///    Kevin 撞到时的原话：「上面显示『现场可长按复制，点一下收起』，
    ///    **这是啥意思啊？**」——他看不懂，也不该看懂：
    ///    记忆 `feedback_app_delivery_roles` 写着**他不做 debug**，
    ///    PM/研发/测试三个角色都是我的。
    ///    把一屏错误现场糊在他脸上，是**把我的活推给他**。
    ///
    ///    → 默认只给一句人话；完整现场收进 `flags.txt` 的 `diag` 开关后面
    ///      （我要现场时自己打开）。痕迹里照样有全文，不影响我排查。
    private func showDiag(_ text: String) {
        guard KbBridge.flag("diag") else {
            if !text.isEmpty { KbBridge.note("（诊断面板已收起，现场：" + String(text.prefix(300)) + "）") }
            setPhase(.idle, hint: KbBridge.hasRetryAudio() ? L.kb_rec_failed_retry : L.kb_rec_failed_plain)
            return
        }
        showDiagRaw(text)
    }

    private func showDiagRaw(_ text: String) {
        // 🚨🚨 H-1（第 2 轮审查）：**必须先 `hideDiag()`，不能只删 `diagView`。**
        //    上一轮加的 ✕ 是**另一个 subview**；开头只移除旧面板的话，
        //    每弹一次就往 view 上多留一个 44×44 的孤儿 ✕，
        //    `hideDiag` 只删得掉最后一个 —— 先前的永远压在右上角、
        //    点了没反应，还挡住历史那一格。
        //    最短复现就在本轮新加的路径上：直录失败弹面板 → 不关 → 再点麦克风
        //    → 走 `hostAlive` 分支的 `showDiag("")`。
        //    **修复引入的新问题，正好被同一轮的另一处修复触发。**
        hideDiag()
        let tv = UITextView()
        // 🚨🚨 **直录的结果永远排第一行，不管这一屏是谁弹的。**
        //    665 那次就是败在顺序上：直录失败 -> 回退 -> 宿主也失败 ->
        //    宿主的诊断把回退提示整个盖掉，于是我们今晚最想要的那个答案
        //    （扩展里为什么起不来）**一个字都没传回来**。
        //    「写了」和「他看得到」是两回事，这已经是今天第三次同型。
        tv.text = (localFallbackDiag.map { $0 + "\n\n" } ?? "") + text
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.textColor = Theme.kbKeyText
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

        // 🚨🚨 H7：**必须有一个真按钮**，tap 手势只能当辅助。
        //    这个面板四边贴满、还 `bringSubviewToFront`，**把 🌐 地球键也盖住了**；
        //    而 `isSelectable = true` 的 UITextView 自带整套手势识别器，
        //    单击有被吞的现实风险（我们没设 `shouldRecognizeSimultaneously`）。
        //    一旦被吞：**面板关不掉、地球键点不到，他只能去杀宿主 App。**
        //    44×44 是苹果自己的最小可点尺寸，别改小。
        let close = UIButton(type: .system)
        close.setTitle("✕", for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 22, weight: .medium)
        // 🚨🚨 2026-09-03 配色闸门抓到的**真 bug**（不是误报）：
        //    原来是白字 + 16% 白底 —— 深色下没问题，**浅色宿主下浮层底是
        //    `#F4F2FA`，白字压上去等于隐形**。而上面那段注释自己写着
        //    「一旦被吞：面板关不掉、地球键点不到，他只能去杀宿主 App」。
        //    这处是我从没看过的地方，靠闸门扫出来的 —— 正是 Kevin 说的
        //    「牵一发动全身，每个地方都要看一下」。
        close.setTitleColor(Theme.kbKeyText, for: .normal)
        close.backgroundColor = Theme.kbKeyDown
        close.layer.cornerRadius = 22
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(hideDiag), for: .touchUpInside)
        view.addSubview(close)
        view.bringSubviewToFront(close)
        NSLayoutConstraint.activate([
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            close.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            close.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                            constant: -8),
        ])
        diagClose = close
    }

    @objc private func hideDiag() {
        diagView?.removeFromSuperview()
        diagView = nil
        // 🚨 关闭按钮是**另一个 subview**，不跟着 tv 一起走 ——
        //    忘了它的话屏幕上会留一个点不动的 ✕，比没有还糟。
        diagClose?.removeFromSuperview()
        diagClose = nil
    }

    /// 🔊 的**唯一出口** —— `isEnabled` / `alpha` / `title` 三个属性一起管。
    ///
    /// 🚨🚨 复审 高-2：上一轮我加了「飞行期间禁用」，但三条回调**只 `setTitle`、
    ///    不碰 `isEnabled`/`alpha`**；而朗读成功既不改 phase 也不触发 `deliver`，
    ///    于是**没有任何东西会恢复它** —— 点一次朗读，按钮从此点不动，
    ///    「再点一下＝停」这条文档行为不可达。
    ///
    /// 🚨 主 App 有 `paintOutputButtons()` 这个唯一恢复点，键盘一个都没有。
    ///    `gate_button_symmetry` 没抓到，是因为它**只查恢复语句存不存在、
    ///    不查可不可达** —— 这写在它自己的「闸门【未】覆盖」第一条里。
    ///    **闸门没坏，是我依赖它去覆盖了它声明不覆盖的那一半。**
    ///
    private func paintSpeakButton() {
        let on = (phase == .idle && !lastOut.isEmpty && !speakBusy)
        // 🚨 角标亮时 Speak **不准变灰**（Kevin 亲口）——
        //    它是他"我要说新的一句"的唯一出口。
        let keepOn = on || !retryBadge.isHidden
        speakButton.isEnabled = keepOn
        speakButton.alpha = keepOn ? 1.0 : 0.45
        if speakBusy {
            speakButton.setTitle("…", for: .normal)
        } else {
            speakButton.setTitle(Speaker.isPlaying ? L.kb_stop : L.kb_speak,
                                 for: .normal)
        }
    }

    private func setPhase(_ p: Phase, hint: String) {
        if p == .listening { listenStartedAt = Date() }   // 🚨 说话起点，给停止后的等待时限用
        refreshRetryBadge()   // 🚨 相位变了角标就要跟着刷 —— 唯一出口
        if p == .thinking && phase != .thinking { thinkingSince = Date() }
        phase = p
        // 🚨 M1 + 高-2：🔊 的三个属性走**同一个出口**，见 `paintSpeakButton()`。
        paintSpeakButton()
        hintLabel.text = hint
        switch p {
        case .idle:
            micButton.setTitle("", for: .normal)
            Theme.setMicGlyph(micButton, side: 88)
            micButton.tintColor = .white
            micButton.backgroundColor = .clear
            micButton.setBackgroundImage(Theme.purpleGrad, for: .normal)
            micButton.isEnabled = true
        case .listening:
            // 🚨🚨 **不再画停止方块。** Kevin 2026-08-28：
            //    「停止符号怎么这么大，像个肚脐眼一样…你抄一下安卓的，不要自己弄。」
            //    安卓 `paintMic(1)` 的原话：「圆圈里放**波形**，不再放停止方块 ——
            //    两个一起显示会挤在一起，而波形才是他要的那个信号」。
            //    停止靠"再点一下"，不靠圆里画个方块。
            micButton.setTitle("", for: .normal)
            micButton.setImage(nil, for: .normal)
            // 🚨 换纯色态**必须先清掉渐变底图** —— 背景图盖在 backgroundColor 之上，
            //    不清的话录音中还是紫渐变、根本变不成红。
            micButton.setBackgroundImage(nil, for: .normal)
            micButton.backgroundColor = Theme.danger
            micButton.isEnabled = true
            listenSince = Date()
        case .thinking:
            micButton.setImage(nil, for: .normal)
            micButton.setTitle("…", for: .normal)
            micButton.setTitleColor(.white, for: .normal)
            micButton.setBackgroundImage(nil, for: .normal)   // 同上：先清渐变底图
            micButton.backgroundColor = Theme.kbKeyDown
            // 🚨🚨 **不再 setEnabled(false)** —— 照抄安卓那条注释的理由：
            //    卡住时他连"重录一次"这个唯一出口都没有，只能盯着一个灰圈。
            //    现在处理中点一下 = 取消这一轮（`tapMic` 里已有这条分支）。
            micButton.isEnabled = true
            busySince = Date()
        }
        // 波形只在 .listening 出现，其余整个隐藏（不是变淡）——
        // 他明确说过没点录音前不该有波形。
        waveView.setActive(p == .listening)
        retickUI()
    }

    /// 波形刷新（.listening）+ 处理中秒数（.thinking）。
    ///
    /// 🚨 **0.12 秒**：安卓的波形是录音线程直接 push 的（约 8 次/秒）。
    ///    iOS 隔着 App Group，只能轮询 —— 频率对不上的话，同一段话
    ///    在两端长得不一样，而"两端看起来不一致"正是他反复点名的毛病。
    ///    结果轮询那条是 0.4 秒，**不能共用**：0.4 秒的波形是一顿一顿的。
    private func retickUI() {
        uiTick?.invalidate(); uiTick = nil
        if phase == .idle { return }
        uiTick = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) {
            [weak self] t in
            guard let self = self else { t.invalidate(); return }
            switch self.phase {
            case .listening:
                // 🚨 M10：**直录时波形的数据源在本进程**（`localVoice.onLevel`
                //    直接 `waveView.push`）。这里再无条件 `replace(KbBridge.levels())`
                //    会把它整个盖掉，而 `clearLevels()` 只在宿主 `begin()` 里调 ——
                //    于是直录成功、真有声音时，他看到的波形不动、或者在重放
                //    **上一次宿主录音的形状** → 他报「没录到」，其实录到了。
                if !self.localMode {
                    let lv = KbBridge.levels()
                    self.waveView.replace(lv)
                    // 🚨 Kevin 2026-08-29：「键变红了，**但没有波形**」。
                    //    键盘的 UI 我看不见，所以让它**自己报读到了什么** ——
                    //    这样他按一次就能分清是哪一种，不用再追问他：
                    //      条数=0  → 跨进程没读到（宿主写了，键盘这边看到的是旧值）
                    //      条数>0 而他看不见 → 数据到了、画没画上（画法的问题）
                    // 🚨 一秒一条，别把痕迹刷爆（uiTick 是 0.12 秒一次）。
                    let now = Date()
                    // 🚨 **本来就有节流，我不该另加一个** —— 只把阈值从 1 秒
                    //    放到 6 秒。1 秒一条会把痕迹刷爆：一轮录音十几条，
                    //    上限一满，`按下麦克风` / `探宿主App` / `自动切回`
                    //    这些真正要看的行全被冲走 ——
                    //    **观测窗口比事件短 = 等于没观测**（今天已经因此瞎了一次）。
                    if now.timeIntervalSince(self.lastWaveNote) >= 6 {
                        self.lastWaveNote = now
                        KbBridge.note("键盘波形：读到 " + String(lv.count) + " 条，最大 "
                                      + String(format: "%.3f", lv.max() ?? -1)
                                      + "，波形隐藏=" + String(self.waveView.isHidden))
                    }
                }
                // 录音末尾倒计时 —— 照抄安卓 `startTailCountdown`：
                // 平时什么都不显示，只在最后 20 秒把剩余秒数写进圆圈，
                // 免得他在毫不知情的情况下被自动停（安卓 2026-08-22 的原因）。
                //
                // 🚨 **两端的上限不一样，这条要报给 2.1**：
                //    安卓键盘 `MAX_SECONDS = 900`，iOS 单句 `Voice.MAX_DURATION = 60`。
                //    差 15 倍。倒计时的**规则**照抄了（最后 20 秒），
                //    但上限本身对不齐 —— 那是产品口径，不归我改。
                // 🚨🚨 **倒计时必须按分段上限（900）算，不是单句的 60**（2026-09-02 09:0x）。
                //    键盘那条路每次 begin() 都接分段，宿主上限就是 900；而这里照 60 倒数，
                //    第 60 秒红圈停在「0」—— Kevin 看到就按停了：「最长只能录 60 秒」。
                //    主 App 其实还在录（探针录满 200 秒）。**上限是他定的 15 分钟，这就是口径。**
                let left = Int(Voice.MAX_DURATION_SEGMENTED
                               - Date().timeIntervalSince(self.listenSince))
                if left <= 20 {
                    self.micButton.setTitle("\(max(0, left))", for: .normal)
                    self.waveView.isHidden = true
                } else {
                    self.micButton.setTitle("", for: .normal)
                    self.waveView.isHidden = false
                }
            case .thinking:
                // 🚨 照抄安卓 `startBusyTick`：一个静止的「…」跟死了没区别。
                //    会动 = 活着，停住 = 真挂了。不占任何版面。
                let sec = Int(Date().timeIntervalSince(self.busySince))
                self.micButton.setTitle(sec <= 0 ? "…" : "\(sec)s", for: .normal)
            case .idle:
                t.invalidate(); self.uiTick = nil
            }
        }
    }

    // MARK: - 录音（说完自动收）

    /// 这一轮遥控的命令序号；`-1` = 没有在进行的。
    private var remoteSeq = -1
    /// 直录的**代次**。起录 +1、取消 +1；异步回调回来先比对，不是本代就整条丢弃。
    ///
    /// 🚨🚨 复审 高-4：`localVoice.stop()` **正是产出路径的触发器** ——
    ///    取消之后 `onWav` 照常回调 → `finishLocal` → transcribe → polish
    ///    → `deliverLocal` → **`insertText` 插进他的输入框**。
    ///    他看到「已取消」，然后 3 秒后微信输入框凭空多出一句英文。
    ///    主 App 为这件事加了 `epoch`，**键盘一道都没有**。
    private var localEpoch = 0
    /// 🔊 正在等 TTS 响应。
    ///
    /// 🚨🚨 **必须是状态，不能只当参数。**
    ///    上一版 `paintSpeakButton(busy:)` 的 busy 是个**参数** ——
    ///    别的地方（`setPhase`）调一次默认 `busy: false` 的它，飞行态就没了。
    ///    录音结束回到 `.idle` 而 TTS 还在飞时，按钮会被重新点亮，
    ///    他再点一次 → **第二个付费 TTS**。
    ///    这正是主 App 高-2 的镜像 —— **同一条规则的第二个出口。**
    private var speakBusy = false
    /// 已经读到过的结果时间戳，用来只认更新的那条。
    private var lastResAt: TimeInterval = 0
    private var pollTimer: Timer?

    // MARK: - 扩展直录（最小实验，见 KbSelfRecord.swift）

    /// 🚨 M12：**必须 `lazy`**。存储属性会让键盘一启动就构造 `AVAudioEngine`，
    ///    而本文件别处早写过这条铁规（「不在扩展启动瞬间创建，否则表现就是
    ///    『选了键盘却弹回上一个』且没有明显报错」）—— 我自己违反了自己的规矩。
    private lazy var localVoice = Voice()
    /// 这一轮走的是扩展直录吗。
    private var localMode = false
    /// `Voice.start()` **同步阶段**就失败了的话，错误落在这 —— 用来判断要不要回退。
    private var localSyncFail: String?
    /// `start()` 已经返回了吗。用来区分「同步失败」和「录完回调」，
    /// 两者走的是同一个 `onWav`。
    private var localArmed = false
    private var localPeak: Float = 0
    private var localFrames = 0
    /// 保护上面那两个数 —— 它们**在渲染线程写、在主线程读**（审查 M3）。
    /// 🚨🚨 中-5：**`os_unfair_lock` 不能当存储属性用 `&` 取址。**
    ///    Swift 不保证 `&存储属性` 每次给出的是**同一个地址**，
    ///    而 `os_unfair_lock` 要求地址固定 —— 地址一变锁就失效，
    ///    **而且不会报任何错**。
    ///    它保护的 `localFrames/localPeak` 就是这次直录实验的全部结论，
    ///    锁悄悄失效 = 结论悄悄不可信。
    ///    → 一次性分配到堆上，地址永远不变。
    private let localLock: UnsafeMutablePointer<os_unfair_lock> = {
        let p = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        p.initialize(to: os_unfair_lock())
        return p
    }()

    /// 取一份快照再用。**别在主线程直接读那两个字段。**
    private func localSnapshot() -> (frames: Int, peak: Float) {
        os_unfair_lock_lock(localLock)
        defer { os_unfair_lock_unlock(localLock) }
        return (localFrames, localPeak)
    }
    /// 直录起不来时给他看的一行。**没有它的话回退是完全静默的**，
    /// 而静默地退回老路正好等于实验没做，两者在界面上分不开。
    private var localFallbackNote: String?
    /// 直录那一次的**完整**现场（含 `Voice.diagnostics()`）。
    ///
    /// 🚨 单有那行短提示不够 —— 665 实测：短提示写进了 hintLabel，
    ///    紧接着宿主也失败、`showDiag` 把整屏盖掉，**他一个字没看到**。
    ///    所以这份要**拼进每一屏诊断的最前面**，谁弹的都一样。
    private var localFallbackDiag: String?

    @objc private func tapMic() {
        // 🚨🚨 **第一行就留痕，在任何判断之前。**
        //    2026-08-30 他说"用不了"，我去看痕迹 —— 他按麦克风之后
        //    **一条记录都没有**，于是"到底是没按、还是按了但键盘当场挂了"
        //    完全分不出来，只能猜。**静默的入口 = 事后无法归因。**
        //    这一行让下次一眼看出：按到了没有、当时宿主是什么状态。
        // 🚨🚨🚨 **先弄清「他此刻在哪个 App 里」—— 这是能不能切回去的前提。**
        //    Kevin 要的是：按一下 → 后台开始录 → **屏幕自动切回微信**。
        //    而 `sourceApplication` 在键盘拉起主 App 时是空的（实测），
        //    所以主 App 不知道该开回哪儿 → 只能停在自己这儿 → 他回不去。
        //    键盘是**跑在宿主 App 里**的，它知道宿主是谁 —— 只是没有公开 API。
        //    这里把几条路都探一遍，**先只留痕，确认拿得到再接进流程**。
        // 🚨🚨 **收进开关，产品路径不跑**（2026-08-31 交叉审查 中-4）。
        //    它用 ObjC 运行时枚举 ivar 再逐个 `value(forKey:)`，
        //    取到 KVC 不兼容的字段抛的是 **ObjC 异常，Swift do/catch 接不住**
        //    → 扩展当场挂，表现是"按了麦克风键盘弹回上一个"且**零诊断**。
        //    现在靠名字过滤侥幸没撞上，那是 iOS 26.x 这一版的实现细节。
        //    而且它跑在**每一次按麦克风**上，还有 dlopen/dlsym +
        //    `_extensionHostAuditToken` —— 全是上架必拒的取值。
        // 🚨🚨 **重新默认开启**（2026-08-31）：里面新增的 SecTask 取法是
        //    「跳过去还能自动跳回来」唯一的信息来源，而 Kevin 明确说
        //    「不切回永远解决不了问题…**我最不能容忍的就是这一点**」。
        //    中-4 提的崩溃风险靠**白名单取值**收窄（只取 _extensionHostAuditToken），
        //    不再枚举所有 ivar 盲取。
        // 🚨🚨🚨 **已拆除（2026-08-31 22:0x）—— 它把他的键盘崩了两次。**
        //    Kevin：「它又给我切回到默认的输入法去了」——
        //    **iOS 在键盘扩展崩溃时会自动切回系统键盘**，这就是那个症状。
        //    这段做 ObjC 运行时枚举 + dlsym + RunningBoard 调用，
        //    上一次我以为收进开关了，**其实只改了另一处**（同一规矩两个出口，
        //    今天第五次栽在这上面）。诊断件不许跑在他每天用的路径上。
        // probeHostApp()   ← 要用就临时改回来，别默认开
        _ = hostByAuditToken()   // 按下这一刻刷新宿主 PID/令牌（露面那次可能已过 60 秒）
        KbBridge.markPressHost()   // 🚨 回程准度：记住按下这一刻的宿主 PID
        KbBridge.note("按下麦克风｜相位=" + String(describing: phase)
                      + "｜宿主活着=" + String(KbBridge.hostAlive)
                      + "｜引擎架着=" + String(KbBridge.hostArmed())
                      + "｜完全访问=" + String(hasFullAccess))
        // 🚨🚨 **后台架在飞时，这一按直接忽略 —— 而且必须挡在最前面。**
        //    交叉审查 中-2：这道闸原来挡在四层嵌套里，被"忽略"的那一按
        //    **已经先抢了 2.5 秒麦克风、起过一次采集栈** ——
        //    而它抢的正是宿主此刻正在架的那只麦克风。**闸挡得晚等于没挡。**
        // 🚨 **`.listening` 要放行**（交叉审查 F7）：后台架在飞的同时
        //    键盘可能被收起又弹出、`restoreRecordingPhase` 把相位恢复成
        //    `.listening` —— 这时他按下是想**停**，被闸吞掉的表现是「停不下来」。
        if bgArmInFlight, phase != .listening {
            KbBridge.note("键盘：后台架还在飞，这一按忽略（别抢它正在架的麦克风）")
            // 🚨🚨 **不能静默吞掉**（交叉审查 20260901_0238 中-1）：
            //    「回来自动接上」那条等待期最长 2 秒，而那 2 秒**恰恰是他刚按完
            //    返回、最想立刻录音的时刻**。没有任何反馈的话，麦克风不变色、
            //    提示行空白、波形不动 —— 跟"按坏了"完全分不开，
            //    正是他反复报的「按了没反应」那一族。
            // 🚨 只动 `hintLabel`，**不动 `phase`** —— 动 phase 会把 `.listening` 打回去。
            //    他这一按和那张条子指向的是同一件事，2 秒后的回调会统一兑现
            //    （回调里已有三项复核，不会重复起录）。
            hintLabel.text = L.kb_preparing
            return
        }
        // ⛔️🚨🚨 **2026-09-03 摘掉了这条早退。** 原来是：
        //        `if retryIfWeHaveAudio() { return }`
        //
        //    它的条件只有「空闲 + 有存货」，**没有任何「他是不是想重发」的判断**。
        //    存货窗口 10 分钟 → **失败过一次之后的 10 分钟内，他每一次点麦克风
        //    都变成重发旧的那段，他想说的新话根本没录上**，而界面只显示「重发中」，
        //    他不会知道。
        //
        //    🚨 **这个行为制造的正是他提这个需求时抱怨的那件事** ——
        //       「说的话没记下来很浪费时间」。所以它不是「待完善的入口」，是 bug。
        //    🚨 2.1 的红线：**麦克风圆钮不许当重试按钮** —— 点麦＝开始新的一段。
        //
        //    代价：**暂时没有重试入口**。可以接受，因为音频已经落盘（`pending.wav`），
        //    话丢不了；而这个入口是有害的。
        //    第二步把重发挂到「听到的话」那一块（Kevin 原话「就在键盘上，
        //    提示让用户再点一次」）—— `heardLabel` 要变成可点控件，那是版式，走出图流程。
        //    🚨 `retryIfWeHaveAudio()` **函数留着**，第二步直接挂上去，别删了再重写。
        // 🚨🚨 重发回来了，但**跟今天下午摘掉的那个不是一回事**：
        //    下午摘掉是因为它**静默** —— 没角标、没另一条路，
        //    他想说新的一句会被悄悄吞掉。
        //    Kevin 09-03 晚定稿的方案把这两点都补上了：
        //      · 琥珀角标让他**看得见**现在这一按是重试
        //      · **Speak 是新录音的出口**，而且角标亮时不准变灰
        //    所以这里的判据是**角标亮着**（＝他看得见），不是"手上有存货"。
        if !retryBadge.isHidden, retryIfWeHaveAudio() { return }
        if phase == .listening { stopListening(); return }
        // 🚨🚨 thinking 必须有出口（交叉审查 H4，安卓修过同型的）。
        //    后端挂了/回调没来时，`phase` 会永远停在 thinking，
        //    麦克风从此点不动 —— 用户只能杀掉宿主 App 才恢复。
        //    超过 90 秒还在 thinking 就当它死了，放行重来。
        if phase == .thinking {
            // 🚨🚨 复审 中-6：**这里原来是 `return`，把他的每一下都静默吞掉**，
            //    而 `setPhase(.thinking)` 的注释白纸黑字写着
            //    「处理中点一下 = 取消这一轮（`tapMic` 里已有这条分支）」
            //    —— **注释描述了一个不存在的分支**，前 90 秒按钮是死的。
            //
            //    两条路（真做取消 / 把按钮禁掉）里选前者：
            //    那条注释的本意是「卡住时要有出口」，禁掉按钮等于把出口关了，
            //    跟它想解决的问题正好相反。取消要的东西工程里都有
            //    （`viewWillDisappear` 已经在这么做）。
            // 🚨 跟 `stopListening` 同一条规矩：**取消这一轮时，在飞的后台架也要取消**
            //    （交叉审查 中-1 说这条分支「有一模一样的洞」）。幂等，没在飞就是空操作。
            cancelBgArm("他取消了这一轮")
            pollTimer?.invalidate()
            pollTimer = nil
            if remoteSeq >= 0 {
                KbBridge.send("cancel")
                remoteSeq = -1
            }
            // 🚨 高-4：**先把代次推掉再 stop** —— `stop()` 会触发 `onWav`，
            //    顺序反了的话那条回调仍属于"本代"，照样会插字。
            localEpoch += 1
            localArmed = false
            if localMode {
                localVoice.stop()
                localMode = false
            }
            KbBridge.note("这一轮被他取消了（处理中点了麦克风）")
            setPhase(.idle, hint: L.kb_cancelled)
            return
        }

        // 🚨🚨 **先试「键盘扩展自己录」** —— 2026-08-28 起。
        //    下面那一大段"扩展绝对不能录音"的论证**已被 Kevin 的实拍反证**
        //    （Typeless 录音时橙点亮着、键盘面板在显示波形、主 App 不在前台），
        //    而它引的 QA1872 是 **2014-09-17 / iOS 8 / 通篇没提 keyboard**，
        //    他手机是 iOS 26.6。**那段论证保留在下面只作历史，别再拿它推导。**
        //    直录起不来就自动回退到宿主那条，所以最坏等于原样。
        // 🚨🚨 高-3：**停播放必须在 `tryLocalRecord()` 之前。**
        //    上一版我加在下面 49 行处，而直录（现在的主路径）在这儿就 return 了。
        //    后果比"录进自己的声音"更贵：`Speaker.play` 已经把 `AVAudioSession`
        //    切到播放类别，直录会带着一个**被我们自己搞坏的会话**去起引擎，
        //    报出来的 stage/code 会被写成"扩展不能录音"的证据 ——
        //    **把这次实验唯一的结论打偏。**
        //    （跟上一轮 高-1 同型：锚点选了"每个出口都有的那一行"，
        //     真正需要修的出口在它前面。）
        Speaker.stop()
        if tryLocalRecord() { return }

        // ↓↓↓ 以下为**存疑**的旧论证（2026-08-28 起不再作为依据）↓↓↓
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
            setPhase(.idle, hint: KbBridge.hasRetryAudio() ? L.kb_rec_failed_retry : L.kb_rec_failed_tap)
            showDiag(bridgeMissingDiag())
            return
        }
        // 🚨🚨🚨 **宿主不在 → 直接把它拉起来，不是弹一句提示就完事（2026-08-30 12:46）。**
        //
        //    Kevin 实测「按了没反应」，痕迹里只有我新加的那行入口留痕：
        //    `按下麦克风｜宿主活着=false｜引擎架着=false`，**之后一条都没有**。
        //    原因就在这道 guard：它 `return` 了，而**拉起主 App 的代码在它下面**
        //    —— 我一路跟他说的「宿主不在就跳转、跳完自己架回来」这条回退路径
        //    **根本不存在**，因为永远走不到。
        //
        //    🚨 这是「假回退」：我以为有兜底，实际那段代码不可达。
        //       判据不是"代码里有没有这个分支"，是**这条路上会不会执行到它**。
        //
        //    拉起来之后主 App 会在前台起录、出稿、并顺手把待命档架好，
        //    下一次按就不用再跳了。
        if !KbBridge.hostAlive {
            // 🚨🚨 **改走 `arm` 而不是 `rec`。** 他 2026-08-30 的原话：
            //    「点了录音之后，又是打开 Transless，然后又回不去微信」——
            //    `rec` 会把他扣在主 App 里录完一整段，录完还留在那儿。
            //    `arm` 只借一个前台瞬间把引擎架好，架好立刻自己退出去；
            //    他点一下微信回来，**从此不用再跳**。
            KbBridge.note("宿主不在 → 拉起主 App 只架引擎（arm），并记下他想录")
            KbBridge.markWantRec()
            let r = openContainerApp("arm", onOpened: { [weak self] ok in
                guard let self = self, !ok else { return }
                KbBridge.note("拉起失败，本次没有录音")
                self.setPhase(.idle, hint: KbBridge.hasRetryAudio() ? L.kb_rec_failed_retry : L.kb_rec_failed_tap)
            })
            if r == .dispatched {
                setPhase(.idle, hint: L.kb_rearming)
                // 🚨🚨🚨 **在拉起主 App 的同一刻就 `completeRequest`。**
                //    上一版是等主 App 架好后发通知回来再调 —— **测下来一次都没跑到**：
                //    键盘拉起主 App 后宿主进后台，**键盘扩展当场被销毁**，
                //    等通知回来已经没人接了。
                //    「等一个已经不存在的对象来接消息」，今天第二次犯。
                //
                //    `completeRequest` 的语义是「扩展做完事了，把用户送回宿主」
                //    （分享扩展全靠它），**公开 API**，我今天挖的 15 条里一条没碰过。
                //    在这一刻调，正好对应 Kevin 看到的 Typeless 现象：
                //    「闪出来，接着马上关掉，又切回微信」。
                if let ctx = self.extensionContext {
                    KbBridge.note("回宿主：拉起主App的同时调 completeRequest")
                    ctx.completeRequest(returningItems: nil) { ok in
                        KbBridge.note("回宿主：completeRequest 回调 ok=" + String(ok))
                    }
                } else {
                    KbBridge.note("回宿主：没有 extensionContext")
                }
                return
            }
            // 连拉都拉不动（响应链里没有能开 URL 的对象）才走老提示。
            KbBridge.note("宿主不在、也拉不起来 —— 只能提示他手动开 App")
        }
        guard KbBridge.hostAlive else {
            setPhase(.idle, hint: L.kb_need_standby)
            // 🚨🚨 H6：**这条路原来不弹面板** —— 而 `localFallbackDiag`
            //    只在 `showDiag()` 里被拼进去。于是「直录失败 + 待机没开」时，
            //    他只看到「先打开 Transless…」，**直录为什么起不来一个字都传不回来**。
            //    这就是 665 那次的重演，只是换了触发条件。
            //    硬规则：**`localFallbackDiag` 非 nil 时，`tapMic` 的任何出口都不许不弹。**
            if localFallbackDiag != nil { showDiag("") }
            return
        }

        // 🚨 上一轮识别出来的中文要在这儿就清掉（交叉审查 低-2）：
        //    下面那条 bgArm 分支会直接 `return`，不清的话屏上会是
        //    「正在准备麦克风…」底下挂着上一句的中文。
        heardLabel.text = ""
        // 🚨🚨 **肯定判据**（交叉审查 低-3）：闸门只能证「这段在主路径的 depth=2」，
        //    证不了「真的跑到了」—— 前面任何人加一条早退，闸门照样 PASS
        //    而后面那条痕迹也不会打印，**又是一次静默**。
        //    所以在这儿留一行"我到了"，别只靠"某行没出现"这种否定判据。
        KbBridge.note("到达架检查点｜架着=" + String(KbBridge.hostArmed()))
        // 🚨🚨🚨 **【主路径】宿主活着但引擎没架 → 先在后台架，不带任何开关。**
        //    位置很要紧：**必须在上面那个 `guard` 的花括号之外**。
        //    上一版我把它插进了 guard 的 else 体里 —— 那意味着「宿主**不**活着」
        //    才执行，而它要解决的恰恰是「宿主**活着**但没架」。
        //    花括号配平、能编译、缩进也看不出来（`if` 照样在 8 格），
        //    所以**静默地一次都没跑过**。交叉审查两轮抓了同一个症状的两种死法
        //    （第一轮是 flag，第二轮是作用域）。
        //    → 闸门 `gate_bgarm_on_main_path.py` 现在会数大括号深度。
        if !KbBridge.hostArmed() {
            armInBackgroundThenStart(tone: tone)
            return
        }

        // 🚨 **回退这件事必须让他看得见。**
        //    直录起不来时我们悄悄走宿主那条 —— 界面跟以前一模一样，
        //    于是「实验做了、结论是什么」他答不上来，我也拿不到
        //    （他手机现在电脑够不着，selftest.txt 拉不回来）。
        //    一行短提示，不挡流程，但他一眼能报给我。
        // 🚨🚨 **真机判据**：走到这里就意味着我们要发一条"裸" `start`（没有先架）。
        //    正常情况下这一行应当永远是 `架着=true`；**出现 `架着=false`
        //    就说明上面那条新路又没接上**（两轮都栽在"代码在但跑不到"）。
        //    这一条不依赖任何静态分析，他按一次我就能判。
        KbBridge.note("走了裸 start｜架着=" + String(KbBridge.hostArmed()))
        // 🚨🚨 **走同一个方法，主路径不再自己发一份 `start`。**
        //    这里原来是 `startOnArmedHost` 的第二份实现，而且两份**行为已经不一样**：
        //    那边有「1.5 秒宿主不应答就改走 arm」的兜底，**这边没有** ——
        //    也就是说他每天走的这条路反而是**没有退路**的那条：
        //    宿主假死时就静静停在 `.listening`，什么都不发生
        //    （正是他 08-31 报的「怎么点都是没听清」那一族的形状）。
        //    合并之后 `via=本来就架着` 也会出现在生产路径上，判据跟代码天然对齐。
        startOnArmedHost(tone: tone, via: "本来就架着", hint: localFallbackNote ?? "")
    }

    /// **键盘扩展自己起 Live Activity** —— 验证 Typeless 的做法。
    ///
    /// 🚨 主 App 在后台起不了岛（真机原文 `Target is not foreground`），
    ///    而 Typeless 的岛**只在录音时出现**、主 App 也不常驻前台。
    ///    最可能的解释：**岛是从键盘扩展发起的**（按下那一刻扩展是活跃的）。
    /// 🚨 **只留痕、不改行为**：起不来就照旧走原来的路，不影响他用。
    /// **用 `AVAudioRecorder` 在键盘扩展里录音** —— 引擎那条被拒时的另一条路。
    ///
    /// 🚨🚨 为什么值得试（2026-08-30）：
    ///    我们从头到尾只用 `AVAudioEngine`，而扩展里它一直报 `2003329396`
    ///    —— **那个错出在引擎这一层**（`engine.start()`）。
    ///    `AVAudioRecorder` 不碰 `inputNode`/HAL，对进程环境要求宽得多。
    ///    **这条一次都没试过**，而 Typeless 做得到，说明路是存在的。
    ///
    /// 🚨 只加不改：引擎成功时这段根本不参与。
    /// - Parameter done: 成功给 wav 数据，失败给原因。
    func recordWithRecorder(seconds: TimeInterval,
                            done: @escaping (Data?, String?) -> Void) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kbrec.wav")
        try? FileManager.default.removeItem(at: url)
        do {
            let s = AVAudioSession.sharedInstance()
            // 🚨 跟引擎那条用同一套档位（`.playAndRecord + .mixWithOthers`），
            //    不抢别人的会话 —— 扩展里抢会话是失败的常见原因。
            try s.setCategory(.playAndRecord, mode: .default,
                              options: [.mixWithOthers, .defaultToSpeaker])
            try s.setActive(true)
            Voice.fixReceiverRoute(s)
            let set: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            let r = try AVAudioRecorder(url: url, settings: set)
            r.isMeteringEnabled = true
            guard r.record() else {
                KbBridge.note("键盘录音机：record() 返回 false")
                return done(nil, "record() 返回 false")
            }
            kbRecorder = r
            KbBridge.note("键盘录音机：开始录了（AVAudioRecorder）")
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self = self, let rec = self.kbRecorder else { return }
                rec.stop()
                self.kbRecorder = nil
                if let d = try? Data(contentsOf: url), d.count > 44 {
                    KbBridge.note("键盘录音机：成功，" + String(d.count) + " 字节 ✅")
                    done(d, nil)
                } else {
                    KbBridge.note("键盘录音机：录出来是空的")
                    done(nil, "录出来是空的")
                }
            }
        } catch {
            KbBridge.note("键盘录音机：也不行 —— " + error.localizedDescription)
            done(nil, error.localizedDescription)
        }
    }

    /// 在键盘扩展里试 `AVCaptureSession` 采音（只留痕）。
    ///
    /// 🚨 判据要能分辨三种结局：拿不到设备 / 起得来但没数据 / 真收到声音。
    ///    都归成"失败"的话，下次排查会走错方向。
    /// 探「键盘此刻跑在哪个 App 里」。只留痕，不改流程。
    ///
    /// 🚨 三条路都试，**每条都要报结果**（拿到什么 / 为什么没拿到）——
    ///    只报一句"拿不到"的话，下次排查分不清是"没这个键"还是"取值失败"。
    /// 🚨 用到的都是**非公开取值**：自用开发版可以，上架前必须换掉或去掉。
    ///    这一点要跟 Kevin 讲清楚，不能偷偷用。
    private func probeHostApp() {
        KbBridge.note("探宿主App：进来了")
        guard let ctx = extensionContext else {
            KbBridge.note("探宿主App：extensionContext 是 nil"); return
        }
        // 🚨🚨 **把这个对象的内部字段全列出来** —— 上一版只按几个猜的名字问
        //    `responds(to:)`，全是"无此方法"，但那**只证明我猜的名字不对**，
        //    不证明"里面没有宿主身份"。**否定结论要有覆盖面。**
        //    这里用 ObjC 运行时把 ivar 和 property 都枚举一遍，
        //    有就一定看得到，没有才能下"拿不到"的结论。
        var lines: [String] = []
        var cls: AnyClass? = object_getClass(ctx)
        while let c = cls, c != NSObject.self {
            var n: UInt32 = 0
            if let ivars = class_copyIvarList(c, &n) {
                for k in 0..<Int(n) {
                    if let nm = ivar_getName(ivars[k]) {
                        lines.append(String(cString: nm))
                    }
                }
                free(ivars)
            }
            var pn: UInt32 = 0
            if let props = class_copyPropertyList(c, &pn) {
                for k in 0..<Int(pn) {
                    lines.append("@" + String(cString: property_getName(props[k])))
                }
                free(props)
            }
            cls = class_getSuperclass(c)
        }
        KbBridge.note("探宿主App·字段(" + String(lines.count) + ")："
                      + lines.joined(separator: ",").prefix(600))

        // 只对**真的存在**的字段取值，避免 KVC 抛异常崩扩展
        var vals: [String] = []
        for nm in lines where nm.lowercased().contains("host")
            || nm.lowercased().contains("bundle") || nm.lowercased().contains("pid")
            || nm.lowercased().contains("client") || nm.lowercased().contains("app") {
            let key = nm.hasPrefix("@") ? String(nm.dropFirst()) : nm
            let v: Any? = (ctx as AnyObject).value(forKey: key)
            vals.append(key + "=" + String(describing: v ?? "nil" as Any))
        }
        KbBridge.note("探宿主App·取值：" + (vals.isEmpty ? "没有相关字段"
                      : vals.joined(separator: " ｜ ").prefix(500).description))

        // 🚨🚨🚨 **从审计令牌反查宿主是谁** —— 这是"跳过去还能跳回来"缺的那块。
        //    `_extensionHostAuditToken` 是宿主进程的 `audit_token_t`（8 个 uint32），
        //    下标 5 是 **pid**；再用 Security 框架按令牌取签名标识 = **bundle id**。
        //    这是 XPC 里识别对端身份的标准做法，不是瞎猜的偏移。
        // 🚨 **这是非公开取值**：自用开发版可以，上架前必须换掉。要跟 Kevin 讲清楚。
        // 🚨 上一版这里是一条合并的 guard，失败时只会说"拿不到或长度不对"——
        //    **两个原因分不开**，我照样得猜。拆开，每种失败各报各的。
        let anyTok = (ctx as AnyObject).value(forKey: "_extensionHostAuditToken")
        guard let anyTok = anyTok else {
            KbBridge.note("探宿主App·令牌：取值返回 nil"); return
        }
        // 🚨🚨 **它是 `NSValue`（`NSConcreteValue`）包着的 `audit_token_t`，不是 `Data`。**
        //    上一版按 `Data` 转，一直失败而我只报了一句"拿不到或长度不对"——
        //    两种原因混在一句里，我照样得猜。**拆开报之后一次就看到了实际类型。**
        var tok = audit_token_t()
        if let nv = anyTok as? NSValue {
            withUnsafeMutableBytes(of: &tok) { raw in
                nv.getValue(raw.baseAddress!, size: MemoryLayout<audit_token_t>.size)
            }
        } else if let d0 = anyTok as? Data,
                  d0.count == MemoryLayout<audit_token_t>.size {
            withUnsafeMutableBytes(of: &tok) { raw in
                d0.copyBytes(to: raw.bindMemory(to: UInt8.self))
            }
        } else {
            KbBridge.note("探宿主App·令牌：既不是 NSValue 也不是 Data，实际类型="
                          + String(describing: type(of: anyTok))); return
        }
        let pid = tok.val.5
        // 🚨 `SecTask*` 那一族在 iOS SDK 里**一个都没暴露**（试过
        //    `SecTaskCopySigningIdentifier` 和 `SecTaskCopyValueForEntitlement`，
        //    都是 `cannot find in scope`）。
        //    改用 `proc_pidpath`：从进程号拿可执行文件路径，
        //    形如 `/private/var/containers/Bundle/Application/<UUID>/WeChat.app/WeChat`
        //    —— **路径里就带着 App 名**，够用来认出他当时在哪个 App。
        // 🚨 `proc_pidpath` 的头文件不在 iOS SDK 的 Swift 模块里（`cannot find in scope`），
        //    但符号在 libSystem 里。用 `dlsym` 在运行时取 —— 不需要头文件。
        // 🚨 `proc_pidpath` 被沙盒挡了（实测返回 0）。多试两个更轻的取名接口，
        //    并且**把 errno 打出来** —— 「没权限(EPERM=1)」和「进程不在(ESRCH=3)」
        //    是两回事，混在一起我又要猜。
        var bid = "?"
        typealias ProcFn = @convention(c) (Int32, UnsafeMutableRawPointer, UInt32) -> Int32
        let h = dlopen(nil, RTLD_NOW)
        var tried: [String] = []
        for name in ["proc_pidpath", "proc_name"] {
            guard let h = h, let sym = dlsym(h, name) else {
                tried.append(name + "=dlsym没有"); continue
            }
            let f = unsafeBitCast(sym, to: ProcFn.self)
            var buf = [UInt8](repeating: 0, count: 4096)
            errno = 0
            let n = buf.withUnsafeMutableBytes { raw -> Int32 in
                f(Int32(pid), raw.baseAddress!, UInt32(raw.count))
            }
            if n > 0 {
                bid = String(cString: buf)
                tried.append(name + "=" + bid)
                break
            }
            tried.append(name + "=返回" + String(n) + " errno=" + String(errno))
        }
        KbBridge.note("探宿主App·取名：" + tried.joined(separator: " ｜ "))
        // 🚨🚨 **把宿主 pid 交给主 App 去查。**
        //    `proc_pidpath` 在**键盘扩展**里被沙盒挡（实测 `errno=1` EPERM），
        //    但**主 App 的沙盒规则跟扩展不一样** —— 这条从没试过。
        //    键盘只负责把 pid 递过去，能不能查得到由主 App 那边验。
        // 🚨🚨🚨 **`SecTask` 一族：从令牌直接问出宿主的 bundle id。**
        //
        //    上面那段注释写着「`SecTask*` 在 iOS SDK 里一个都没暴露，
        //    试过 `SecTaskCopySigningIdentifier`…都是 `cannot find in scope`」——
        //    **那句话把编译期看不见当成了运行时不存在。**
        //    同一个文件里 `proc_pidpath` 正是因为"头文件不在 Swift 模块里"
        //    才改用 `dlsym` 运行时取的；我分清过一次，隔壁又混了一次。
        //
        //    这一族跟 `proc_pidpath` **不是一条路**：它只要令牌，
        //    不去读别人的可执行文件路径 —— 沙盒挡的是后者。
        //    这是 XPC 里确认对端身份的正规做法。
        if bid == "?" || !bid.contains(".app/") {
            typealias CreateFn = @convention(c)
                (CFAllocator?, audit_token_t) -> Unmanaged<AnyObject>?
            typealias CopyIdFn = @convention(c)
                (AnyObject, UnsafeMutablePointer<Unmanaged<CFError>?>?)
                -> Unmanaged<CFString>?
            var secTried: [String] = []
            let hSec = dlopen("/System/Library/Frameworks/Security.framework/Security",
                              RTLD_NOW) ?? dlopen(nil, RTLD_NOW)
            if let hSec = hSec,
               let symC = dlsym(hSec, "SecTaskCreateWithAuditToken"),
               let symI = dlsym(hSec, "SecTaskCopySigningIdentifier") {
                let create = unsafeBitCast(symC, to: CreateFn.self)
                let copyId = unsafeBitCast(symI, to: CopyIdFn.self)
                if let taskRef = create(nil, tok) {
                    let task = taskRef.takeRetainedValue()
                    var err: Unmanaged<CFError>?
                    if let idRef = copyId(task, &err) {
                        let ident = idRef.takeRetainedValue() as String
                        secTried.append("签名标识=" + ident)
                        // 🚨 这就是**宿主的 bundle id** —— 直接存进来源字段
                        if ident.contains(".") {
                            KbBridge.rememberSource(ident)
                            KbBridge.note("🎉 探宿主App·SecTask：拿到了宿主包名 "
                                          + ident + "（已存进来源，回程能用了）")
                        }
                    } else {
                        secTried.append("CopySigningIdentifier=nil"
                                        + (err.map { " err=" + String(describing:
                                            $0.takeRetainedValue()) } ?? ""))
                    }
                    // 🚨🚨 **`SecTaskCreateWithAuditToken` 成功了**（没报 nil），
                    //    说明这一族运行时存在、也认这个令牌 —— 只是
                    //    `CopySigningIdentifier` 回 nil。
                    //    换同族里更常用的那个：按 entitlement 取
                    //    `application-identifier`，返回 `TEAMID.com.tencent.xin`，
                    //    **这才是认对端身份的标准做法**（XPC 里到处这么用）。
                    typealias CopyEntFn = @convention(c)
                        (AnyObject, CFString,
                         UnsafeMutablePointer<Unmanaged<CFError>?>?)
                        -> Unmanaged<CFTypeRef>?
                    if let symE = dlsym(hSec, "SecTaskCopyValueForEntitlement") {
                        let copyEnt = unsafeBitCast(symE, to: CopyEntFn.self)
                        for key in ["application-identifier",
                                    "com.apple.application-identifier"] {
                            var e2: Unmanaged<CFError>?
                            guard let v = copyEnt(task, key as CFString, &e2) else {
                                secTried.append(key + "=nil")
                                continue
                            }
                            let any = v.takeRetainedValue()
                            guard let str = any as? String else {
                                secTried.append(key + "=非字符串 "
                                                + String(describing: type(of: any)))
                                continue
                            }
                            secTried.append(key + "=" + str)
                            // 形如 `AX3W379KV8.com.tencent.xin` —— 去掉队伍前缀
                            let bidOnly = str.contains(".")
                                ? str.split(separator: ".").dropFirst()
                                     .joined(separator: ".")
                                : str
                            if bidOnly.contains(".") {
                                KbBridge.rememberSource(bidOnly)
                                KbBridge.note("🎉 探宿主App·SecTask：拿到了宿主包名 "
                                              + bidOnly + "（已存进来源，回程能用了）")
                                break
                            }
                        }
                    } else {
                        secTried.append("SecTaskCopyValueForEntitlement dlsym 取不到")
                    }
                } else {
                    secTried.append("CreateWithAuditToken 返回 nil")
                }
            } else {
                secTried.append("dlsym 取不到（hSec="
                                + String(hSec != nil) + "）")
            }
            KbBridge.note("探宿主App·SecTask：" + secTried.joined(separator: " ｜ "))
        }
        // 🚨🚨🚨 **最后一条：问 `LSApplicationWorkspace` 谁在最前面。**
        //    键盘显示的时候，**最前面那个 App 就是宿主** —— 这是唯一
        //    不需要"读别人身份"的角度：我们问的是系统"现在谁在前台"。
        //
        //    前面全部拿不到：`proc_pidpath`/`proc_name`（EPERM）、
        //    `SecTaskCopySigningIdentifier`（nil）、
        //    `SecTaskCopyValueForEntitlement`（nil）、
        //    URL 的 `sourceApplication`（键盘发起时恒为「未知」）。
        //
        //    🚨 私有 API，Swift 看不见 —— 用 `NSClassFromString` 运行时取。
        //       （跟 `proc_pidpath` 用 `dlsym` 同一套路：**编译期看不见 ≠ 运行时没有**。）
        //    🚨 上架前必须换掉，这一条要跟 Kevin 讲清楚。
        // 🚨🚨 **每次都探，不设前置条件（2026-08-31 修）。**
        //    上一版写的是「来源为空才探」，而早先那个短信调试探针
        //    把来源写进去了、保质期又是 7 天 —— **这条实验被我自己永久挡住**，
        //    痕迹里一条都没有，我还以为是它取不到。
        //    「前置条件是我自己毁掉的」，今天第四次。
        //    每次探的代价只是一次运行时取值，而**来源本来就该跟着他换 App 更新**。
        if true {
            var lsTried: [String] = []
            if let cls = NSClassFromString("LSApplicationWorkspace") as? NSObject.Type {
                let defSel = NSSelectorFromString("defaultWorkspace")
                if cls.responds(to: defSel),
                   let ws = cls.perform(defSel)?.takeUnretainedValue() as? NSObject {
                    for name in ["frontmostApplication",
                                 "frontmostApplicationProxy",
                                 "currentApplication"] {
                        let sel = NSSelectorFromString(name)
                        guard ws.responds(to: sel) else {
                            lsTried.append(name + "=没这个方法"); continue
                        }
                        guard let px = ws.perform(sel)?.takeUnretainedValue()
                                as? NSObject else {
                            lsTried.append(name + "=nil"); continue
                        }
                        for idName in ["applicationIdentifier", "bundleIdentifier"] {
                            let idSel = NSSelectorFromString(idName)
                            guard px.responds(to: idSel),
                                  let v = px.perform(idSel)?.takeUnretainedValue()
                                    as? String, v.contains(".") else { continue }
                            lsTried.append(name + "." + idName + "=" + v)
                            // 🚨 别把我们自己当成宿主
                            if !v.hasPrefix("com.kevin.transless") {
                                KbBridge.rememberSource(v)
                                KbBridge.note("🎉 探宿主App·LSWorkspace：宿主是 " + v
                                              + "（已存进来源，回程能用了）")
                            }
                            break
                        }
                        if !lsTried.isEmpty && lsTried.last!.contains("=com") { break }
                    }
                } else {
                    lsTried.append("defaultWorkspace 取不到")
                }
            } else {
                lsTried.append("NSClassFromString 拿不到这个类")
            }
            KbBridge.note("探宿主App·LSWorkspace：" + lsTried.joined(separator: " ｜ "))

            // 🚨🚨 **RunningBoard：按 pid 拿进程信息。** 这是系统自己管进程用的那套，
            //    `RBSProcessHandle` 正对「pid → 是哪个 App」。
            //    先列方法、再调 —— 上一轮猜 LSWorkspace 的三个名字全错。
            var rbs: [String] = []
            if let rc: AnyClass = NSClassFromString("RBSProcessHandle") {
                var cn: UInt32 = 0
                if let meta: AnyClass = object_getClass(rc),
                   let ms = class_copyMethodList(meta, &cn) {
                    var names: [String] = []
                    for i in 0..<Int(cn) {
                        let nm = NSStringFromSelector(method_getName(ms[i]))
                        if nm.lowercased().contains("pid")
                            || nm.lowercased().contains("handle") { names.append(nm) }
                    }
                    free(ms)
                    rbs.append("类方法[" + names.prefix(8).joined(separator: ",") + "]")
                }
                // 最常见的签名：+handleForPID:error:
                let sel = NSSelectorFromString("handleForPID:error:")
                if (rc as? NSObject.Type)?.responds(to: sel) == true {
                    typealias F = @convention(c)
                        (AnyClass, Selector, Int32, UnsafeMutableRawPointer?) -> AnyObject?
                    if let imp = class_getMethodImplementation(
                            object_getClass(rc)!, sel) {
                        let f = unsafeBitCast(imp, to: F.self)
                        if let h = f(rc, sel, Int32(pid), nil) as? NSObject {
                            for idName in ["bundleIdentifier", "applicationIdentifier"] {
                                let idSel = NSSelectorFromString(idName)
                                if h.responds(to: idSel),
                                   let v = h.perform(idSel)?.takeUnretainedValue()
                                    as? String, v.contains(".") {
                                    rbs.append(idName + "=" + v)
                                    if !v.hasPrefix("com.kevin.transless") {
                                        KbBridge.rememberSource(v)
                                        KbBridge.note("🎉 探宿主App·RBS：宿主是 " + v
                                                      + "（已存进来源，回程能用了）")
                                    }
                                    break
                                }
                            }
                            if rbs.count < 2 {
                                rbs.append("拿到 handle 但取不出 bundle id，"
                                           + "handle 类=" + String(describing: type(of: h)))
                            }
                        } else {
                            rbs.append("handleForPID 返回 nil")
                        }
                    }
                } else {
                    rbs.append("没有 handleForPID:error:")
                }
            } else {
                rbs.append("RBSProcessHandle 这个类不存在")
            }
            // 🚨🚨 **真正对口的是 `handleForAuditToken:error:`**（方法列表转储确认，
            //    `handleForPID:error:` 根本不存在 —— 上一轮猜错了名字）。
            //    它要一个 `RBSAuditToken` 对象，所以先看怎么造。
            if let atCls: AnyClass = NSClassFromString("RBSAuditToken") {
                var cn: UInt32 = 0
                var mk: [String] = []
                if let meta: AnyClass = object_getClass(atCls),
                   let ms = class_copyMethodList(meta, &cn) {
                    for i in 0..<Int(cn) {
                        let nm = NSStringFromSelector(method_getName(ms[i]))
                        if nm.lowercased().contains("token") { mk.append(nm) }
                    }
                    free(ms)
                }
                rbs.append("RBSAuditToken 类方法[" + mk.prefix(6).joined(separator: ",") + "]")
                // 常见签名：+tokenFromAuditToken: / +tokenWithAuditToken:
                // 🚨 **优先 `tokenFromAuditTokenRef:`（传指针）**。
                //    `tokenFromAuditToken:` 是结构体**按值**传，
                //    通过 `@convention(c)` 函数指针很容易 ABI 对不上 ——
                //    上一轮 `handleForAuditToken=nil` 多半就是这么来的
                //    （造出来的 token 是垃圾，而它不会报错）。
                for maker in ["tokenFromAuditTokenRef:", "tokenFromAuditToken:"] {
                    let mSel = NSSelectorFromString(maker)
                    guard (atCls as? NSObject.Type)?.responds(to: mSel) == true,
                          let mImp = class_getMethodImplementation(
                            object_getClass(atCls)!, mSel) else { continue }
                    var atok: AnyObject?
                    if maker.contains("Ref") {
                        typealias MKR = @convention(c)
                            (AnyClass, Selector, UnsafeRawPointer) -> AnyObject?
                        let mf = unsafeBitCast(mImp, to: MKR.self)
                        atok = withUnsafePointer(to: &tok) { p in
                            mf(atCls, mSel, UnsafeRawPointer(p))
                        }
                    } else {
                        typealias MK = @convention(c)
                            (AnyClass, Selector, audit_token_t) -> AnyObject?
                        let mf = unsafeBitCast(mImp, to: MK.self)
                        atok = mf(atCls, mSel, tok)
                    }
                    guard let atok = atok else {
                        rbs.append(maker + "=nil"); continue
                    }
                    rbs.append(maker + "→" + String(describing: type(of: atok)))
                    guard let hCls: AnyClass = NSClassFromString("RBSProcessHandle"),
                          let hImp = class_getMethodImplementation(
                            object_getClass(hCls)!,
                            NSSelectorFromString("handleForAuditToken:error:")) else {
                        rbs.append("handleForAuditToken 取不到 imp"); break
                    }
                    // 🚨 **把 error 接出来** —— nil 而不知道为什么，等于没测。
                    typealias HF = @convention(c)
                        (AnyClass, Selector, AnyObject,
                         UnsafeMutablePointer<NSError?>?) -> AnyObject?
                    let hf = unsafeBitCast(hImp, to: HF.self)
                    var herr: NSError?
                    let hres = withUnsafeMutablePointer(to: &herr) { ep in
                        hf(hCls, NSSelectorFromString("handleForAuditToken:error:"),
                           atok, ep)
                    }
                    guard let h = hres as? NSObject else {
                        rbs.append("handleForAuditToken=nil"
                                   + (herr.map { " err=" + $0.domain + "/"
                                                 + String($0.code) + " "
                                                 + $0.localizedDescription } ?? " 无错误信息"))
                        continue
                    }
                    var got = false
                    for idName in ["bundleIdentifier", "applicationIdentifier",
                                   "identity", "attributes"] {
                        let idSel = NSSelectorFromString(idName)
                        guard h.responds(to: idSel),
                              let o = h.perform(idSel)?.takeUnretainedValue()
                            else { continue }
                        if let v = o as? String, v.contains(".") {
                            rbs.append(idName + "=" + v); got = true
                            if !v.hasPrefix("com.kevin.transless") {
                                KbBridge.rememberSource(v)
                                KbBridge.note("🎉 探宿主App·RBS：宿主是 " + v
                                              + "（已存进来源，回程能用了）")
                            }
                            break
                        }
                        // identity 是个对象，再往里问一层
                        if let obj = o as? NSObject {
                            for k2 in ["embeddedApplicationIdentifier",
                                       "bundleIdentifier", "identifier"] {
                                let s2 = NSSelectorFromString(k2)
                                if obj.responds(to: s2),
                                   let v2 = obj.perform(s2)?.takeUnretainedValue()
                                    as? String, v2.contains(".") {
                                    rbs.append(idName + "." + k2 + "=" + v2); got = true
                                    if !v2.hasPrefix("com.kevin.transless") {
                                        KbBridge.rememberSource(v2)
                                        KbBridge.note("🎉 探宿主App·RBS：宿主是 " + v2
                                                      + "（已存进来源，回程能用了）")
                                    }
                                    break
                                }
                            }
                            if got { break }
                        }
                    }
                    if !got {
                        // 🚨 取不出来就把 handle 的方法列表打出来，下一轮直接看
                        var hn: UInt32 = 0
                        var hm: [String] = []
                        if let hms = class_copyMethodList(type(of: h), &hn) {
                            for i in 0..<Int(hn) {
                                hm.append(NSStringFromSelector(method_getName(hms[i])))
                            }
                            free(hms)
                        }
                        rbs.append("handle=" + String(describing: type(of: h))
                                   + " 方法[" + hm.prefix(12).joined(separator: ",") + "]")
                    }
                    break
                }
            } else {
                rbs.append("RBSAuditToken 类不存在")
            }
            KbBridge.note("探宿主App·RBS：" + rbs.joined(separator: " ｜ "))

        // 🚨🚨 **csops 探测已摘除（2026-08-31 18:5x）。**
        //    加上之后键盘连续三轮弹不出来（`键盘按钮数=0`）—— 那段里有
        //    嵌套的 `withUnsafePointer` / 对非终止缓冲区做 `String(cString:)`，
        //    都是会让扩展当场挂掉的写法，而扩展一挂**他的键盘就是坏的**。
        //    要再试这条，得先在**主 App**里验安全（主 App 挂了不影响他打字），
        //    确认不崩再挪进键盘。**不许拿他的键盘当实验台。**
            // 🚨 猜名字是在碰运气 —— 把**真实方法列表**列出来，一次看清有什么。
            for clsName in ["LSApplicationWorkspace", "LSApplicationProxy"] {
                guard let c: AnyClass = NSClassFromString(clsName) else {
                    KbBridge.note("方法列表 " + clsName + "：类不存在"); continue
                }
                var names: [String] = []
                var n: UInt32 = 0
                if let ms = class_copyMethodList(c, &n) {
                    for i in 0..<Int(n) {
                        let nm = NSStringFromSelector(method_getName(ms[i]))
                        let low = nm.lowercased()
                        if low.contains("pid") || low.contains("audit")
                            || low.contains("front") || low.contains("running")
                            || low.contains("current") {
                            names.append(nm)
                        }
                    }
                    free(ms)
                }
                var cn: UInt32 = 0
                if let meta: AnyClass = object_getClass(c),
                   let ms2 = class_copyMethodList(meta, &cn) {
                    for i in 0..<Int(cn) {
                        let nm = NSStringFromSelector(method_getName(ms2[i]))
                        let low = nm.lowercased()
                        if low.contains("pid") || low.contains("audit")
                            || low.contains("front") || low.contains("running")
                            || low.contains("current") {
                            names.append("+" + nm)
                        }
                    }
                    free(ms2)
                }
                KbBridge.note("方法列表 " + clsName + "（含 pid/audit/front/running/current）："
                              + (names.isEmpty ? "一个都没有"
                                 : names.prefix(14).joined(separator: " , ")))
            }
        }
        KbBridge.setHostPid(Int(pid))
        KbBridge.note("探宿主App·令牌：宿主 pid=" + String(pid) + "｜路径=" + bid)

        // 🚨🚨 拿到路径之后再进一步：读它的 `Info.plist`。
        //    要的是两样：`CFBundleIdentifier`（身份）和 **URL scheme**（怎么开回去）。
        //    有 scheme 就能用**公开 API** `open(URL)` 切回去，不必碰私有的
        //    `LSApplicationWorkspace` —— 这对将来上架差别很大，所以先试这条。
        //    🚨 读别人的 bundle 可能被沙盒挡，挡了就如实报，别假装拿到了。
        guard bid.contains(".app/") else { return }
        let appDir = (bid as NSString).deletingLastPathComponent      // …/WeChat.app
        let plist = appDir + "/Info.plist"
        guard let dict = NSDictionary(contentsOfFile: plist) as? [String: Any] else {
            KbBridge.note("探宿主App·plist：读不了（多半被沙盒挡）｜" + plist.suffix(60))
            // 🚨🚨 **什么都别写。** 上一版在这里写 `"WeChat.app"`（目录名），
            //    而消费端按 bundle id 查表 —— 必然 miss，还把这个字段污染成
            //    "看起来有值、其实没用"，痕迹跟着一起说谎。
            //    宁可留空走落桌面，也不要一个查不动的值。
            return
        }
        let hostBid = (dict["CFBundleIdentifier"] as? String) ?? "?"
        var schemes: [String] = []
        if let types = dict["CFBundleURLTypes"] as? [[String: Any]] {
            for t in types {
                schemes += (t["CFBundleURLSchemes"] as? [String]) ?? []
            }
        }
        KbBridge.note("探宿主App·plist：bundle=" + hostBid
                      + "｜scheme=" + (schemes.isEmpty ? "无" : schemes.prefix(4).joined(separator: ",")))
        // 🚨🚨 **一个字段只装一种东西**（2026-08-31 交叉审查 高-3）。
        //    上一版是 `rememberSource(schemes.first ?? hostBid)` ——
        //    最常见的那条（读到 scheme）写进去的是 `"weixin"`，
        //    而消费端 `backSchemes[src]` 的键是 bundle id，**必然 miss**。
        //    现在：bundle id 归 bundle id，scheme 单独存。
        if hostBid != "?" { KbBridge.rememberSource(hostBid) }
        if let sc = schemes.first { KbBridge.rememberSourceScheme(sc) }
    }



    private func probeCaptureStack() {
        DispatchQueue.global().async {
            let cap = AVCaptureSession()
            guard let dev = AVCaptureDevice.default(for: .audio) else {
                KbBridge.note("键盘采集栈：拿不到音频设备"); return
            }
            do {
                let inp = try AVCaptureDeviceInput(device: dev)
                guard cap.canAddInput(inp) else {
                    KbBridge.note("键盘采集栈：加不了输入"); return
                }
                cap.addInput(inp)
                let out = AVCaptureAudioDataOutput()
                let sink = AltAudioSink()
                out.setSampleBufferDelegate(sink, queue: DispatchQueue(label: "kbcap"))
                guard cap.canAddOutput(out) else {
                    KbBridge.note("键盘采集栈：加不了输出"); return
                }
                cap.addOutput(out)
                self.kbSink = sink
                self.kbCapture = cap
                cap.startRunning()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    cap.stopRunning()
                    KbBridge.note(String(format:
                        "键盘采集栈：收到 %d 个采样块，峰值 %.3f %@",
                        sink.blocks, sink.peak,
                        sink.peak > 0.001 ? "✅ 有声音" : "（静音）"))
                    self.kbCapture = nil; self.kbSink = nil
                }
            } catch {
                KbBridge.note("键盘采集栈：起不来 —— " + error.localizedDescription)
            }
        }
    }

    private func tryKeyboardLiveActivity() {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                KbBridge.note("键盘灵动岛：系统里被关掉了")
                return
            }
            do {
                _ = try Activity.request(
                    attributes: RecActivityAttributes(),
                    contentState: .init(phase: "正在听", seconds: 0),
                    pushType: nil)
                KbBridge.markIsland(true)
                KbBridge.note("键盘灵动岛：起来了 ✅（扩展可以起岛）")
            } catch {
                KbBridge.note("键盘灵动岛：起不来 —— " + error.localizedDescription)
            }
        }
        #else
        KbBridge.note("键盘灵动岛：这个编译环境没有 ActivityKit")
        #endif
    }

    private func stopListening() {
        // 🚨🚨 **他按的是"停"，在飞的那次后台架必须当场取消**（交叉审查 中-1）。
        //    不取消的话：宿主 1.2 秒内快速回一条 `error` → 相位被打回 `.idle`、
        //    `remoteSeq` 归 -1 → arm 回调的三项复核**全过** →
        //    要么再发一条 `start`（他按的是停止，结果又开始录），
        //    要么 `markWantRec` + 把他拽去主 App。
        //    `cancelBgArm` 是幂等的，没在飞就是空操作。
        cancelBgArm("他按了停止")
        setPhase(.thinking, hint: "")
        if localMode { localVoice.stop(); return }
        // 🚨 停止之后才开始等：等多久按录了多久给（最少 120 秒）—— 15 分钟的录音有 15 段要拼
        let spoke = Date().timeIntervalSince(listenStartedAt)
        // 🚨 存下来给历史用。**这是"他说了多久"，不是端到端耗时** ——
        //    跟安卓 `durMs` 同一个口径（`VoiceImeService.java:2127`：
        //    「durMs 是他说话的时长」）。量错对象的话两端同名字段就是两个东西。
        lastSpokeMs = Int(spoke * 1000)
        pollDeadline = Date().addingTimeInterval(max(120, spoke))
        hostBeatStaleNoted = false
        KbBridge.note("键盘：停止｜说了 " + String(Int(spoke)) + " 秒，等结果最多 " + String(Int(max(120, spoke))) + " 秒")
        // 🚨🚨 **停止时把「此刻的档位」一起送过去**（Kevin 2026-09-04）。
        //    他的原话：「录音开始前界面默认在翻译 tab，**录音过程中点击转写，
        //    结果仍被归到翻译**……期望：**以结束录音时所在的 tab 为准**。」
        //
        //    根因：档位原来只在 `send("start", …)` 里发一次 —— 也就是
        //    **按下录音那一刻就冻住了**，他中途改档，宿主根本不知道。
        //
        // 🚨 规则有两半，这里只做前一半，后一半在宿主那边（见 `case "stop"`）：
        //    ① 录音**进行中**改档 → 算数（就是这一行）；
        //    ② 停录**之后**、结果还在飞时改档 → **不算数**
        //       —— 所以档位在**发 stop 的这一刻**取一次就固定，之后不再看。
        KbBridge.send("stop", args: ["mode": sentMode(),
                                     "tone": KbBridge.prefs.string(forKey: "vime.tone") ?? "",
                                     "lang": KbBridge.prefs.string(forKey: "vime.lang") ?? "en"])
    }

    // MARK: - 扩展直录

    /// 试着**在键盘扩展里直接录**。起得来返回 true（这一轮就走这条），
    /// 起不来返回 false（调用方接着走宿主代录那条）。
    ///
    /// 🚨 判据在 `KbSelfRecord`：**拿到非静音 PCM** 才算成功。
    ///    「引擎没报错」不算 —— 后台那次就是没报错但 `入0`，一帧声音都没有。
    /// **拉起自己的主 App。** 苹果 DTS 明确支持这条（thread 812091，2026-01）：
    /// 4.4.1 那句 `other apps` **不含自家容器 App**，他说跟 App Review 确认过。
    ///
    /// 🚨 **2026-08-29 更正：能自动切回来。** 这条注释原来写着"没有 API"，
    ///    是**没验过就写下的断言**，而它一直被当成产品前提在引用。
    ///    真机实测：`UIApplication` 对 `suspend` 这个 selector `responds(to:) == true`，
    ///    调用后 App 进后台（state=2），**录音靠 `UIBackgroundModes: audio` 在后台继续**。
    ///    主 App 在收到第 3 帧音频（＝麦克风确实在出数据）后自己退回去，
    ///    见 `KbVoiceHost.returnToPreviousApp`。
    /// 🚨 `suspend` 是**私有 selector**，上架审核有被拒先例 —— 这一点没解决，别当成已定。
    ///
    /// 🚨 **两种失败必须分得开**：
    ///    ① 响应链里根本找不到能开 URL 的对象
    ///    ② 找到了但 `open` 返回 false（iOS 26 没开完全访问就是 `-54`）
    ///    今晚已经在"两种失败长得一样"上栽过好几次。
    /// 拉起容器 App 的结果。**别用一个 Bool 表达三件事。**
    ///
    /// 🚨 复审 中-3：原来 `app.open` 的 completion 只 `note`、不影响返回值，
    ///    于是「open 返回 false」在返回值上**跟成功完全一样** ——
    ///    而这个函数的注释自己写着「两种失败必须分得开」。
    enum OpenResult {
        /// 叫醒命令发出去了，结果要等 completion（见 `onOpened`）
        case dispatched
        /// 响应链里根本找不到能开 URL 的对象 —— 当场就知道失败
        case noOpener
    }

    /// **拉起主 App 失败时的统一收尾。**
    ///
    /// 🚨🚨 为什么收在这里：撤 `token` 和撤 `wantRec` 是**同一条规矩的两半**
    ///    —— "没拉起来就不该留下任何'他要录音'的痕迹"。
    ///    原来只撤了 `token`，`wantRec` 由三个调用点各自负责，结果
    ///    **1892 那处从来没撤过**（我上一轮以为改了，其实锚点命中了另一处），
    ///    `startOnArmedHost` 的兜底那处连 `onOpened` 都没传。
    ///    后果：条子留在共享区 → 他晚点自己打开 Transless，**没按录音却开始录音**。
    ///    → 收进这一个出口，三个调用点谁也不用记得（同一规矩多个出口，本月第五次）。
    /// 🚨 `takeWantRec()` 是"取走即清"，没有意图时是空操作，重复调用无害。
    private func openFailed(_ token: Double) {
        KbBridge.cancelRec(at: token)
        _ = KbBridge.takeWantRec()
    }

    /// - Parameter onOpened: `app.open` 的 completion（`false` = 没开成）。
    ///   🚨 **失败时必须撤条子**，否则他下次自己打开 App 会莫名其妙开始录音。
    @discardableResult
    func openContainerApp(_ path: String = "rec",
                          onOpened: ((Bool) -> Void)? = nil) -> OpenResult {
        // 🚨 **先留条子，再叫醒。** 冷启动时 URL 本身送不到（实测 `url=无`），
        //    所以意图不能挂在 URL 上 —— URL 只负责把 App 叫起来。
        // 🚨 参数**从键盘这份**送过去（H4）：主 App 读自己的 UserDefaults
        //    会让"键盘里选了正式语气、出来却是随意"再次发生。
        let ud = UserDefaults.standard
        // 🚨 中-3：**拿住这次写入的令牌**，撤的时候凭它撤。
        let token = KbBridge.requestRec(args: [
            "tone": tone,
            "mode": sentMode(),
            "lang": sentLang(),
        ])
        guard let url = URL(string: "transless://" + path) else {
            self.openFailed(token)
            return .noOpener
        }
        // 🚨🚨🚨 **先试 `extensionContext.open` —— 这是扩展的官方开 URL 通道。**
        //
        //    2026-08-31 查实：走响应链拿到的是 `UIApplication`，
        //    那等于**容器 App 自己开自己** —— iOS 因此不给来源，
        //    主 App 侧一律记成「来自 未知」，于是回程不知道该开回哪。
        //    （对照：我的测试 App 自己 `open` 时，主 App 拿到的是
        //     `来自 com.kevin.tprobe`，**说明来源机制本身是好的，
        //     是我们用错了开 URL 的通道**。）
        //
        //    `extensionContext` 属于**宿主**那一侧，来源归属很可能不一样。
        //    🚨 这条**没验过**，所以：成了就用，没成立刻退回原来那条，
        //    并且**把走了哪条打进痕迹**，下次一看就知道。
        // 🚨🚨🚨 **`extensionContext.open` 对键盘扩展【不成立】——实测回调 false。**
        //    2026-08-31 14:39 Kevin 实撞：「我关掉了主 APP，再点录音，它说录音失败」。
        //    根因就是这段：我加了新通道**却没写退路**，它返回 false 就直接放弃了。
        //    （`NSExtensionContext.open` 是给 share/action 扩展用的，键盘不在其列。）
        //    → 这条已停用。留着注释是为了**别有人再试一遍**：
        //      通道本身能调、`responds(to:)` 也为真，**只有回调是 false**，
        //      所以"能调用"不能当成"能用"。
        //
        //    要重新验它就把 `TRANSLESS_EXTOPEN=1` 打开 —— **而且必须保留下面的退路**。
        // 🚨 2026-09-02：改成文件开关（App Group 的 extopen.txt）—— 环境变量在真机上根本给不进来，这条路等于从没跑过
        if KbBridge.flagFile("extopen"),
           let ctx = extensionContext {
            var settled = false
            // 🚨 URL 可由 extopen_url.txt 覆盖（测 https/通用链接能不能从键盘开）
            var u2 = url
            if let fu = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: KbBridge.group)?
                .appendingPathComponent("Library/Caches/extopen_url.txt"),
               let txt = try? String(contentsOf: fu, encoding: .utf8),
               let alt = URL(string: txt.trimmingCharacters(in: .whitespacesAndNewlines)) { u2 = alt }
            KbBridge.note("拉起主App：试 extensionContext.open " + u2.absoluteString)
            ctx.open(u2) { ok in
                KbBridge.note("拉起主App：extensionContext.open 回调 " + String(ok))
                settled = ok
                if ok { DispatchQueue.main.async { onOpened?(true) } }
            }
            if settled { return .dispatched }
            KbBridge.note("拉起主App：extensionContext 那条没成，退回响应链")
        }
        var r: UIResponder? = self
        while let cur = r {
            // iOS 18+ 起 `UIApplication` 不一定在键盘的响应链上，
            // 所以两种写法都试：先直接认类型，再退回选择器。
            if let app = cur as? UIApplication {
                // 🚨 实验（2026-09-02）：让响应链上的 UIApplication 去开一个 https（通用链接）。
                //    extensionContext.open 连 https 都是 false；这条对自家 scheme 是通的，
                //    看系统会不会把 https://transless.net/kb/arm 当通用链接、以宿主身份拉主 App。
                //    URL 从 ulopen_url.txt 读；空/不存在就走原来的 transless://arm。
                var url = url
                if let fu = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: KbBridge.group)?
                    .appendingPathComponent("Library/Caches/ulopen_url.txt"),
                   let txt = try? String(contentsOf: fu, encoding: .utf8),
                   let alt = URL(string: txt.trimmingCharacters(in: .whitespacesAndNewlines)), alt.scheme == "https" {
                    url = alt
                    KbBridge.note("拉起主App：改开通用链接 " + alt.absoluteString)
                }
                // 🚨🚨 实验：**把主 App 在后台悄悄拉起，不上前台**（2026-09-02 08:5x）。
                //    依据：扒表看到 `UIApplication -launchApplicationWithIdentifier:suspended:`；
                //    假设 Typeless 平时就是这样拉主 App 的，所以**平时根本不跳**，
                //    只有冷启动起不了麦克风（2003329396）时才被迫跳一次 —— 跟他描述的
                //    「通常不跳、偶尔跳」吻合。
                // 🚨 私有 API；由 App Group 的 `Library/Caches/launchsusp.txt` 开关，
                //    默认关。响应且返回真 → 不再 open()（也就不跳）；否则照旧走 open()。
                if KbBridge.flagFile("launchsusp") {
                    let lsel = NSSelectorFromString("launchApplicationWithIdentifier:suspended:")
                    if app.responds(to: lsel),
                       let m = class_getInstanceMethod(type(of: app), lsel) {
                        typealias LFn = @convention(c) (AnyObject, Selector, NSString, Bool) -> Bool
                        let f = unsafeBitCast(method_getImplementation(m), to: LFn.self)
                        let ok = f(app, lsel, "com.kevin.transless" as NSString, true)
                        KbBridge.note("拉起主App：launchApplicationWithIdentifier:suspended:YES 返回 "
                                      + String(ok) + (ok ? " → 不跳，等它在后台架" : " → 退回 open()"))
                        if ok {
                            DispatchQueue.main.async { onOpened?(true) }
                            return .dispatched
                        }
                    } else {
                        KbBridge.note("拉起主App：launchApplicationWithIdentifier:suspended: 不响应")
                    }
                }
                app.open(url, options: [:]) { ok in
                    KbBridge.note("拉起主App：open 回调 " + String(ok))
                    // 🚨 中-3：**以 completion 为判据**。没开成就撤条子，
                    //    否则条子留在共享区没人取，他下次自己开 App 就开始录音。
                    if !ok { self.openFailed(token) }
                    DispatchQueue.main.async { onOpened?(ok) }
                }
                KbBridge.note("拉起主App：走 UIApplication")
                return .dispatched
            }
            let sel = NSSelectorFromString("openURL:")
            if cur.responds(to: sel) {
                _ = cur.perform(sel, with: url)
                KbBridge.note("拉起主App：走 openURL: 选择器")
                // 🚨 选择器这条**拿不到 completion** —— 这是已知的覆盖缺口，
                //    写出来，别让它冒充"已确认成功"。
                KbBridge.note("拉起主App：选择器路径没有回调，成败未知")
                return .dispatched
            }
            r = cur.next
        }
        KbBridge.note("拉起主App：响应链里找不到能开 URL 的对象")
        self.openFailed(token)
        return .noOpener
    }

    /// **他刚才那一按不该白费。**
    ///
    /// 场景：宿主没了 → 键盘跳去 `arm` 架引擎 → 主 App 架好后自己把他送回微信 →
    /// 键盘重新出现。这时候如果引擎已经架好、而他 40 秒内确实按过录音，
    /// **就替他把那一按兑现掉**，不用他再按第二次。
    ///
    /// 🚨 三道闸，少一道都会变成"他想打字却自己开录了"：
    ///    ① 意图必须是**他本人按出来的**（`markWantRec` 只在跳转那两处写）
    ///    ② 意图**取走即清**，只兑现一次
    ///    ③ 现在必须不在录音中，且引擎确实架好了
    /// **手上有存货时，这一按是"重发"而不是"重录"。**
    ///
    /// 🚨 Kevin 2026-08-31：「你不要让我再说一次…因为已经录了，我不想再重新录一遍」。
    /// - Returns: 处理掉了就返回 true（调用方不要再往下走新录音）
    private func retryIfWeHaveAudio() -> Bool {
        guard phase == .idle, KbBridge.hasRetryAudio() else { return false }
        KbBridge.note("键盘：手上有存货，这一按走【重发】，不重录")
        remoteSeq = KbBridge.send("retry", args: [:])
        setPhase(.thinking, hint: L.kb_resending)
        startPolling()
        return true
    }

    private func autoStartIfHeMeantTo() {
        // 🚨 复核**提到这里**，两条分支（直通 / 等 2 秒）自然一致
        //    —— 等待分支复核了三项、直通分支一项都没有，那是"同一规矩两处实现"
        //    的老形状（交叉审查 20260901_0238 低-1）。
        guard phase == .idle, remoteSeq < 0, !localMode,
              KbBridge.recordingSince(maxAge: 60) == nil else { return }
        // 🚨🚨 **意图先只看不取**：取走即清，而下面可能要等引擎，
        //    等失败时如果已经取走了，这一按就彻底没了。
        guard KbBridge.peekWantRec() else { return }
        guard KbBridge.hostArmed() else {
            // 🚨🚨🚨 **这里原来直接 `return`，而且没有任何重试** ——
            //    这就是 Kevin 2026-08-31 报的
            //    「返回微信后，**录音按钮并没有自动开启**」。
            //    时序上这个失败几乎必然：`arm` 那一跳里主 App 架引擎约 0.4 秒，
            //    而他一按左上角返回，键盘 `viewDidAppear` 可能比
            //    `markArmed(true)` 落地还早 —— 于是"只试一次"必然试在空档上。
            //    → 等它一下（顺带发一次 `prearm` 催它）。**复用同一套等待机制，
            //      不新造第二套。**
            guard !bgArmInFlight else { return }
            KbBridge.note("回来自动接上：意图还在但引擎没架好 → 等它一下（最多 2 秒）")
            tryBackgroundArm(wait: 2.0) { [weak self] ok in
                guard let self = self else { return }
                guard ok else {
                    KbBridge.note("回来自动接上：等了 2 秒引擎还是没架好，这一次放弃"
                                  + "（意图留着，他再按一下仍然接得上）")
                    // 🚨 **收掉「正在准备麦克风…」**：这句是 `tapMic` 的在飞闸写上去的，
                    //    而这条路原来不收 —— 屏上挂着"正在准备"却什么都没在准备，
                    //    **这句假话是我们自己写的**（交叉审查 20260901_0252 中-1）。
                    self.clearPreparingHint()
                    return
                }
                // 🚨 等回来时局面可能已经变了 —— 跟 `armInBackgroundThenStart`
                //    同一道复核，不复核就会盖掉别人那一单。
                guard self.phase == .idle, self.remoteSeq < 0, !self.localMode else {
                    KbBridge.note("回来自动接上：等到了但局面已变，丢弃这一次")
                    self.clearPreparingHint()
                    return
                }
                // 🚨 第三条早退，跟另外两条同型：不收提示就会挂着"正在准备"
                guard KbBridge.takeWantRec() else {
                    self.clearPreparingHint(); return
                }
                KbBridge.note("键盘出现：等到引擎架好了 → 替他把那一按兑现掉")
                self.startOnArmedHost(tone: self.tone, via: "回来自动接上(等到的)")
            }
            return
        }
        guard KbBridge.takeWantRec() else { return }
        KbBridge.note("键盘出现：他刚才按过录音且引擎已架好 → 自动接上，不用他再按")
        // 🚨🚨 **走同一个方法，别在这里抄第二份。**
        //    这里原来是 `startOnArmedHost` 的近似复制，**少了那段
        //    「1.5 秒宿主不应答就改走 arm」的兜底** —— 而 Kevin 2026-08-31
        //    报的「返回微信后录音按钮并没有自动开启」正好落在这条没有退路的路上：
        //    宿主没应答，它就静静停在 `.listening`，什么都不会发生。
        //    合并之后这条路自动获得兜底。（同一规矩两处实现必漂，这个月第四次。）
        startOnArmedHost(tone: tone, via: "回来自动接上")
    }

    /// **宿主引擎已架好时的那条路：只发命令，不跳转。**
    ///
    /// 🚨 提成方法是因为现在有**两个**调用点（原本的「已架好」，
    ///    和新加的「后台现架成功」）。抄第二份必漂 —— 这个月已经栽过两次
    ///    （同一规矩两处实现 / 四处实现，改一处等于没改）。
    /// - Returns: 恒 true（"这一按我处理掉了"），跟调用方原来的语义一致。
    /// **宿主活着但引擎没架时该做的事**：先让它在后台架，架成了就不跳。
    ///
    /// 🚨🚨 **这是产品行为，不许挂在任何 flag 后面。**
    ///    上一版我把它写在 `tryLocalRecord()` 里，而那个函数第一行是
    ///    `if !KbBridge.flag("probeaudio") { return false }`，外面还套着
    ///    `if KbBridge.flag("jump")` —— **双开关默认都关着，整条路一行都不跑**，
    ///    我却准备让他按一次然后我去读两条不会出现的痕迹行。
    ///    交叉审查（20260901_0136 高-1）抓出来的。「代码在 ≠ 它被跑过」。
    ///
    /// 🚨 Apple DTS 2026-09-01 已确认：键盘认不出宿主、也没有回程 API
    ///    （论坛 826851，两问两答都是 No）→ 唯一出路是**别离开宿主**，
    ///    而离开的唯一理由就是「引擎没架好」。所以这条路是主线，不是实验。
    private func armInBackgroundThenStart(tone: String) {
        // 🚨 重入闸：等的这 1.2 秒里相位还是 `.idle`，他再按一下会再进来。
        guard !bgArmInFlight else {
            KbBridge.note("键盘：后台架还在飞，这一按忽略")
            return
        }
        KbBridge.note("键盘：宿主活着但引擎没架 → 先让它在后台架一次（这一按不发 start）")
        setPhase(.idle, hint: L.kb_preparing)
        tryBackgroundArm { [weak self] ok in
            guard let self = self else { return }
            // （在飞标记已由 `finishBgArm` 清掉 —— **只有一个地方清**）
            // 🚨🚨 **回来时局面可能已经变了**（交叉审查 高-2）。
            //    这 1.2 秒里按钮是能点的：他可能按了「重发」（`retry` 那一单
            //    会被我们覆盖、连它的轮询表都被 `startPolling` 停掉）、
            //    直录可能已经跑起来（两路抢同一个 inputNode）、
            //    键盘可能收起又弹出（`autoStartIfHeMeantTo` 已经发过 start）。
            //    **不复核就发 start，是拿旧决定盖掉新局面。**
            guard self.phase == .idle, self.remoteSeq < 0, !self.localMode else {
                KbBridge.note("后台架回来时局面已变（相位=" + String(describing: self.phase)
                              + " seq=" + String(self.remoteSeq)
                              + " 直录=" + String(self.localMode) + "）→ 丢弃这一次")
                // 🚨 丢弃归丢弃，**「准备中…」这四个字得收掉**（交叉审查 F4）：
                //    不收的话屏上写着"准备中"而实际已经在录，文字跟真实状态对不上。
                self.clearPreparingHint()
                return
            }
            if ok {
                KbBridge.note("🎉 后台架成了 —— 这一按不跳，直接发 start")
                self.startOnArmedHost(tone: tone, via: "后台现架成功")
                return
            }
            KbBridge.note("后台架不起来（等了 1.2 秒）→ 退回跳转那条（验过能用）")
            KbBridge.markWantRec()
            // 🚨🚨 **必须传 `onOpened`**（交叉审查 高-4）：`.dispatched` 只表示
            //    "命令发出去了"，真成没成看这个回调。不传的话 `open` 回 false
            //    （iOS 26 上没开完全访问就是 `-54`）时，键盘照样显示
            //    「回到你刚才那个 App 继续」—— **让他去点一个根本没被打开的 App**。
            let r3 = self.openContainerApp("arm", onOpened: { [weak self] opened in
                guard let self = self, !opened else { return }
                // 🚨 撤意图由 `openFailed` 统一做了 —— 这里**不要再撤一遍**，
                //    留着会让下一个人以为"每个调用点都得自己撤"，然后照抄到第五处。
                KbBridge.note("拉起主App失败（撤意图已由 openFailed 统一做掉）")
                guard self.phase != .listening else { return }
                self.setPhase(.idle, hint: L.err_open_app_failed)
            })
            switch r3 {
            case .dispatched:
                self.setPhase(.idle, hint: L.kb_rearming)
                if let ctx = self.extensionContext {
                    ctx.completeRequest(returningItems: nil) { ok2 in
                        KbBridge.note("回宿主：completeRequest 回调 ok=" + String(ok2))
                    }
                }
            default:
                // 🚨 交叉审查 高-3：这里原来**没有 else** —— 拉不起来时
                //    不改相位、不给提示，他会对着「准备中…」一直等，
                //    跟卡死分不开。同一条规矩的第二个出口又漏了。
                KbBridge.note("后台架不起来、也拉不起主App（noOpener）→ 明说，别让他干等")
                self.setPhase(.idle, hint: L.err_open_app_failed)
            }
        }
    }

    @discardableResult
    /// - Parameter via: 这一路是**本来就架着**还是**刚在后台现架的** ——
    ///   写进痕迹，否则两个不同机制会被混成一个结论（交叉审查 中-4）。
    /// - Parameter hint: 相位提示。直录回退时要把那句短提示带过来，
    ///   否则「实验做了、结论是什么」他答不上来（默认空串＝原行为）。
    private func startOnArmedHost(tone: String, via: String,
                                  hint: String = "") -> Bool {
        KbBridge.note("键盘：宿主引擎已架好，直接发命令，不跳转｜via=" + via)
        // 🚨🚨 **起岛那句已从这里拿掉**（交叉审查 中-3）。
        //    它自己的注释写着「只留痕、不改行为」= 诊断件，
        //    而这个方法现在有**两个**产品调用点 → 一次点击最多请求两个岛，
        //    **全文件没有任何地方 `end` 它们**，而 Kevin 明确否掉过常挂的岛。
        //    诊断路径（`tryLocalRecord` 里那处，本来就在 flag 后面）保留。
        // 🚨 **别拿上一单的旧结果当这一单的**：这行原来只在主路径上有，
        //    合并进来之后三个调用点都受益（`pollRaw` 是按 `after: lastResAt` 取的）。
        lastResAt = 0
        remoteSeq = KbBridge.send("start", args: [
            "tone": tone,
            "mode": sentMode(),
            "lang": sentLang(),
        ])
        setPhase(.listening, hint: hint)
        startPolling()
        // 🚨🚨🚨 **回退：3 秒宿主不应答就改走跳转。**
        //
        //    Kevin 2026-08-29 被锁进死循环：键盘以为小窗活着 →
        //    只发命令不跳转 → 宿主卡住不回 →
        //    键盘报「Transless 被系统关掉了」→ 他去开 App、还是卡 →
        //    再按又是同一句。**那条新路当时没有任何退路。**
        //
        //    有了这段，最坏情况**退回老行为**（跳过去录），而不是把他锁死。
        //    🚨 **新路径不许比老路径更糟 —— 这是底线。**
        let mySeq = remoteSeq
        hostAnswered = false
        // 🚨 **从 3 秒缩到 1.5 秒（2026-08-31）。**
        //    他实测：杀掉主 App 后第一次按只是干等然后提示，
        //    「过了一段时间我再点」才跳。那段干等就是这里。
        //    缩短是安全的：判据挂在**共享区的"正在录"标记**上，
        //    引擎已架好时宿主起录只要 ~100ms 就会写上它 ——
        //    1.5 秒对活着的宿主绰绰有余，对死掉的宿主少浪费一半时间。
        //    （`staleAfter=6` 那 6 秒里 `hostAlive` 仍是过期的真，
        //      所以这条兜底是那种情况下唯一的出路。）
        fallbackWork?.cancel()
        let fb = DispatchWorkItem { [weak self] in
            // 🚨 跑起来就把手柄放掉 —— 否则它一直指着一个已经跑完的工作项，
            //    后面的 `cancel()` 是空操作、而"在不在飞"也读不准。
            self?.fallbackWork = nil
            // 🚨🚨🚨 **必须带上「还在听」这一条**（交叉审查 20260901_0238 高-1）。
            //    合并主路径之后这条兜底也落到了他每天走的路上，而它原来的三个判据
            //    （`hostAnswered` / `remoteSeq == mySeq` / `recordingSince`）
            //    **没有一条能识别"他已经按停了"**：
            //    按下 → 1.5 秒内再按一次停 → `stopListening` 只改相位、发 `stop`，
            //    `remoteSeq` 没变、`hostAnswered` 还是 false、宿主已停录所以
            //    `recordingSince` 为 nil → 三项全过 → **把他拽去 Transless**，
            //    还顺手 `markWantRec()` 留下假条子 → 下次键盘一出现
            //    **替他自动开录一次他从没按过的录音**。
            //    这条闸同时把 thinking 期间取消、切档等出口一并挡掉。
            guard let self = self, self.phase == .listening,
                  !self.hostAnswered,
                  self.remoteSeq == mySeq else { return }
            // 🚨🚨🚨 **「宿主已经在录」也算应答（2026-08-30 补）。**
            //    这条兜底是从**按下**开始计时的，而宿主要等他
            //    **说完**才出稿 —— 说话超过 3 秒就会被这条兜底
            //    当成"宿主卡住了"然后拽去主 App。
            //    也就是说：不修这一行，**正常使用几乎必然被跳走**，
            //    而且越是正常说话（说得久）越会跳。
            //    判据挂在**共享区那个"正在录"标记**上 ——
            //    它是宿主真起录时写的，比"有没有出稿"早得多。
            if KbBridge.recordingSince(maxAge: 60) != nil {
                self.hostAnswered = true
                KbBridge.note("兜底：宿主确实在录，不跳（等他说完）")
                return
            }
            // 🚨🚨 **改走 `arm` 而不是 `rec`（2026-08-31）。**
            //    `rec` 会把他扣在主 App 里录完一整段、录完还留在那儿 ——
            //    那正是他 08-30 骂的那件事。`arm` 只架引擎、架好自己
            //    送他回微信，再靠 `markWantRec` 把这一按接上。
            KbBridge.note("不跳转那条 3 秒没应答 → 去架引擎（arm），回来自动接上")
            self.pollTimer?.invalidate(); self.pollTimer = nil
            self.remoteSeq = -1
            KbBridge.markPip(false)
            KbBridge.markWantRec()
            // 🚨🚨 **这是 `openContainerApp` 四个调用点里最后一个漏口**
            //    （交叉审查 20260901_0216 中-1，是**穷举**四个调用点得出的）。
            //    原来 `_ =` 丢弃返回值、不传 `onOpened`、还无条件显示
            //    「回到你刚才那个 App 继续」—— 拉不起来时等于**让他去点一个
            //    根本没被打开的 App**。撤意图由 `openFailed` 统一做，这里只管说实话。
            let r4 = self.openContainerApp("arm", onOpened: { [weak self] opened in
                guard let self = self, !opened else { return }
                KbBridge.note("兜底：拉起主App失败，本次没有录音")
                guard self.phase != .listening else { return }
                self.setPhase(.idle, hint: L.err_open_app_failed)
            })
            if r4 == .dispatched {
                self.setPhase(.idle, hint: L.kb_rearming)
            } else {
                KbBridge.note("兜底：连拉都拉不动（noOpener）→ 明说")
                self.setPhase(.idle, hint: L.err_open_app_failed)
            }
        }
        fallbackWork = fb
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: fb)
        return true
    }

    /// **让后台的宿主现在就把引擎架起来**，最多等 `wait` 秒。
    ///
    /// 🚨🚨 这是台账里挂了很久的「还没试的第 2 条」：
    ///    以前所有「后台架引擎」的失败实验，**键盘都不在场**；
    ///    而键盘显示着的时候，我们这一整套在系统眼里是"正在被使用"，
    ///    iOS 放行音频输入的条件很可能不一样。
    ///    **前置条件不同的实验，不能拿旧结论套。**
    ///
    /// 🚨 不阻塞主线程（扩展的看门狗比 App 严，卡住的表现是"键盘弹回上一个"、零诊断）。
    /// - Parameter done: `true` = 架起来了；`false` = 等超时还没架好。
    private func tryBackgroundArm(wait: TimeInterval = 1.2,
                                  done: @escaping (Bool) -> Void) {
        if KbBridge.hostArmed() { return done(true) }
        _ = KbBridge.send("prearm", args: [:])
        bgArmStartedAt = Date()
        bgArmTick(deadline: Date().addingTimeInterval(wait), done: done)
    }

    /// 轮询一拍。**做成实例方法**，不用自引用的局部函数（那个没法取消、还漏上下文）。
    private func bgArmTick(deadline: Date, done: @escaping (Bool) -> Void) {
        let w = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if KbBridge.hostArmed() { return self.finishBgArm(true, done) }
            if Date() >= deadline { return self.finishBgArm(false, done) }
            self.bgArmTick(deadline: deadline, done: done)
        }
        bgArmWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
    }

    /// 收尾：**先清状态再回调** —— 回调里可能又发起一次，顺序反了会互相踩。
    private func finishBgArm(_ ok: Bool, _ done: (Bool) -> Void) {
        bgArmWork = nil
        bgArmStartedAt = nil
        done(ok)
    }

    /// 把「准备中…」那句收掉 —— **只在它确实还挂着时收**，
    /// 免得把别的路径刚设好的提示也擦掉。
    private func clearPreparingHint() {
        guard phase == .idle, hintLabel.text == L.kb_preparing else { return }
        setPhase(.idle, hint: "")
    }

    /// 取消正在飞的那次（切走／卡住时用）。没有在飞就什么都不做。
    private func cancelBgArm(_ why: String, uiSafe: Bool = true) {
        guard let w = bgArmWork else { return }
        w.cancel()
        bgArmWork = nil
        bgArmStartedAt = nil
        // 🚨 取消这条路**不走 `finishBgArm`，`done` 永远不会被调用** ——
        //    所以「准备中…」没有任何人收尾，会一直挂在那儿（交叉审查 F4）。
        // 🚨 `deinit` 里传 `uiSafe: false` —— 那时不该再碰界面（`teardown` 的契约）。
        if uiSafe { clearPreparingHint() }
        KbBridge.note("后台架：取消（" + why + "）")
    }

    private func tryLocalRecord() -> Bool {
        // 🚨🚨🚨 **默认直接放弃直录（2026-08-30）。**
        //    Apple 官方《App Extension Programming Guide · Custom Keyboard》原文：
        //    **自定义键盘无法访问麦克风，因此不可能做听写输入。**
        //    我们真机上撞了一整晚的 `2003329396` 就是这条规则的表现。
        //    每次按都去撞一遍 = 白等 1–2 秒 + 抢麦克风打断宿主那条真路。
        //    `flags.txt` 里写 `probeaudio` 可以打开来复现。
        if !KbBridge.flag("probeaudio") { return false }
        // 🚨 起录前停播放。`tapMic` 那边也停了一次，**这里仍然要停** ——
        //    规则该落在**真正起录的那个函数**上：换个调用方进来就不会漏，
        //    而且多停一次无害。（`gate_stop_before_record` 查的就是这个。）
        Speaker.stop()
        // 🚨🚨 **每一次尝试都要留痕，包括"没尝试"。**
        //    2026-08-28 从他手机上拉容器：`selftest.txt` 一个都没有，
        //    而偏好里 `kb.cmd.seq=7 / kb.res.kind=error` 明明白白说
        //    **键盘走了宿主那条路** —— 也就是 `tryLocalRecord` 返回了 false，
        //    却**什么痕迹都没留下**，于是"它到底跑没跑、为什么退出"无从判断。
        //    这正是今晚反复出现的那个形状：**静默的路径 = 实验等于没做。**
        // 🚨 `完全访问` 是 `open()` 能不能成的前提：
        //    iOS 26 上没开的话 `open()` 直接 `-54`（DTS 原话：这是有意的）。
        //    记下来，免得下次又要靠猜。
        // 🚨🚨 **让键盘自己报出它是哪个版本、自己的 Info.plist 里有没有那个键。**
        //    它一直报「Target does not include NSSupportsLiveActivities」，
        //    而我已经加进 project.yml、也从装机产物里读出是 true、版本也顶到 949。
        //    **到底是 iOS 跑着旧扩展，还是我加错了 target —— 靠猜分不开，让它自己说。**
        let info = Bundle.main.infoDictionary ?? [:]
        KbBridge.note("键盘自报｜版本=" + String(describing: info["CFBundleVersion"] ?? "?")
                      + "｜NSSupportsLiveActivities="
                      + String(describing: info["NSSupportsLiveActivities"] ?? "没有这个键"))
        KbBridge.note("tryLocalRecord 进入｜完全访问=" + String(hasFullAccess))
        // 🚨 **每次按都试一次「键盘起灵动岛」**（只留痕、不改行为）。
        //    原来只在"不跳转"那条分支里试，而他现在走的是跳转，
        //    结果那条一次都没跑过 —— **代码在≠它被跑过**，今天第四次。
        //    放这里的话，他按一次能同时给出两个答案：
        //      ① 键盘自己能不能录（引擎重试后成不成）
        //      ② 键盘能不能起灵动岛
        tryKeyboardLiveActivity()
        if KbSelfRecord.disabled {
            KbBridge.note("直录被 TRANSLESS_NO_SELFREC 关掉了")
            return false
        }
        // 🚨🚨 **这里曾经有一段 `send("yield")` + `Thread.sleep(0.25)`，已删。**
        //    交叉审查（20260828_1933）把它判成必修，两条理由我都接受：
        //    · 宿主 `hold.stop()` 之后**没有任何地方恢复** —— 键盘这条路
        //      一次都碰不到 `reclaimMic()`，等于我们自己把他的待机打死，
        //      **最坏情况比原样更差**，直接推翻我写的「最坏等于原样」。
        //    · 那 250ms 是纯猜的：待机没开时 `drain()` 第一句 `guard standby`
        //      就返回，yield 是空操作；待机开着但宿主刚醒时退化成 2 秒轮询，
        //      250ms 等不到 —— 于是"四档全拒"会被我读成"扩展不能录音"，
        //      **而真相只是宿主还没松手**。这是这个实验最贵的一种错。
        //    · 主线程 sleep 叠加四档会话切换，扩展看门狗比 App 严，
        //      被杀的表现就是「键盘弹回上一个」，**零诊断**。
        //    → 会话真被宿主占着的话，让**系统**去拒，把 stage 和四档 code
        //      原样报出来 —— 那是证据，比我盲等 250ms 强。
        localPeak = 0
        localFrames = 0
        localSyncFail = nil
        localArmed = false
        // 🚨 M5：这两个**必须跟着清**。不清的话第 2 次任何一屏诊断
        //    都会在最上面拼上**第 1 次**的错误 —— 我会照着过期报错去改。
        localFallbackNote = nil
        localFallbackDiag = nil
        localMode = true
        localVoice.onLevel = { [weak self] v in
            guard let self = self else { return }
            // 🚨🚨 M3（交叉审查）：**这个闭包跑在音频渲染线程上**，
            //    而 `localFrames`/`localPeak` 在主线程被读去出判词。
            //    无锁地并发读写 = 计数可能少、峰值可能丢 ——
            //    **而这两个数正是这次实验的全部结论**（帧数决定"起没起来"，
            //    峰值决定 OK/SILENT）。读串了就是把错的结论当成答案。
            //    用 `os_unfair_lock` 而不是队列：渲染线程上不许做会阻塞/分配的事。
            os_unfair_lock_lock(self.localLock)
            self.localFrames += 1
            self.localPeak = max(self.localPeak, v)
            os_unfair_lock_unlock(self.localLock)
            // 波形照样能画 —— 直录时数据就在本进程，不用过 App Group
            // 🚨 `DispatchQueue.main.async` 在实时线程上是会分配内存的，
            //    严格说属于实时线程违规；压力下可能掉帧（审查 M3 同段点名）。
            //    这里保留是因为波形只是显示、掉几帧不影响结论，
            //    **而结论那两个数已经被上面的锁保住了**。
            DispatchQueue.main.async { self.waveView.push(v) }
        }
        heardLabel.text = ""
        // 🚨 高-4：捕获**本代**。取消会把 `localEpoch` 推掉，
        //    于是这条回调回来时对不上，整条丢弃。
        let ep = localEpoch
        localVoice.start(onPartial: { _ in }) { [weak self] r in
            guard let self = self else { return }
            guard ep == self.localEpoch else {
                KbBridge.note("直录回调属于上一代（已取消/已重开），丢弃")
                return
            }
            // 🚨 `Voice.start()` 的失败是**在 start() 里面同步回调**的
            //    （权限不对、引擎起不来都是）。`localArmed` 就是用来分这两种：
            //    还没 armed = 还在 start() 里 = 同步失败 = 该回退；
            //    已经 armed = 真的录完了。
            //    分不开的话，一次起不来会被当成"录了个空的"，
            //    然后既不回退、也不报错，界面卡在录音中。
            guard self.localArmed else {
                self.localSyncFail = "\(r)"
                return
            }
            // 🚨 高-3(a)：**把本代一起送过去**。原来 `finishLocal` 里写的是
            //    `let ep = localEpoch`（重新取当前值），那**不是闸**——
            //    这道 async 排队期间若发生取消，它捕获到的是新代次，
            //    后面三道全部自我对齐，一路走到 `insertText`。
            DispatchQueue.main.async { self.finishLocal(r, ep: ep) }
        }
        localArmed = true

        if let f = localSyncFail {
            // 🚨🚨 **把「键盘自己录为什么没成」原样写进痕迹。**
            //    以前只存在变量里，只有出错弹窗才看得到 —— 而这条路
            //    每次都会静默走过去（直录失败 → 跳转），**等于每次都白丢一份证据**。
            // 🚨 这条特别值钱：之前那次"键盘录不了"是在**我们自己的 App 里**测的，
            //    那时主 App 自己占着麦克风会话。**在微信里是不是同样结果，从来没测过。**
            //    要是在微信里能录，整个"跳过去再跳回来"就都不需要了。
            KbBridge.note("键盘直录没成：" + String(f.prefix(150)))
            // 🚨🚨 **第三条采音路：`AVCaptureSession`。**
            //    引擎（`2003329396`）和录音机（`record()=false`）都试过了，
            //    **采集栈在键盘里一次没试过** —— 它走的是 AVFoundation 采集栈，
            //    跟前两条不是同一套。宿主前台跑它是能出数据的（115 个采样块）。
            //    键盘扩展是**跟着微信一起在前台**的进程，理应比后台的宿主有戏。
            //    只留痕、不改流程：先确认它到底行不行。
            probeCaptureStack()
            // 🚨 引擎被拒 → 立刻用录音机试 2 秒，看这条路通不通。
            //    先只留痕、不改流程：确认它行了再接进产品路径。
            recordWithRecorder(seconds: 2) { _, _ in }
            localMode = false
            // 只留前 40 个字，提示条是一行的东西，塞长了会被挤成看不清的一条
            KbBridge.note("直录同步失败：" + String(f.prefix(240)))
            // 🚨🚨 **唯一能录的地方是"主 App 在前台"**（三档实测），
            //    而苹果 DTS 明确说键盘可以拉起自家容器 App
            //    （thread 812091，2026-01；4.4.1 的 `other apps` 不含它）。
            //    → 直录起不来时，跳过去录才是官方形态。
            //
            // 🚨 **藏在开关后面，默认不跳**：切到别的 App 是他**看得见**的交互，
            //    按铁律「先出方案 → 他点头 → 才写代码」，**形态归 2.1 定**。
            //    我只用它做验证；没开这个开关时，行为跟以前一模一样。
            //
            // 🚨🚨 **2026-08-29 更正：能自动切回来，这条旧断言作废。**
            //    真机实测 `UIApplication` 认 `suspend`，主 App 收到第 3 帧音频后
            //    自己退回上一个 App，录音在后台继续（见 `KbVoiceHost.returnToPreviousApp`）。
            //    Kevin 当天原话：「切回来这个动作不该由我触发，是后台系统触发的」。
            // 🚨 **同一句过时断言当时写在两处，我第一次只改了一处** ——
            //    「规矩要按每个出口落地」的反面样本，两处现在都改了。
            // 🚨 遗留未决：`suspend` 是私有 selector，上架审核风险没解决。
            // 🚨🚨 **必须 `return true`。** 审查 H1：`tapMic` 里是
            //    `if tryLocalRecord() { return }`，返回 `false` 的语义是
            //    「这条没走成，接着走宿主那条」—— 于是主 App 被 URL 拉起来录一路，
            //    **宿主同时又收到 `start` 再录一路，两路抢同一个 inputNode**。
            //    那样我拿到的帧数/峰值**测的是哪一路自己都说不清**。
            //    （00:02 那次面包屑里 `6 秒` 出现在 `3 秒` 前面，就是两套计时器在跑。）
            //
            //    只有**响应链里根本找不到能开 URL 的对象**时才落回宿主，
            //    而那一条 `openContainerApp` 自己会留痕。
            if KbBridge.flag("jump") {
                // 🚨 中-3：`dispatched` 只表示**命令发出去了**，
                //    真成没成看 `onOpened`；没开成就落回宿主那条。
                // 🚨🚨 **麦克风热着就别跳。**
                //    苹果 DTS 明说没有 API 能把宿主 App 切回前台，
                //    所以正解不是"跳完想办法回来"，是**根本别跳**：
                //    主 App 的麦克风一直开着（真机实测后台能连续采 3 分钟以上），
                //    这一按只是告诉它「从现在开始收」。
                // 🚨 判据带新鲜度（8 秒）：宿主被系统杀掉时来不及清那个标志，
                //    读到过期的"热着"会让这一按**什么都不发生** —— 比多跳一次糟得多。
                // 🚨🚨🚨 **上面那条"常开麦克风已撤"已作废（2026-08-31 推翻）。**
                //    当时的理解是「引擎架着 = 麦克风常开 = 他不接受」。
                //    他 2026-08-30 澄清了真正的理由：**反对的是"没人知道它在不在听"，
                //    不是耗电**（「用户说什么都有理由怀疑被这个输入法记下来」）。
                //    → 现在的做法：**引擎一直架着，但输入用
                //      `AVAudioApplication.setInputMuted` 在系统层面静音**，
                //      按下才解、松开就静。实测静音期间 **94~96% 的采样点是数字零**
                //      （没静音时 1~3%），系统自己也如实显示麦克风状态。
                //    **他当场验收通过**：「点了一下它就开了麦克风，再关它也关了…
                //      比 Typeless 更好用呀」。
                //    详见 `voice_ime/打通经过_无跳转录音.md`。
                // 🚨 下面这句"Typeless 的真实做法是画中画"**是当时的猜测，从未证实**，
                //    而且画中画那条路已于 2026-08-30 整条作废（他两次被它坑住）。
                //    Typeless 到底怎么做的**至今没测到**：连试四轮 UI 自动化都够不到
                //    它的键盘（按坐标当地球键 / 它的键没有无障碍标签 / 长按弹的是
                //    系统键盘自己的布局菜单 / 真地球键只在两个系统键盘间轮换）。
                //    唯一测到的硬事实：**把它进程全杀干净后，它的主 App 会自己回来**。
                //    （旧说法保留在下面，仅作历史，别当依据。）
                //    Typeless 的真实做法是**画中画**：让主 App 在后台仍算"可见"，
                //    **需要时才开麦**（它自己的发布说明写着「仅在您说话时开启麦克风」）。
                //    → 方向改回画中画，这段留成 `false` 不再触发。
                // 🚨🚨🚨 **小窗活着就别跳。这是整件事的解法。**
                //    苹果 DTS 明说没有 API 能把宿主 App 切回前台，
                //    所以正解不是"跳完想办法回来"，是**根本不跳**：
                //    主 App 挂着一个画中画小窗 → 系统当它"可见" → **后台也能起录**。
                //    真机对照（2026-08-29）：不开小窗，后台自检压根没跑；
                //    开着小窗，后台起录成功、拿到 12 帧。
                // 🚨🚨🚨 **宿主活着就别跳 —— 这是整件事的终点。**
                //
                //    2026-08-29 从 Typeless 身上抓到的做法（他手机上列进程：
                //    它常年跑着主App + keyboard + dynamicisland）：
                //    **主 App 活着 → 按键盘只发命令 → 根本不跳 → 不存在"回不来"。**
                //
                //    而「后台起不了录」那一关，答案是**起录那一刻才亮灵动岛**：
                //      没有岛           → 后台起录 `输入源 0 个`
                //      岛一直挂着       → 能录，但 Kevin 否掉（丑）
                //      **按下才亮、用完就收** → ✅ `OK 拿到非静音音频 / 峰值 0.519`
                //    iOS 要的不是"一直可见"，是"**起录那一刻**可见"。
                //
                //    🚨 判据从 `pipReady()` 换成 `hostAlive` —— 画中画那条已作废
                //       （前台请求被忽略、退后台才接管，都试过）。
                //    🚨 下面那段 3 秒回退还在：宿主不应答就退回跳转，
                //       **新路径不许比老路径更糟**。
                // 🚨🚨🚨 **判据从「宿主活着」改回「灵动岛亮着」。**
                //
                //    2026-08-30 00:40 Kevin 实撞：按下去只出「没听清，离手机近一点」，
                //    **一帧音频都没录到**。链路是：
                //      宿主活着 → 键盘走不跳转、发命令 →
                //      宿主在后台拿不到麦克风 → 我加的保险拒绝 →
                //      键盘把这个拒绝当成「没听清」显示给他。
                //
                //    🚨 **「宿主活着」不等于「宿主能录」** —— 后台的宿主活着但没有麦克风。
                //       判据挂错了对象，今天第 N 次。
                //    → 只有**岛真的亮着**（宿主才有可见存在、后台才给麦）才走不跳转；
                //      否则老老实实跳，那条是验过能用的。
                // 🚨🚨 **闸门从「岛亮着」放宽到「宿主活着」（2026-08-30）。**
                //    上面那句「宿主活着≠宿主能录」在**只播保活**下成立；
                //    可录保活（`.playAndRecord` 常驻）下**不成立** ——
                //    那时后台一直握着输入路由，活着就是能录。
                //    宿主真录不了会答一个错误，键盘还有 3 秒回退兜底。
                // 🚨🚨 判据是 **`hostArmed`（引擎架好了）**，不是 `hostAlive`（活着）。
                //    2026-08-30 实测：宿主活着但引擎没架时，后台起录必被拒
                //    （`2003329396`）—— 那时发命令等于把他锁在"没听清"里。
                //    **只有引擎架着才不用跳**；没架就老老实实跳，那条是验过能用的。
                // 🚨🚨🚨 **宿主活着但【引擎没架】时，必须去 arm 一次，不能发 start。**
                //    Kevin 2026-08-31 深夜：「一直说『没听清，再说一次』，怎么点都一样」。
                //    痕迹里就是这个形态：
                //      `按下麦克风｜宿主活着=true｜引擎架着=false` → 还是发了 start
                //      → 主 App 在后台起录 → `2003329396` → 「没听清」
                //      → 他再点，同一条路，**永远循环**
                //    「活着」和「能录」是两回事 —— 这条我在别处写过，
                //    但**这个分支漏了**（同一规矩多个出口，今天第六次）。
                if !KbBridge.hostArmed() {
                    armInBackgroundThenStart(tone: tone)
                    return true
                }
                if KbBridge.hostArmed() {
                    return startOnArmedHost(tone: tone, via: "本来就架着")
                }
                if false, KbBridge.hotMicReady() {
                    KbBridge.note("键盘：麦克风热着，直接发命令，不跳转")
                    remoteSeq = KbBridge.send("start", args: [
                        "tone": tone,
                        "mode": sentMode(),
                        "lang": sentLang(),
                    ])
                    setPhase(.listening, hint: "")
                    startPolling()
                    return true
                }
                if openContainerApp("rec", onOpened: { [weak self] ok in
                    guard let self = self, !ok else { return }
                    // 🚨 中-2：**说实话**。这里并没有落回宿主 ——
                    //    没有 `send("start")`、没有 `startPolling()`。
                    //    而且拉不起主 App 时宿主多半也不在，真落回一样会失败，
                    //    所以**不骑墙**：本次就是没录成，把话说清楚。
                    //    （留着"落回宿主代录"那句的话，下次按日志排查会查错方向。）
                    KbBridge.note("拉起失败，本次没有录音；已提示他去开完全访问")
                    // 🚨 **没跳成就不该留意图**（交叉审查 F3）：同一规矩在
                    //    `armInBackgroundThenStart` 的失败回调里落地了，**这个出口漏了**。
                    //    留着条子的后果：他晚点自己打开 Transless 会**无端起录**。
                    _ = KbBridge.takeWantRec()
                    // 🚨 这个 completion 是异步的，可能落在他已经重新开录之后 ——
                    //    那时把界面打回待命，而录音还在跑。
                    guard self.phase != .listening else { return }
                    self.setPhase(.idle, hint: L.err_open_app_failed)
                }) == .dispatched {
                    // 🚨🚨🚨 **这里原来是 `.idle`，那一行就是他今天报的三件事的根因。**
                    //    Kevin 2026-08-29：「看不出它在录音」「我也不知道该怎么停下来」
                    //    「回到微信点了这个录音键它也不会再录音」——
                    //    三句话都指向同一件事：**跳走之后键盘把自己设成了「待命」**。
                    //    待命态既不显示录音、也没有停止动作，再按一下自然是"重新开始"（又跳一次）。
                    //
                    //    改成 `.listening` 之后三件一起解掉，而且**不用新写任何东西**：
                    //      · `setPhase` 末尾的 `retickUI()` 会起波形刷新
                    //      · `uiTick` 的 `.listening` 分支里 `!localMode` 那条
                    //        **本来就在画宿主的波形**（`KbBridge.levels()`）→ 他看得见在录
                    //      · 按钮变红、`tapMic` 的第一行 `if phase == .listening { stopListening() }`
                    //        → 再按一下就是停止（`send("stop")` → 宿主 `case "stop": finish()`）
                    //    **原来这三样都是现成的，只是相位不对，全都没被接上。**
                    setPhase(.listening, hint: "")
                    return true
                }
                KbBridge.note("jump：拉不起主App，落回宿主那条")
            }
            localFallbackNote = "直录起不来，已回退：" + String(f.prefix(40))
            localFallbackDiag = "=== 扩展直录 ===\n起不来：" + f + "\n"
                + Voice.diagnostics()
            // 电脑够得着时直接拉这份，不用等他截图。
            // 🚨 实验结果**无论成败都要落地**，不然又是一次"测了但不知道结果"。
            // 🚨🚨 `started: false` —— **只有这条分支才是真的"引擎没起来"**
            //    （`Voice.start()` 同步就失败了）。`finishLocal` 那几个调用点
            //    走到那里就意味着引擎已经起来过，必须用默认的 `true`，
            //    否则「哑麦克风」会被打成「起不来」，**结论正好反过来**（H-5）。
            // 🚨 上面原来有**两条一模一样的调用**（复制粘贴残留，第 1 轮 M8），
            //    而 `writeSelfTest` 是覆盖写 —— 写两遍只是白写一次。已删一条。
            KbBridge.writeSelfTest(KbSelfRecord.report(
                ok: false, frames: 0, peak: 0, note: f,
                foreground: true, who: "扩展", started: false))
            return false
        }
        KbBridge.note("直录起来了，进入 listening")
        setPhase(.listening, hint: "")
        return true
    }

    private func finishLocal(_ r: Result<Data, Voice.Failure>, ep: Int) {
        // 🚨🚨 高-3(a)：**比对，不是重新取值**。
        //    上一版写的是 `let ep = localEpoch` —— 那是把当前值抄一遍，
        //    等于这道闸恒为真。真正的闸是拿**起录时那一代**来比。
        guard ep == localEpoch else {
            KbBridge.note("出稿回调属于上一代（已取消/键盘已切走），整条丢弃")
            return
        }
        localMode = false
        waveView.setActive(false)
        // 🚨 **一次快照，整段用它** —— 别在几处分别读那两个字段，
        //    那样同一份报告里的帧数和峰值可能来自不同时刻。
        let snap = localSnapshot()

        switch r {
        case .failure(let f):
            KbBridge.writeSelfTest(KbSelfRecord.report(
                ok: false, frames: snap.frames, peak: snap.peak,
                note: "\(f)\n" + localVoice.frameHealth, foreground: true, who: "扩展"))
            setPhase(.idle, hint: KbBridge.hasRetryAudio() ? L.kb_rec_failed_retry : L.kb_rec_failed_tap)
            showDiag(KbSelfRecord.report(ok: false, frames: snap.frames,
                                         peak: snap.peak, note: "\(f)",
                                         foreground: true, who: "扩展"))
        case .success(let wav):
            let voiced = snap.peak >= KbSelfRecord.voiced
            // 🚨 M1：把取数健康度带上。**没有它，「转换全失败」和
            //    「系统给了哑麦克风」在报告里长得一模一样**，而这个实验的
            //    判据恰好就是"有没有声音" —— 分不开就会把假 SILENT 当结论。
            let note = "wav \(wav.count) 字节\n" + localVoice.frameHealth
            KbBridge.writeSelfTest(KbSelfRecord.report(
                ok: true, frames: snap.frames, peak: snap.peak,
                note: note, foreground: true, who: "扩展"))
            // 🚨 **全程静音也要说出来**，别把一段空气送去后端然后报"没听清"。
            //    那样他看到的是"又失败了"，而真正的信息（引擎起来了、
            //    但一帧声音都没进来）就丢了。
            if !voiced {
                setPhase(.idle, hint: KbBridge.hasRetryAudio() ? L.kb_rec_failed_retry : L.kb_rec_failed_tap)
                showDiag(KbSelfRecord.report(ok: true, frames: snap.frames,
                                             peak: snap.peak, note: note,
                                             foreground: true, who: "扩展"))
                return
            }
            let mode = Backend.Mode(
                rawValue: KbBridge.prefs.string(forKey: "vime.mode")
                    ?? "en") ?? .en
            let lang = KbBridge.prefs.string(forKey: "vime.lang") ?? "en"
            Backend.transcribe(wav: wav) { [weak self] t in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    // 🚨 高-4：第三道闸。网络回调隔着几秒，最容易落在取消之后。
                    guard ep == self.localEpoch else { return }
                    switch t {
                    case .failure(let e):
                        self.setPhase(.idle, hint: "")
                        // 🚨 中-7：**人话上屏、原文进诊断**。
                        //    `"\(e)"` 是 description（`[internal] 后端原文` /
                        //    `NSURLError 网络不可达`），断网时他看到的是
                        //    一屏技术文字、**没有任何"该干什么"**。
                        //    `showDiag` 留给**录音本身**失败（那才是要他复制的现场）。
                        KbBridge.note("失败·键盘直录：" + String("\(e)".prefix(160)))
                        self.hintLabel.text = e.userText
                    case .success(let zh):
                        self.heardLabel.text = zh
                        Backend.polish(text: zh, tone: self.tone, mode: mode,
                                       lang: lang) { [weak self] p in
                            DispatchQueue.main.async {
                                guard let self = self else { return }
                                // 🚨 高-4：第四道闸 —— 它下游就是 `insertText`。
                                guard ep == self.localEpoch else { return }
                                switch p {
                                case .failure(let e):
                                    self.setPhase(.idle, hint: "")
                                    KbBridge.note("失败·键盘润色："
                                                  + String("\(e)".prefix(160)))
                                    self.hintLabel.text = e.userText
                                case .success(let en):
                                    self.deliverLocal(zh: zh, out: en)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// 直录这条路的落地。**跟 `deliver()` 干的是同一件事** ——
    /// 🚨 两处要一起改（历史、朗读按钮、插字、回到待命，一条都不能少）。
    private func deliverLocal(zh: String, out: String) {
        // 🚨🚨 H-2（第 2 轮审查）：**宿主路径有这道 guard，直录路径漏了。**
        //    后端 200 但 `out` 为空串（只录到语气词/静音时的常见返回）时：
        //    插入空字符串、提示被清空、`heardLabel` 也清空 ——
        //    他看到的是麦克风转回紫色，**一个字、一行提示、一个面板都没有**。
        //    这就是今晚最贵的那种失败「什么都没发生」的第一条现实路径。
        //    🚨 空结果时**保留 `heardLabel` 上的中文**，至少证明"听到了"。
        guard !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            heardLabel.text = zh
            setPhase(.idle, hint: L.kb_host_slow)
            return
        }
        let mode = KbBridge.prefs.string(forKey: "vime.mode") ?? "en"
        History.add(mode: mode, tone: tone, zh: zh, out: out, durMs: lastSpokeMs,
                    // 🚨 KPI ④ 按目标语言去重：只有翻译档（en）才有目标语言，整理/逐字传空。
                    lang: mode == "en" ? (KbBridge.prefs.string(forKey: "vime.lang") ?? "en") : "")
        lastOut = out
        heardLabel.text = ""
        textDocumentProxy.insertText(out)
        setPhase(.idle, hint: "")
    }

    // MARK: - 遥控：等主 App 把结果递回来

    /// 🚨 Darwin 通知只降延迟、**不作唯一路径** —— 进程被挂起时它会丢，
    ///    只靠它的表现是「有时候能用」，那种间歇性故障比彻底坏掉还难查。
    ///    所以这里是**轮询**，通知那条以后可以加，加了也只是让它更快。
    private func startPolling() {
        pollTimer?.invalidate()
        pollDeadline = (phase == .listening) ? nil : Date().addingTimeInterval(120)   // 说话不设限
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) {
            [weak self] t in
            guard let self = self else { t.invalidate(); return }
            if self.remoteSeq < 0 { t.invalidate(); return }
            // 2026-09-02 Kevin：在短信里按停 → 转 20 秒 → 弹「Transless 被系统关掉了」，而它明明开着。
            //    真相：他中途切回短信，宿主被【挂起】不是被【杀】——心跳停了，但它的「出稿保活」
            //    后台任务还在转写，结果随后会落进共享槽。这里一见心跳停就判死、把 remoteSeq 清掉，
            //    等于自己把即将到来的结果扔了，再报一个错的原因。
            //    → 等结果期间**心跳停不算死**，只由下面的 pollDeadline（≥120 秒、有动静就续）兜底，
            //      到期说的是「等太久了」——宁可说慢，不许说它死了。
            if !KbBridge.hostAlive, !self.hostBeatStaleNoted {
                self.hostBeatStaleNoted = true
                KbBridge.note("键盘：宿主心跳停了（多半被挂起），结果还在等，不判死")
            }
            if let d = self.pollDeadline, Date() > d {
                t.invalidate()
                self.remoteSeq = -1
                self.setPhase(.idle, hint: L.kb_host_slow)
                return
            }
            guard let r = KbBridge.takeResult(seq: self.remoteSeq,
                                              after: self.lastResAt) else { return }
            self.lastResAt = r.at
            self.hostAnswered = true
            if let d = self.pollDeadline { self.pollDeadline = max(d, Date().addingTimeInterval(60)) }   // 有动静就续期
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
                // 🚨🚨 **不许把诊断铺成黑屏给他**（2026-08-29 他实撞）。
                //    他原话：「刚点了录音键，然后就到黑屏去了…发了一堆东西」。
                //    那是给**我**看的现场，不该出现在他脸上。
                //    → 屏上只留一句人话，完整现场进「录音诊断」页（他要看再去看）。
                KbBridge.note("宿主报错（已收进诊断，不铺黑屏）："
                              + String(r.body.prefix(160)))
                if r.body.contains("\n") || r.body.count > 24 {
                    self.setPhase(.idle, hint: L.err_empty)
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
        let mode = KbBridge.prefs.string(forKey: "vime.mode") ?? "en"
        History.add(mode: mode, tone: tone, zh: zh, out: out, durMs: lastSpokeMs,
                    // 🚨 KPI ④ 按目标语言去重：只有翻译档（en）才有目标语言，整理/逐字传空。
                    lang: mode == "en" ? (KbBridge.prefs.string(forKey: "vime.lang") ?? "en") : "")
        lastOut = out
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
            rawValue: KbBridge.prefs.string(forKey: "vime.mode") ?? "en") ?? .en
        let lang = KbBridge.prefs.string(forKey: "vime.lang") ?? "en"
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
                                zh: zh, out: en, durMs: self.lastSpokeMs,
                                // 🚨 KPI ④：翻译档才带目标语言，整理/逐字传空
                                lang: mode == .en ? lang : "")
                    self.lastOut = en
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

    /// **停掉这一轮的一切**：录音、轮询、代次、界面状态。
    ///
    /// 🚨🚨 复审 20260829_0937 高-1：这段原来在 `deinit` 和 `viewWillDisappear`
    ///    里**各写了一遍，而且两遍不一样** —— `deinit` 有 `send("cancel")`，
    ///    `viewWillDisappear` 没有。我自己在注释里写着「两个出口一起改」，
    ///    然后还是只改了一半。**同一条规矩两处实现，迟早漂。**
    ///
    /// 而且两处都只"停"不"收拾"：不清 `remoteSeq`、不重置 `phase` ——
    /// 后果是麦克风在键盘切走后**继续开着**（主 App 录满 60 秒、橙点一直亮，
    /// 违反 P1「没在说话时麦克风必须真的是关的」），
    /// 切回来还是红色停止态，按一下发了 `stop` 却没人重启轮询，永远停在「…」。
    ///
    /// - Parameter uiSafe: `deinit` 里传 `false` —— 那时不该再碰界面。
    /// - Parameter cancelRemote: 要不要把主 App 那边的录音也撤掉。
    ///   🚨🚨 **只有 `deinit` 传 true。**
    ///   `viewWillDisappear` 会在**他切到别的 App** 时触发，而那时候
    ///   录音应当继续（Kevin 2026-08-31 明确要的场景：切窗口继续说）。
    ///   上一版这里无条件 `send("cancel")`，一条链造出两个症状：
    ///   录音当场停 + 回来按停止后无限 loading（撤单后 `remoteSeq = -1`，
    ///   再按停止没有对应的活，键盘就在等一个永远不会来的结果）。
    private func teardown(uiSafe: Bool, cancelRemote: Bool) {
        // 🚨🚨 **键盘收起时那段 composing 要「定稿」，不能删掉、也不能当没发生。**
        //
        //    他打了一半拼音就切走键盘（或按 Home、或宿主收键盘），
        //    输入框里正挂着 "niha" 这样一段。两种错法都很糟：
        //      · 删掉它 → **他打的东西凭空消失**（比留着更糟）；
        //      · 什么都不做 → 记账 `shownComposing` 还留着，下次键盘起来
        //        第一次 `clearShownComposing()` 会删掉**他后来自己打的字**
        //        （记账和屏幕分家，删错对象）。
        //    正确做法是**只清记账、不动文档**：那段拼音就当他打的字留在那儿，
        //    跟安卓「切走前 `commitPending()`」是同一个取舍 ——
        //    **绝不静默吞掉他打的东西**。
        shownComposing = ""
        // 🚨🚨 **键盘收起/销毁时必须取消在飞的后台架**（交叉审查 F2）。
        //    不取消的话链子照跑（block 是 `[weak self]`，VC 还活着就一直跑），
        //    到点照样 `markWantRec()` + 拉主 App + 在已经消失的扩展上
        //    调 `completeRequest` —— 于是**他没按录音，下次自己打开 App 却开始录音**。
        //    那正是 `openContainerApp` 注释里要防的事，换了个入口又发生。
        cancelBgArm("键盘收起/销毁", uiSafe: uiSafe)
        // 🚨 那条 1.5 秒兜底也要一起取消 —— 否则键盘都不在了，
        //    它还会把主 App 拉起来（交叉审查 20260901_0252 低-2）。
        fallbackWork?.cancel()
        fallbackWork = nil
        // 🚨 **先推代次再 stop**：`localVoice.stop()` 会同步触发 `onWav`，
        //    顺序反了的话那条回调仍属于"本代"，照样会一路走到 `insertText`。
        localEpoch += 1
        localArmed = false
        // 🚨 低-5：**busy 也要复位** —— 不复位的话切走再回来，
        //    🔊 是一个点不动的「…」，而那次 TTS 早就没人接了。
        speakBusy = false
        if localMode {
            localVoice.stop()
            localMode = false
        }
        // 🚨 撤单只在**键盘真被销毁**时做（`deinit`）。
        //    隐藏（切 App）时保住这一单：他多半正说着话切过去继续说。
        // 🚨🚨🚨 **销毁也不撤单了**（Kevin 2026-09-04 实测复现后改）。
        //
        //    他的原话：「我点这个微信窗口点录音，我切到美团去了，
        //    然后再回到微信，它这个录音就自动停了，就没了？」
        //
        //    痕迹（他手机 16:32）把整条链摆得很清楚：
        //      16:32:36 按下麦克风
        //      16:32:40 键盘隐藏但录音继续（seq=852），不撤单   ← 这条对
        //      16:32:41 上一条录音已作废                        ← 一秒后被撤了
        //    也就是说 iOS 在他切走时**把键盘扩展整个销毁**，
        //    走的是 `deinit → teardown(cancelRemote: true)` 这条 —— 
        //    「切走不撤单」那条判断**只管隐藏、管不住销毁**。
        //    一条规矩两个出口，只落地了一个。
        //
        // 🚨 **录音本来就不在键盘进程里**（苹果不让扩展录音，真正在录的是
        //    后台的宿主）。键盘没了不代表录音该没 —— 撤单是我们自己多做的动作。
        //
        // 🚨 但**不能只删这一句**：新键盘起来时 `remoteSeq = -1`，
        //    他按停止会没有任何反应（"还在录但停不下来"比停掉更糟）。
        //    所以单号写进共享区，`viewDidAppear` 那边接回来（见那处）。
        if remoteSeq >= 0 {
            KbBridge.markKeyboardGone()
            KbBridge.note("键盘" + (cancelRemote ? "被销毁" : "隐藏")
                          + "，录音继续（seq=" + String(remoteSeq) + "），不撤单")
        }
        // 🚨 `remoteSeq` 是本进程内存里的，进程没了它自然就没了；
        //    这里**不主动清**，免得隐藏（没销毁）那一路把自己的单号丢掉。
        // 🚨 **三个浮层都要收**（2026-08-31 交叉审查 低-2）。
        //    上一版只收了语言那个 —— 打开历史 → 切走 → 切回来，
        //    历史面板还盖在键盘上。诊断面板同理
        //    （`hideDiag` 的注释自己写过「留一个点不动的 ✕ 比没有还糟」）。
        // 🚨 `deinit` 传的是 `uiSafe: false` —— 那时不该再碰界面。
        //    这三行原来不受 `uiSafe` 管（交叉审查 20260901_0216 低-2）。
        if uiSafe {
            hideLangPicker()
            hideHistory()
            hideDiag()
        }
        pollTimer?.invalidate()
        pollTimer = nil
        pendingWatch?.invalidate()
        pendingWatch = nil
        // 🚨 还在录就别把界面刷回 idle —— 回来时得看得出"还在录"。
        //    `viewWillAppear` 里的 `restoreRecordingPhase()` 会按主 App 的
        //    真实状态再校一次，这里只是不要先把它抹掉。
        if uiSafe && phase != .idle && remoteSeq < 0 {
            // `setPhase(.idle)` 会连带停 `uiTick`、关波形、把 🔊 刷回来 ——
            // 不重置的话 `retickUI` 的 0.12 秒定时器**永不退出**
            // （它只在 `.idle` 时 invalidate），键盘不可见时还在重放陈旧波形。
            setPhase(.idle, hint: "")
        }
    }

    deinit {
        // 🚨 键盘被销毁时**必须撤单**：否则主 App 还在替一个已经不存在的键盘
        //    录音，麦克风指示灯一直亮着，而没有任何人会来收结果。
        // 🚨 `uiSafe: false` —— deinit 里不该再碰界面。
        teardown(uiSafe: false, cancelRemote: true)
        // 🚨 低-5：堆上那把锁要还回去（键盘扩展会反复销毁重建）。
        //    🚨🚨 复审 中-4：上一版这两行**被关进了 `if localMode {}` 里**
        //       （批量插入落错了位置，缩进也是乱的）——
        //       而正常用完一次之后 `localMode` 就是 false，
        //       **于是"已修"的那个泄漏在绝大多数生命周期里根本没修**。
        localLock.deinitialize(count: 1)
        localLock.deallocate()
    }

    /// 🚨 扩展里 `deinit` 不保证及时 —— 键盘被收起/切走时先在这里停一次。
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 🚨 跟 `deinit` **走同一个** `teardown()`。
        //    原来这两处各写一遍、而且写得不一样，正是复审 高-1 抓到的。
        teardown(uiSafe: true, cancelRemote: false)
    }

    /// **宿主在浅↔深之间切换时，整块键盘要跟着翻。**
    ///
    /// 🚨 为什么必须有这个：`Theme.kb*` 是在 `viewDidLoad` 建控件那一刻**读一次**的，
    ///    宿主 App 中途切外观（微信跟随系统、或者用户在设置里翻）时，
    ///    键盘视图并不会重建 —— 结果就是「下巴翻成深色了、我们还是浅面板」。
    ///    这正是今天那条被证伪的老结论的同族：**外观不是我们说了算的**。
    /// 🚨 只在 `userInterfaceStyle` **真的变了**时才重建，否则 iOS 会为
    ///    尺寸类、动态字体等一堆无关变化反复调这个方法。
    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        let now = traitCollection.userInterfaceStyle
        guard previous?.userInterfaceStyle != now else { return }
        let light = (now == .light)
        guard light != Theme.hostIsLight else { return }
        Theme.hostIsLight = light
        overrideUserInterfaceStyle = light ? .light : .dark
        KbBridge.note("外观变了：宿主改成" + (light ? "浅色" : "深色") + "，重刷配色")
        repaintForAppearance()
    }

    /// 按当前外观把已经建好的控件重新上色。
    /// 🚨 背景那层是 CALayer，**必须整个换掉**（浅色是纯色层、深色是渐变+柔光，
    ///    结构都不一样），只改 backgroundColor 换不过来。
    private func repaintForAppearance() {
        view.backgroundColor = Theme.chin
        bgLayer?.removeFromSuperlayer()
        bgLayer = Theme.keyboardBackground(view.bounds)
        view.layer.insertSublayer(bgLayer!, at: 0)
        hintLabel.textColor = Theme.kbHint
        heardLabel.textColor = Theme.kbKeyText
        for b in [typeButton, speakButton] {
            b.backgroundColor = Theme.kbBottomKey
            b.setTitleColor(Theme.kbBottomText, for: .normal)
            b.tintColor = Theme.kbBottomText
        }
        // 发送键是强调色，不跟外观走；麦克风圆钮同理。
        paintMode()          // 两行功能键的选中/未选中态在这里统一刷
    }

    override func viewDidLayoutSubviews() {
        logKbFrame("重排")
        super.viewDidLayoutSubviews()
        // 🚨🚨 **圆角取短边，不是取高度。**
        //    Kevin 2026-08-31：「第一次录音失败、提示让我再说一次的时候，
        //    那个小圆圈就会变成一个橄榄球形。这个已经说了很多次了。」
        //    上一版写的是 `bounds.height / 2` —— 按钮一旦不是正方形，
        //    高度的一半就正好画出**胶囊/橄榄球**。取短边则最差也只是圆角矩形，
        //    **结构上不可能出现橄榄球**。
        // 🚨 圆角已交给 `CircleButton.layoutSubviews` —— **这里不再设第二遍**
        //    （同一件事两处实现必漂，今天已经栽过四次）。这里只留量测。
        let w = micButton.bounds.width, h = micButton.bounds.height
        // 🚨 **它为什么会不是正方形，我不猜 —— 让它自己喊出来。**
        //    布局上宽高是硬约束（`heightAnchor == widthAnchor`）、上下也都钉在
        //    micWrap 上，按理永远是正方形。既然他反复看到橄榄球，
        //    说明**有约束在运行时被打断了**，而那件事只有现场才知道。
        //    差 1pt 以内算正常（浮点/缩放），超了就留痕。
        // 🚨 中-6：**只防"扁"不够，还要防"缩到看不见"。**
        //    宽高相等是硬约束、尺寸是 999 → 撑不下时先缩尺寸，
        //    可以一路缩到接近 0，而 `abs(w-h) > 1` 恒不成立、探针一声不吭。
        //    44pt 是苹果的最小可点尺寸。
        let bad = (abs(w - h) > 1 || w < 44) && w > 0 && h > 0
        // 🚨 中-5：**留痕要节流。** `viewDidLayoutSubviews` 在转屏、键盘高度变化、
        //    切档、插警告条时会连着触发，不节流就每帧写一条，把真正要看的行冲走
        //    ——而那正是它唯一有用的时候。同一个文件里波形留痕就是因为这个
        //    从 1 秒放宽到 6 秒（「观测窗口比事件短 = 等于没观测」）。
        if bad, Date().timeIntervalSince(lastShapeNote) > 6 {
            lastShapeNote = Date()
            KbBridge.note("🚨 麦克风键形状不对：宽 " + String(format: "%.1f", w)
                          + " 高 " + String(format: "%.1f", h)
                          + "｜相位=" + String(describing: phase)
                          + "｜提示=" + (hintLabel.text?.isEmpty == false ? "有" : "无")
                          + "｜警告条=" + (fullAccessWarning?.isHidden == false ? "有" : "无"))
        }
        bgLayer?.frame = view.bounds
        bgLayer?.sublayers?.forEach { $0.frame = view.bounds }
    }
}

/// **永远是圆的按钮** —— 圆角由它自己在 `layoutSubviews` 里算。
///
/// 🚨🚨 Kevin 2026-08-31 第 N 次报「录音符号是橄榄形」。
///    模拟器渲染 + 量化后的真相跟前几次猜的都不一样：
///    按钮**是正方形**（205×205，宽高比 1.000），但**圆角半径比边长的一半还大** ——
///    Core Animation 在 `cornerRadius > 边长/2` 时画出来正是那个带尖角的橄榄形。
///
///    为什么会大：圆角在 `viewDidLayoutSubviews` 里按**当时**的尺寸算（88 → 44），
///    而「没录上」提示一出现，竖排被压缩、按钮缩到 68pt —— **半径没跟着重算**。
///    我上一轮改的是「取短边」，没改「什么时候算」，所以照旧。
///
///    → 让按钮**自己**在 `layoutSubviews` 里算：它的 bounds 一变就重算，
///      不依赖外面谁记得调。**结构上不可能再错。**
final class CircleButton: UIButton {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2
        clipsToBounds = true
        // 🚨 图标按比例缩放，别被压扁（按钮变小时 88pt 的图会被拉变形）
        imageView?.contentMode = .scaleAspectFit
    }
}

/// 键盘上带内边距的 label（轻警告条用）。
private final class PaddedLabel: UILabel {
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: UIEdgeInsets(top: 0, left: 16,
                                                       bottom: 0, right: 16)))
    }
}
