import AVFoundation
import AVKit
import UIKit

/// **画中画保活**：让宿主 App 在键盘弹出时仍然处于"不算后台"的位置。
///
/// ## 为什么做这个（三档实测逼出来的，不是拍脑袋）
///
/// 2026-08-28 夜，从 Kevin 手机上直接拉的原文：
///
/// | 场景 | 结果 |
/// |---|---|
/// | 键盘扩展自己录 | ❌ `2003329396`、`输入源 0 个`（**连按 5 次，一字不差**）|
/// | 宿主**前台** | ✅ 帧数 12、峰值 0.405（真人声）|
/// | 宿主**真后台** | ❌ `2003329396`、`输入源 0 个` |
///
/// 🚨 **关键签名**：`配置档1` + `输入 48000Hz/1ch` + `输入源 0 个` 同时成立 ——
///    **系统允许配置、允许激活、连格式都给，就是不把麦克风接进路由。**
///    **失败在"配置之后"，所以调配置永远调不到它。**
///
/// → **iOS 是按【进程状态】决定给不给输入路由的。**
///   而 PiP 改的正好是进程状态 —— 这是唯一还没试过、且直接冲着那一层去的手段。
///
/// ## 🚨 这条路的风险，写在最前面
///
/// **「PiP 能让宿主在后台拿到输入路由」目前没有任何直接证据。**
/// 它同样可能只让宿主自己好使，而**「键盘 → 宿主」那一跳照样不通**。
/// **所以先做最小验证，别先做完整方案** ——
/// 判据是：**开着 PiP、宿主在后台时，自检能不能拿到非静音 PCM**。
///
/// ## 为什么用 `AVSampleBufferDisplayLayer` 而不是播一个视频文件
///
/// 不需要任何素材：iOS 15+ 起 `AVPictureInPictureController` 支持
/// `contentSource:` 直接挂一个 sample buffer 层。
/// 少一个资源文件 = 少一处"资源没进包"的坑（今晚已经踩过码表、图片那类）。
@available(iOS 15.0, *)
final class PipKeepAlive: NSObject {

    static let shared = PipKeepAlive()

    /// 🚨 只认环境变量：真机上用户设不了（只有 `devicectl process launch -e` 能注入），
    ///    所以它**不会**影响发给他的包的行为 —— 这是个纯实验开关。
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["TRANSLESS_PIP"] == "1"
            || KbBridge.flag("pip")
    }

    private var layer: AVSampleBufferDisplayLayer?
    private var controller: AVPictureInPictureController?
    private var timer: Timer?

    private override init() { super.init() }

    /// 挂上 PiP。**失败要说清失败在哪一步**，别只报一句"没起来"。
    func arm(on host: UIView) {
        guard PipKeepAlive.enabled else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            KbBridge.note("PiP：这台设备不支持画中画")
            return
        }
        let l = AVSampleBufferDisplayLayer()
        // 🚨 4×4 太小、可能不被当成"在屏上的视频" —— PiP 要求内容真的在播且可见。
        //    120×80 是能被系统接受的最小实用尺寸；位置放在左上角、不挡操作。
        l.frame = CGRect(x: 8, y: 8, width: 120, height: 80)
        l.videoGravity = .resizeAspect
        host.layer.addSublayer(l)
        layer = l

        let src = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: l, playbackDelegate: self)
        let c = AVPictureInPictureController(contentSource: src)
        c.delegate = self
        // 🚨 必须允许自动进入 —— 我们要的正是"切走时自动进 PiP"。
        controller = c
        // 🚨 **不许自动进入**：自动那次会在帧还没喂上时就触发，
        //    实测直接 `-1001`，而且它的失败会先于我的显式请求，
        //    把日志顺序搅乱（14:28:23 先失败、再"请求进入"）。
        // 🚨🚨 **改回自动进入，并且不再手动调 。**
        //    实测： **为真**时手动请求，
        //    仍然  —— 所以不是不可用，是**这个时机不许你主动进**。
        //    苹果的设计就是：**由系统在 App 进后台那一刻自动接管**，
        //    而不是 App 在前台自己喊。
        //    （我上一版把它关掉，等于把唯一合法的入口也关了。）
        c.canStartPictureInPictureAutomaticallyFromInline = true
        KbBridge.note("PiP：已挂上（等 isPictureInPicturePossible）")

        // 🚨 光挂上不够，层里必须**真的有帧在走**，否则系统不认它是"正在播放的视频"。
        //    这一条是我预判的失败点：**如果 PiP 起不来，先查是不是没喂帧。**
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) {
            [weak self] _ in
            self?.feed()
        }
    }

    /// 往层里喂一帧全黑画面。**只为让 PiP 认为有视频在播，不显示任何内容。**
    private func feed() {
        guard let l = layer, l.isReadyForMoreMediaData else { return }
        var buf: CVPixelBuffer?
        CVPixelBufferCreate(nil, 4, 4, kCVPixelFormatType_32BGRA, nil, &buf)
        guard let pb = buf else { return }
        var info = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 15),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid)
        var fmt: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil, imageBuffer: pb, formatDescriptionOut: &fmt)
        guard let f = fmt else { return }
        var sb: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pb,
            dataReady: true, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: f, sampleTiming: &info, sampleBufferOut: &sb)
        if let s = sb { l.enqueue(s) }
    }

    /// 🚨 **等 `isPictureInPicturePossible` 为真再请求。**
    ///
    /// 上一版盲发请求 → `-1001`。而 `AVPictureInPictureController` 本来就有这个
    /// 前置状态可查，**我一次都没查过它**（今晚老毛病：不看前置条件就动作，
    /// 然后把失败当成结论）。
    ///
    /// 🚨 **「一直不可用」和「请求了但被拒」是两种不同的失败** ——
    ///    等超时要单独记一行，否则下一个人分不开。
    /// 当前场景的激活状态。**`-1001` 的判据就挂在它上面。**
    private var sceneActive: Bool {
        UIApplication.shared.connectedScenes.contains {
            $0.activationState == .foregroundActive
        }
    }

    private var sceneDesc: String {
        UIApplication.shared.connectedScenes.map {
            switch $0.activationState {
            case .foregroundActive: return "前台活跃"
            case .foregroundInactive: return "前台非活跃"
            case .background: return "后台"
            case .unattached: return "未附着"
            @unknown default: return "未知"
            }
        }.joined(separator: ",")
    }

    /// 🚨🚨 **请求 PiP 的前提是【场景 foregroundActive】，不是 `isPictureInPicturePossible`。**
    ///
    /// 查到的原文（带错误码搜才命中的）：
    /// > Error Code -1001 … occurs when the UIScene for the content source has an
    /// > activation state other than `UISceneActivationStateForegroundActive`.
    ///
    /// 我上一版把闸门挂在 `isPictureInPicturePossible` 上 —— **它为真时请求照样 -1001**，
    /// 因为那个属性问的是"内容行不行"，而 -1001 说的是"你的场景状态行不行"。
    /// **判据又一次挂在了错的对象上。**
    ///
    /// 🚨 PiP 的设计是**在前台启动、带着它进后台** —— 启动时机必须在切走**之前**。
    func startIfNeeded() {
        guard PipKeepAlive.enabled, let c = controller else { return }
        var waited = 0.0
        func tryOnce() {
            if c.isPictureInPictureActive { return }
            if sceneActive && c.isPictureInPicturePossible {
                KbBridge.note("PiP：场景=\(sceneDesc)、possible=true，"
                              + "请求进入（等了 \(waited) 秒）")
                c.startPictureInPicture()
                return
            }
            waited += 0.5
            if waited > 10 {
                // 🚨 **两个前提分开报** —— 否则下次还是分不清卡在哪一个。
                KbBridge.note("PiP：等 10 秒仍不满足 —— 场景=\(sceneDesc)、"
                              + "possible=\(c.isPictureInPicturePossible)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { tryOnce() }
        }
        // 先让帧跑 2 秒再开始等 —— 层里没帧时它必然不 possible。
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { tryOnce() }
    }
}

@available(iOS 15.0, *)
extension PipKeepAlive: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerDidStartPictureInPicture(
        _ c: AVPictureInPictureController) {
        KbBridge.note("PiP：已进入 ✅")
    }
    func pictureInPictureController(
        _ c: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error) {
        // 🚨 **失败原因必须落地** —— 今晚丢过一次证据了。
        // 🚨 -1001 = 场景不是 foregroundActive。**把状态一起记下来**，
        //    否则光看错误码还要再查一轮。
        KbBridge.note("PiP：进不去 —— \((error as NSError).code) "
                      + (error as NSError).domain
                      + "｜当时场景=" + PipKeepAlive.shared.sceneDesc)
    }
    func pictureInPictureControllerDidStopPictureInPicture(
        _ c: AVPictureInPictureController) {
        KbBridge.note("PiP：已退出")
    }
}

@available(iOS 15.0, *)
extension PipKeepAlive: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    setPlaying playing: Bool) {}
    func pictureInPictureControllerTimeRangeForPlayback(
        _ c: AVPictureInPictureController) -> CMTimeRange {
        // 直播式：无限时间轴。PiP 不会显示进度条。
        CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    func pictureInPictureControllerIsPlaybackPaused(
        _ c: AVPictureInPictureController) -> Bool { false }
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    didTransitionToRenderSize size: CMVideoDimensions) {}
    func pictureInPictureController(_ c: AVPictureInPictureController,
                                    skipByInterval: CMTime,
                                    completion: @escaping () -> Void) { completion() }
}
