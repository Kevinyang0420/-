import XCTest

/// Kevin 2026-09-06 亲口报、且说「不止一次出现」：
/// 「说了一堆话…点结束后提示第一段未转出无内容」「**也没有重新上传处理的按钮**」。
///
/// 🚨 这一组测的是**分流**：什么时候该说"麦克风没收到"、什么时候该留住音频给重发。
///    判据挂在**零采样点占比**上 —— 峰值那个指标 2026-08-31 已被正负样本判死。
final class SilenceVerdictTests: XCTestCase {

    // MARK: - 真数字静音（麦克风没解开静音）

    func testAllZeroIsMicDead() {
        XCTAssertTrue(SilenceVerdict.micGotNothing(zeroPct: 100))
        XCTAssertTrue(SilenceVerdict.micGotNothing(zeroPct: 99))
        XCTAssertTrue(SilenceVerdict.micGotNothing(zeroPct: 98))
    }

    /// 🚨 门槛用 `>= 98` 不用 `== 100` 的理由，要有用例守着：
    ///    WAV 头之后偶有一两个非零采样点，卡死 100 这道闸**永远不成立**。
    func testAlmostAllZeroStillCountsAsDead() {
        XCTAssertTrue(SilenceVerdict.micGotNothing(zeroPct: 99),
                      "🚨 卡死 100 的话，一两个杂散采样点就能让这道闸永远不生效")
    }

    // MARK: - 确实有声音

    func testNormalSpeechIsNotDead() {
        // 正常说话的零占比通常在个位数到二十几
        for z in [0, 3, 22, 60, 97] {
            XCTAssertFalse(SilenceVerdict.micGotNothing(zeroPct: z),
                           "零占比 \(z)% 被判成没收到声音 —— 他说的话会被扔掉")
        }
    }

    /// 数据太短（`zeroPct` 回 -1）时**当作有声音**。
    /// 🚨 拿不准偏向「他说了话」：误判成"没声音"会扔掉他说的一大段（他骂的就是这个），
    ///    误判成"有声音"最多让他多点一次重发。**代价不对称。**
    func testUnknownFallsBackToHasSound() {
        XCTAssertFalse(SilenceVerdict.micGotNothing(zeroPct: -1))
    }

    // MARK: - 🚨 他撞的那一档：说了话、后端说没听出内容

    /// **必须留住音频**，好给他重发键。
    func testKeepsAudioWhenThereWasSound() {
        XCTAssertTrue(
            SilenceVerdict.keepAudioForRetry(needsRespeak: true, zeroPct: 12),
            "🚨 他说了一大段，我们把它扔了 —— 这正是他报的那件事")
    }

    /// 真静音时作废是对的：重传必然还是没内容，白花钱。
    func testDropsAudioWhenMicGotNothing() {
        XCTAssertFalse(
            SilenceVerdict.keepAudioForRetry(needsRespeak: true, zeroPct: 100))
    }

    /// 🚨 **反向对照**：不是 respeak 的失败（网络、超时…）**本来就该留** ——
    ///    只测 respeak 那条的话，把所有失败都作废也全绿。
    func testOtherFailuresAlwaysKeepAudio() {
        XCTAssertTrue(
            SilenceVerdict.keepAudioForRetry(needsRespeak: false, zeroPct: 100),
            "🚨 网络失败也把音频扔了 —— 那跟他报的是同一种伤害")
    }
}
