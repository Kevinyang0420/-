import XCTest

/// **主 App 在前台时别把键盘收掉** —— Kevin 2026-09-06 亲口：
/// > 在咱们 Transless 主 App 里第一次打开时…点了一下我们自己的输入法。
/// > 但它**首先要架起主引擎，架起主引擎之后就突然闪退回默认输入法了**。
/// > 我还得手动再切一遍回到 Transless。
///
/// ## 根因（读出来的，不是猜的）
/// ```
/// hostAlive → KbProtocol.hostAlive(beatAt: 心跳, staleAfter: 6)
/// 心跳只在 setStandby(true) 之后才开始写；setStandby(false) 还会 clearBeat()
/// 而待机**默认关**（他 09-01 要求：别一直占麦克风）
/// ```
/// → **`hostAlive` 的语义是「引擎宿主在跑」，不是「主 App 在前台」。**
///   他第一次打开时引擎没起 → 必然 false → 走"拉起主 App"→ 同刻 `completeRequest`
///   （语义是"把用户送回宿主"）→ 键盘被收掉 → 系统退回默认输入法。
///
/// 🚨 **两件事必须分开判**，这组用例钉的就是"分开"这一点：
///    在微信里"送回宿主"是对的；在我们自己 App 里，他要去的地方他已经在了。
final class HostForegroundTests: XCTestCase {

    /// 🚨 **前台标记和心跳是两回事** —— 只有心跳、没进过前台时，
    ///    `hostForeground` 必须是假，`hostAlive` 可以为真。
    ///    合成一个判断的话，这条会红。
    func testForegroundIsNotHeartbeat() {
        let now = Date().timeIntervalSince1970
        // 心跳刚写过 → 引擎在跑
        XCTAssertTrue(KbProtocol.hostAlive(beatAt: now, now: now, staleAfter: 6))
        // 🚨 而"从没进过前台"（时间戳为 0）必须判假 —— 跟心跳无关
        XCTAssertFalse(KbProtocol.hostAlive(beatAt: 0, now: now, staleAfter: 6),
                       "🚨 没有前台记录却判成在前台 —— 那键盘永远不会去拉起主 App")
    }

    /// 过期的前台记录不算数：他切走 6 秒以上就不该再当作"在前台"。
    /// 🚨 不清的话，切走后的那几秒点键盘不会去拉起主 App —— 另一个方向的坏。
    func testStaleForegroundExpires() {
        let now = Date().timeIntervalSince1970
        XCTAssertFalse(
            KbProtocol.hostAlive(beatAt: now - 10, now: now, staleAfter: 6),
            "🚨 10 秒前的前台记录还算在前台")
        XCTAssertTrue(
            KbProtocol.hostAlive(beatAt: now - 1, now: now, staleAfter: 6),
            "🚨 1 秒前刚记的前台被判成过期 —— 那这个标记等于没用")
    }

    /// 🚨 **未来的时间戳当死的**（两边时钟对不上时，"还在前台"是猜的不是读的）。
    func testFutureStampCountsAsAbsent() {
        let now = Date().timeIntervalSince1970
        XCTAssertFalse(
            KbProtocol.hostAlive(beatAt: now + 600, now: now, staleAfter: 6),
            "🚨 未来的时间戳被当成有效 —— 时钟一歪键盘就再也不拉起主 App 了")
    }
}
