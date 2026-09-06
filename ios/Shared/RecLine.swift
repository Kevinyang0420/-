import Foundation

/// 录音诊断里**一行**长什么样 —— 从 `RecLog.dump()` 抽出来的纯格式化。
///
/// 🚨 为什么值得单独一个文件：Kevin 复制出来的诊断长这样
/// ```
/// 09-06 13:24:27  0.0s 0KB  出稿完成：（第 1 段未转出，无内容）
/// 09-06 14:52:35  0.0s 0KB  出稿完成：Testing, testing.   ← 成功那次也是 0
/// ```
///    值不是没记，是**那两行拿到的就是 0**。而这份诊断存在的唯一理由，
///    就是分开「麦克风没收到」和「收到了但没转出」——全是 0 的时候它分不了。
///
/// 🚨 判据必须挂在**他粘出来的那段文本**上，不能挂在「`RecLog.add` 被调用了」上。
///    「记了」和「他看得见」是两件事，这个形状今天出现了第十次。
///    抽成纯函数就是为了让判据挂得住。
enum RecLine {

    /// 一行的样子：`MM-dd HH:mm:ss  12.3s 384KB  出稿完成：…`
    static func render(when: String, sec: Double, bytes: Int,
                       result: String, detail: String) -> String {
        let body = detail.isEmpty ? result : "\(result)：\(detail)"
        // 🚨 **不足 1KB 显示字节数，不显示 `0KB`。**
        //    整除会把「传了 44 字节（只剩 WAV 头）」渲染成 `0KB`，
        //    跟「一个字节都没传」长得一模一样 —— 而这份诊断存在的理由
        //    正是把这两件事分开。判据抓出来的，不是我想到的。
        let size = bytes >= 1024 ? "\(bytes / 1024)KB" : "\(bytes)B"
        return String(format: "%@  %.1fs %@  %@", when, sec, size, body)
    }

    /// 这一行**有没有真的带上音频事实**。
    ///
    /// 🚨 用途是当判据：`0.0s 0KB` 正是他手机上那个坏形状。
    ///    注意「生命周期事件」（起录闸通过之类）本来就没有音频，
    ///    所以这个判断只该用在**出稿那两行**上，不是每一行。
    static func carriesAudioFacts(_ line: String) -> Bool {
        // 「什么都没传」的指纹是 `0.0s 0B` —— 注意是 `0B` 不是 `0KB`：
        // 不足 1KB 现在按字节显示，所以 `0KB` 这个写法只会出现在恰好 0 的时候。
        return !(line.contains(" 0.0s ") && line.contains(" 0B "))
    }
}
