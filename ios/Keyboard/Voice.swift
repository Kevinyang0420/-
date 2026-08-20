import Foundation
import AVFoundation
import Speech

/// 键盘里的语音输入。
///
/// 🚨 2026-08-20 修正：我一度断言「iOS 键盘扩展拿不到麦克风」——**错的**。
///    Typeless 就是键盘扩展，麦克风就在键盘里。我引的是 Apple 那份 iOS 8 时代的
///    存档文档，没验证它还成不成立。
///
/// 但确实有个真实约束：在键盘进程里直接激活 AVAudioSession 有时会失败
///    （Apple 论坛 561015905 / 561145187）。已上架产品普遍用「键盘出 UI、
///    容器 App 录音、App Group 回传」的拆分架构兜底。
///    所以这里两条都实现：先就地录，失败了明确报出来，再走容器 App 那条。
///
/// 判据：失败必须**说清是哪一步**，不许只说"识别失败" —— 他不做 debug，
///      我要靠他截的那一屏定位。
final class Voice: NSObject {

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
        var description: String {
            stage == .none ? detail : "\(stage.rawValue)：\(detail)"
        }
    }

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))

    private(set) var running = false

    /// 一次性把两个权限要齐。键盘扩展里弹不出系统权限框，
    /// 所以容器 App 必须先要过一次 —— 这里只读状态，没授权就明说去 App 里给。
    static func permissionState() -> Failure? {
        if SFSpeechRecognizer.authorizationStatus() != .authorized {
            return Failure(stage: .permissionSpeech, detail: "去「说英文」App 里授权一次")
        }
        if AVAudioSession.sharedInstance().recordPermission != .granted {
            return Failure(stage: .permissionMic, detail: "去「说英文」App 里授权一次")
        }
        return nil
    }

    func start(onPartial: @escaping (String) -> Void,
               onDone: @escaping (Result<String, Failure>) -> Void) {
        if let p = Voice.permissionState() { return onDone(.failure(p)) }
        guard let rec = recognizer, rec.isAvailable else {
            return onDone(.failure(Failure(stage: .recognizer, detail: "中文识别器当前不可用")))
        }

        let session = AVAudioSession.sharedInstance()
        do {
            // 🚨 键盘进程里这一步最容易炸。炸了要原样把 code 报出来，别吞。
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            let ns = error as NSError
            return onDone(.failure(Failure(stage: .audioSession,
                                           detail: "code \(ns.code) —— 键盘里开不了录音，要走 App 兜底")))
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let node = engine.inputNode
        let fmt = node.outputFormat(forBus: 0)
        node.removeTap(onBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buf, _ in
            req.append(buf)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            cleanup()
            return onDone(.failure(Failure(stage: .engine, detail: error.localizedDescription)))
        }
        running = true

        var latest = ""
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            if let r = result {
                latest = r.bestTranscription.formattedString
                onPartial(latest)
                if r.isFinal {
                    self?.cleanup()
                    onDone(.success(latest))
                }
            }
            if error != nil {
                self?.cleanup()
                // 已经听到东西就按成功算 —— 停止时报错是常态，别把内容丢了
                if latest.isEmpty {
                    onDone(.failure(Failure(stage: .none, detail: "没听清，再说一次")))
                } else {
                    onDone(.success(latest))
                }
            }
        }
    }

    func stop() {
        request?.endAudio()
    }

    private func cleanup() {
        running = false
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
