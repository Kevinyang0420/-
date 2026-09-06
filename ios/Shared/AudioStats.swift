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
}
