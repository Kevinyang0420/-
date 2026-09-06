import XCTest

/// `RoundTally` —— 诊断里那两行的 `sec / bytes` 从哪来。
///
/// 🚨 这组的核心是**分段要累加**。只记最后一段的话，
///    录 120 秒的两段会显示 60 秒，而 60 这个数**看起来完全正常** ——
///    没有判据挡着的话，没人会怀疑它。
final class RoundTallyTests: XCTestCase {

    /// 🚨 两段各 60 秒 → 总数必须是 120，**不是 60**。
    func testSegmentsAccumulate() {
        var t = RoundTally()
        t.add(round: 7, sec: 60, bytes: 1_920_000)
        t.add(round: 7, sec: 60, bytes: 1_920_000)
        XCTAssertEqual(t.sec, 120, accuracy: 0.001,
                       "🚨 只记了最后一段 —— 录 120 秒会显示 60 秒，"
                       + "而 60 看起来完全正常，没人会怀疑")
        XCTAssertEqual(t.bytes, 3_840_000)
        XCTAssertEqual(t.parts, 2)
    }

    /// 短录音（不分段）也要有数。
    func testSinglePart() {
        var t = RoundTally()
        t.add(round: 1, sec: 8.5, bytes: 272_000)
        XCTAssertEqual(t.sec, 8.5, accuracy: 0.001)
        XCTAssertEqual(t.bytes, 272_000)
        XCTAssertFalse(t.isEmpty)
    }

    /// 一个字节都没传过 → `isEmpty`。
    /// 🚨 这是「录了但没传」和「传了但没转出」的分界，两者修法完全不同。
    func testEmptyWhenNothingSent() {
        let t = RoundTally()
        XCTAssertTrue(t.isEmpty)
        XCTAssertEqual(t.sec, 0)
        XCTAssertEqual(t.bytes, 0)
    }

    /// 起新一轮要清零 —— 不清的话第二轮会带着上一轮的数。
    func testResetClears() {
        var t = RoundTally()
        t.add(round: 1, sec: 60, bytes: 1_920_000)
        t.reset()
        XCTAssertTrue(t.isEmpty, "🚨 没清零 —— 下一轮的诊断会带着上一轮的量")
        XCTAssertEqual(t.sec, 0)
        XCTAssertEqual(t.bytes, 0)
    }

    /// 🚨 脏值不许进：负数/NaN 会让总和变成一个**看起来正常**的小数字。
    func testRejectsGarbage() {
        var t = RoundTally()
        t.add(round: 3, sec: -5, bytes: 100)
        t.add(round: 3, sec: .nan, bytes: 100)
        t.add(round: 3, sec: 10, bytes: -1)
        XCTAssertTrue(t.isEmpty, "🚨 脏值被算进去了 —— 总量会莫名其妙地不对")
        t.add(round: 3, sec: 10, bytes: 320_000)
        XCTAssertEqual(t.parts, 1, "🚨 好值被一起挡掉了 —— 那就没数可看了")
    }

    /// 🚨 **轮次一变自己清零** —— 这条是为了不靠"记得在四个起录出口 reset"。
    ///    漏了的表现是**这一轮带着上一轮的量**，数字看起来完全正常。
    func testNewRoundClearsItself() {
        var t = RoundTally()
        t.add(round: 1, sec: 60, bytes: 1_920_000)
        t.add(round: 2, sec: 8, bytes: 256_000)
        XCTAssertEqual(t.sec, 8, accuracy: 0.001,
                       "🚨 新一轮带着上一轮的量 —— 他会看到一个偏大的秒数，"
                       + "而那个数看起来完全正常")
        XCTAssertEqual(t.bytes, 256_000)
        XCTAssertEqual(t.parts, 1)
    }

    /// 反向对照：**同一轮内必须继续累加**，不能每次都清。
    /// 🚨 只测"换轮会清"的话，"每次都清"也会绿 —— 而那时分段永远只剩最后一段。
    func testSameRoundKeepsAccumulating() {
        var t = RoundTally()
        for _ in 0..<3 { t.add(round: 9, sec: 60, bytes: 1_920_000) }
        XCTAssertEqual(t.parts, 3, "🚨 同一轮被清掉了 —— 分段只会剩最后一段")
        XCTAssertEqual(t.sec, 180, accuracy: 0.001)
    }
}
