import XCTest

/// `ThinkHint` —— 「处理中… 已等 N 秒」的判断逻辑。
///
/// 🚨 重点在**「别覆盖别人」**：Kevin 录 120 秒时看不出「在传/在转/卡住」，
///    秒表是为这个加的；但它一旦盖掉错误提示，就是**用一个没用的信息
///    换掉一个有用的**，而且屏幕上有字、完全不报错。
final class ThinkHintTests: XCTestCase {

    // MARK: 交不交出控制权

    /// 还没接管过 → **不许交**。否则秒表永远起不来。
    func testNeverYieldBeforeOwning() {
        XCTAssertFalse(ThinkHint.shouldYield(owned: "", current: nil))
        XCTAssertFalse(ThinkHint.shouldYield(owned: "", current: "重发中…"))
        XCTAssertFalse(ThinkHint.shouldYield(owned: "", current: ""))
    }

    /// 接管过、文本还是自己那句 → 继续接管。
    func testKeepWhenTextIsStillOurs() {
        XCTAssertFalse(ThinkHint.shouldYield(owned: "处理中… 已等 5 秒",
                                             current: "处理中… 已等 5 秒"))
    }

    /// 🚨 接管过、文本被别人改了（比如报错）→ **立刻交出去**。
    func testYieldWhenSomeoneElseWrote() {
        XCTAssertTrue(ThinkHint.shouldYield(owned: "处理中… 已等 5 秒",
                                            current: "网络不通，重发一次试试"))
        XCTAssertTrue(ThinkHint.shouldYield(owned: "处理中… 已等 5 秒",
                                            current: nil),
                      "🚨 被清空也算别人写的 —— 继续接管会把空白又填上")
    }

    // MARK: 显示什么

    /// 安静期内不出手。
    func testQuietPeriod() {
        for n in 0..<ThinkHint.quietSec {
            XCTAssertNil(ThinkHint.line(elapsed: n, template: "已等 %1$@ 秒"),
                         "🚨 第 \(n) 秒就抢过来了，`setPhase` 传的那句没人看得见")
        }
    }

    /// 到点了就出手，而且**秒数真的填进去了**。
    /// 🚨 反向对照：只测"非 nil"的话，返回没替换的模板也会绿，
    ///    而那时用户看到的是字面的 `%1$@`。
    func testFillsElapsedSeconds() {
        let s = ThinkHint.line(elapsed: 7, template: "处理中… 已等 %1$@ 秒")
        XCTAssertEqual(s, "处理中… 已等 7 秒")
        XCTAssertFalse(s?.contains("%1$@") ?? true,
                       "🚨 占位符没被替换 —— 屏幕上会出现字面的 %1$@")
    }

    /// 秒数会变 —— 「还活着」和「卡死了」就是靠这个区分的。
    func testValueChangesOverTime() {
        let a = ThinkHint.line(elapsed: 5, template: "已等 %1$@ 秒")
        let b = ThinkHint.line(elapsed: 6, template: "已等 %1$@ 秒")
        XCTAssertNotEqual(a, b,
                          "🚨 两秒显示同一句 —— 那跟一个不动的转圈没区别，"
                          + "他还是分不出卡没卡住")
    }
}
