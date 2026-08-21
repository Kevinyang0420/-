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
    func start(onPartial: @escaping (String) -> Void,
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
            if let ch = out.int16ChannelData, out.frameLength > 0 {
                self.pcm.append(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength))
                    .withMemoryRebound(to: UInt8.self) { Data($0) })
            }
        }
        engine.prepare()
        do { try engine.start() }
        catch {
            cleanup()
            return onWav(.failure(Failure(stage: .engine, detail: error.localizedDescription)))
        }

        running = true
        // 到总上限自动停
        capTimer = Timer.scheduledTimer(withTimeInterval: Voice.MAX_DURATION, repeats: false) {
            [weak self] _ in self?.stop()
        }
        // 每秒推一次计时给界面
        DispatchQueue.main.async { [weak self] in self?.tick() }
    }

    private func tick() {
        guard running, !finished else { return }
        onPartial?("")   // 界面自己按 elapsed 显示计时
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.tick() }
    }

    // MARK: - 停止

    func stop() {
        guard running, !finished else { return }
        finished = true
        capTimer?.invalidate(); capTimer = nil

        let data = pcm
        cleanup()

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
