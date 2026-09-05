import Foundation

/// **测试时一律不碰 AVAudio 的总开关**（`TRANSLESS_NO_ARM=1`）。
///
/// 🚨🚨 立它是因为我为同一件事挑错了三次层，每次都以为"这回堵住了"：
///
///   | 我挡的位置 | 为什么没挡住 |
///   |---|---|
///   | `KbVoiceHost.tryArmOnColdLaunch()` | 那只是**八个架引擎调用点之一**，`didBecomeActive` 那条照样架 |
///   | `Voice.armIdle()` | `armIdleNow()` 也直接调 `start`，绕过去了 |
///   | `Voice.start()` | 还有**第三个入口**：`AudioHold.start` ← `armForBackground` |
///
/// 所以判据改成**枚举**：把所有会碰 `AVAudioEngine` / `setActive(true)`
/// 的入口列出来，每一个都过这一个开关。闸门脚本 `gate_audio_gate.py`
/// 盯着这份名单，漏一个就红。
///
/// 🚨 为什么要它：模拟器上这些调用会撞 `AudioToolbox _ReportRPCTimeout`
///    直接 abort，**把跟录音毫无关系的版式／纯逻辑用例一起带崩**，
///    失败信息还长得像「App 没起来」——指向完全错误的层。
///
/// 🚨 只给不测录音的用例用；真正测录音的用例不带这个开关，行为一点没变。
///    默认（不设这个环境变量）时 `off` 恒为 false，产品行为不受影响。
enum AudioGate {
    static let off: Bool =
        ProcessInfo.processInfo.environment["TRANSLESS_NO_ARM"] == "1"
}
