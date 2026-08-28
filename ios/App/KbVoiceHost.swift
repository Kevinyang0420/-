import AVFoundation
import UIKit

/// 键盘语音的**宿主**：主 App 在后台替键盘录音、转写、润色。
///
/// 为什么要这样，见 `KbBridge` 文件头 —— 一句话：**iOS 禁止扩展进程录音**，
/// 系统检查的是「调用方是不是扩展」，跟怎么配音频会话无关。
///
/// ## 一次完整的来回
///
/// ```
/// 键盘按麦克风  →  KbBridge.send("start", args: 语气/模式/语言)
///                        ↓  Darwin 通知（外加 1 秒轮询兜底）
///                  本类收到 → Voice.start() 开录
/// 键盘再按一下  →  KbBridge.send("stop")
///                  本类 Voice.stop() → Backend.transcribe → Backend.polish
///                        ↓
///                  KbBridge.reply(kind: "text", body: 结果)
///                        ↓
///                  键盘读到，插进光标
/// ```
///
/// ## 待机（standby）是什么、为什么要它
///
/// 键盘要能**随时**叫醒我们，而 iOS 只让「正在播放或录制音频」的 App
/// 留在后台。所以待机期间我们放着一段**听不见的静音**（见 `AudioHold`）。
///
/// 🚨🚨 **待机期间麦克风必须是关的** —— 产品经理 2026-08-28 的 P1/P2：
///    「没在说话时麦克风必须真的是关的」，且「判据挂在系统状态栏那个橙点上，
///    不是靠文案声明」。所以保活用播放、不用录音。
///
/// 🚨🚨 **两件事只能在真机上验，模拟器测出来的绿是假的**：
///    ① 待机能不能真的活下来 —— 判据是键盘上那行「宿主在线 / 离线」
///       （读心跳时间戳，宿主一死就翻）
///    ② **后台状态下能不能从零开始起录** —— iOS 对后台起录有限制。
///       竞品 Typeless 最终走的是**画中画 PiP**，而 PiP 恰好能让 App
///       处于"接近前台"的状态 —— **它们绕到 PiP，很可能正是因为
///       光放静音起不了录**。这条不许靠推断结案。
///    验收判据见 `voice_ime/_需求与验收_iOS后台录音.md`。
final class KbVoiceHost {

    static let shared = KbVoiceHost()

    /// 待机开着没有。用户在 App 里显式打开，关掉就立刻放开麦克风。
    private(set) var standby = false
    /// 这一轮结果要不要顺手写进 selftest.txt（Mac 自检在等）。
    private var selfTestFull = false

    /// 待机多久自动关。
    /// 🚨 必须有上限：常驻后台会耗电。产品经理的 E1/E2 就是量这笔账
    ///    （开一小时 vs 关一小时，**判据是两者之差**）。
    ///    Typeless 用的是 5 分钟，我们取 10 分钟 —— 键盘每次用都会续期，
    ///    所以真正会触发的是「打开了但没在用」。
    static let standbyLimit: TimeInterval = 600

    /// 暂停自动超时。**只给 `BgRecProbe` 用。**
    ///
    /// 🚨 自测要跑一整夜，而待机默认 10 分钟没用就自己关。不关掉这个超时的话，
    ///    第二档还没到宿主就停了 —— 那样测出来的"起不了录"**是我们自己关的，
    ///    不是 iOS 拦的**。这类"被自己的设计伪装成故障"最难查。
    var suspendTimeout = false

    private var openedAt = Date()
    private var timer: Timer?
    private var lastSeq = 0
    private var busySeq = -1
    private let voice = Voice()
    fileprivate let hold = AudioHold()

    /// 待机状态变了就喊一声，App 界面上那个开关跟着变。
    var onChange: (() -> Void)?

    private init() {}

    // ------------------------------------------------------------ 开关

    func setStandby(_ on: Bool) {
        if on == standby { return }
        standby = on
        if on {
            openedAt = Date()
            // 🚨 只接开待机之后的命令。判断在 `KbProtocol`（有自测），
            //    别在这儿写 `= 0` —— 那会把上一次待机残留的命令重放一遍，
            //    表现是「一打开待机它自己就开始录音」，而且**只在第二次使用时出现**。
            lastSeq = KbProtocol.alignOnStandby(currentSeq: KbBridge.currentSeq)
            hold.start()
            KbBridge.beat()
            observe()
            timer = Timer.scheduledTimer(withTimeInterval: KbBridge.beatEvery,
                                         repeats: true) { [weak self] _ in
                self?.tick()
            }
        } else {
            timer?.invalidate(); timer = nil
            KbBridge.stopObserving(Unmanaged.passUnretained(self).toOpaque())
            if voice.running { voice.stop() }
            hold.stop()
            KbBridge.clearBeat()
        }
        onChange?()
    }

    /// 主 App 界面自己要录音时，先把保活停掉。
    ///
    /// 🚨🚨 保活现在只放静音、**不碰输入节点**，但**仍然要让开** ——
    ///    冲突不在输入节点，在**音频会话类别**：保活设的是 `.playback`，
    ///    录音要的是 `.record`/`.playAndRecord`。两个引擎各自往同一个
    ///    共享会话上按自己的类别，后设的赢，先起的那个悄悄失效。
    ///    不让开的表现是「待机开着的时候，随手翻译录不了音」——
    ///    而随手翻译是 iOS 上**唯一一直能用**的录音入口，
    ///    等于新功能把老功能弄坏了。
    func yieldMic() { hold.stop() }

    /// 界面用完了，还在待机就把保活重新起回来。
    /// 🚨 `busySeq < 0` 这个条件不能省：正在替键盘录音时不该去抢。
    func reclaimMic() { if standby && busySeq < 0 { hold.start() } }

    /// 还能待机多久（秒）。界面上倒计时用。
    var remaining: TimeInterval {
        standby ? max(0, KbVoiceHost.standbyLimit - Date().timeIntervalSince(openedAt)) : 0
    }

    // ------------------------------------------------------------ 心跳 + 轮询

    private func tick() {
        guard standby else { return }
        if remaining <= 0 && !suspendTimeout {
            // 🚨 H4（产品经理 2026-08-28）：**「该不该这么频繁地需要恢复」
            //    比「恢复得顺不顺」重要。** 如果他一天撞上五次
            //    「Transless 被系统关掉了」，那不是恢复路径的毛病，
            //    是 10 分钟这个上限本身的毛病 —— 而这只能拿真实使用节奏去量。
            //    记的是**每次过期的时刻**，不是一个计数器：
            //    只有时刻才算得出"多久撞一次"，计数器算不出。
            var t = UserDefaults.standard.array(forKey: "standby.expiredAt")
                as? [Double] ?? []
            t.append(Date().timeIntervalSince1970)
            if t.count > 200 { t.removeFirst(t.count - 200) }
            UserDefaults.standard.set(t, forKey: "standby.expiredAt")
            setStandby(false)
            return
        }
        KbBridge.beat()
        drain()
    }

    /// Darwin 通知的回调是个 C 函数指针，**捕获不了 self**，
    /// 所以走一个静态跳板转回单例。
    private func observe() {
        KbBridge.observeCommands(Unmanaged.passUnretained(self).toOpaque()) {
            _, _, _, _, _ in
            DispatchQueue.main.async { KbVoiceHost.shared.drain() }
        }
        // 🚨 自检那条**必须在这里注册** —— 2026-08-28 我写完 KbBridge 里的
        //    `writeSelfTest` / `observeSelfTest` 就去汇报"自检通道已加"，
        //    而**这两个函数零调用点**，post 过去根本没人接。
        //    跟记忆 `feedback_diagnostic_log_without_exit` 同型：
        //    **写了记录的代码 != 记录会产生**。
        KbBridge.observeSelfTest(Unmanaged.passUnretained(self).toOpaque()) {
            _, _, _, _, _ in
            DispatchQueue.main.async { KbVoiceHost.shared.runSelfTest() }
        }
    }

    // ------------------------------------------------------------ Mac 触发的自检

    /// Mac 侧：
    /// ```
    /// xcrun devicectl device notification post --device <id> \
///       --name com.kevin.transless.selftest
    /// xcrun devicectl device copy from --device <id> \
///       --domain-type appGroupDataContainer \
    ///       --domain-identifier group.com.kevin.transless \
    ///       --source selftest.txt --destination ./selftest.txt
    /// ```
    /// 🚨 **覆盖范围**：从这里往下跟按麦克风走同一条路（同一个 `voice`、
    ///    同一次 `yieldMic`），但**跳过了「键盘 -> App Group -> 宿主」那一跳**。
    ///    别把它的绿当成整条链的绿。
    func runSelfTest() {
        if voice.running {
            KbBridge.writeSelfTest("SKIP 正在录音中，没跑自检")
            return
        }
        // ---- 完整档：走跟键盘一模一样的那条路（send -> takeCommand -> begin）
        if KbBridge.readSelfTestCmd()["full"] == "1" {
            let c = KbBridge.readSelfTestCmd()
            guard standby else {
                // 🚨 这条必须单独报。不待机时 `drain()` 什么都不做，
                //    文件会停在"已下发"，读起来像"卡住了"，
                //    而真相是**宿主压根没在接活**。两种要分得开。
                KbBridge.writeSelfTest("FAIL 宿主没在待机（standby=false），命令不会被取走")
                return
            }
            selfTestFull = true
            _ = KbBridge.send("start", args: ["tone": c["tone"] ?? "",
                                              "mode": c["mode"] ?? "en",
                                              "lang": c["lang"] ?? "en"])
            drain()
            let sec = Double(c["sec"] ?? "4") ?? 4
            DispatchQueue.main.asyncAfter(deadline: .now() + sec) { [weak self] in
                self?.finish()
            }
            // 🚨 兜底：整条链**没有任何回调**时也要留下痕迹。
            DispatchQueue.main.asyncAfter(deadline: .now() + sec + 40) {
                [weak self] in
                guard let self = self, self.selfTestFull else { return }
                self.selfTestFull = false
                KbBridge.writeSelfTest("HANG 完整链路 \(Int(sec) + 40) 秒无结果")
            }
            return
        }
        let st = Self.where_()
        yieldMic()
        var settled = false
        voice.start(onPartial: { _ in }) { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self, !settled else { return }
                settled = true
                switch r {
                case .success:
                    KbBridge.writeSelfTest("OK 起录成功\n" + st)
                case .failure(let f):
                    // 🚨 「没听清，再说一次」= 录成功了但太短 —— 那正是我要的
                    //    「起得来」，别记成失败（探针那边同一个坑）。
                    let s = "\(f)"
                    if s.contains("没听清") {
                        KbBridge.writeSelfTest("OK 起录成功（内容太短，符合预期）\n" + st)
                    } else {
                        KbBridge.writeSelfTest("FAIL " + s + "\n" + st + "\n"
                                               + Voice.diagnostics())
                    }
                }
                self.reclaimMic()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self = self else { return }
            if self.voice.running { self.voice.stop() }
        }
        // 🚨 起录**根本没回调**也要留下痕迹 —— 否则"文件没变"会被读成
        //    "通知没送到"，而真相可能是"送到了但卡死了"。两种要分得开。
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            if !settled {
                settled = true
                KbBridge.writeSelfTest("HANG 起录 6 秒无回调\n" + st + "\n"
                                       + Voice.diagnostics())
            }
        }
    }

    // ------------------------------------------------------------ 处理命令

    private func drain() {
        guard standby, let cmd = KbBridge.takeCommand(after: lastSeq) else { return }
        lastSeq = cmd.seq
        openedAt = Date()                    // 用一次续一次期
        switch cmd.action {
        case "start": begin(seq: cmd.seq, args: cmd.args)
        case "stop": finish()
        case "yield":
            // 🚨 键盘要自己录了，把音频会话整个让开。
            //    `AudioHold.stop()` 里会 setActive(false, .notifyOthersOnDeactivation)
            //    —— 那一句是今晚修 `!int` 时加的，正好是这里需要的。
            if voice.running { voice.stop() }
            hold.stop()
        case "cancel":
            if voice.running { voice.stop() }
            busySeq = -1
            hold.start()
        default: break
        }
    }

    private func begin(seq: Int, args: [String: String]) {
        if voice.running { voice.stop() }
        busySeq = seq
        // 键盘那条波形的数据源。清一次再接，别把上一轮的尾巴带进来。
        KbBridge.clearLevels()
        voice.onLevel = { KbBridge.pushLevel($0) }
        // 🚨 让开麦克风再交给 Voice —— 两个引擎抢同一个输入节点会打架。
        hold.stop()
        let tone = Prompts.normalize(args["tone"])
        let mode = Backend.Mode(rawValue: args["mode"] ?? "en") ?? .en
        let lang = args["lang"] ?? "en"
        voice.start(onPartial: { _ in }, onWav: { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self, self.busySeq == seq else { return }
                switch r {
                case .failure(let f):
                    // 🚨🚨 **失败时必须带上「当时 App 在不在前台」**。
                    //    这一版最大的未知数就是「后台能不能从零起录」——
                    //    而「在后台失败」和「在前台也失败」指向完全不同的修法：
                    //      · 后台失败、前台成功 → 是 iOS 的后台起录限制 → 得上画中画 PiP
                    //      · 两边都失败 → 是我们自己的音频配置问题
                    //    不带这一条的话，一次真机测试回来还是分不清，
                    //    又要再测一次。**一次测试要能给出答案，不管答案是哪个。**
                    self.done(seq: seq, kind: "error",
                              body: "\(f)\n\n" + Self.where_() + "\n"
                                  + Voice.diagnostics())
                case .success(let wav):
                    KbBridge.reply(seq: seq, kind: "partial", body: L.st_recognizing)
                    Backend.transcribe(wav: wav) { [weak self] t in
                        DispatchQueue.main.async {
                            guard let self = self, self.busySeq == seq else { return }
                            switch t {
                            case .failure(let f):
                                self.done(seq: seq, kind: "error", body: "\(f)")
                            case .success(let zh):
                                KbBridge.reply(seq: seq, kind: "partial", body: zh)
                                Backend.polish(text: zh, tone: tone, mode: mode,
                                               lang: lang) { [weak self] p in
                                    DispatchQueue.main.async {
                                        guard let self = self,
                                              self.busySeq == seq else { return }
                                        switch p {
                                        case .failure(let f):
                                            self.done(seq: seq, kind: "error",
                                                      body: "\(f)")
                                        case .success(let en):
                                            // 🚨 把「听到的中文」一起送回去：
                                            //    键盘要拿它落历史。只送出稿的话
                                            //    历史里那一条永远缺左半边，
                                            //    而且是**装到手机上才看得出来**。
                                            self.done(seq: seq, kind: "text",
                                                      body: Self.pack(zh: zh, out: en))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        })
    }

    private func finish() {
        guard voice.running else { return }
        voice.stop()                          // 结果从 onWav 回来，见 begin
    }

    /// 出错那一刻主 App 在哪 —— 前台 / 后台 / 非活跃。
    ///
    /// 🚨 用 `applicationState` 而不是「我以为它在后台」。
    ///    键盘弹出来的时候主 App 一定不在前台，但**不在前台**有两种
    ///    （`.background` 真进后台 / `.inactive` 过渡态），
    ///    而 iOS 的后台起录限制只对前者生效。分不开就判不出根因。
    static func where_() -> String {
        let st = UIApplication.shared.applicationState
        let name: String
        switch st {
        case .active: name = "前台活跃"
        case .inactive: name = "非活跃（过渡态）"
        case .background: name = "后台"
        @unknown default: name = "未知"
        }
        return "出错时主App  \(name)\n待机保活    "
            + (KbVoiceHost.shared.hold.running ? "在跑" : "没在跑")
    }

    /// 最终结果的载荷格式：`{"zh": 听到的, "out": 出稿}`。
    /// 🚨 键盘那边 `deliver()` 按同一个格式解 —— **两处必须一起改**，
    ///    所以打包和解包各自只有一个地方，别再散着写。
    static func pack(zh: String, out: String) -> String {
        let d = try? JSONSerialization.data(withJSONObject: ["zh": zh, "out": out])
        return d.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    private func done(seq: Int, kind: String, body: String) {
        voice.onLevel = nil
        KbBridge.clearLevels()
        KbBridge.reply(seq: seq, kind: kind, body: body)
        if selfTestFull {
            selfTestFull = false
            KbBridge.writeSelfTest((kind == "text" ? "OK 完整链路通了" : "FAIL ")
                                   + body + "\n" + Self.where_())
        }
        busySeq = -1
        if standby { hold.start() }           // 交完货重新待机
    }
}

// ---------------------------------------------------------------- 保活

/// 待机期间**放一段听不见的静音**，让 iOS 认为我们在播放音频、从而不挂起进程。
///
/// 🚨🚨 **这里绝不能占麦克风。** 第一版写的是「开着输入节点、把采到的样本丢掉」，
///    那违反产品经理 2026-08-28 定的 **P1：后台常驻期间，没在说话时麦克风
///    必须真的是关的**，配套 **P2：判据挂在系统状态栏那个橙点上，不是靠文案声明**。
///    占着麦克风的话橙点一直亮 —— 用户看到的就是"它一直在听我说话"，
///    而我们的隐私说明会变成一句圆不回来的话。
///    （我当时的理由是「放静音是骗系统、审核不待见」。**那个取舍站不住**：
///     P1 是隐私承诺，不能为了规避审核风险去违反它。）
///
/// 🚨 **只有播放，没有输入节点** —— 引擎里根本没接麦克风，
///    所以「待机时不占麦克风」不是靠自觉，是**结构上做不到**。
///
/// ⚠️ **有一个只能真机验的未知数**：App 在后台（只放着静音）时，
///    收到命令能不能**从零开始**打开麦克风录音。iOS 对「后台起录」有限制。
///    竞品 Typeless 最终走的是**画中画 PiP**（产品经理的竞品考古，一手发布说明），
///    而 PiP 恰恰能让 App 处于"接近前台"的状态 —— **它们绕到 PiP，
///    很可能就是因为光放静音起不了录**。
///    这一条不许靠推断结案，判据见 `_需求与验收_iOS后台录音.md`。
private final class AudioHold {

    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?

    var running: Bool { engine?.isRunning ?? false }

    func start() {
        if running { return }
        stop()
        let s = AVAudioSession.sharedInstance()
        do {
            // 🚨 `.playback` 而不是 `.playAndRecord` —— 类别本身就不含录音，
            //    这是"待机不占麦克风"的第二道结构性保证。
            // 🚨 `.mixWithOthers` 让用户的音乐/播客继续放。
            //    不加的话一进待机就把他正在听的东西掐了。
            try s.setCategory(.playback, mode: .default,
                              options: [.mixWithOthers])
            try s.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }
        let e = AVAudioEngine()
        let p = AVAudioPlayerNode()
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100,
                                      channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt,
                                         frameCapacity: 44100) else { return }
        buf.frameLength = buf.frameCapacity          // 全零 = 一秒静音
        e.attach(p)
        e.connect(p, to: e.mainMixerNode, format: fmt)
        e.mainMixerNode.outputVolume = 0
        do {
            try e.start()
        } catch {
            return
        }
        p.scheduleBuffer(buf, at: nil, options: .loops)
        p.play()
        engine = e
        player = p
    }

    func stop() {
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        // 🚨🚨 **必须把会话也停掉，不能只停引擎**（2026-08-28 真机实证）。
        //    Kevin 装 592 之后报「四档配置全被拒，code 560557684」——
        //    `560557684` = `0x21696e74` = `'!int'` = **CannotInterruptOthers**：
        //    **别的东西正占着音频，我们打断不了。**
        //    而占着的那个**就是我们自己**：保活的 `.playback` 会话还是 active 的，
        //    引擎停了不代表会话让开了。于是切到 `.record` 时被自己挡住。
        //
        //    🚨 这跟前五次完全不是一类（前五次是扩展里的 `'what'` Unspecified）——
        //    **App Group 那条链已经通了，卡点前移到主 App 自己配不起会话。**
        //
        //    判据别挂在"不报错"上，挂在**当前路由 入N ≥ 1**（今天已经被
        //    "配置成功但路由没有输入口"骗过一次）。
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }
}
