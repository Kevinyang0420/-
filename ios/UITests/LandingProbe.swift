import XCTest

/// **只做一件事：盯着「短信」的前后台状态，看跳转之后他会不会被送回来。**
///
/// 🚨 Kevin：「我从短信打开它，它还是会回到微信」——那是我硬编码的兜底，已删。
///    现在走 `_deactivateForReason:`（不需要认出宿主）。
///    判据：**短信重新变成前台（state=4）**。
///    我在外面用 Darwin 通知触发跳转，这里只负责看。
final class LandingProbe: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testWhereDoWeLand() throws {
        let sms = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        let us = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        sms.activate()
        XCTAssertTrue(sms.wait(for: .runningForeground, timeout: 20), "短信没起来")
        NSLog("LAND 短信已在前台，开始观察 40 秒（外部会触发跳转）")
        var sawUsFg = false
        var backToSms = false
        for t in 1...40 {
            Thread.sleep(forTimeInterval: 1)
            let s = sms.state.rawValue, u = us.state.rawValue
            if u == 4 { sawUsFg = true }
            if sawUsFg && s == 4 { backToSms = true }
            NSLog("LAND t=%ds 短信=%d 我们=%d%@", t, s, u,
                  backToSms ? " ← 回到短信了" : "")
            if backToSms { break }
        }
        NSLog("LAND 【判据】我们跳出来过吗=%d；之后回到短信了吗=%d",
              sawUsFg ? 1 : 0, backToSms ? 1 : 0)
    }
}
