import XCTest

/// 验证：TRANSLESS_RETURN 默认是 "stay"（不自动退出），冷启动跳转落在 Transless 之后，
/// iOS 会不会真的在左上角画出「‹ 微信」系统返回胶囊。这是四条自动回程路全部证伪之后
/// 唯一还站得住的路径——但从没人专门截图验证过胶囊本身真的出现。
final class CheckReturnCapsule: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testCapsuleAppearsAfterColdJump() throws {
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
        NSLog("CRC 按之前：微信=%d Transless=%d", wx.state.rawValue, tl.state.rawValue)
        micBtn.tap()
        NSLog("CRC ✅ 按了麦克风（冷启动，应该会真跳转）")

        // 冷启动+跳转+架好，按之前代码注释大概 0.5~1.5 秒；给够时间再截图
        for t in 1...8 {
            Thread.sleep(forTimeInterval: 0.5)
            NSLog("CRC t=%.1fs 微信=%d Transless=%d", Double(t) * 0.5, wx.state.rawValue, tl.state.rawValue)
            if tl.state.rawValue == 4 {
                // Transless 真的到前台了——这就是要截的那一刻
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = "CRC_transless_foreground"; shot.lifetime = .keepAlways; add(shot)
                NSLog("CRC ✅ Transless 在前台了，已截图")
                break
            }
        }
        Thread.sleep(forTimeInterval: 1.5)
        let shotFinal = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shotFinal.name = "CRC_final"; shotFinal.lifetime = .keepAlways; add(shotFinal)
        NSLog("CRC 最终状态：微信=%d Transless=%d", wx.state.rawValue, tl.state.rawValue)
    }
}
