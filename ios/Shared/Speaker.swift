import AVFoundation

/// 播放后端合成的 mp3（Andrew 的声音）。跟安卓 `Speaker.java` 一一对应。
///
/// 🚨 一次只放一段 —— 连点两下不能变成两个声音叠着。
/// 🚨 播放前要把音频会话切到 playback：录音那一步把它设成了 .record，
///    不切回来的话**一点声音都没有**，而且不报错（最难查的那种）。
enum Speaker {

    private static var player: AVAudioPlayer?

    static var isPlaying: Bool { player?.isPlaying ?? false }

    static func play(_ mp3: Data, done: @escaping (String?) -> Void) {
        stop()
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .spokenAudio, options: [])
            try s.setActive(true)
            let p = try AVAudioPlayer(data: mp3)
            p.delegate = Delegate.shared
            Delegate.shared.done = done
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            done(error.localizedDescription)
        }
    }

    static func stop() {
        player?.stop()
        player = nil
    }

    private final class Delegate: NSObject, AVAudioPlayerDelegate {
        static let shared = Delegate()
        var done: ((String?) -> Void)?
        func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully ok: Bool) {
            Speaker.player = nil
            done?(ok ? nil : "播放没完成")
            done = nil
        }
        func audioPlayerDecodeErrorDidOccur(_ p: AVAudioPlayer, error: Error?) {
            Speaker.player = nil
            done?(error?.localizedDescription ?? "解码失败")
            done = nil
        }
    }
}
