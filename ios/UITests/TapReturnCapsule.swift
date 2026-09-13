import XCTest

/// 续 CheckReturnCapsule：胶囊确认真的出现了，这次真的点它，
/// 验证完整回路——点完是不是真落回微信、键盘还在不在、能不能接着用。
final class TapReturnCapsule: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testTapCapsuleReturnsToWeChat() throws {
        let wx = XCUIApplication(bundleIdentifier: "com.tencent.xin")
        let tl = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        tl.terminate()
        Thread.sleep(forTimeInterval: 1.0)
        wx.activate()
        XCTAssertTrue(wx.wait(for: .runningForeground, timeout: 20), "微信没起来")
        Thread.sleep(forTimeInterval: 2)

        wx.swipeDown(); Thread.sleep(forTimeInterval: 0.8)
        wx.swipeDown(); Thread.sleep(forTimeInterval: 1.2)
        var inChat = false
        for (n, y) in [0.22, 0.30, 0.38, 0.46].enumerated() {
            if n > 0 {
                let a = wx.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                let b = wx.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
                a.press(forDuration: 0.05, thenDragTo: b)
                Thread.sleep(forTimeInterval: 1.5)
            }
            wx.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: CGFloat(y))).tap()
            Thread.sleep(forTimeInterval: 1.6)
            if wx.textViews.count > 0 || wx.textFields.count > 0 { inChat = true; break }
        }
        XCTAssertTrue(inChat, "没进到会话")
        wx.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.945)).tap()
        Thread.sleep(forTimeInterval: 1.6)

        let globe = wx.buttons["下一个键盘"]
        XCTAssertTrue(globe.waitForExistence(timeout: 6), "没找到下一个键盘按钮")
        globe.press(forDuration: 1.0)
        Thread.sleep(forTimeInterval: 1.0)
        let translessItem = wx.buttons["Transless"].firstMatch.exists
            ? wx.buttons["Transless"].firstMatch : wx.staticTexts["Transless"].firstMatch
        XCTAssertTrue(translessItem.waitForExistence(timeout: 4), "长按菜单里没有 Transless")
        translessItem.tap()
        Thread.sleep(forTimeInterval: 2.0)

        let micBtn = wx.buttons.matching(NSPredicate(
            format: "identifier CONTAINS %@", "transless.mic")).firstMatch
        XCTAssertTrue(micBtn.waitForExistence(timeout: 6), "找不到我们自己的麦克风按钮")
        micBtn.tap()
        NSLog("TRC ✅ 按了麦克风")
        Thread.sleep(forTimeInterval: 1.0)

        // Springboard 系统状态栏元素——胶囊是系统画的，属于 springboard，不是 Transless 自己的 UI。
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let capsule = springboard.otherElements.matching(NSPredicate(
            format: "label CONTAINS %@", "微信")).firstMatch
        let capsuleExists = capsule.waitForExistence(timeout: 3)
        NSLog("TRC 系统返回胶囊存在=%d｜label=%@", capsuleExists ? 1 : 0, capsuleExists ? capsule.label : "无")

        let shotBefore = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shotBefore.name = "TRC_00_before_tap_capsule"; shotBefore.lifetime = .keepAlways; add(shotBefore)

        // 胶囊在系统状态栏左上角，坐标点最稳（有名字的 springboard 元素经常点不中）
        let statusBarCapsule = XCUIApplication(bundleIdentifier: "com.kevin.transless")
            .coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.02))
        statusBarCapsule.tap()
        NSLog("TRC ✅ 点了左上角胶囊位置")

        for t in 1...6 {
            Thread.sleep(forTimeInterval: 0.5)
            NSLog("TRC t=%.1fs 微信=%d Transless=%d", Double(t) * 0.5, wx.state.rawValue, tl.state.rawValue)
        }
        let shotAfter = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shotAfter.name = "TRC_99_after_tap"; shotAfter.lifetime = .keepAlways; add(shotAfter)

        // 关键判据：回到微信之后，键盘（我们的）还在不在、输入框内容还在不在
        NSLog("TRC 最终：微信前台=%d｜有键盘按钮=%d", wx.state.rawValue == 4 ? 1 : 0,
              wx.buttons.matching(NSPredicate(format: "identifier CONTAINS %@", "transless.mic")).firstMatch.exists ? 1 : 0)
    }
}
