import Foundation
import AVFoundation
import Speech

/// 键盘里的语音输入，**支持长时间连续说**（默认上限 15 分钟）。
///
/// 🚨 核心约束：iOS 的 `SFSpeechRecognizer` 单次识别任务**只能撑约 1 分钟**，
///    到点它自己就 isFinal 结束了。想说 10–15 分钟，只有一条路：
///    **音频引擎一直开着，识别任务定期滚动重启，把每段定稿的文字累加起来。**
///    这就是下面 ROTATE_AFTER 的用途 —— 不是优化，是唯一能做到的做法。
///
/// 🚨 2026-08-20 修正：我一度断言「iOS 键盘扩展拿不到麦克风」——错的。
///    Typeless 就是键盘扩展、麦克风就在键盘里。我引的是 iOS 8 时代的存档文档。
///
/// 但键盘进程里激活 AVAudioSession 确实可能失败（Apple 论坛 561015905 / 561145187），
/// 所以失败时必须**说清卡在哪一步**，好让他截图定位、并改走不依赖录音的兜底。
final class Voice: NSObject {

    /// 单段识别多久滚动一次。留足余量 —— Apple 的硬上限在 60 秒附近。
    private static let ROTATE_AFTER: TimeInterval = 45
    /// 总时长上限。Typeless 大约是 15 分钟，跟它对齐。
    static let MAX_DURATION: TimeInterval = 15 * 60

    enum Stage: String {
        case permissionSpeech = "语音识别权限"
        case permissionMic = "麦克风权限"
        case audioSession = "音频会话(键盘进程内)"
        case recognizer = "识别器不可用"
        case engine = "录音引擎"
        case none = ""
    }

    struct Failure: Error, CustomStringConvertible {
        let stage: Stage
        let detail: String
        var description: String { stage == .none ? detail : "\(stage.rawValue)：\(detail)" }
    }

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var rotateTimer: Timer?
    private var startedAt = Date()

    /// 已经定稿的部分（前面几段滚动出来的）
    private var settled = ""
    /// 当前这一段的实时文本
    private var current = ""

    private var onPartial: ((String) -> Void)?
    private var onDone: ((Result<String, Failure>) -> Void)?
    private var finished = false

    private(set) var running = false

    /// 说了多久，给界面显示用
    var elapsed: TimeInterval { running ? Date().timeIntervalSince(startedAt) : 0 }

    private var combined: String {
        let c = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if settled.isEmpty { return c }
        if c.isEmpty { return settled }
        return settled + c
    }

    static func permissionState() -> Failure? {
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            return Failure(stage: .permissionSpeech, detail: "去 Transless App 里授权一次")
        }
        if AVAudioSession.sharedInstance().recordPermission != .granted {
            return Failure(stage: .permissionMic, detail: "去 Transless App 里授权一次")
        }
        return nil
    }

    // MARK: - 开始

    func start(onPartial: @escaping (String) -> Void,
               onDone: @escaping (Result<String, Failure>) -> Void) {
        if let p = Voice.permissionState() { return onDone(.failure(p)) }
        guard let rec = recognizer, rec.isAvailable else {
            return onDone(.failure(Failure(stage: .recognizer, detail: "中文识别器当前不可用")))
        }

        self.onPartial = onPartial
        self.onDone = onDone
        settled = ""; current = ""; finished = false
        startedAt = Date()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            let ns = error as NSError
            return onDone(.failure(Failure(stage: .audioSession,
                detail: "code \(ns.code) —— 键盘里开不了录音，改走「译光标前的中文」")))
        }

        // 音频引擎只开这一次，之后一直跑；滚动的只是识别任务。
        let node = engine.inputNode
        let fmt = node.outputFormat(forBus: 0)
        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buf, _ in
            self?.request?.append(buf)
        }
        engine.prepare()
        do { try engine.start() }
        catch {
            cleanup()
            return onDone(.failure(Failure(stage: .engine, detail: error.localizedDescription)))
        }

        running = true
        startTask()
        startRotateTimer()
    }

    /// 开一段新的识别任务。前一段的文字已经并进 settled 了。
    private func startTask() {
        guard let rec = recognizer else { return }
        current = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        task = rec.recognitionTask(with: req) { [weak self] result, error in
            guard let self = self, self.running else { return }
            if let r = result {
                self.current = r.bestTranscription.formattedString
                self.onPartial?(self.combined)
                if r.isFinal {
                    // 这一段收了：并进 settled。如果是用户主动停的，就整体结束；
                    // 否则说明撞到了 Apple 的时长上限，自动接一段继续。
                    self.settleCurrent()
                    if self.finished { self.finish(.success(self.settled)) }
                    else { self.startTask() }
                }
            }
            if error != nil {
                self.settleCurrent()
                if self.finished || !self.settled.isEmpty {
                    // 已经听到东西就按成功算 —— 停止时报错是常态，别把内容丢了
                    self.finish(self.settled.isEmpty
                        ? .failure(Failure(stage: .none, detail: "没听清，再说一次"))
                        : .success(self.settled))
                } else {
                    self.finish(.failure(Failure(stage: .none, detail: "没听清，再说一次")))
                }
            }
        }
    }

    private func settleCurrent() {
        let c = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !c.isEmpty {
            if !settled.isEmpty && !settled.hasSuffix("，") && !settled.hasSuffix("。") {
                settled += "，"        // 段与段之间补个停顿，免得两段黏成一个词
            }
            settled += c
        }
        current = ""
    }

    /// 到点把当前这段收掉，让 isFinal 触发，然后自动接下一段。
    private func startRotateTimer() {
        rotateTimer?.invalidate()
        rotateTimer = Timer.scheduledTimer(withTimeInterval: Voice.ROTATE_AFTER, repeats: true) {
            [weak self] _ in
            guard let self = self, self.running, !self.finished else { return }
            if Date().timeIntervalSince(self.startedAt) >= Voice.MAX_DURATION {
                self.stop()                      // 到 15 分钟总上限，收工
            } else {
                self.request?.endAudio()         // 只收当前这段，engine 继续跑
            }
        }
    }

    // MARK: - 停止

    func stop() {
        guard running, !finished else { return }
        finished = true
        request?.endAudio()
    }

    private func finish(_ r: Result<String, Failure>) {
        guard running else { return }
        cleanup()
        onDone?(r)
        onDone = nil
        onPartial = nil
    }

    private func cleanup() {
        running = false
        rotateTimer?.invalidate(); rotateTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
