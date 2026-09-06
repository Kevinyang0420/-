import Foundation

/// **这一轮实际送出去的音频总量。**
///
/// 🚨 为什么要它（2026-09-06，0 从 Kevin 手机上那份诊断查出来的）：
///    「出稿完成 / 出稿失败」这两行 —— **正是他复制出来会看到的那两行** ——
///    一直写死 `sec: 0, bytes: 0`：
/// ```
/// 13:24:27  0.0s 0KB  出稿完成：（第 1 段未转出，无内容）
/// 14:52:35  0.0s 0KB  出稿完成：Testing, testing.      ← 成功那次也是 0
/// ```
///    值不是没记，是**记在了别的行上**，而他看的那两行拿不到音频事实。
///    于是这份诊断分不出「麦克风没收到」和「收到了但没转出」——
///    **而那正是它存在的唯一理由。**
///
/// 🚨 **分段时必须是各段之和，不是最后一段。**
///    只记最后一段的话，录 120 秒会显示 60 秒，
///    重演安卓那个「按住 26.6 秒、录到 1.9 秒」的读数歧义。
struct RoundTally {
    private(set) var sec: Double = 0
    private(set) var bytes: Int = 0
    /// 送出去过几段（0 = 这一轮什么都没传）
    private(set) var parts: Int = 0

    /// 当前是哪一轮。-1 = 还没开过张。
    private var round = -1

    /// 计入一段。
    ///
    /// 🚨🚨 **轮次一变自己清零** —— 不设独立的 `reset()` 调用点。
    ///    起录有**四个** `voice.start(` 出口（而旁边的注释还写着"三个"，
    ///    它本身就是这条规矩漏过一次的证据）。在四处各写一遍 reset，
    ///    以后加第五个出口必然漏 —— 而漏掉的表现是**这一轮带着上一轮的量**，
    ///    数字看起来完全正常，没人会怀疑。
    mutating func add(round r: Int, sec s: Double, bytes b: Int) {
        if r != round {
            sec = 0
            bytes = 0
            parts = 0
            round = r
        }
        add(sec: s, bytes: b)
    }

    private mutating func add(sec s: Double, bytes b: Int) {
        // 🚨 负数和 NaN 不许进来：它们会让总和变成一个**看起来正常**的小数字，
        //    而"总量偏小"正是这个字段最容易骗人的坏法。
        guard s.isFinite, s >= 0, b >= 0 else { return }
        sec += s
        bytes += b
        parts += 1
    }

    mutating func reset() {
        sec = 0
        bytes = 0
        parts = 0
    }

    /// 这一轮一个字节都没送出去过。
    /// 🚨 用它区分「录了但没传」和「传了但没转出」—— 两者的修法完全不同。
    var isEmpty: Bool { parts == 0 }
}
