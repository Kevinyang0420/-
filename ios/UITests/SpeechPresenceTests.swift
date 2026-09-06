import XCTest

/// `SpeechPresence` —— 判「这一段录音里有没有人说话」。
///
/// 🚨 **为什么值得单独测**：这个判断错了，Kevin 会直接骂人 ——
///    判成"没说话"就让他把说过的话重说一遍（他 2026-09-06 01:50 骂过），
///    判成"说了话"就让他重发一段静音、拿到同样的结果、关进循环。
///
/// 🚨🚨 **这些用例证明的是「判据会不会失败」，不是「阈值定得对不对」。**
///    `minRatio` 现在是推出来的、**没拿真样本标定过**。
///    标定要一条真静音 + 一条真说话，从 `KbBridge.note` 的
///    「这一段电平：peak=… floor=… ratio=…」里取。**别拿这些用例冒充标定。**
final class SpeechPresenceTests: XCTestCase {

    private func stats(_ levels: [Float]) -> SpeechPresence.Stats {
        var s = SpeechPresence.Stats()
        for l in levels { s.feed(l) }
        return s
    }

    // MARK: - 正样本：说了话

    /// 说话：本底很低、峰值窜上去 —— 比值远超阈值。
    func testSpeechIsDetected() {
        let s = stats([0.02, 0.03, 0.41, 0.66, 0.30, 0.04, 0.02])
        XCTAssertTrue(SpeechPresence.spoke(s),
                      "🚨 把说过的话判成没说 —— 他会被要求重说一遍，"
                      + "那正是他骂过的那件事。\(s.debugLine)")
    }

    // MARK: - 负样本：真没说话

    /// 纯底噪：一直在一个很低的档上小幅起伏，峰值抬不起来。
    func testSilenceIsDetected() {
        let s = stats([0.020, 0.022, 0.019, 0.021, 0.023, 0.020])
        XCTAssertFalse(SpeechPresence.spoke(s),
                       "🚨 静音被判成说了话 —— 他会去重发一段静音，"
                       + "拿到同样的结果，关进循环。\(s.debugLine)")
    }

    /// 麦克风完全没进声音（全 0）—— 这不是"拿不准"，是确定没有。
    func testAllZeroIsNotSpeech() {
        XCTAssertFalse(SpeechPresence.spoke(stats([0, 0, 0, 0, 0])))
    }

    // MARK: - 🚨 拿不准时必须偏向「他说了话」

    /// 帧数太少（不到 ~0.3 秒）：**样本不够就不许下结论**，按说了话处理。
    ///
    /// 🚨 两种错的代价不对称：误判"没说话"要他重说（他骂过），
    ///    误判"说了话"最多白点一次重发。所以往"他说了"那边偏。
    func testTooFewFramesFallsBackToSpoke() {
        XCTAssertTrue(SpeechPresence.spoke(stats([0.02, 0.02])),
                      "🚨 样本不够就下了'没说话'的结论 —— 拿不准要偏向他说了话")
    }

    /// 一帧都没有（录音根本没开起来）—— 同上，不下结论。
    func testEmptyStatsFallsBackToSpoke() {
        XCTAssertTrue(SpeechPresence.spoke(SpeechPresence.Stats()))
    }

    // MARK: - 统计本身

    /// 🚨 **跨轮不清零的话第二轮读到的是两轮之和** —— `Voice.start` 里清。
    ///    这条用例守的是 `Stats` 自己是值类型、新建就是干净的。
    func testFreshStatsIsClean() {
        let s = SpeechPresence.Stats()
        XCTAssertEqual(s.peak, 0)
        XCTAssertEqual(s.frames, 0)
    }

    /// 本底为 0 时不许除零炸掉。
    func testRatioSurvivesZeroFloor() {
        let s = stats([0, 0.5, 0])
        XCTAssertTrue(s.ratio.isFinite, "🚨 ratio 除零了：\(s.debugLine)")
    }

    /// 峰值/本底记的是**整段的极值**，不是最后一帧。
    func testTracksExtremes() {
        let s = stats([0.10, 0.80, 0.05, 0.30])
        XCTAssertEqual(s.peak, 0.80, accuracy: 0.001)
        XCTAssertEqual(s.floor, 0.05, accuracy: 0.001)
        XCTAssertEqual(s.frames, 4)
    }
}
