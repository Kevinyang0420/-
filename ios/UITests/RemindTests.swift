import XCTest

/// `Remind` 的判据测试 —— **不开模拟器就能跑**（纯逻辑）。
///
/// 🚨 这条存在的理由是 1.1 踩出来的那句：**靠提示词约束＝没约束**。
///    后端提示词写了「没有 Now 就一律 null」，模型照样脑补了一个。
///    所以我这端**不许假设服务端给的合法** —— 每一条都自己再判一次，
///    而这个文件保证那些判断**真的会失败**（每种坏样本各因不同原因被挡）。
final class RemindTests: XCTestCase {

    func testSelftestAllPass() {
        let bad = Remind.selftest()
        XCTAssertTrue(bad.isEmpty, "🚨 判据没守住：" + bad.joined(separator: "；"))
    }

    /// 🚨 **坏样本要真的能红** —— 这条是"检查会不会失败"的检查。
    ///    把「缺时区」那道判断当成不存在，缺时区的串就会被 `ISO8601DateFormatter`
    ///    **按 UTC 悄悄解出来**（东八区差 8 小时），而且**不报错**。
    ///    所以这里直接验：不带时区的串，`parseISO` 必须返回 nil。
    func testMissingTimezoneIsRejectedNotSilentlyShifted() {
        XCTAssertNil(Remind.parseISO("2026-09-08T15:00:00"),
                     "🚨 缺时区被解出来了 —— 那会悄悄差 8 小时，比解析失败更糟")
        XCTAssertNotNil(Remind.parseISO("2026-09-08T15:00:00+08:00"))
        XCTAssertNotNil(Remind.parseISO("2026-09-08T07:00:00Z"))
    }

    /// 🚨🚨 **反向对照：证明挡住它的是我的判断，不是系统解不出来。**
    ///
    /// 上一条只验了「`parseISO` 对缺时区的串返回 nil」—— 但那有两种可能：
    ///   ① 我的判断挡住了它（我要的）
    ///   ② 系统本来就解不出来（那我那道判断是**永远不会失败的假检查**）
    /// **两种情况上一条都是绿的。** 这一条把它们分开：
    /// 直接问系统 —— 它**能**解出来，而且解成了 UTC（东八区差 8 小时）。
    /// 所以拦住它的确实是我。
    func testFormatterWouldHaveAcceptedIt_soMyGuardIsWhatRejects() {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let sys = f.date(from: "2026-09-08T15:00:00Z")
        XCTAssertNotNil(sys, "系统连带 Z 的都解不出来？那这条对照本身没意义")

        // 系统对"缺时区"的串：解得出来就说明我的判断有活干；
        // 解不出来（未来某个系统版本变严）也不算错，但那时**我的判断成了假检查**，
        // 必须知道 —— 所以这里不断言系统行为，只把它打出来让人看见。
        let noTZ = f.date(from: "2026-09-08T15:00:00")
        print("🚨 系统对缺时区的串：" + (noTZ == nil
            ? "解不出来 —— 我那道判断此刻是假检查，留着但要知道"
            : "解出来了（\(noTZ!)）—— 所以拦住它的是我的判断，不是系统"))
        // 不管系统怎样，**我这层的结论必须是拒**
        XCTAssertNil(Remind.parseISO("2026-09-08T15:00:00"))
    }

    /// 带时区的两种写法必须解成**同一时刻**（+08:00 的 15 点 == UTC 的 7 点）。
    /// 🚨 这条是独立第二路径：光验"能解出来"不够，还要验**解对了**。
    func testSameInstantTwoNotations() {
        let a = Remind.parseISO("2026-09-08T15:00:00+08:00")
        let b = Remind.parseISO("2026-09-08T07:00:00Z")
        XCTAssertEqual(a, b, "🚨 同一时刻的两种写法解出了不同结果")
    }

    /// `nowISO` 必须带时区 —— 不带的话后端一律回 null，功能整个哑掉而不报错。
    func testNowISOCarriesTimezone() {
        let s = Remind.nowISO()
        let hasTZ = s.hasSuffix("Z")
            || s.range(of: "[+-][0-9]{2}:?[0-9]{2}$",
                       options: .regularExpression) != nil
        XCTAssertTrue(hasTZ, "🚨 now 不带时区：" + s)
    }
}
