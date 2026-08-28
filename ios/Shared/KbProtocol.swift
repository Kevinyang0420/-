import Foundation

/// 键盘 ⇄ 主 App 协议里的**纯判断**。一行 I/O 都没有，所以能被测。
///
/// 🚨 为什么要从 `KbBridge` 里抽出来：那些判断读的是 App Group 的
///    `UserDefaults`，而 **App Group 在模拟器里根本装不上** ——
///    没有描述文件时 Xcode 会把这类受限 entitlement 剥掉
///    （2026-08-28 实测：清理重签之后 `codesign -d --entitlements` 仍然是空的）。
///    也就是说跨进程那一段**只能等真机**。
///
///    但协议里最容易出错的不是"读写通不通"，是**这三个判断**：
///      · 哪些命令算"新的"（弄错 → 一打开待机它自己就开始录音）
///      · 宿主算不算还活着（弄错 → 对着一个死宿主干等）
///      · 一条结果是不是回给我这一轮的（弄错 → 上一轮的结果插进这一轮）
///    这三条不碰存储，现在就能测 —— **别把"测不了跨进程"当成"什么都测不了"。**
///
/// 自测：`swift Shared/KbProtocol.swift`（Mac 上直接跑，不用模拟器），
/// 或在 App 里调 `KbProtocol.selfTest()`。
enum KbProtocol {

    // ------------------------------------------------------------ 命令去重

    /// 这条命令算不算"新的"。
    ///
    /// 🚨 靠**序号只增**，不靠时间戳。时间戳判"新不新"要选阈值，
    ///    而进程刚被唤醒时时钟差一点就会把旧命令当新的重放一遍。
    static func isNewCommand(seq: Int, lastSeen: Int) -> Bool {
        return seq > lastSeen
    }

    /// 刚打开待机时，`lastSeen` 该对齐到哪。
    ///
    /// 🚨 必须对齐到**当前序号**，不是 0。对齐到 0 的话，
    ///    上一次待机期间残留的那条命令会被当成新的立刻执行一遍 ——
    ///    表现就是「一打开待机它自己就开始录音」。
    ///    这种错**只在第二次使用时出现**，第一次测永远测不到。
    static func alignOnStandby(currentSeq: Int) -> Int {
        return currentSeq
    }

    // ------------------------------------------------------------ 宿主死活

    /// 宿主还活着吗。`beatAt` 是它最后一次心跳的秒数；`<= 0` 表示从来没跳过。
    static func hostAlive(beatAt: TimeInterval, now: TimeInterval,
                          staleAfter: TimeInterval) -> Bool {
        if beatAt <= 0 { return false }
        // 🚨 未来的时间戳也当死的：那说明两边时钟对不上，
        //    这时候"还活着"是猜的，不是读出来的。
        if beatAt > now + staleAfter { return false }
        return now - beatAt < staleAfter
    }

    // ------------------------------------------------------------ 结果配对

    /// 这条结果该不该收。
    ///
    /// 🚨 两个条件缺一不可：
    ///    · 序号对得上 —— 否则上一轮的结果会插进这一轮
    ///    · 比上次读到的更新 —— 否则同一条 partial 会被反复当成新结果
    static func acceptResult(resSeq: Int, mySeq: Int,
                             resAt: TimeInterval, lastAt: TimeInterval) -> Bool {
        return resSeq == mySeq && resAt > lastAt
    }

    // ------------------------------------------------------------ 自测

    /// 好样本 + 坏样本。**每条判据都要能说出"什么输入让它失败"**。
    static func selfTest() -> [String] {
        var bad: [String] = []
        func ck(_ ok: Bool, _ what: String) {
            if !ok { bad.append(what) }
        }

        // --- 命令去重
        ck(isNewCommand(seq: 5, lastSeen: 4), "序号更大应该算新命令")
        ck(!isNewCommand(seq: 4, lastSeen: 4), "同一个序号不该再执行一遍")
        ck(!isNewCommand(seq: 3, lastSeen: 4), "更小的序号不该执行")
        // 🚨 这一条盯的正是「一打开待机就自己录音」
        ck(!isNewCommand(seq: 7, lastSeen: alignOnStandby(currentSeq: 7)),
           "刚打开待机时，残留的那条命令不该被当成新的")
        ck(isNewCommand(seq: 8, lastSeen: alignOnStandby(currentSeq: 7)),
           "对齐之后，真正的新命令仍然要收")

        // --- 宿主死活
        let stale: TimeInterval = 6
        ck(hostAlive(beatAt: 100, now: 103, staleAfter: stale), "3 秒前跳过 = 活着")
        ck(!hostAlive(beatAt: 100, now: 107, staleAfter: stale), "7 秒没跳 = 死了")
        // 🚨🚨 `now` 必须**贴近 0**，这两条才区分得开有没有那个守卫。
        //    上一版写的是 `beatAt: 0, now: 100` —— 那时候
        //    `now - beatAt = 100` 早就超期了，**把守卫整个删掉它照样过**。
        //    注入坏实现时当场漏网，才发现样本选错了：
        //    **样本要能分辨我想验的那件事，不是随手填两个数。**
        ck(!hostAlive(beatAt: 0, now: 3, staleAfter: stale),
           "从没跳过 = 死了（哪怕 now 很小）")
        ck(!hostAlive(beatAt: -1, now: 3, staleAfter: stale),
           "负数 = 死了（哪怕 now 很小）")
        ck(!hostAlive(beatAt: 100, now: 100 - 99, staleAfter: stale),
           "心跳在未来 = 时钟对不上，不许判成活着")
        // 边界：正好 staleAfter 秒算死（判据是「小于」）
        ck(!hostAlive(beatAt: 100, now: 106, staleAfter: stale),
           "正好卡在 staleAfter 上应该算死")

        // --- 结果配对
        ck(acceptResult(resSeq: 3, mySeq: 3, resAt: 10, lastAt: 9), "序号对且更新 = 收")
        ck(!acceptResult(resSeq: 2, mySeq: 3, resAt: 10, lastAt: 9),
           "上一轮的结果不该插进这一轮")
        ck(!acceptResult(resSeq: 3, mySeq: 3, resAt: 9, lastAt: 9),
           "同一个时间戳不该重复收")
        ck(!acceptResult(resSeq: 3, mySeq: 3, resAt: 8, lastAt: 9),
           "更旧的结果不该收")
        // 🚨 反向样本：没有在进行的这一轮时（mySeq = -1），什么都不该收
        ck(!acceptResult(resSeq: 3, mySeq: -1, resAt: 10, lastAt: 0),
           "没有在进行的轮次时不该收任何结果")

        return bad
    }
}

// 🚨 **这个文件里不放任何顶层语句。**
//    原来结尾有一段 `#if KBPROTOCOL_MAIN … #endif` 的运行入口，
//    本以为 iOS 构建时那个标志没定义、整段会被跳过 —— **实际被编进去了**，
//    xcodebuild 报 `statements are not allowed at the top level`。
//    我没有去猜它为什么被定义：**把入口整个搬出这个文件**，歧义就不存在了。
//    跑自测的入口由 `D:\_build\gate_kb_protocol.py` 在 Mac 上临时生成。
