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

    /// 总时长上限（跟安卓一致，防超大包）。
    static let MAX_DURATION: TimeInterval = 60
    /// 连续模式下**单句**的封顶秒数。跟安卓 `MAX_UTTERANCE_SECONDS` 一致。
    /// 有人一口气说 30 秒不带停的，到点强制切一句。
    static let MAX_UTTERANCE: TimeInterval = 30
    /// 连续模式**整场**封顶。跟安卓 `MAX_CONTINUOUS_SECONDS` 一致。
    /// 🚨 必须有：连续模式没有"松手"这个动作，
    ///    用户放着不管就会一直占着麦克风、一直耗电。
    static let MAX_CONTINUOUS: TimeInterval = 600

    private static let SAMPLE_RATE: Double = 16000

    enum Stage: String {
        case permissionMic = "麦克风权限"
        case audioSession = "音频会话"
        case engine = "录音引擎"
        case none = ""
    }

    struct Failure: Error, CustomStringConvertible {
        let stage: Stage
        let detail: String
        var description: String { stage == .none ? detail : "\(stage.rawValue)：\(detail)" }
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

    // MARK: - 连续模式（Kevin 2026-08-26 要的"随手翻译"同传场景）

    /// 非 nil = 连续模式。每断出一句回调一次，**在主线程**。
    private var onUtterance: ((Data) -> Void)?
    /// 断句器。逻辑在 `SilenceSplitter`（纯逻辑、6 组自测、两端同一份口径）。
    private var splitter: SilenceSplitter?
    var isContinuous: Bool { running && onUtterance != nil }

    private(set) var running = false
    var elapsed: TimeInterval { running ? Date().timeIntervalSince(startedAt) : 0 }

    /// 音频会话配置的**退让阶梯**。从独占到最朴素，逐档试。
    ///
    /// 🚨 顺序有讲究：第一档跟容器 App 里一直在用的那套一模一样
    ///    （改动不许影响本来就好用的那一端）；后面几档才是给扩展退让用的。
    static let audioLadder: [(cat: AVAudioSession.Category,
                              mode: AVAudioSession.Mode,
                              opts: AVAudioSession.CategoryOptions)] = [
        (.record, .measurement, .duckOthers),
        (.playAndRecord, .measurement, [.mixWithOthers, .defaultToSpeaker]),
        (.playAndRecord, .default, [.mixWithOthers, .allowBluetooth,
                                    .defaultToSpeaker]),
        (.record, .default, []),
    ]

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

    static func permissionState() -> Failure? {
        if AVAudioSession.sharedInstance().recordPermission != .granted {
            return Failure(stage: .permissionMic, detail: "去 Transless App 里授权一次")
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
    func start(onPartial: @escaping (String) -> Void,
               onUtterance: ((Data) -> Void)? = nil,
               onWav: @escaping (Result<Data, Failure>) -> Void) {
        if let p = Voice.permissionState() { return onWav(.failure(p)) }
        self.onPartial = onPartial
        self.onWav = onWav
        pcm = Data()
        finished = false
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
        var usedRung = -1
        for (i, rung) in Voice.audioLadder.enumerated() {
            do {
                try session.setCategory(rung.cat, mode: rung.mode, options: rung.opts)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
                usedRung = i
                break
            } catch {
                sessionErr = error as NSError
                continue
            }
        }
        if usedRung < 0 {
            let ns = sessionErr
            return onWav(.failure(Failure(
                stage: .audioSession,
                detail: "四档配置全被拒（最后一次 code \(ns?.code ?? -1)）"
                    + Voice.context())))
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
        if inFormat.sampleRate <= 0 || inFormat.channelCount == 0 {
            cleanup()
            return onWav(.failure(Failure(
                stage: .engine,
                detail: "拿不到麦克风输入（格式 \(inFormat.sampleRate)Hz/"
                    + "\(inFormat.channelCount)ch）" + Voice.context(rung: usedRung))))
        }
        // 目标格式：16k 单声道 Int16。用转换器把麦克风原始格式转过来。
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                            sampleRate: Voice.SAMPLE_RATE,
                                            channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            return onWav(.failure(Failure(stage: .engine, detail: "建不了音频转换器")))
        }

        node.removeTap(onBus: 0)
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
            guard let ch = out.int16ChannelData, out.frameLength > 0 else { return }
            let n = Int(out.frameLength)
            self.pcm.append(UnsafeBufferPointer(start: ch[0], count: n)
                .withMemoryRebound(to: UInt8.self) { Data($0) })

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
                    + "输入 \(Int(inFormat.sampleRate))Hz/"
                    + "\(inFormat.channelCount)ch\n"
                    + Voice.context(rung: usedRung))))
        }

        running = true
        self.onUtterance = onUtterance
        self.splitter = (onUtterance != nil) ? SilenceSplitter() : nil
        // 到总上限自动停。
        // 🚨 连续模式用整场上限，不是单句的 60 秒 ——
        //    照用 MAX_DURATION 的话，说到第 60 秒会被无声掐掉。
        capTimer = Timer.scheduledTimer(
            withTimeInterval: onUtterance != nil ? Voice.MAX_CONTINUOUS
                                                : Voice.MAX_DURATION,
            repeats: false) { [weak self] _ in self?.stop() }
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
    private func cut() {
        let data = pcm
        pcm = Data()
        guard data.count >= Int(Voice.SAMPLE_RATE) / 2 else { return }
        let wav = Voice.wrapWav(pcm: data, sampleRate: Int(Voice.SAMPLE_RATE))
        let cb = onUtterance
        DispatchQueue.main.async { cb?(wav) }
    }

    // MARK: - 停止

    func stop() {
        guard running, !finished else { return }
        finished = true
        capTimer?.invalidate(); capTimer = nil

        let data = pcm
        // 🚨 连续模式下末尾这一段**可能只是静音**（刚切完一句才按的停止）。
        //    照发的话后端返回空结果，白花一次调用还闪一条空气泡。
        //    `hasVoice` 就是为这一刻写的 —— 它不是装饰。
        let tailWorth = splitter.map { $0.hasVoice } ?? true
        let wasContinuous = onUtterance != nil
        onUtterance = nil
        splitter = nil
        cleanup()

        if wasContinuous && !tailWorth {
            // 正常收尾，不是错 —— 界面不该报"没听清"
            onWav?(.success(Data()))
            onWav = nil; onPartial = nil
            return
        }
        // 太短 = 没说话（不足约 0.5 秒）
        if data.count < Int(Voice.SAMPLE_RATE) {
            onWav?(.failure(Failure(stage: .none, detail: "没听清，再说一次")))
            onWav = nil; onPartial = nil
            return
        }
        onWav?(.success(Voice.wrapWav(pcm: data, sampleRate: Int(Voice.SAMPLE_RATE))))
        onWav = nil; onPartial = nil
    }

    private func cleanup() {
        running = false
        capTimer?.invalidate(); capTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
