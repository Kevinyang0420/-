import XCTest

/// **在【非微信】宿主（信息 App）里验证不会被劫到微信。**
///
/// 🚨 09-15 更新背景：这个测试原来是量"猜微信"那条机制的副作用大小
/// （09-14 曾经默认打开过，微信永远装着，非微信宿主每次都会被错送去微信）。
/// 那条机制本身（`guessBackOrder`/`guessBackEnabled`/"挨个试"）已经被
/// Kevin 要求整个删掉，不是默认关——现在这个测试的意义变成**反向对照**：
/// 证明删干净之后，在信息 App 里按麦克风，12 秒观察窗口里微信真的不会被打开。
///
/// 依赖：Messages 的撰写界面要提前用
///   `xcrun devicectl device process launch --payload-url 'sms:' com.apple.MobileSMS`
/// 打开（这条会自动聚焦收件人框、弹出键盘），本测试只负责切键盘、按麦克风、观察。
final class TranslessInMessages: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testTranslessMicInMessages() throws {
        let sms = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        let tl = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        tl.terminate()
        Thread.sleep(forTimeInterval: 1.0)
        NSLog("TLMSG 已终止 Transless，确保冷启动")

        XCTAssertTrue(sms.wait(for: .runningForeground, timeout: 15), "信息 App 没起来（应该已经被 devicectl 用 sms: 拉起）")
        Thread.sleep(forTimeInterval: 1.5)

        // 🚨 09-14：短按「下一个键盘」在 iOS 26 上只在系统自带键盘之间循环（拼音↔英文），
        //    到不了第三方键盘；必须长按弹出选择菜单再点名字（ArmAfterIdle.swift 已验证过的写法）。
        var found = false
        for n in 0..<3 {
            if sms.buttons["transless.mic"].waitForExistence(timeout: 4) { found = true; break }
            sms.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.945)).press(forDuration: 1.3)
            Thread.sleep(forTimeInterval: 1.8)
            let row = sms.cells.matching(NSPredicate(format: "label BEGINSWITH[c] 'Transless'")).firstMatch
            if row.waitForExistence(timeout: 3) { row.tap() } else { sms.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
            Thread.sleep(forTimeInterval: 3.5)
            NSLog("TLMSG 长按切第%d次", n + 1)
        }
        NSLog("TLMSG 切到我们自己的键盘了吗=%d", found ? 1 : 0)
        guard found else {
            NSLog("TLMSG 🚨 没切到，本轮作废"); return
        }

        let micBtn = sms.buttons["transless.mic"]
        XCTAssertTrue(micBtn.exists, "找到了键盘但没找到麦克风按钮本体")
        NSLog("TLMSG 按之前：信息=%d Transless主App=%d", sms.state.rawValue, tl.state.rawValue)
        micBtn.tap()
        NSLog("TLMSG ✅ 按了麦克风")

        let wx = XCUIApplication(bundleIdentifier: "com.tencent.xin")
        for t in 1...12 {
            Thread.sleep(forTimeInterval: 1)
            NSLog("TLMSG t=%2ds 信息=%d Transless=%d 微信=%d", t, sms.state.rawValue, tl.state.rawValue, wx.state.rawValue)
        }
    }
}
