import AVFoundation
import AVKit
import UIKit

/// PiP 保活 · **第三轮：换 `AVPlayerLayer` + 运行时生成的小视频**。
///
/// ## 前两轮为什么放弃
///
/// 用 `AVSampleBufferDisplayLayer` 那条（见 `PipKeepAlive.swift`）实测三次：
///
/// ```
/// 14:28:23  自动进入（帧没喂上）                    → -1001
/// 14:31:12  possible=true 时手动请求                 → -1001
/// 14:39:31  场景=前台活跃、possible=true 时手动请求   → -1001  ← 🚨
/// ```
///
/// 🚨 **第三次最关键**：论坛查到 `-1001` 的官方成因是
/// 「场景不是 `foregroundActive`」，**我们把这个条件满足了，照样 -1001。**
/// 而搜索结果里正好有一句对得上：
/// > *Some developers report that even when logging the activationState as
/// >  `UISceneActivationStateForegroundActive`, PiP still fails to start.*
///
/// → **我们落在那个"已知但没解释"的桶里**，继续在 sample buffer 上调是碰运气。
///
/// 同一批资料还写着：
/// > *PiP mode works without issues when using `AVPlayerViewController` /
/// >  `AVPlayerLayer`, instead of a custom `AVPictureInPictureController` setup.*
/// 以及 sample-buffer 那条有已知缺陷（`PGPegasusErrorDomain -1003`、
/// iOS 15 上第二次进 PiP 失败）。
///
/// **所以第三轮换成官方最常走的那条：`AVPlayerLayer`。**
///
/// ## 🚨 视频**运行时生成**，不进包
///
/// 用 `AVAssetWriter` 写一段 1 秒的纯黑无声视频到 tmp，循环播放。
/// 这样**不需要任何资源文件** —— 今晚已经在"资源没进包"这类坑上栽过
/// （码表、图标、Secrets），少一个资源就少一处。
///
/// ## 🚨 判据没变
///
/// **PiP 起来了 ≠ 成功。** 成功的判据始终是
/// **宿主在后台时拿到非静音 PCM**（判词 `[宿主] OK` + 峰值 > 0.08）。
@available(iOS 15.0, *)
final class PipPlayerKeepAlive: NSObject {

    static let shared = PipPlayerKeepAlive()

    static var enabled: Bool {
        ProcessInfo.processInfo.environment["TRANSLESS_PIP2"] == "1"
            || KbBridge.flag("pip2")
    }

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var layer: AVPlayerLayer?
    private var pip: AVPictureInPictureController?

    private var obs: NSKeyValueObservation?
    private var obsReady: NSKeyValueObservation?
    private var box: PlayerBox?
    private var bgObs: NSObjectProtocol?

    /// 🚨 **在「即将进后台」那一刻再请求一次。**
    ///    iPhone 上前台调 `startPictureInPicture()` 常被静默忽略（今天正是这个现象：
    ///    调了、possible=true、**三个回调一个都没来**）。
    ///    画中画真正的时机是「App 要走了」，所以在那一刻再试一次。
    func armBackgroundRetry() {
        guard bgObs == nil else { return }
        bgObs = NotificationCenter.default.addObserver(
            // 🚨 用 `didEnterBackground` 而不是 `willResignActive`：
            //    后者是**转场进行中**，场景已经不是 foregroundActive，
            //    实测报 `-1001 AVKitErrorDomain`（不合格）。
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self = self, let c = self.pip,
                  !c.isPictureInPictureActive else { return }
            KbBridge.note("PiP2：App 要进后台了，再请求一次进入")
            self.player?.play()
            c.startPictureInPicture()
        }
    }

    private override init() { super.init() }

    func arm(on host: UIView) {
        guard PipPlayerKeepAlive.enabled else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            KbBridge.note("PiP2：设备不支持")
            return
        }
        makeVideo { [weak self] url in
            guard let self = self, let url = url else {
                KbBridge.note("PiP2：视频没生成出来")
                return
            }
            // 🚨🚨 **画中画要求 App 有一个「正在播放」的音频会话**，否则
            //    `isPictureInPicturePossible` 永远是 false —— 2026-08-29 真机
            //    12 秒都进不去，就是卡在这。**光有视频不够，得有播放身份。**
            // 🚨 `.mixWithOthers`：不许打断他正在听的东西。
            do {
                let sess = AVAudioSession.sharedInstance()
                try sess.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try sess.setActive(true)
                KbBridge.note("PiP2：音频会话已就位（playback + 不打断别人）")
            } catch {
                KbBridge.note("PiP2：音频会话设不上 —— " + error.localizedDescription)
            }
            let item = AVPlayerItem(url: url)
            let q = AVQueuePlayer()
            // 🚨 静音：这段视频只为占住"正在播视频"这个身份，不该发出声音，
            //    也不该抢走他正在听的东西。
            // 🚨 用 `volume = 0` 而不是 `isMuted` —— 静音标记有可能让 iOS
            //    不把它当成「正在播放媒体」，从而拒绝画中画。
            //    音量 0 一样听不见，但身份还是"在放"。
            q.volume = 0
            self.looper = AVPlayerLooper(player: q, templateItem: item)
            // 🚨🚨 **「装进 UIView」那一版当场崩溃，已撤。**
            //    2026-08-29 15:09 真机：装上后 App 起来两秒就没了（进程数 0），
            //    痕迹停在「音频会话已就位」，`已挂上` 那行都没打出来。
            //    **而我是把它装到 Kevin 手机上之后才发现的** —— 顺序错了：
            //    这种结构性改动应当先在模拟器上跑一次再上真机。
            //    退回原来的写法（裸 `AVPlayerLayer` 挂在 window 上），它至少不崩。
            let l = AVPlayerLayer(player: q)
            l.frame = CGRect(x: 0, y: 0, width: 240, height: 135)
            l.opacity = 0.02
            host.layer.addSublayer(l)
            // 🚨 图层放大到接近整屏：太小的图层 iOS 可能不认。
            //    它是纯黑的、盖在最底下，用户看不见（上面有正常界面）。
            // 🚨 **放最上面，别塞到最底层。** 上一版我 `insertSublayer(at: 0)`，
            //    图层被整个界面盖住 —— iOS 很可能因此判定它「不可见」而拒绝画中画。
            //    现在放最上面但**几乎全透明**：系统看得见、他看不见。
            //    尺寸也给足（太小的图层也有被拒的报告）。
            l.videoGravity = .resizeAspect
            self.player = q
            self.layer = l
            q.play()

            guard let c = AVPictureInPictureController(playerLayer: l) else {
                KbBridge.note("PiP2：控制器建不出来")
                return
            }
            c.delegate = self
            // 🚨 **改成 false 试一次。** 开着自动模式时，前台手动
            //    `startPictureInPicture()` 有被静默忽略的报告 ——
            //    而"调了、possible=true、三个回调一个都不来"正是这个形状。
            //    （`TRANSLESS_PIPAUTO=1` 可以切回自动，方便对照。）
            c.canStartPictureInPictureAutomaticallyFromInline =
                ProcessInfo.processInfo.environment["TRANSLESS_PIPAUTO"] == "1"
            self.pip = c
            KbBridge.note("PiP2：已挂上｜图层就绪=" + String(l.isReadyForDisplay)
                          + " 速率=" + String(q.rate))
            self.armBackgroundRetry()
            // 图层就绪也要盯着 —— 它比 possible 晚，晚的那个才是真正的发令枪。
            self.obsReady = l.observe(\.isReadyForDisplay, options: [.new, .initial]) {
                [weak self] lay, _ in
                guard lay.isReadyForDisplay else { return }
                KbBridge.note("PiP2：图层第一帧就绪了")
                self?.start()
            }
            // 🚨🚨 **等它真的「可以进」了再进，别按固定秒数猜。**
            //    2026-08-29 真机：3 秒后请求，`possible=false` → 直接失败。
            //    `isPictureInPicturePossible` 要等播放器把第一帧准备好才变 true，
            //    **这个时间不固定**，按秒数等就是在赌。
            // 🚨 **必须带 `.initial`**：注册的时候它可能**已经**是 true 了，
            //    只订「变化」就永远收不到 —— 2026-08-29 真机就是这样：
            //    `possible=true` 却一次回调都没有。
            //    **「只订变化」漏掉「注册前已经成立」，是同一族的老坑。**
            self.obs = c.observe(\.isPictureInPicturePossible,
                                 options: [.new, .initial]) {
                [weak self] ctl, _ in
                guard let self = self, ctl.isPictureInPicturePossible,
                      !ctl.isPictureInPictureActive else { return }
                KbBridge.note("PiP2：现在可以进了，请求进入")
                self.start()
            }
            // 🚨 兜底：一直没变成 true 也要出声，**别静默地什么都不发生**
            //    —— 那正是今天反复栽的那一类。
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
                guard let self = self, let c = self.pip else { return }
                if !c.isPictureInPictureActive {
                    KbBridge.note("PiP2：12 秒还进不去（possible="
                                  + String(c.isPictureInPicturePossible)
                                  + "）—— 这条路在这台机上不成立")
                }
            }
        }
    }

    private func start() {
        guard let c = pip, !c.isPictureInPictureActive else { return }
        // 🚨🚨 **两个条件都要满足**：`possible=true` **且** 图层第一帧已就绪。
        //    2026-08-29 真机：`possible=true` 但 `isReadyForDisplay=false` 时请求，
        //    **三个回调一个都不来** —— 调用被系统直接吞掉。
        //    「可以进」和「画面准备好了」是两件事，我把它们当成了一件。
        guard layer?.isReadyForDisplay == true else {
            KbBridge.note("PiP2：先等图层出第一帧（现在还没就绪），不急着请求")
            return
        }
        let active = UIApplication.shared.connectedScenes.contains {
            $0.activationState == .foregroundActive
        }
        KbBridge.note("PiP2：请求进入（场景前台=\(active) possible=\(c.isPictureInPicturePossible)）")
        c.startPictureInPicture()
        // 🚨 调完立刻回读一次 —— 分开「调用没被受理」和「受理了还没生效」。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            KbBridge.note("PiP2：调用后 0.6 秒｜已进入=" + String(c.isPictureInPictureActive)
                          + " 可进入=" + String(c.isPictureInPicturePossible)
                          + " 播放速率=" + String(describing: self.player?.rate ?? -1))
        }
    }

    /// 用 `AVAssetWriter` 现写一段 1 秒纯黑视频。**不进包、不依赖任何素材。**
    private func makeVideo(_ done: @escaping (URL?) -> Void) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipkeep.mp4")
        try? FileManager.default.removeItem(at: url)
        guard let w = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            return done(nil)
        }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 160, AVVideoHeightKey: 90,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard w.canAdd(input) else { return done(nil) }
        w.add(input)
        w.startWriting()
        w.startSession(atSourceTime: .zero)

        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 160, 90, kCVPixelFormatType_32BGRA, nil, &pb)
        guard let buf = pb else { return done(nil) }
        // 30 帧 = 1 秒
        for i in 0..<30 {
            while !input.isReadyForMoreMediaData { usleep(2000) }
            adaptor.append(buf, withPresentationTime:
                CMTime(value: CMTimeValue(i), timescale: 30))
        }
        input.markAsFinished()
        w.finishWriting {
            // 🚨 判据是**文件真的写出来了且非空**，不是 `finishWriting` 回调被调用。
            let n = (try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            KbBridge.note("PiP2：视频写完 \(n ?? 0) 字节")
            done((n ?? 0) > 0 ? url : nil)
        }
    }
}

@available(iOS 15.0, *)
extension PipPlayerKeepAlive: AVPictureInPictureControllerDelegate {
    /// 🚨 **把「要开始了」也打出来。** 只记 did/failed 的话，
    ///    「请求了但系统压根没受理」和「受理了但失败」长得一模一样 ——
    ///    今天就卡在这：调用之后**两个回调一个都没来**，等于什么都不知道。
    func pictureInPictureControllerWillStartPictureInPicture(
        _ c: AVPictureInPictureController) {
        KbBridge.note("PiP2：系统受理了，即将进入")
    }

    func pictureInPictureControllerDidStartPictureInPicture(
        _ c: AVPictureInPictureController) {
        KbBridge.note("PiP2：已进入 ✅")
    }
    func pictureInPictureController(
        _ c: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error) {
        let e = error as NSError
        KbBridge.note("PiP2：进不去 —— \(e.code) \(e.domain)")
    }
}

/// 一个「本体就是播放层」的视图 —— 苹果示例的标准写法。
final class PlayerBox: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
