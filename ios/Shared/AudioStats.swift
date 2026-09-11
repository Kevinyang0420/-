import Foundation

/// 从 WAV 字节里量出「这段到底录到了什么」—— **纯函数，没有依赖，能进测试包。**
///
/// 🚨 从 `KbVoiceHost` 抽出来的理由：那边拖着音频引擎和 App Group，
///    编不进测试包 —— 于是**「字节 → 零占比」这半一直没被验过**，
///    而真正会出错的正是这半（偏移算错、按字节而不是按采样点数、
///    忘了跳 44 字节 WAV 头…）。
///    上面那半（数字 → 判定）我用手打的数验过，
///    **手打的数证明不了解析对不对**。
enum AudioStats {

    /// WAV 头长度。16-bit PCM 单声道的标准头。
    static let headerBytes = 44

    /// **零采样点占比（0…100）**；数据太短回 -1。
    ///
    /// 🚨 判「是不是真的数字静音」用这个，**不要用峰值** ——
    ///    峰值 2026-08-31 被正负样本判死：安静环境读 1334、
    ///    放着声音反而读 575。
    /// 🚨 坏样本实测（2026-09-06）：**忘了跳 44 字节头**时，
    ///    真静音读出来是 **99%** 而不是 100% —— 而 99 仍然过得了
    ///    `deadZeroPct = 98` 的门槛，**行为一点都不会变**。
    ///    这种 bug 不会被任何"看行为"的验证抓到，只会悄悄偏一点；
    ///    录音更短、或者头更长时才突然翻车。**所以这一层必须有自己的用例。**
    static func zeroPct(_ d: Data?) -> Int {
        guard let d = d, d.count > headerBytes + 2 else { return -1 }
        let n = (d.count - headerBytes) / 2
        guard n > 0 else { return -1 }
        var zeros = 0
        d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for k in 0..<n
            where raw.loadUnaligned(fromByteOffset: headerBytes + k * 2,
                                    as: Int16.self) == 0 { zeros += 1 }
        }
        return zeros * 100 / n
    }

    /// **砍掉开头那一整段连续的零**，返回砍过的 wav（头部长度不变，只改数据段）。
    ///
    /// 🚨 为什么需要它（2026-09-07 Kevin 实撞 #80）：
    ///    前摇让「起录指令一到就开始留音」，而那一刻主 App 还在后台、
    ///    麦克风还没真出数据 —— 于是开头灌进约 4 秒**纯零**。
    ///    零占比一算 99%，`SilenceVerdict` 判成"麦克风什么都没收到"，
    ///    **连转写请求都不发**，他说的那一段被整段扔掉。
    ///    同一段音频，电平那条判据（peak/ratio）却说"判定说了话" ——
    ///    **两个实现，相反的结论，而错的那个决定了发不发。**
    ///
    /// 🚨 砍掉的**只是纯零**，一个有声的采样点都不会丢。
    ///    留 `leadIn` 那点引子是怕把辅音的起头切掉。
    /// 🚨 全零时**原样返回**：那种情况本来就该被判成静音，
    ///    砍成空的反而会让下游拿不准（`zeroPct` 返回 -1 = "数据太短"＝当有声音）。
    static func trimLeadingZeros(_ d: Data, leadInMs: Int = 100) -> Data {
        guard d.count > headerBytes + 2 else { return d }
        let n = (d.count - headerBytes) / 2
        var first = -1
        d.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for k in 0..<n where raw.loadUnaligned(
                fromByteOffset: headerBytes + k * 2, as: Int16.self) != 0 {
                first = k
                break
            }
        }
        guard first > 0 else { return d }          // 全零 或 开头就有声 → 原样
        let lead = leadInMs * 16                    // 16kHz：每毫秒 16 个采样
        let cut = max(0, first - lead)
        guard cut > 0 else { return d }
        var out = d.subdata(in: 0..<headerBytes)
        out.append(d.subdata(in: (headerBytes + cut * 2)..<d.count))
        return out
    }

    /// 开头被砍掉了多少毫秒（只为写进诊断，不参与判断）。
    static func trimmedMs(_ before: Data, _ after: Data) -> Int {
        return max(0, (before.count - after.count) / 2 / 16)
    }
}
