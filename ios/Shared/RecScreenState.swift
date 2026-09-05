import Foundation

/// 主 App 录音屏的**状态机**（2.1《交互规格 · 主 App 录音屏》R1–R4）。
///
/// 🚨🚨 **这里只有状态和文案，没有一行版式。**
///    方向 A/B/C 还等 Kevin 挑，**版式归 Grok、形态归他** ——
///    但 2.1 已经确认：**状态机和判据在三个方向下是共用的**，
///    所以这一层现在就能定死，他挑完只需要接一个 `render`。
///
/// ## 这一屏只有两件任务
/// **① 让他知道正在录 ② 让他能说"我说完了"。别的都是附加。**
///
/// 🚨 **每一态都必须有可读的东西** —— 屏上空白跟"App 卡住了"在用户眼里没有区别。
///    他 2026-08-29 报的「跳过去了也没有启动录音」就是这么来的：
///    **录起来了，他看不见。**
enum RecScreenState: Equatable {

    /// R0 准备中。**主 App 一拿到前台就进**，不等录音真起来。
    ///
    /// 🚨 起录闸最长要等 6 秒（等 `didBecomeActive`）——
    ///    **那 6 秒屏上空着的话，他看到的还是"没反应"。**
    /// 🚨 **这一态的停止必须【可点】**：做成灰的不可点，他一点没反应，
    ///    又变回"没反应"。**R0 期间点它 ＝ 取消并返回。**
    case preparing
    /// R1 正在录。**必须有可见反馈 + 停止。**
    case recording
    /// R2 处理中（他点了停止，或到了上限）。
    case processing
    /// R3 出稿了。🚨 **必须明说"可以回去了"** ——
    /// 形态是甲，他得**自己**点回去；不说的话他会站在这儿等它自己跳，
    /// 而它永远不会跳（⑤：我们的不会自动跳回，他已经说过很多遍）。
    case done
    /// R4 出错了。🚨 **要说清坏在【哪一步】，不是"失败"两个字。**
    case failed(String)

    /// 这一态屏上的主标题。**任何一态都不许是空的**（判据 V6）。
    var title: String {
        switch self {
        case .preparing: return L.rec_r0_title
        case .recording: return L.rec_r1_title
        case .processing: return L.rec_r2_title
        case .done: return L.rec_r3_title
        case .failed: return L.rec_r4_title
        }
    }

    /// 副行。R4 这一档带上具体是哪一步坏了。
    var detail: String {
        switch self {
        case .preparing: return ""
        case .recording: return L.rec_r1_hint
        case .processing: return ""
        case .done: return L.rec_r3_hint
        case .failed(let why):
            let w = why.trimmingCharacters(in: .whitespacesAndNewlines)
            // 🚨 原因为空时也不许退化成空白 —— 那就又变成"跟没反应一样"。
            return String(format: L.rec_r4_detail, w.isEmpty ? L.rec_r4_title : w)
        }
    }

    /// 这一态的主操作按钮文案；`nil` ＝ 这一态没有主操作。
    ///
    /// 🚨 R1 **必须**能停：没有停止 ＝ 每句话都得等满上限，**跟坏的没区别**。
    var primaryAction: String? {
        switch self {
        // 🚨 R0 的按钮是**取消**，而且必须可点（2.1 裁定，判据 V7）
        case .preparing: return L.rec_r0_cancel
        case .recording: return L.rec_r1_stop
        case .processing: return nil
        case .done: return nil          // 主操作是系统左上角那个返回箭头
        case .failed: return L.rec_r4_retry
        }
    }

    /// 🚨 **判据 V6 的落点**：这一态屏上到底有没有可读的东西。
    ///
    /// 判据挂在**文案本身**上，不是"代码里有没有调 setText" ——
    /// 后者在文案被改成空串时照样为真。
    var hasVisibleText: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 到达上限时怎么办。
    ///
    /// 🚨 **上限是保险丝，不是交互**：有停止按钮之后正常路径永远走不到它。
    ///    到点**当作用户点了停止 → 进 R2 出稿**，
    ///    **不是丢弃** —— 丢弃会让他说了一分钟白说。
    ///    （现在的实物就是到点自动停且不丢，这条保持。）
    static func onCapReached() -> RecScreenState { .processing }

    /// R0 等太久还没起录时该去哪。
    ///
    /// 🚨 **不许无限停在"正在准备"**（判据 V8）——
    ///    那跟"没反应"在屏幕上是一回事。超时就说清「录音没起来」。
    static func onPrepareTimeout(_ why: String) -> RecScreenState { .failed(why) }
}
