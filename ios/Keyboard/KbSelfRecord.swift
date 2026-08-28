import Foundation

/// 🚨🚨 **最小实验：键盘扩展到底能不能自己录音？**（2026-08-28 立项）
///
/// ## 为什么要推翻重来
///
/// 我们整套架构（主 App 后台代录 + 键盘当遥控器 + App Group + 保活 + 那个开关）
/// 的**地基**是一句话：「iOS 禁止扩展进程录音」。
/// 而那句话的出处是苹果技术问答 **QA1872**：
///
/// > "App extensions in **iOS 8** are not allowed to record audio"
/// > 最后更新 **2014-09-17**，**通篇没有出现过 keyboard extension**。
///
/// **Kevin 的手机是 iOS 26.6。** 我们拿一份十二年前、明确限定 iOS 8、
/// 连"键盘"两个字都没提的文档，当成了今天的铁律。
///
/// **反证是他自己拍的**（2026-08-28 17:40，iOS 26.6）：Typeless 录音时
/// **灵动岛橙点亮着、屏幕上是 Typeless 的键盘面板、主 App 不在前台**。
/// 无论它用的是哪种机制，「扩展绝对不能录音」这个前提都站不住。
///
/// ## 这个实验怎么判
///
/// 🚨 **判据是「拿到非静音的 PCM」**，不是"没报错"、不是"路由里有输入口"。
///    ——「引擎起来了」和「真的有声音进来」是两回事，
///    而后台那次诊断正好是「没报错但 `入0`」，所以这条必须挂在**数据**上。
///
/// 结果写进 App Group 的 `selftest.txt`，电脑上
/// `xcrun devicectl device copy from --domain-type appGroupDataContainer` 拉得到，
/// 不用等 Kevin 截图。
///
/// ## 失败也不许让他没法用
///
/// 直录失败就**自动回退**到现在这条（主 App 代录）。所以这一版
/// **最坏情况等于原样**，不会因为做实验把他手上能用的东西弄坏。
enum KbSelfRecord {

    /// 关掉直录、强制走宿主那条。留一个开关是因为：万一直录能起来但音质/稳定性有问题，
    /// 我要能在**不重新发包**的情况下让他退回去（`process launch -e` 或下一版默认值）。
    static var disabled: Bool {
        ProcessInfo.processInfo.environment["TRANSLESS_NO_SELFREC"] == "1"
    }

    /// 峰值音量到多少才算「真的录到了声音」。
    ///
    /// 🚨 这个数不是拍的：`Voice` 的音量公式是 `min(1, sqrt(rms)*1.9)`，
    ///    而**连续模式的静音判据 `SILENCE_LEVEL` 就是 0.08**（两端同一个数）。
    ///    也就是说 0.08 以下我们自己的分句器都当它是静音。
    ///    所以「峰值没超过 0.08」＝ 从头到尾都是静音，
    ///    那正是「引擎起来了但没有声音进来」这个失败形态。
    static let voiced: Float = 0.08

    /// 一次直录的结果，写成一行给电脑拉。
    static func report(ok: Bool, frames: Int, peak: Float,
                       note: String, foreground: Bool) -> String {
        let verdict: String
        if !ok {
            verdict = "FAIL 扩展直录起不来"
        } else if peak < voiced {
            // 🚨 这一档必须单独存在：引擎起来了、也拿到帧了，**但全是静音**。
            //    如果把它算成成功，我们会得出"扩展能录"的错误结论，
            //    然后在一个永远只录到静音的架构上继续盖楼。
            verdict = "SILENT 扩展直录起来了但全程静音"
        } else {
            verdict = "OK 扩展直录拿到非静音音频"
        }
        return String(format: "%@\n帧数 %d  峰值 %.3f（阈值 %.2f）\n当时键盘在%@\n%@",
                      verdict, frames, peak, voiced,
                      foreground ? "前台" : "非前台", note)
    }
}
