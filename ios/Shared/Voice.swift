import Foundation
import AVFoundation

/// 录音 → WAV → 后端转写。**跟安卓同一条链**（Kevin 2026-08-21 规矩：两端一致）。
///
/// 🚨 原来这里用 `SFSpeechRecognizer` 做端上识别。2026-08-21 改成录音传后端
///    （火山 `/api/audio`，doubao ASR，订阅包免费）——安卓那版就是这么做的，
///    两端拉齐、行为一致，也不再依赖设备自带识别服务。
///
/// 交互：按一下开始录、再按一下停；停了自动转写→整理→翻译→上屏。
final class Voice: NSObject {

    /// 总时长上限（**没接分段时**）。
    ///
    /// 🚨 60 秒不是拍脑袋，是**后端实测的天花板**除以余量：
    ///    `/api/audio` 在 240s/7.3MB 上稳定 504（`probe_upload_ceiling.py`，
    ///    安卓那轮跑的），60 秒 ≈ 1.9MB，留 3 倍余量。
    ///    **整段传的前提下，这个数不许调大。**
    static let MAX_DURATION: TimeInterval = 60

    /// 🚨 **接了分段之后**的总时长上限（Kevin 2026-08-24 要 15 分钟，等了 7 天）。
    ///
    /// **先到 5 分钟，不是一步到 900** —— 分段收尾器是新代码，
    /// 先在这个量级上跑通，再谈 15 分钟；否则一次要同时验
    /// 「切得对不对」和「15 分钟会不会爆内存」。
    /// 安卓那边是 `MAX_SECONDS = 900`，**这是两端目前最大的一处不对齐**。
    /// 🚨🚨 **抬到 900，对齐安卓（2026-08-31）。**
    ///    Kevin 2026-08-24 就要求「语音输入支持录 15 分钟」，安卓 `MAX_SECONDS = 900`
    ///    早就做了，iOS 一直卡在 60；他 08-31 撞到：「怎么才一分钟不到就停了」，
    ///    并且点名「**我都说了要对齐安卓**」。
    ///
    ///    上一版写 300 的理由是「分段收尾器是新代码，先到 5 分钟」——
    ///    那是**我给自己留的余量，不是他要的口径**，而两端不一致他会当成
    ///    「iOS 版不好用」。安卓拿同一个后端跑 900 秒已经在用，
    ///    分段是 60 秒一段（离网关天花板 3 倍余量），长度本身不增加单次风险。
    static let MAX_DURATION_SEGMENTED: TimeInterval = 900

    /// 每段多少秒。**跟安卓 `Segments.SEG_SECONDS` 同一个数、同一张实测表。**
    static let SEG_SECONDS = 60

    /// 段与段之间重叠多少毫秒。跟安卓 `Segments.OVERLAP_MS` 一致。
    /// 🚨 不重叠的话，正好被切在中间那个字**两边都丢**。
    static let SEG_OVERLAP_MS = 500
    /// 连续模式下**单句**的封顶秒数。跟安卓 `MAX_UTTERANCE_SECONDS` 一致。
    /// 有人一口气说 30 秒不带停的，到点强制切一句。
    static let MAX_UTTERANCE: TimeInterval = 30
    /// 连续模式**整场**封顶。跟安卓 `MAX_CONTINUOUS_SECONDS` 一致。
    /// 🚨 必须有：连续模式没有"松手"这个动作，
    ///    用户放着不管就会一直占着麦克风、一直耗电。
    static let MAX_CONTINUOUS: TimeInterval = 600

    /// 🚨 由 `private` 放开到模块内可见：热麦那条路要用它把 PCM 重新封成 WAV。
    ///    **不是加了个新常量** —— 采样率只能有一份，两份早晚会漂。
    static let SAMPLE_RATE: Double = 16000

    enum Stage: String {
        // 🚨 拆两档：**下一步完全不同**（一个点一下就能允许，一个必须去设置）。
        //    合成一档必然指错一半人的路。
        case permissionAsk = "麦克风权限·还没问过"
        case permissionDenied = "麦克风权限·已拒绝"
        case audioSession = "音频会话"
        case engine = "录音引擎"
        case none = ""
    }

    struct Failure: Error, CustomStringConvertible {
        let stage: Stage
        let detail: String
        var description: String { stage == .none ? detail : "\(stage.rawValue)：\(detail)" }

        /// 给用户看的那一句。🚨 **`description` 是给我们看的，不许直接上屏。**
        ///
        /// 🚨🚨 **这里的措辞是【欠着的】，不是我定的。**
        ///    `stage` 已经把"坏在哪一步"分得很清（权限/会话/引擎），
        ///    正好是录音屏判据 V5 要的粒度 ——
        ///    **但每一步该对用户说什么话，是产品措辞，我不自己编。**
        ///    已把这四档列给 2.1，拿到文案就替换。
        ///    在那之前用**已批准的通用句**兜底：**宁可笼统，也不贴异常原文、
        ///    更不编一句听起来很专业但没人审过的话。**
        var userText: String {
            // 🚨 四档都**不提阶段名**：`Stage` 的原始值是给我们看的，
            //    出现在界面上只会让他觉得这软件在讲黑话。
            //    **但原始 stage + detail 必须进诊断**（判据 ERR1，
            //    见 `_文案_随手翻译屏的提示与错误.md`）。
            if detail.contains("没听清") { return L.err_empty }
            switch stage {
            case .permissionAsk:    return L.err_mic_ask
            case .permissionDenied: return L.err_mic_denied
            case .audioSession:     return L.err_audio_session
            case .engine:           return L.err_engine
            case .none:             return L.err_other
            }
        }
    }

    /// 🚨🚨 **必须在音频会话激活之后再建**，不能在对象初始化时就建。
    ///    `AVAudioEngine` 一建出来就会去拿当前的输入路由；会话还没配的时候
    ///    拿到的是个无效路由，之后 `start()` 抛
    ///    `AVAudioSessionErrorCodeUnspecified`（'what' / 2003329396）。
    ///    容器 App 里不容易碰到 —— App 活得久、路由早就稳了；
    ///    **键盘扩展是随起随停的**，每次都撞在这上面。
    ///    （Kevin 2026-08-28 真机 build 554 的报错就是这个码。）
    private var engine = AVAudioEngine()
    private var pcm = Data()                    // 累积的 16bit 单声道 PCM
    private var startedAt = Date()
    private var capTimer: Timer?

    private var onPartial: ((String) -> Void)?
    /// 停止后回调：把录好的 WAV 交出去（由上层去调 Backend.transcribe）。
    private var onWav: ((Result<Data, Failure>) -> Void)?
    private var finished = false

    // 🚨 M1（交叉审查）：转换失败/空帧的计数。**必须能被读到** ——
    //    不然「转换全失败」和「系统给了哑麦克风」在报告里长得一模一样，
    //    而这个实验的判据恰好就是"有没有声音"。
    /// 转换器报错的帧数。
    private(set) var convErrCount = 0
    /// 最后一次转换错误的 code。
    private(set) var convErrCode = 0
    /// 转换后长度为 0、被丢掉的帧数。
    private(set) var emptyFrames = 0

    /// 这一轮的取数健康度，拼进诊断。
    /// 梯子最后落在第几档（-1 = 还没起过，99 = 复用了现成会话）。
    /// 🚨 成功时也要能读到 —— 原来只在**失败**时才报，
    ///    而「录得起来但采不到声」走的是**成功**分支。
    private(set) var lastRung = -1

    /// 主 App 注入「此刻在前台还是后台」。扩展里拿不到 `UIApplication`，
    /// 没注入就是 nil，心跳打「?」—— **不猜**。
    static var appStateProbe: (() -> String)?

    /// 心跳用的累计帧与下一个打点阈值。**只在 tap 里改**（同一线程）。
    fileprivate var hbFrames = 0
    fileprivate var hbNext = 0

    /// 🚨🚨 **全局：此刻有几个 `Voice` 实例真的在收音。**
    ///
    ///    立它的原因（2026-09-04 实测抓到）：`KbVoiceHost` 那个
    ///    「进后台就把麦克风还回去」的观察者，用 `busySeq == -1` 判
    ///    「有没有在录音」——而 **`busySeq` 的每一处赋值都在 `KbVoiceHost` 里**，
    ///    它只知道键盘那条路，**完全不知道主 App 自己那一屏在录**。
    ///    注释写着「② 正在录音 —— 他可能正说着话切出去看别的东西」，
    ///    **而这个检查恰恰覆盖不到那个场景**。
    ///
    ///    实测日志里两条心跳交错出现 = **两个 `Voice` 实例同时在录**，
    ///    共用同一个 `AVAudioSession`。`arming` 一旦为 false，
    ///    那个观察者就会 `disarm()` 把会话关掉，**连带掐掉主 App 那份**。
    ///    这就是 Kevin「切走录音就停了」最可能的机制。
    ///
    /// 🚨 计数挂在**装/拆 tap** 上，不是挂在某个业务状态标志上：
    ///    tap 在 = 真的在收音（肯定判据）；标志会漏设、会漂。
    private static let recLock = NSLock()
    private static var recCount = 0
    /// 此刻有没有**任何**录音在进行。给别处判「能不能动麦克风」用。
    static var anyRecording: Bool {
        recLock.lock(); defer { recLock.unlock() }
        return recCount > 0
    }
    private static func recEnter() {
        recLock.lock(); recCount += 1; recLock.unlock()
    }
    private static func recLeave() {
        recLock.lock(); recCount = max(0, recCount - 1); recLock.unlock()
    }

    var frameHealth: String {
        "转换失败 \(convErrCount) 帧（code \(convErrCode)）· 空帧 \(emptyFrames) 帧"
    }

    // MARK: - 连续模式（Kevin 2026-08-26 要的"随手翻译"同传场景）

    /// 非 nil = 连续模式。每断出一句回调一次，**在主线程**。
    private var onUtterance: ((Data) -> Void)?

    /// **长录音分段**：每满 `SEG_SECONDS` 交出一段 WAV，边录边传。
    ///
    /// 🚨 **接了它，上限才会从 60 抬到 `MAX_DURATION_SEGMENTED`** ——
    ///    没人收段就抬上限 ＝ 攒一个必然 504 的大包。
    /// 🚨 它跟 `onUtterance`（连续模式按静音切句）**不是一回事**：
    ///    这个按**字节数**切，跟他说没说完全无关，纯粹为了绕开体积和内存。
    var onSegment: ((Data) -> Void)?

    /// 这一轮切过段没有 —— `stop()` 靠它决定尾巴走哪条路。
    private var didSegment = false
    /// 断句器。逻辑在 `SilenceSplitter`（纯逻辑、6 组自测、两端同一份口径）。
    private var splitter: SilenceSplitter?
    var isContinuous: Bool { running && onUtterance != nil }

    private(set) var running = false
    var elapsed: TimeInterval { running ? Date().timeIntervalSince(startedAt) : 0 }

    /// 音频会话配置的**退让阶梯**。从独占到最朴素，逐档试。
    ///
    /// 🚨 顺序有讲究：第一档跟容器 App 里一直在用的那套一模一样
    ///    （改动不许影响本来就好用的那一端）；后面几档才是给扩展退让用的。
    /// 🚨🚨🚨 **可混音的排在最前 —— 2026-09-05 Kevin 报障后改。**
    ///
    /// 他的原话：「我手机打开 QQ 音乐放歌，提示播放有点问题…而且播放视频也是没有声音。
    /// 这个原因是不是因为我们的 Transless 在后台控制麦克风导致的？
    /// 但 QQ 音乐跟麦克风没关系，它只是播放声音，为什么会出现这种情况呢？」
    ///
    /// **他问到点子上了，而且这是我们的 bug。**
    /// iOS 的音频会话是**全机唯一的共享资源**：谁激活了一个不可混音的类别，
    /// 谁就接管整条路由。原来第一档是 `(.record, .measurement, .duckOthers)` ——
    /// `.record` **独占且不可混音**，一起录就把别人的播放掐掉。
    /// 而「键盘语音待机」会让主 App 在**后台**录音 →
    /// 他放歌/看视频时只要待机起了录，**声音就没了**。
    ///
    /// 🚨 `.duckOthers` 配 `.record` 本来就没有意义（没有"压低"可言，是直接掐断）。
    ///
    /// 🚨 **为什么敢换顺序**：`.playAndRecord + .mixWithOthers` 这一档
    ///    扩展里和画中画那条路**一直在用、录得好好的**，不是没验证过的新配置。
    ///    代价是理论上录音增益可能不如 `.measurement` 独占档 ——
    ///    **但"把用户手机的声音弄没了"比这个严重得多**，这个取舍我明说。
    ///    `.record` 留在最后当兜底：前面全被拒时才用，那时本来也放不了音。
    static let audioLadder: [(cat: AVAudioSession.Category,
                              mode: AVAudioSession.Mode,
                              opts: AVAudioSession.CategoryOptions)] = [
        // 🚨🚨 **`.default` 模式必须排在 `.measurement` 前面**（2026-09-05 第二次报障）。
        //    Kevin：「用 QQ 音乐播歌，它只是从**打电话的那个听筒**里出声，
        //    没有从喇叭里播出来」。
        //
        //    根因：`.measurement` 模式关掉信号处理，**会忽略 `.defaultToSpeaker`** ——
        //    我上一版把 `.defaultToSpeaker` 写在 `.measurement` 那档里，
        //    **选项写了但不生效**，于是 `.playAndRecord` 按它的默认走听筒，
        //    整机输出被带过去。
        //
        // 🚨 这是我上一个修复的**二阶效应**：
        //      改之前 `.record` 没有输出路由 → 别人直接没声音
        //      改之后 `.playAndRecord` 有路由了 → 但默认是听筒
        //    **两个都不对。** 修一个问题时要问一句"我把它换成了什么"。
        (.playAndRecord, .default, [.mixWithOthers, .allowBluetooth,
                                    .defaultToSpeaker]),
        (.playAndRecord, .measurement, [.mixWithOthers, .defaultToSpeaker]),
        // 🚨 下面两档**都不可混音**，只在上面全被系统拒了才会走到 ——
        //    走到这里说明会话本来就配不起来，那时别人也放不了音。
        (.record, .measurement, []),
        (.record, .default, []),
    ]

    /// **只在输出真的落到听筒时才把它推回扬声器。**
    ///
    /// 🚨 Kevin 2026-09-05 第二次报障：「用 QQ 音乐播歌，它只是从**打电话的那个听筒**
    ///    里出声，没有从喇叭里播出来」。
    ///
    /// 🚨 **为什么不是无条件 `overrideOutputAudioPort(.speaker)`**：
    ///    那样**戴着耳机也会被强推到外放** —— 在别人旁边放出声音，比现在这个还糟。
    ///    所以判据挂在**当前路由**上：只有当输出确实是内置听筒时才纠正。
    ///    耳机/蓝牙/外放这三种情况下这个函数什么都不做。
    ///
    /// 🚨 `.defaultToSpeaker` 是正道（它自己就认耳机），这里只是兜底 ——
    ///    因为 `.measurement` 模式会忽略它，而我们的阶梯里还留着那一档。
    static func fixReceiverRoute(_ session: AVAudioSession) {
        let outs = session.currentRoute.outputs
        guard outs.contains(where: { $0.portType == .builtInReceiver }) else { return }
        do {
            try session.overrideOutputAudioPort(.speaker)
            KbBridge.note("路由落到听筒了，已推回扬声器")
        } catch {
            KbBridge.note("推回扬声器失败：" + String((error as NSError).code))
        }
    }

    /// 跑在扩展里还是容器 App 里。
    /// 🚨 判据是 bundle 路径以 `.appex` 结尾 —— 这是系统给的事实，
    ///    不是我们自己设的标志位（标志位会忘了设）。
    static var inExtension: Bool {
        Bundle.main.bundleURL.pathExtension == "appex"
    }

    /// 失败时附的现场。**故意写得啰嗦** —— 用户截一张图就该够我定性，
    /// 不该再花一轮来回问「你当时是在键盘里还是在 App 里」。
    static func context(rung: Int = -1) -> String {
        let perm: String
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: perm = "已授权"
        case .denied: perm = "被拒绝"
        default: perm = "还没问"
        }
        // 🚨 换行排版：真机上这段被截断过，横着排一行读不完。
        var out = (inExtension ? "键盘扩展" : "主App") + " · 权限\(perm)"
        if rung >= 0 { out += " · 配置档\(rung + 1)" }
        let r = AVAudioSession.sharedInstance().currentRoute
        out += "\n输入源 \(r.inputs.count) 个"
        if let first = r.inputs.first { out += "（\(first.portType.rawValue)）" }
        return out
    }

    /// 录音失败时的**完整现场**。全部读**当前实际值**，不是我们想设的值。
    ///
    /// 🚨 为什么要有这个：`AVAudioSessionErrorCodeUnspecified` 本来就是
    ///    "未指定错误" —— **苹果自己都不说是什么**。
    ///    520 → 555 → 557 三轮都是「猜根因 → 改 → 出包 → 他试 → 还是不行」，
    ///    每一轮消耗他一次真机测试，而我们的信息只增加了一行报错。
    ///    **不能再盲改了，先让它自己说清楚。**
    ///
    /// 🚨 读的是 `session.category` 这些**实际生效的属性**，
    ///    不是我们传给 `setCategory` 的那些参数 —— 那两者可能不一样，
    ///    而"我们想设什么"这个信息对定位毫无用处。
    static func diagnostics() -> String {
        let s = AVAudioSession.sharedInstance()
        var out: [String] = []
        out.append("=== 录音现场 ===")
        out.append("跑在      \(inExtension ? "键盘扩展" : "主App")")
        out.append("类别      \(s.category.rawValue)")
        out.append("模式      \(s.mode.rawValue)")
        out.append("选项      \(s.categoryOptions.rawValue)")
        out.append("采样率    \(Int(s.sampleRate))Hz")
        out.append("输入声道  \(s.inputNumberOfChannels)")
        out.append("有输入吗  \(s.isInputAvailable)")
        // 可用输入设备：个数 + 名字。0 个 = 系统层面就没给我们麦克风。
        let avail = s.availableInputs ?? []
        out.append("可用输入  \(avail.count) 个\(avail.map { $0.portName }.joined(separator: ","))")
        let r = s.currentRoute
        out.append("当前路由  入\(r.inputs.count) 出\(r.outputs.count)")
        if let i = r.inputs.first {
            out.append("  输入口  \(i.portType.rawValue) \(i.portName)")
        }
        let perm: String
        switch s.recordPermission {
        case .granted: perm = "已授权"
        case .denied: perm = "被拒绝"
        default: perm = "还没问"
        }
        out.append("麦克风权限 \(perm)")
        out.append("其它App在放音 \(s.isOtherAudioPlaying)")
        return out.joined(separator: "\n")
    }

    /// 录音权限的**三态** —— 全工程只从这里取。
    ///
    /// 🚨🚨 2026-09-04 实撞：Kevin 报「面对面那个录音按钮点了根本没反应」。
    ///    诊断日志里 `权限=1735552628` —— 而这个枚举只有
    ///    `undetermined(1970168948) / denied(1684369017) / granted(1735552628)`
    ///    这三个 FourCC 值。**读到的其实是 granted**，但代码里拿它去跟
    ///    `.undetermined` / `.denied` 比，两个都不成立、直接往下走，
    ///    结果卡在更里面一层，而外面**一句反馈都没有** → 表现成"点了没反应"。
    ///
    /// 🚨 `AVAudioSession.recordPermission` 在 **iOS 17 起已废弃**，
    ///    新系统上要用 `AVAudioApplication.shared.recordPermission`。
    ///    两个枚举**不是同一个类型**，散在 5 处各写各的必然走散 ——
    ///    所以收成这一个咽喉，调用方只认这三种情况。
    enum MicPerm { case undetermined, denied, granted }

    static func micPermission() -> MicPerm {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .undetermined: return .undetermined
            case .denied: return .denied
            case .granted: return .granted
            // 🚨 未来新增的枚举值**当成"没决定"**，不当成"拒绝" ——
            //    判错成拒绝会把人推去设置页，而他其实什么都没做错。
            @unknown default: return .undetermined
            }
        }
        switch AVAudioSession.sharedInstance().recordPermission {
        case .undetermined: return .undetermined
        case .denied: return .denied
        case .granted: return .granted
        @unknown default: return .undetermined
        }
    }

    /// 请求录音权限 —— 同样收成一处（新旧 API 的回调签名不一样）。
    static func requestMic(_ done: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission(completionHandler: done)
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission(done)
        }
    }

    static func permissionState() -> Failure? {
        // 🚨🚨 **扩展里跳过这条预检**（2026-08-28）。
        //
        //    `Voice.start()` 第一句就用它同步返回失败，而 665 真机实测
        //    的现象正是「扩展里同步失败、回退到宿主」——
        //    **同步失败的出口只有两个：这条预检，和音频会话四档全拒。**
        //
        //    `recordPermission` 查的是**调用方 bundle** 的 TCC 状态。
        //    容器 App 授权过，不代表扩展这边这个 API 一定回 `.granted`；
        //    而**扩展根本没办法自己去请求权限** ——
        //    于是它在扩展里可能是一道**永远打不开、也没人打得开的门**。
        //
        //    跳过之后：真有权限就录起来（预检本来多余）；真没有的话，
        //    系统会在 `setActive` / `engine.start()` 拒掉，
        //    **报出来的是系统的真实原因**，比我们编的这句准。
        //
        //    🚨 这不是"绕过权限"——TCC 该拒照样拒，我们只是不再拿一个
        //       可能失准的预判去代替系统的判断。
        //    🚨 容器 App 里**保留**：那里它准确，而且用户点得动授权框。
        if inExtension { return nil }
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            break
        case .undetermined:
            // 还没问过 —— 系统还会弹框，点一下就能允许
            return Failure(stage: .permissionAsk, detail: "还没问过")
        default:
            // 🚨 已拒绝 —— **系统不会再弹**，只能去设置里开。
            //    兜底也归到这一档：指错路的代价不对称（见文件头）。
            return Failure(stage: .permissionDenied, detail: "已拒绝")
        }
        return nil
    }

    // MARK: - 开始

    /// - onPartial: 目前录音阶段没有实时文字（转写在停止后做），保留签名给上层显示计时。
    /// - onWav: 停止后把 WAV 交出来；失败则给出卡在哪一步。
    /// 开录。`onUtterance` 非 nil 就是**连续模式**：说一句出一句。
    ///
    /// 🚨 两种模式共用同一段 tap，差别只在"切不切" ——
    ///    复制一份出来做连续模式的话，以后改采样率/WAV 头就有两处要改。
    /// 每帧音量（0…1）。键盘那条波形靠它。**单句模式也会给**。
    var onLevel: ((Float) -> Void)?

    /// `reuseSession` = **直接用当前这个音频会话，不碰类别、不重新激活**。
    ///
    /// 🚨 给方案 B 用：待机保活已经持着 `.playAndRecord`，
    ///    实测那时后台的路由是 `入1 出1`（有输入口）。
    ///    而会话阶梯第一档是 `.record + .measurement + .duckOthers`，
    ///    **会把类别换掉、并在后台重新 `setActive`** ——
    ///    那恰恰是实测失败的那一步（`2003329396`）。
    ///    **复用就是绕开它。**
    func start(onPartial: @escaping (String) -> Void,
               onUtterance: ((Data) -> Void)? = nil,
               reuseSession: Bool = false,
               onWav: @escaping (Result<Data, Failure>) -> Void) {
        // 🚨🚨 **`TRANSLESS_NO_ARM=1` 的唯一闸口。**
        //    挡的位置我挪了两次，记下来免得下次又挑错层：
        //      第一版挂在 `KbVoiceHost.tryArmOnColdLaunch()` —— 那只是
        //        **八个架引擎调用点之一**，`didBecomeActive` 那条照样架，
        //        测试还是被带崩，而我以为已经挡住了；
        //      第二版挂在 `armIdle()` —— 但 `armIdleNow()` 也直接调 `start`，
        //        照样漏。
        //    真正的咽喉是**崩溃栈里的那一层**：`Voice.start` →
        //    `AVAudioEngine.inputNode` → AudioToolbox RPC 超时 → abort。
        //    挡在这里，八个调用点全都覆盖到。
        //
        //    只给跟麦克风无关的 UI／纯逻辑测试用；真正测录音的用例不带这个开关。
        if AudioGate.off { return }
        if let p = Voice.permissionState() { return onWav(.failure(p)) }
        self.onPartial = onPartial
        self.onWav = onWav
        pcm = Data()
        finished = false
        // 🚨 跨轮必须清零，否则第二轮读到的是两轮之和 —— 旧数据冒充新数据。
        convErrCount = 0
        convErrCode = 0
        emptyFrames = 0
        startedAt = Date()

        // 🚨🚨 **按阶梯试配置**，不是只试一档（2026-08-26 加）。
        //    `.record + .measurement + .duckOthers` 在**容器 App** 里一直没问题，
        //    但 Kevin 在**键盘扩展**里录不了音 ——
        //    「录音引擎未能完成操作，com.apple.coreaudio.avfaudio 错误 200」。
        //    扩展的音频会话限制比 App 严，独占型的类别/选项常被拒。
        //    所以退让着试：独占 → 混音共存 → 最朴素。
        //    哪一档成了就记下来（`usedRung`），失败时一起报出去。
        let session = AVAudioSession.sharedInstance()
        var sessionErr: NSError?
        // 🚨 M9：**四档各自失败于什么原因，是这个实验最有价值的信息之一** ——
        //    被别人占着（`!int`）和被权限拒，code 完全不同。原来只报最后一档。
        var rungErrs: [String] = []
        var usedRung = -1
        // 🚨🚨🚨 **复用会话也必须确保它是激活的（2026-08-30 22:5x）。**
        //    症状：前台、不静音、引擎报"起来了"，**基线采样却是 0 字节**。
        //    根因：我今晚为了保住会话，把「保活重设会话」那条也关了，
        //    于是 `reuseSession` 这条路**从头到尾没有任何人调用 `setActive`** ——
        //    会话没激活，引擎起得来也没有数据流。
        //    🚨 只 `setActive`、**不碰类别** —— 改类别在后台会被拒（`560557684`），
        //    而只激活是安全的。
        if reuseSession {
            do {
                try session.setActive(true, options: [])
                // 复用会话也要查一次：上一轮可能就是落在听筒上的
                Voice.fixReceiverRoute(session)
            } catch {
                KbBridge.note("复用会话时激活失败："
                              + String((error as NSError).code))
            }
        }
        if reuseSession {
            // 🚨 只记录、不改动。判据仍然是后面能不能拿到帧。
            usedRung = 99
        }
        // 🚨🚨 **小窗活着时，第一档必须是「可录也可播」。**
        //    梯子默认第一档是 `.record`（只录）——**它会把画中画那路播放掐掉**，
        //    Kevin 2026-08-29 亲眼看到：「那个画中画好像就消失了」。
        //    小窗一消失，主 App 下次就又被挂起 → 又要跳转 → 又回不来。
        //    `.playAndRecord + .mixWithOthers` 两件事同时成立，且不打断他在听的东西。
        // 🚨🚨 **在键盘扩展里，第一档必须是「共存」的。**
        //    默认第一档是 `.record + .duckOthers`（只录 + 压低别人）——
        //    而此刻主 App 正持有一个 `.playAndRecord` 的保活会话，
        //    两个会话互相抢，扩展这边就拿不到输入路由（`输入源 0 个`）。
        //    2026-08-29：**「键盘能不能录」和「宿主持有可录会话」这个组合从没一起试过**，
        //    而之前每次失败时宿主都是「只播」模式 —— 范围没覆盖到。
        //    → 扩展里改用 `.playAndRecord + .mixWithOthers`（不抢、不打断）。
        let ladder: [(cat: AVAudioSession.Category, mode: AVAudioSession.Mode,
                      opts: AVAudioSession.CategoryOptions)] =
            Voice.inExtension
            // 🚨 这两个阶梯**原来也是 `.measurement` 打头**，
            //    而 `pipReady()` 那条正是「待机」场景 —— 他撞上的就是它。
            //    `.measurement` 忽略 `.defaultToSpeaker` → 整机输出走听筒。
            //    三个阶梯一起改，别只改默认那个（同一条规矩三处实现，改一处等于没改）。
            ? [(.playAndRecord, .default, [.mixWithOthers, .allowBluetooth,
                                           .defaultToSpeaker]),
               (.playAndRecord, .measurement, [.mixWithOthers, .defaultToSpeaker]),
               (.record, .measurement, [])]
            : KbBridge.pipReady()
            ? [(.playAndRecord, .default, [.mixWithOthers, .allowBluetooth,
                                           .defaultToSpeaker]),
               (.playAndRecord, .measurement, [.mixWithOthers, .defaultToSpeaker])]
            : Voice.audioLadder
        for (i, rung) in ladder.enumerated() where !reuseSession {
            do {
                try session.setCategory(rung.cat, mode: rung.mode, options: rung.opts)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                Voice.fixReceiverRoute(session)
                usedRung = i
                break
            } catch {
                let e = error as NSError
                sessionErr = e
                rungErrs.append("档\(i)=\(e.code)")
                continue
            }
        }
        lastRung = usedRung
        if usedRung < 0 {
            let ns = sessionErr
            return onWav(.failure(Failure(
                stage: .audioSession,
                detail: "四档配置全被拒（各档 code：\(rungErrs.joined(separator: " "))"
                    + "，最后一次 \(ns?.code ?? -1)）" + Voice.context())))
        }

        // 🚨 会话配好之后**重建引擎** —— 见 `engine` 那段注释。
        //    旧引擎可能缓存着会话激活前的无效路由。
        engine.stop()
        engine = AVAudioEngine()

        let node = engine.inputNode
        let inFormat = node.outputFormat(forBus: 0)
        // 🚨 会话激活成功 ≠ 麦克风路由可用。扩展里常见的形态是
        //    `setActive` 过了、但输入节点是 0 Hz / 0 声道 ——
        //    再往下走只会在 `engine.start()` 抛一个看不懂的错误码。
        //    在这里就拦住，并说清是"拿不到麦克风"而不是"引擎坏了"。
        // 🚨🚨 **这里原来直接 return failure，已改成只记录不拦**（交叉审查 H5）。
        //    它跟 `permissionState()` 是同一族：**在 `engine.start()` 让系统
        //    给出裁决之前，我们自己先判了失败。**
        //    而 `inputNode.outputFormat` 在 `setActive` 之后、路由还没落定时
        //    返回 0Hz/0ch 是**已知瞬态**，扩展这种随起随停的进程尤其容易撞上。
        //    后果：引擎一次都没被 start 过，我们却据此得出"扩展不能录音"。
        //    → 记下观测值，照常往下走；真起不来时系统会拒，
        //      **报出来的是系统的原因**，而且诊断里分得清是谁拦的。
        let badFormat = inFormat.sampleRate <= 0 || inFormat.channelCount == 0
        // 目标格式：16k 单声道 Int16。用转换器把麦克风原始格式转过来。
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                            sampleRate: Voice.SAMPLE_RATE,
                                            channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            // 🚨🚨 H-4（第 2 轮审查）：**H5 想保住的观测值，在最可能走到的那条路上照样丢了。**
            //    0Hz 的 `inFormat` 根本走不到 `engine.start()` —— `AVAudioConverter`
            //    对无效源格式返回 nil，**这条 guard 先命中**，而它原来只有一句
            //    光秃秃的中文：没有 `badFormat`、没有档位、没有现场。
            //    比改之前还彻底：改之前那条 return 至少带了"拿不到麦克风"的定性。
            cleanup()
            return onWav(.failure(Failure(
                stage: .engine,
                detail: "建不了音频转换器\n"
                    + (badFormat ? "起 engine 前格式已是 0（路由未落定？）\n" : "")
                    + Voice.context(rung: usedRung))))
        }

        // 🚨🚨 H-4 的第二条现实路径：**非法格式喂给 `installTap` 会让扩展直接崩。**
        //    若 converter 侥幸非 nil（比如 `sampleRate>0` 但 `channelCount==0`
        //    这种半残格式），下一句 `installTap` 抛 ObjC 异常
        //    `required condition is false: IsFormatSampleRateAndChannelCountValid`，
        //    **Swift 接不住 → 扩展崩 → 表现是「键盘弹回上一个」，零诊断。**
        //    这不是回到 H5 之前的"自己判决"：那时是**不让系统裁决**，
        //    现在是**不把非法格式喂给一个会抛异常的 API**，
        //    而且诊断里写明**是我们拦的**。
        if badFormat {
            cleanup()
            return onWav(.failure(Failure(
                stage: .engine,
                detail: "格式非法，没敢喂给 installTap（会抛异常导致扩展崩）\n"
                    + "我们拦的，不是系统拒的\n"
                    + "输入 \(inFormat.sampleRate)Hz/\(inFormat.channelCount)ch\n"
                    + Voice.context(rung: usedRung))))
        }

        node.removeTap(onBus: 0)
        // 🚨 心跳计数每次装 tap 都归零 —— 不归零的话第二段录音会
        //    从上一段的秒数接着数，日志里那个「第 N 秒」就不是这一次的。
        hbFrames = 0
        hbNext = 0
        Voice.recEnter()
        node.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak self] buf, _ in
            guard let self = self else { return }
            let ratio = Voice.SAMPLE_RATE / inFormat.sampleRate
            let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio + 16)
            guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: cap) else { return }
            var err: NSError?
            var supplied = false
            converter.convert(to: out, error: &err) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true
                status.pointee = .haveData
                return buf
            }
            // 🚨🚨 M1（交叉审查）：**转换失败原来被整个丢掉。**
            //    `err` 声明了却从不检查，失败时 `out.frameLength == 0`
            //    被下面这道 guard 静默吞掉 → `frames=0, peak=0` →
            //    报告打出 **`SILENT 全程静音`**。
            //    **而这个错误结论跟「系统给了哑麦克风」长得一模一样** ——
            //    这个实验的判据就是"有没有声音"，让它被转换失败伪装成静音，
            //    整轮结论就是错的。
            //    → 计数 + 记最后一次 code，进诊断；判据看得见它才不会误判。
            if let e = err {
                self.convErrCount += 1
                self.convErrCode = e.code
            }
            guard let ch = out.int16ChannelData, out.frameLength > 0 else {
                self.emptyFrames += 1
                return
            }
            let n = Int(out.frameLength)
            self.lastTapAt = Date()
            // 🚨🚨 **录音心跳：由音频 tap 自己驱动，绝不用定时器。**
            //
            //    要回答的问题是 Kevin 2026-09-04 提的：
            //    「开始录音后切到别的窗口查资料再回来，录音要能继续」。
            //    没有心跳的话，「切走后断了」和「一直在录但结果没上传」
            //    **在日志里长得一模一样**，而这两种坏法的修法完全不同。
            //
            // 🚨 为什么不能用 `Timer` 每 5 秒打一条：**tap 已经死掉之后，
            //    定时器照样会准时打印「还在录」** —— 那是永远不会失败的检查，
            //    比没有检查更糟。帧数只有 tap 真收到数据才会涨，
            //    **它涨 = 真的还在收音**，这是肯定判据。
            //
            // 🚨 `appState` 由主 App 注入（扩展里拿不到 `UIApplication`）。
            //    没注入就打「?」，不猜。
            self.hbFrames += n
            if self.hbFrames >= self.hbNext {
                self.hbNext = self.hbFrames + Int(Voice.SAMPLE_RATE * 5)
                let secs = Double(self.hbFrames) / Voice.SAMPLE_RATE
                KbBridge.note("录音心跳：第 " + String(Int(secs)) + " 秒｜累计帧="
                              + String(self.hbFrames) + "｜"
                              + (Voice.appStateProbe?() ?? "?"))
            }
            // 🚨🚨 **待命档：转完就扔，不进缓冲。**
            //    这是整套「不跳转」的地基：iOS **不许后台从零开始录音**
            //    （2026-08-30 用引擎/录音机/采集栈三条 API 分别验过，
            //      灵动岛亮着也不行；Apple 论坛的结论也是同一句：
            //      「录音会话必须最初在前台建立，之后才能从后台暂停/恢复」）。
            //    → 引擎在**前台**就起好，之后一直活着；键盘按下时
            //      我们只是**开始把采样留下来**，而不是新建一个录音。
            //    🚨 音量照常往外抛 —— 待命时也要能看出麦克风是活的，
            //      否则"引擎其实早死了"这件事会一直藏着。
            if self.arming {
                // 待命档：追加和取走都要过锁（见 `pcmLock` 那段）
                self.pcmLock.lock()
                if self.keeping {
                    self.pcm.append(UnsafeBufferPointer(start: ch[0], count: n)
                        .withMemoryRebound(to: UInt8.self) { Data($0) })
                }
                self.pcmLock.unlock()
            } else {
                self.pcm.append(UnsafeBufferPointer(start: ch[0], count: n)
                    .withMemoryRebound(to: UInt8.self) { Data($0) })
            }

            // 🚨 音量**要在这道 guard 之前**算完抛出去。
            //    原来 level 是在下面算的，而单句模式在这一行就 return 了
            //    —— 键盘走的正是单句模式，等于**一个音量值都拿不到**。
            //    「代码里有这个变量」和「这条路上会算它」是两回事。
            var s0: Double = 0
            for i in 0..<n { let v = Double(ch[0][i]); s0 += v * v }
            let lv = Float(min(1.0,
                ((s0 / Double(n)).squareRoot() / 32768.0).squareRoot() * 1.9))
            self.onLevel?(lv)

            // 🚨 **长录音分段**（单句模式也要走）：满一段就交出去，
            //    `pcm` 只留最后 `SEG_OVERLAP_MS` 那点尾巴当重叠。
            //    放在这道 guard **之前** —— 单句模式在下一行就 return 了，
            //    写在后面等于这段代码在键盘那条路上永远不执行。
            //    （这个坑上面那段注释刚记过一次：「代码里有」≠「这条路上会走到」。）
            if self.onSegment != nil, self.splitter == nil {
                let segBytes = Int(Voice.SAMPLE_RATE) * 2 * Voice.SEG_SECONDS
                if self.pcm.count >= segBytes {
                    self.emitSegment()
                }
            }

            guard let sp = self.splitter else { return }   // 单句模式，到此为止

            // 🚨 音量公式**逐字对着安卓 `ShortRecorder` 抄**：
            //    rms = sqrt(Σv²/采样数)/32768，再 min(1, sqrt(rms)*1.9)。
            //    （开方再放大是因为人耳对响度非线性，直接用 rms
            //      正常说话只能推到 5% 高度。）
            //    公式不一样的话，同样的说话音量两端算出不同的 level，
            //    而 SILENCE_LEVEL 是同一个 0.08 —— 等于阈值实际上不同。
            var sum: Double = 0
            for i in 0..<n {
                let v = Double(ch[0][i])
                sum += v * v
            }
            let rms = (sum / Double(n)).squareRoot() / 32768.0
            let level = Float(min(1.0, rms.squareRoot() * 1.9))
            let frameMs = n * 1000 / Int(Voice.SAMPLE_RATE)

            // 整场到顶：收工（`stop()` 会把最后这段交出去）。
            if self.pcm.count >= Int(Voice.SAMPLE_RATE) * 2
                * Int(Voice.MAX_CONTINUOUS) {
                DispatchQueue.main.async { [weak self] in self?.stop() }
                return
            }
            // 🚨 单句到顶也要切：有人一口气说 30 秒不带停，
            //    光等静音会攒成一坨发不出去。
            let tooLong = self.pcm.count >= Int(Voice.SAMPLE_RATE) * 2
                * Int(Voice.MAX_UTTERANCE)
            if sp.feed(level, frameMs) || tooLong {
                sp.reset()
                self.cut()
            }
        }
        engine.prepare()
        // 🚨 `badFormat` 只进诊断、不做判决 —— 见上面 H5 那段。
        //    诊断文本必须能分辨**「我们自己拦的」还是「系统拒的」**，
        //    今晚这两类长得一模一样，害我们把自己的门当成苹果的限制。
        // 🚨🚨 **被拒就重新激活会话再试一次**（2026-08-29 加）。
        //    扩展侧现在的形态是 `输入 48000Hz/1ch` + `输入源 1 个` +
        //    `engine.start` 报 `2003329396` —— **格式合法、麦克风也在路由里**，
        //    卡的是 `start()` 本身。（今天之前是 `输入源 0 个`，那是根本没给麦，两回事。）
        //    `2003329396`（CoreAudio 的 `'what'`）最常见的成因是
        //    **那一刻会话不是活跃的**，扩展这种随起随停的进程尤其容易撞。
        // 🚨 **只重试一次，不写循环** —— 循环会把「起不来」变成「卡住」，那更糟。
        var retried = false
        do { try engine.start() }
        catch {
            retried = true
            try? AVAudioSession.sharedInstance()
                .setActive(true, options: .notifyOthersOnDeactivation)
            Voice.fixReceiverRoute(AVAudioSession.sharedInstance())
            Thread.sleep(forTimeInterval: 0.12)
            engine.prepare()
            do { try engine.start() }
            catch {
            cleanup()
            // 🚨 **把现场带上**。原来只报 `localizedDescription`，
            //    到用户手里就是「com.apple.coreaudio.avfaudio 错误 200」——
            //    那句话对定位一点用都没有，害我们多花了一轮才找到方向。
            let ns = error as NSError
            return onWav(.failure(Failure(
                stage: .engine,
                // 🚨 **换行**：这段在真机上被截断过（Kevin 的截图只看得到
                //    「… 输入 4800…」，后面全没了）。一个看不完的诊断
                //    等于没有诊断 —— 最关键的那半永远读不到。
                detail: "\(ns.code)\n\(ns.domain)\n"
                    + (retried ? "（重试后仍被拒）\n" : "")
                    + "输入 \(Int(inFormat.sampleRate))Hz/"
                    + "\(inFormat.channelCount)ch\n"
                    // 🚨 H5：把「起 engine 之前格式就已经是 0」作为**观测**记下来，
                    //    但**判决交给系统**。有这一行我们才分得清是路由没落定
                    //    还是系统真的拒绝 —— 这两类今晚长得一模一样，
                    //    害我们把自己写的门当成了苹果的限制。
                    + (badFormat ? "起 engine 前格式已是 0（路由未落定？）\n" : "")
                    + "（已重新激活会话重试过一次）"
                    + Voice.context(rung: usedRung))))
            }
        }

        running = true
        self.onUtterance = onUtterance
        self.splitter = (onUtterance != nil) ? SilenceSplitter() : nil
        // 到总上限自动停。
        // 🚨 连续模式用整场上限，不是单句的 60 秒 ——
        //    照用 MAX_DURATION 的话，说到第 60 秒会被无声掐掉。
        // 🚨🚨🚨 **待命档不许挂这个定时器（2026-08-30 03:45 查到的真根因）。**
        //    待命档借用 `start()` 把引擎架起来，而这个「录满就自动停」的闹钟
        //    会在 `MAX_DURATION` 到点时调 `stop()` → **摘 tap、停引擎**。
        //    症状极具迷惑性：`arming`、`engine.isRunning`、共享区待命标记
        //    **全是绿的**，但 tap 一个采样都不再送 —— 他说了话却报"没听清"。
        //    时间线也对得上：架好之后大约一分钟开始坏，之后每次都坏。
        //    🚨 我为这个症状先后打了两个补丁（保活别碰会话），
        //       **都不是根因** —— 因为我没先量就先修。
        //    待命档的"录多久"由 `beginKeep/endKeep` 那一对管，不归它管。
        if !arming {
            capTimer = Timer.scheduledTimer(
                // 🚨 上限**跟着能力走**：接了分段才敢用长的那个。
                withTimeInterval: onUtterance != nil
                    ? Voice.MAX_CONTINUOUS
                    : (onSegment != nil ? Voice.MAX_DURATION_SEGMENTED
                                        : Voice.MAX_DURATION),
                repeats: false) { [weak self] _ in self?.stop() }
        }
        // 每秒推一次计时给界面
        DispatchQueue.main.async { [weak self] in self?.tick() }
    }

    private func tick() {
        guard running, !finished else { return }
        onPartial?("")   // 界面自己按 elapsed 显示计时
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.tick() }
    }

    /// 连续模式：把攒到现在的 PCM 切出去当一句，继续录下一句。
    ///
    /// 🚨 在**音频线程**（tap 回调）里调，跟往 `pcm` 追加是同一个线程，
    ///    所以取走再清空不会跟追加打架。回调 hop 回主线程给界面。
    /// 停止时**这条尾巴该怎么走** —— 抽成纯函数，**就是为了能被自测量到**。
    ///
    /// 🚨🚨 **这是花 Kevin 钱的那个判断。** 切过段之后，尾巴只许从
    ///    `onSegment` 出去一次；**要是同时又从 `onWav` 交一份**，
    ///    同一段音频会被转两次 —— 多一次 `/api/audio`、多一次模型、
    ///    拼接结果里还多一段重复的话。**不崩、不报错、日志里什么都没有。**
    ///
    /// 🚨 抽出来之前这个判断埋在 `stop()` 里，而 `stop()` 要 AVAudioEngine，
    ///    headless 测不了 —— **于是它就成了"注释写得很清楚、没有任何检查守着"**。
    ///    今天反复抓的就是这个形态。
    enum TailPlan: Equatable {
        /// 切过段：尾巴够长，从 `onSegment` 交一次；**不再走 `onWav` 交音频**
        case segment
        /// 切过段：尾巴太短（按停止那一下的静音），一段都不发；**同样不走 `onWav`**
        case segmentSkipTail
        /// 没切过段：老路，整段从 `onWav` 出去
        case wholeWav
        /// 没切过段且太短 = 没说话
        case tooShort
        /// 连续模式收尾，末尾只是静音
        case quietTail
    }

    static func tailPlan(didSegment: Bool, wasContinuous: Bool,
                         tailWorth: Bool, bytes: Int,
                         sampleRate: Int) -> TailPlan {
        if wasContinuous && !tailWorth { return .quietTail }
        if didSegment {
            return bytes >= sampleRate / 2 ? .segment : .segmentSkipTail
        }
        return bytes < sampleRate ? .tooShort : .wholeWav
    }

    /// 🚨 由 `gate_all_selftests.py` 自动发现并运行。
    ///    判据挂在**决策**上：切过段的任何一种情况都**不许**回到 `.wholeWav`。
    static func selfTest() -> String? {
        var bad: [String] = []
        let sr = Int(Voice.SAMPLE_RATE)
        func plan(_ seg: Bool, _ cont: Bool, _ worth: Bool, _ b: Int) -> TailPlan {
            return tailPlan(didSegment: seg, wasContinuous: cont,
                            tailWorth: worth, bytes: b, sampleRate: sr)
        }
        // ① 切过段 + 尾巴够长 -> 只走 onSegment
        if plan(true, false, true, sr) != .segment {
            bad.append("切过段+长尾巴：没走 segment")
        }
        // ② 🚨 切过段 + 尾巴太短 -> 也不许回到整段 wav（那就是转两次）
        if plan(true, false, true, sr / 4) != .segmentSkipTail {
            bad.append("切过段+短尾巴：应当 segmentSkipTail")
        }
        // ③ 🚨🚨 **核心**：切过段的任何一种，都不许是 wholeWav
        for b in [0, sr / 4, sr, sr * 10] {
            let p = plan(true, false, true, b)
            if p == .wholeWav {
                bad.append("切过段却判成 wholeWav（bytes=\(b)）—— **同一段会被转两次**")
            }
        }
        // ④ 阴性对照：没切过段时**必须**走 wholeWav，别把老路也堵了
        if plan(false, false, true, sr * 2) != .wholeWav {
            bad.append("没切过段：老路被堵了")
        }
        // ⑤ 没切过段且太短 = 没说话
        if plan(false, false, true, sr / 2) != .tooShort {
            bad.append("没切过段+太短：应当 tooShort")
        }
        // ⑥ 连续模式末尾只是静音 -> 正常收尾，不是错
        if plan(false, true, false, sr * 2) != .quietTail {
            bad.append("连续模式静音尾：应当 quietTail")
        }
        // ⑦ 🚨 优先级：切过段 + 连续模式静音尾 -> 静音尾优先（不发空段）
        if plan(true, true, false, sr * 2) != .quietTail {
            bad.append("静音尾优先级不对")
        }
        return bad.isEmpty ? nil : bad.joined(separator: "; ")
    }

    /// 交出一段（长录音分段用）。**在音频线程调**，跟往 `pcm` 追加同线程。
    ///
    /// 🚨 留 `SEG_OVERLAP_MS` 的尾巴给下一段：被切在中间的那个字
    ///    至少在一边是完整的，重复出来的由 `Segments.join()` 去掉。
    private func emitSegment() {
        let overlapBytes = Int(Voice.SAMPLE_RATE) * 2 * Voice.SEG_OVERLAP_MS / 1000
        let data = pcm
        pcm = data.count > overlapBytes ? data.suffix(overlapBytes) : Data()
        didSegment = true
        let wav = Voice.wrapWav(pcm: data, sampleRate: Int(Voice.SAMPLE_RATE))
        let cb = onSegment
        DispatchQueue.main.async { cb?(wav) }
    }

    private func cut() {
        let data = pcm
        pcm = Data()
        guard data.count >= Int(Voice.SAMPLE_RATE) / 2 else { return }
        let wav = Voice.wrapWav(pcm: data, sampleRate: Int(Voice.SAMPLE_RATE))
        let cb = onUtterance
        DispatchQueue.main.async { cb?(wav) }
    }

    // MARK: - 停止

    /// 只摘 tap + 停引擎，**不动音频会话**。给 `stop()` 在取快照之前用。
    ///
    /// 🚨 单独抽出来是因为顺序有意义：先让渲染线程停止写 `pcm`，再读它。
    ///    `cleanup()` 后面照常调，两者幂等。
    private func stopTapOnly() {
        engine.inputNode.removeTap(onBus: 0)
        Voice.recLeave()
        if engine.isRunning { engine.stop() }
    }

    /// 🚨 H-3（第 2 轮审查）：对象被回收时也要把引擎和会话放掉。
    ///    扩展是随起随停的进程，靠调用方记得调 `stop()` 不可靠。
    deinit { if running { cleanup() } }

    /// **待命中**：引擎在跑、麦克风路由握在手里，但采样直接丢弃。
    ///
    /// 🚨 这不是"省事"，是**唯一合法的后台起录方式**（见 tap 里那段注释）。
    /// 🚨🚨🚨 **保护 `pcm` 的锁。**
    ///
    ///    `stop()` 那条路早就写明了「必须先摘 tap 再取快照 —— `Data` 是 COW
    ///    值类型，**并发读+写是未定义行为**，可能崩溃，也可能悄悄拿到撕裂的数据」。
    ///    而待命档的 `endKeep()` **不摘 tap**（摘了后台就再也装不回来），
    ///    于是它在 tap 还活着的时候直接读 `pcm` —— **正好踩中那条警告**。
    ///    2026-08-30 他真机上的表现：用成一次，第二次按停止时整个 App 消失，
    ///    痕迹断在录音中间、下一条就是"冷启动"。**没有崩溃日志，因为它就是 UB。**
    ///    → 待命档改用锁把追加和取走串起来。临界区只有一次 append，很短。
    private let pcmLock = NSLock()

    /// **系统级麦克风静音开关**（iOS 17+ `AVAudioApplication.setInputMuted`）。
    ///
    /// 🚨🚨 **Kevin 2026-08-30 澄清的真正要求**：他反对麦克风常开
    ///    **不是耗电，是信任** —— 「用户说什么都有理由怀疑被这个输入法记下来，
    ///    那就不会有人用这个产品」。
    ///    → 判据不是「我们承诺丢弃了」，而是「**系统层面确实没在听，用户查得到**」。
    ///
    /// 所以形态是：**引擎一直架着**（后台重架架不起来，那条今晚验死了），
    /// 但**输入在系统层面静音**；只有他按下录音的那几秒才解静音。
    /// 系统自己知道这个状态，也会这么显示给用户。
    static func setMicMuted(_ muted: Bool, why: String) {
        guard #available(iOS 17.0, *) else { return }
        do {
            try AVAudioApplication.shared.setInputMuted(muted)
            KbBridge.note("系统麦克风：" + (muted ? "已静音" : "已解静音")
                          + "（" + why + "）｜系统确认="
                          + String(AVAudioApplication.shared.isInputMuted))
        } catch {
            KbBridge.note("系统麦克风：切换失败 —— " + error.localizedDescription)
        }
    }

    /// 只给静音探针用：开录时**不要**自动解静音（默认 false，产品路径不受影响）。
    static var suppressAutoUnmute = false

    var keeping = true

    /// 引擎此刻真的在跑吗（外部只读）。
    /// 🚨 判据要挂在**引擎自己**上，不是挂在我们的布尔标志上 ——
    ///    系统会在路由变化时把引擎停掉而不通知我们。
    var engineRunning: Bool { engine.isRunning }

    /// tap 最后一次真的送来采样的时刻。
    ///
    /// 🚨🚨 为什么必须有它：2026-08-30 03:26 实测到一个**静默的坏**——
    ///    `engine.isRunning == true`、`arming == true`、共享区待命标记也在，
    ///    但 **tap 已经不送数据了**（连录 3.5 秒只攒到不足半秒）。
    ///    只看"引擎在不在跑"完全看不出来，表现就是他说了话却报"没听清"。
    ///    **「引擎起来了」和「一直在出数据」是两件事。**
    private(set) var lastTapAt = Date.distantPast

    /// 待命档下引擎起来了没。
    /// **这一次 `stop()` 不许碰音频会话。**
    ///
    /// 🚨 只给「本轮原本架着待命、现在要退回老路重录」那条用：
    ///    那时会话是好的、马上还要用，`cleanup()` 里的 `setActive(false)`
    ///    一关，后台那条输入路由就没了，下一次按必然 `2003329396`。
    /// 🚨 调用方必须**用完就清**（`defer`），别让它跨轮次残留。
    /// **这一次 `stop()` 不许碰音频会话。**
    ///
    /// 🚨 由 `stop(keepSession:)` 设、`cleanup()` 末尾复位 —— **不再是调用方管**。
    ///    上一版是静态全局 + 调用方 `defer` 清，只有 `stop()` **同步**走完
    ///    `cleanup()` 才成立；一旦 `cleanup()` 从别的队列被调到，
    ///    读到的就是已经清成 false 的值 → **整轮修法空转，而且不报错**。
    private var keepSessionOnCleanup = false

    var arming = false

    /// 不录的时候把引擎 `pause()` 掉 —— 目的是**麦克风指示灯别一直亮着**。
    ///
    /// 🚨 Kevin 2026-08-29：「我都说了很多遍了，**不能一直开着麦克风**」。
    ///    `pause()` 保留音频单元、只停渲染，按苹果论坛的说法
    ///    「暂停/恢复可以从后台做」。**但这一条我还没在真机验过** ——
    ///    真机上要是恢复不了，`beginKeep()` 会自动退回"不暂停"档，
    ///    并把这件事记进痕迹，而不是静默失败。
    /// 🚨🚨 **实测否定：默认关掉（2026-08-30 02:45 真机）。**
    ///    痕迹原文：`待命档开闸失败：从暂停恢复失败：… Code=2003329396`。
    ///    也就是说 **`pause()` 之后在后台 `start()` 起不来** ——
    ///    苹果论坛那句"可以从后台暂停/恢复"对**输入**引擎不成立
    ///    （多半只对播放成立）。
    ///    → 引擎一旦架起来就**一直跑**。代价写在这里，不藏着：
    ///      **麦克风指示灯在待命期间是亮的**，这跟 Kevin 说的
    ///      「不能一直开着麦克风」有冲突，要跟他摊开讲、一起决定怎么收窄。
    ///    `TRANSLESS_PAUSEMIC=1` 可以打开来复现这个失败。
    static var pauseWhenIdle: Bool {
        ProcessInfo.processInfo.environment["TRANSLESS_PAUSEMIC"] == "1"
    }

    /// 恢复失败过一次之后就不再暂停（自愈，避免每次都失败一遍）。
    private static var pauseProvenBad = false

    /// **前台把引擎架起来，进待命档。** 必须在 App 前台调用。
    func armIdle(reuseSession: Bool, done: @escaping (String?) -> Void) {
        if arming && engine.isRunning { return done(nil) }
        keeping = false
        arming = true
        start(onPartial: { _ in }, reuseSession: reuseSession) { r in
            // 🚨🚨 **别把失败原因扔掉。** 这里原来是 `{ _ in }`，
            //    于是引擎起不来时只剩一句没用的「引擎没起来」，
            //    我据此瞎猜了三轮（信号量、时序、会话）。
            //    `Voice` 本来就把现场（类别/激活/输入源/错误码）打包在 failure 里，
            //    **它一直在，是我没接**。
            if case .failure(let f) = r {
                KbBridge.note("待命档起不来的真实原因："
                              + String(describing: f).prefix(300))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if self.engine.isRunning {
                if Voice.pauseWhenIdle && !Voice.pauseProvenBad { self.engine.pause() }
                // 🚨 架好之后**立刻系统级静音** —— 平时绝不听。
                Voice.setMicMuted(true, why: "待命中，不听")
                done(nil)
            } else {
                self.arming = false
                done("待命档引擎没起来")
            }
        }
    }

    /// **同步版的架待命档** —— 起完就地判断，不派发。
    ///
    /// 🚨🚨 为什么要它：`armIdle` 的回调是 `DispatchQueue.main.asyncAfter` 派发的，
    ///    而调用方在**主线程上用信号量等它** —— 主线程被堵住，那个回调永远跑不到，
    ///    必然超时报「引擎没起来」。**这是我自己写出来的死锁**
    ///    （2026-08-30 21:5x 连撞三次，而同一段逻辑用异步调就是成功的）。
    /// 🚨 判据是**返回 nil 且 `engine.isRunning` 为真**，不是"没抛错"。
    func armIdleNow(reuseSession: Bool) -> String? {
        if arming && engine.isRunning { return nil }
        keeping = false
        arming = true
        start(onPartial: { _ in }, reuseSession: reuseSession) { _ in }
        if engine.isRunning {
            if Voice.pauseWhenIdle && !Voice.pauseProvenBad { engine.pause() }
            return nil
        }
        arming = false
        return "引擎没起来"
    }

    /// **开始把采样留下来。** 后台可调 —— 它不新建录音，只是打开闸门。
    func beginKeep() -> String? {
        guard arming else { return "还没进待命档" }
        pcmLock.lock(); pcm = Data(); pcmLock.unlock()
        // 🚨 探针专用：要测「静着录出来是什么」，就不能让开录这一步把静音解掉。
        //    产品路径 `suppressAutoUnmute` 恒为 false，不受影响。
        if !Voice.suppressAutoUnmute {
            Voice.setMicMuted(false, why: "他按下了录音")
        }
        if !engine.isRunning {
            do { try engine.start() } catch {
                // 🚨 恢复不了就**永久退回"不暂停"档**，并说清楚。
                //    不这么做的话每次录音都要先失败一次。
                Voice.pauseProvenBad = true
                return "从暂停恢复失败：" + (error as NSError).description.prefix(80).description
            }
        }
        keeping = true
        return nil
    }

    /// **原地把引擎重新拉起来**（中断结束后用）。成功返回 nil。
    ///
    /// 🚨 不重建引擎、不碰会话 —— 只 `start()`。
    ///    重建引擎要重新拿 `inputNode`，那在后台是拿不到的。
    func restartEngine() -> String? {
        if engine.isRunning { return nil }
        do { try engine.start(); return nil }
        catch { return String("\((error as NSError).code)") }
    }

    /// **收工**：把留下来的采样包成 wav 交出去，引擎继续待命。
    func endKeep() -> Data? {
        guard arming else { return nil }
        // 🚨 关闸门 + 取走，**必须在同一个临界区里做完** ——
        //    分两步的话 tap 可能正卡在中间，读到撕裂的数据或直接崩。
        pcmLock.lock()
        keeping = false
        let d = pcm
        pcm = Data()
        pcmLock.unlock()
        Voice.setMicMuted(true, why: "录完了，回到不听")
        if Voice.pauseWhenIdle && !Voice.pauseProvenBad && engine.isRunning {
            engine.pause()
        }
        // 🚨 采不到时**把现场打出来**，别只返回 nil ——
        //    今晚就因为这里悄无声息，我连着三轮在猜「是静音起作用了还是本来没采」。
        if d.count < Int(Voice.SAMPLE_RATE) / 2 {
            KbBridge.note(String(format:
                "采不到：%d 字节｜引擎在跑=%@｜tap 距今 %.1f 秒｜arming=%@｜keeping=%@",
                d.count, engine.isRunning ? "是" : "否",
                Date().timeIntervalSince(lastTapAt), arming ? "是" : "否",
                keeping ? "是" : "否"))
        }
        guard d.count >= Int(Voice.SAMPLE_RATE) / 2 else { return nil }
        return Voice.wrapWav(pcm: d, sampleRate: Int(Voice.SAMPLE_RATE))
    }

    /// 彻底收摊（退出待命）。
    func disarm() {
        arming = false
        keeping = true
        stopTapOnly()
        if engine.isRunning { engine.stop() }
    }

    /// - Parameter keepSession: 这一次**别碰音频会话**。
    ///   只给「本轮原本架着待命、马上还要重起录」那条用：那时会话是好的、
    ///   `setActive(false)` 一关，后台那条输入路由就没了，下一次按必然 `2003329396`。
    func stop(keepSession: Bool) {
        // 🚨🚨 **赋值必须在 `stop()` 的 guard 之后**（交叉审查 20260901_2314 中-C）：
        //    `stop()` 第一行就可能早退（`capTimer` 或配置变化观察者已经停过一次），
        //    早退 → `cleanup()` 不跑 → `defer` 不跑 → **标志留在 true**。
        //    而它原来还是 `static`，这个进程里有**三个 Voice 实例**
        //    （AppDelegate / BgRecProbe / KbVoiceHost）——
        //    残留的真值会让主 App「随手翻译」那次也不关会话。
        //    → 现在是实例属性，且只在真要 cleanup 的路径上置位。
        guard running, !finished else { return }
        keepSessionOnCleanup = keepSession
        stop()
    }

    func stop() {
        guard running, !finished else { return }
        finished = true
        capTimer?.invalidate(); capTimer = nil

        // 🚨🚨 M3（交叉审查）：**必须先摘 tap 再取快照。**
        //    原来是 `let data = pcm` 在主线程先拍快照、之后才 `cleanup()` 摘 tap；
        //    而 tap 回调在**音频渲染线程**往 `pcm` 里 append。
        //    Swift 的 `Data` 是 COW 值类型，**并发读+写是未定义行为** ——
        //    可能崩溃，也可能悄悄拿到撕裂的数据（那就变成"录到了但内容不对"）。
        //    48kHz / 2048 帧下这个窗口每约 42ms 出现一次，按停止那一瞬正好撞上。
        //    摘 tap 之后渲染线程不会再写，快照才是安全的。
        stopTapOnly()
        let data = pcm
        // 🚨 连续模式下末尾这一段**可能只是静音**（刚切完一句才按的停止）。
        //    照发的话后端返回空结果，白花一次调用还闪一条空气泡。
        //    `hasVoice` 就是为这一刻写的 —— 它不是装饰。
        let tailWorth = splitter.map { $0.hasVoice } ?? true
        let wasContinuous = onUtterance != nil
        onUtterance = nil
        splitter = nil
        cleanup()

        // 🚨 决策**只在 `tailPlan` 里做一次** —— 它有自测守着（`selfTest`）。
        //    别在这里再写一遍判断：两处实现早晚会漂，而这条漂了就是花他的钱。
        let plan = Voice.tailPlan(didSegment: didSegment,
                                  wasContinuous: wasContinuous,
                                  tailWorth: tailWorth, bytes: data.count,
                                  sampleRate: Int(Voice.SAMPLE_RATE))
        if plan == .quietTail {
            // 正常收尾，不是错 —— 界面不该报"没听清"
            onWav?(.success(Data()))
            onWav = nil; onPartial = nil
            return
        }
        // 🚨 **切过段：最后这截也从 `onSegment` 出去**，然后收工。
        //    这里**绝不能再从 `onWav` 交一份** —— 同一段音频会被转两次，
        //    是实打实的两次计费；而且拼接时会多出一段重复的话。
        //    尾巴太短就直接不发（不足 0.5 秒基本是按停止那一下的静音）。
        if plan == .segment || plan == .segmentSkipTail {
            let segCb = onSegment
            if plan == .segment {
                let wav = Voice.wrapWav(pcm: data,
                                        sampleRate: Int(Voice.SAMPLE_RATE))
                DispatchQueue.main.async { segCb?(wav) }
            }
            didSegment = false
            onSegment = nil
            // 🚨 `onWav` 给一个空 Data 表示「我这边完事了，结果去分段器取」。
            //    调用方靠**它自己有没有接 `onSegment`** 判断走哪条路 ——
            //    不靠这个空值猜（空值也可能是"没听清"，两种意思撞在一起）。
            onWav?(.success(Data()))
            onWav = nil; onPartial = nil
            return
        }
        // 太短 = 没说话（不足约 0.5 秒）
        if plan == .tooShort {
            onWav?(.failure(Failure(stage: .none, detail: "没听清，再说一次")))
            onWav = nil; onPartial = nil
            return
        }
        onWav?(.success(Voice.wrapWav(pcm: data, sampleRate: Int(Voice.SAMPLE_RATE))))
        onWav = nil; onPartial = nil
    }

    private func cleanup() {
        running = false
        // 🚨🚨🚨 **`arming` 也要清**（交叉审查 20260901_2132 高）。
        //    `armIdle` 内部就是 `start(...)`，所以 `arming == true ⇒ running == true`；
        //    而这里原来只清 `running` —— **引擎都拆了，`arming` 还是 true**。
        //    下游拿它当判据的地方就全被骗：`finish()` 会把一条走老路的录音
        //    路由进待命档分支 → `endKeep()` 返回 nil → 立刻「没听清」把他刚说的丢掉；
        //    而老路那条还在跑，一分钟后又插一段进输入框。
        //    **单一配置点：让这个状态位在引擎没了的时候就是 false。**
        capTimer?.invalidate(); capTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        Voice.recLeave()
        // 🚨 清 `arming` 放在 `removeTap` **之后**（交叉审查 20260901_2204 低）：
        //    清得太早时 tap 还挂着，中间那几行看到的是「不在待命但 tap 还在」的矛盾态。
        arming = false
        if engine.isRunning { engine.stop() }
        // 🚨🚨 **小窗活着时不许关会话。**
        //    `setActive(false)` 会把画中画那路播放一起掐掉 —— 小窗一没，
        //    主 App 下次就又被系统挂起 → 又得跳转 → 又回不来。
        //    实测 2026-08-29：录完之后 `kb.pip.at` 变 false，根因就在这一行。
        //    小窗自己就是"留在后台"的理由，会话留着不关也不会怎样。
        // 🚨🚨 **可录保活活着时同样不许关会话（2026-08-30 补）。**
        //    小窗那条已经写了，**保活这条没写** —— 同一个道理、两个理由，
        //    只落实了一个。`setActive(false)` 一关，后台那条输入路由就没了，
        //    下一次按麦克风又回到"四档全被拒"。
        //    判据不是"我加了判断"，是**录完之后再按一次还能录**。
        // 🚨🚨🚨 **第三个豁免：本轮原本架着待命（2026-09-01 交叉审查 高-1/高-2）。**
        //    会话被抽走的**真凶就是下面这行** —— 上一轮我想在调用方跳过
        //    `voice.stop()` 来躲开它，被判死：跳过 `stop()` 会让引擎不停、
        //    录音全丢、麦克风常亮。**正解是让 `stop()` 照常摘 tap、清状态，
        //    只是不碰会话。**
        //    调用方（`KbVoiceHost.begin`）在 `stop()` 前后设/清这个开关。
        // 🚨 **两条痕迹缺一不可**：没有它们，「豁免生效了」和「没拿到麦克风」
        //    在日志里长得一模一样，下次排查分不开（审查官原话）。
        if keepSessionOnCleanup {
            KbBridge.note("cleanup：这次跳过关会话（keep）")
        }
        defer { keepSessionOnCleanup = false }   // 🚨 用完就复位，别跨轮次残留
        if !KbBridge.pipReady() && !KbBridge.holdAlive() && !keepSessionOnCleanup {
            KbBridge.note("cleanup：关掉会话")
            try? AVAudioSession.sharedInstance()
                .setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: - WAV 封装（16bit 单声道 + 44 字节头），跟安卓 wav() 一致

    static func wrapWav(pcm: Data, sampleRate: Int) -> Data {
        let dataLen = pcm.count
        let byteRate = sampleRate * 2
        var h = Data()
        func str(_ s: String) { h.append(contentsOf: s.utf8) }
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; withUnsafeBytes(of: &x) { h.append(contentsOf: $0) } }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; withUnsafeBytes(of: &x) { h.append(contentsOf: $0) } }
        str("RIFF"); u32(36 + dataLen); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(1)
        u32(sampleRate); u32(byteRate); u16(2); u16(16)
        str("data"); u32(dataLen)
        var out = h
        out.append(pcm)
        return out
    }
}
