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

    private let engine = AVAudioEngine()
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

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            let ns = error as NSError
            return onWav(.failure(Failure(stage: .audioSession, detail: "code \(ns.code)")))
        }

        let node = engine.inputNode
        let inFormat = node.outputFormat(forBus: 0)
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
            return onWav(.failure(Failure(stage: .engine, detail: error.localizedDescription)))
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
