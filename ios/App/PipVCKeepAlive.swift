import AVFoundation
import AVKit
import UIKit

/// PiP 保活 · **第四轮：用 `AVPlayerViewController`**（`TRANSLESS_PIP3=1`）。
///
/// 🚨🚨 前三轮全部自建 `AVPictureInPictureController`，全部卡在同一堵墙：
/// ```
/// possible=true、图层第一帧就绪、startPictureInPicture() 调了
///   → will/did/failed 三个回调一个都不来（前台）
///   → 在退后台时调则 -1001 AVKitErrorDomain
/// ```
/// 而**我们自己 2026-08-28 那份调研里就引了苹果社区的原话**：
/// > *PiP mode works without issues when using `AVPlayerViewController` /
/// >  `AVPlayerLayer`, **instead of a custom `AVPictureInPictureController` setup**.*
///
/// **这一条摆在那儿两周，四轮都没试。** 这轮就试它。
///
/// 🚨 为什么非要 PiP：苹果 DTS 明说**没有 API 能把宿主 App 切回前台**，
///    所以"跳过去再切回来"是死路。PiP 让主 App 在后台仍算"可见"，
///    **需要时才开麦**（Typeless 发布说明原话：「仅在您说话时开启麦克风」）——
///    既不用跳，也不用一直开着麦克风（Kevin 明确否掉常开麦）。
///
/// 🚨 判据不是「PiP 起来了」，是**宿主在后台时能拿到非静音 PCM**。
///    起来了只是必要条件。
@available(iOS 15.0, *)
final class PipVCKeepAlive: NSObject {

    static let shared = PipVCKeepAlive()

    /// 🚨 **默认开。** Kevin 2026-08-29 认可这个形态：
    ///    「做成一个小窗…隐藏在后台或者角落里…尽量做小、做透明」。
    ///    `TRANSLESS_NOPIP=1` 可以临时关掉（排查用）。
    /// 🚨🚨 **改回默认关（2026-08-29 止血）。**
    ///    默认开之后 Kevin 连撞两次「打开 Transless 就卡死」——
    ///    第一次是我把生成视频的忙等放在主线程（已修），**第二次仍然卡**，
    ///    说明还有第二个原因没找到。
    ///    **在没找到之前不许默认开** —— 他的 App 能用比这个功能重要。
    ///    我自己测的时候用 `TRANSLESS_PIP3=1` 打开。
    /// 🚨 **默认开**（2026-08-29 二次开启，这次是验过的）：
    ///    完整链路真机跑通 —— 打开 App → 切走一次 → 小窗常驻 →
    ///    **后台起录成功（12 帧）** → 录完小窗还在。
    ///    之前那次默认开是我冒进（主线程忙等把界面冻住），已修并复现不出来了。
    ///    `TRANSLESS_NOPIP=1` 可临时关掉。
    /// 🚨🚨🚨 **默认关（2026-08-29 第二次关，这次是他被卡进死循环）。**
    ///
    /// 他实测：键盘提示「Transless 被系统关掉了」→ 打开 App →
    /// **界面卡住出不来**、右上角画中画一直在转 → 回微信又是同一句提示 → 死循环。
    ///
    /// 🚨 我两次把它默认开、两次把他坑住。**在没有一次完整的、他不在场的
    ///    真机长跑验证之前，不许再默认开。**
    ///    我自己测用 `TRANSLESS_PIP3=1`。
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["TRANSLESS_PIP3"] == "1"
            || KbBridge.flag("pip3")
    }

    private var vc: AVPlayerViewController?
    private var looper: AVPlayerLooper?
    private var player: AVQueuePlayer?
    /// 🚨 `AVPlayerViewController` **没有** `isPictureInPictureActive` 这个属性
    ///    （那是 `AVPictureInPictureController` 才有的）——自己按代理回调记。
    private(set) var pipActive = false
    /// 播放器挂上了没有（还没进小窗，但已经可以被系统接管）。
    static var armed: Bool { shared.vc != nil }
    /// 播放器真的在播（速率 > 0）—— 画中画要接管的前提。
    static var playing: Bool { (shared.player?.rate ?? 0) > 0 }
    private var beat: Timer?
    private var arming = false

    private override init() { super.init() }

    func arm(on host: UIViewController) {
        guard PipVCKeepAlive.enabled else { return }
        // 🚨 幂等：每次回前台都会调，已经挂上就别重复建播放器。
        if vc != nil { return }
        if arming { return }
        arming = true
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            KbBridge.note("PiP3：设备不支持")
            return
        }
        makeVideo { [weak self] url in
            guard let self = self, let url = url else {
                KbBridge.note("PiP3：视频没生成出来")
                self?.arming = false
                return
            }
            // 🚨 会话必须先立起来 —— 第三轮实测这是 `possible` 从 false 变 true 的卡点。
            // 🚨🚨 2026-09-03 Kevin 撞到「点录音显示准备中就卡死」——根因就在这三行：
            //    原来写死 `.playback`，而 **`.playback` 不具备录音能力** → 画中画一挂上就把会话降级，
            //    之后键盘/宿主要录音时会话已经不能录（痕迹：`音频会话设不上 561017449` + 他那句卡死）。
            //    而我们的 PiP 视频**本来就是无声的**（只有视频轨、`volume=0`），根本不需要独占音频。
            //    → 铁律：**绝不把一个「能录」的会话降级成「只播」**。
            //      已经是 record/playAndRecord 就原样不动；否则设 `.playAndRecord`（能播也能录）。
            do {
                let s = AVAudioSession.sharedInstance()
                let cur = s.category
                if cur == .record || cur == .playAndRecord {
                    KbBridge.note("PiP3：会话已是可录档（" + cur.rawValue + "），不动它")
                    if !s.isOtherAudioPlaying { try? s.setActive(true) }
                    // 🚨 这一支是「会话已经是可录档，不动它」——
                    //    但"不动类别"不等于"路由是对的"：上一轮可能就落在听筒上。
                    Voice.fixReceiverRoute(s)
                } else {
                    try s.setCategory(.playAndRecord, mode: .default,
                                      options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
                    try s.setActive(true)
                    Voice.fixReceiverRoute(s)
                    KbBridge.note("PiP3：会话设成 playAndRecord（可播可录，不挡录音）")
                }
            } catch {
                KbBridge.note("PiP3：音频会话设不上 " + error.localizedDescription
                              + "｜当前档=" + AVAudioSession.sharedInstance().category.rawValue)
            }
            let q = AVQueuePlayer()
            q.volume = 0
            self.looper = AVPlayerLooper(player: q, templateItem: AVPlayerItem(url: url))
            self.player = q

            let v = AVPlayerViewController()
            v.player = q
            v.allowsPictureInPicturePlayback = true
            v.canStartPictureInPictureAutomaticallyFromInline = true
            v.showsPlaybackControls = false
            v.delegate = self
            // 🚨 必须真的进视图层级、真的有尺寸；几乎全透明，他看不见。
            v.view.frame = CGRect(x: 0, y: 0, width: 240, height: 135)
            v.view.alpha = 0.02
            v.view.isUserInteractionEnabled = false
            host.addChild(v)
            host.view.addSubview(v.view)
            v.didMove(toParent: host)
            self.vc = v
            self.arming = false
            q.play()
            KbBridge.note("PiP3：已挂上（AVPlayerViewController 路线）")
        }
    }

    /// **按需把小窗叫出来 / 收回去。**
    ///
    /// 🚨 Kevin 2026-08-29 定的形态：「小窗做小、做透明，**只在录音时浮出来，
    ///    说完就收回去**」。所以不能让它一直挂着 ——
    ///    但这要求「App 已经在后台时还能临时进画中画」，
    ///    **这一条没验过**，先做出来测。验不过就退回"一直挂着但极小极透明"。
    func showNow() {
        guard let v = vc else { KbBridge.note("PiP3：还没挂上，开不了小窗"); return }
        player?.play()
        if pipActive { KbBridge.note("PiP3：小窗本来就开着"); return }
        KbBridge.note("PiP3：请求把小窗叫出来（此刻 App="
                      + (UIApplication.shared.applicationState == .active ? "前台" : "后台") + "）")
        v.perform(NSSelectorFromString("startPictureInPicture"))
    }

    func hideNow() {
        guard let v = vc, pipActive else { return }
        KbBridge.note("PiP3：收回小窗")
        v.perform(NSSelectorFromString("stopPictureInPicture"))
    }

    /// 生成一段 1 秒纯黑视频（不进包，跟第三轮同一个做法）。
    /// 🚨🚨🚨 **必须离开主线程。**
    ///
    /// 2026-08-29 事故：这个函数里有 `while !input.isReadyForMoreMediaData { usleep }`
    /// 的忙等，而 `arm(on:)` 是在主队列上调它的 —— **界面被整个冻住**。
    /// Kevin 当场撞到：「点了之后主 App 跳出来，半天没有反应，卡死在这里了」。
    /// 以前这段代码在（第三轮里同样写法），但那条是**默认关**的，从没跑过；
    /// 我今天把画中画设成默认开，**每次启动都撞**。
    /// 🚨 「这段代码一直都在」不等于「它被跑过」—— 又一次范围错。
    private func makeVideo(_ done: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .utility).async { self.makeVideoOnWorker(done) }
    }

    private func makeVideoOnWorker(_ done: @escaping (URL?) -> Void) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipkeep3.mp4")
        try? FileManager.default.removeItem(at: url)
        guard let w = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            return done(nil)
        }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 160, AVVideoHeightKey: 90,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input, sourcePixelBufferAttributes: nil)
        input.expectsMediaDataInRealTime = false
        w.add(input)
        w.startWriting()
        w.startSession(atSourceTime: .zero)
        var buf: CVPixelBuffer?
        CVPixelBufferCreate(nil, 160, 90, kCVPixelFormatType_32ARGB, nil, &buf)
        if let b = buf {
            CVPixelBufferLockBaseAddress(b, [])
            memset(CVPixelBufferGetBaseAddress(b), 0,
                   CVPixelBufferGetDataSize(b))
            CVPixelBufferUnlockBaseAddress(b, [])
            for i in 0..<30 {
                while !input.isReadyForMoreMediaData { usleep(2000) }
                adaptor.append(b, withPresentationTime:
                    CMTime(value: CMTimeValue(i), timescale: 30))
            }
        }
        input.markAsFinished()
        w.finishWriting {
            let n = (try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            KbBridge.note("PiP3：视频写完 \(n ?? 0) 字节")
            DispatchQueue.main.async { done(url) }
        }
    }
}

@available(iOS 15.0, *)
extension PipVCKeepAlive: AVPlayerViewControllerDelegate {
    func playerViewControllerWillStartPictureInPicture(
        _ c: AVPlayerViewController) {
        KbBridge.note("PiP3：系统受理了，即将进入")
    }
    func playerViewControllerDidStartPictureInPicture(
        _ c: AVPlayerViewController) {
        pipActive = true
        KbBridge.markPip(true)
        beat?.invalidate()
        beat = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] t in
            guard let self = self, self.pipActive else { t.invalidate(); return }
            KbBridge.markPip(true)
            // 🚨 **录音会切换音频会话，播放会被打断而不自己恢复。**
            //    播放一停，iOS 就把画中画收掉 —— 实测：第一次录完小窗还在，
            //    **第二次录完就没了**。心跳里把它续上，代价是一次空调用。
            if (self.player?.rate ?? 0) == 0 {
                self.player?.play()
                KbBridge.note("PiP3：播放被打断了，已续上（不然小窗会被系统收走）")
            }
        }
        KbBridge.note("PiP3：已进入 ✅（键盘从现在起不用跳转）")
    }
    func playerViewControllerDidStopPictureInPicture(_ c: AVPlayerViewController) {
        pipActive = false
        beat?.invalidate()
        KbBridge.markPip(false)
        KbBridge.note("PiP3：小窗已收回")
    }

    func playerViewController(_ c: AVPlayerViewController,
                              failedToStartPictureInPictureWithError e: Error) {
        let ns = e as NSError
        KbBridge.note("PiP3：进不去 —— \(ns.code) \(ns.domain)")
    }
}
