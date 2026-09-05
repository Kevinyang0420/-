import AppIntents
import Foundation

/// **在后台起录的 App Intent** —— 验证「不跳出微信也能开麦克风」这条路。
///
/// ## 为什么做它（2026-08-30 调研后的唯一活路）
///
/// 苹果 DTS 的正式答复是两个 No：键盘没法识别宿主 App，容器 App 也没法知道
/// 是谁拉起了它。iOS 26.4 之后连私有路子（`_hostBundleID` 等）全部返回 nil，
/// 我实测也一致 —— 拿得到宿主 pid，但 `proc_pidpath`/`proc_name` 被沙盒挡死
/// （`errno=1` EPERM）。**所以「跳过去再切回来」这条路是死的。**
///
/// 剩下唯一能同时满足他两个要求（麦克风用时才开 + 全程不离开微信）的架构：
/// **Live Activity + App Intent 在后台起录**。
/// Apple 文档对 `AudioRecordingIntent` 的原话是：
/// 「Adopt this protocol to record audio **from the background** when your app intent runs.」
///
/// 这也对得上 Typeless 在他手机上的形态：主 App 不常驻、`dynamicisland.appex` 常驻。
///
/// ## 🚨 这一版先验前提，不接产品
///
/// `LiveActivityIntent` **跑在主 App 自己的进程里**，所以它能直接调 `KbVoiceHost`。
/// 验的就是一件事：**App 在后台时，由这个 Intent 触发的起录到底成不成。**
/// 成了，再接「键盘 → 后端 → APNs push-to-start」那一半（需要他建 APNs 密钥）。
///
/// 🚨 判据是**痕迹里出现 `Intent 起录：拿到 N 字节`**，不是"Intent 跑了"。
///    「跑了」和「录到了」是两回事，今天已经在这上面栽过好几次。
@available(iOS 18.0, *)
struct StartRecIntent: LiveActivityIntent, AudioRecordingIntent {
    static var title: LocalizedStringResource = "开始录音"
    static var description = IntentDescription("在后台开始录音，不用离开当前 App")

    /// 🚨 `openAppWhenRun = false` 是关键：**它就是为了不把他拽走**。
    ///    设成 true 的话等于又回到跳转，那这条路就白走了。
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult {
        RecIntentBridge.shared.startFromIntent()
        return .result()
    }
}

/// Intent 和宿主之间的接线板。
///
/// 🚨 单独一层是因为 `Shared/` 里的文件**两个 target 都会编**
///    （主 App 和键盘扩展），而 `KbVoiceHost` 只存在于主 App。
///    直接引用会让键盘那边编不过 —— 今天已经因为类似的事炸过一次。
public final class RecIntentBridge {
    public static let shared = RecIntentBridge()
    /// 主 App 启动时把真正的动作塞进来；键盘那边永远是 nil，不会被调用。
    public var onStart: (() -> Void)?
    public func startFromIntent() {
        KbBridge.note("Intent 起录：被触发了（此刻由系统在后台运行）")
        if let f = onStart { f() } else {
            KbBridge.note("Intent 起录：没人接（这不是主 App 进程）")
        }
    }
}
