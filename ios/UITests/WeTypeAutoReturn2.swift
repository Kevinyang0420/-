import XCTest

/// 续 WeTypeAutoReturn：上一轮只是切到了「按住 说话」这个条形按钮，
/// 还没真的按下去录音。这次做真实的「press and hold」手势，模拟真实说话，
/// 松手之后**完全不再碰任何东西**，只看微信状态会不会自己变化。
final class WeTypeAutoReturn2: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testWeTypeHoldToTalk() throws {
        let wx = XCUIApplication(bundleIdentifier: "com.tencent.xin")
        wx.activate()
        XCTAssertTrue(wx.wait(for: .runningForeground, timeout: 20), "微信没起来")
        Thread.sleep(forTimeInterval: 2)

        // 这一轮微信应该还停在上一轮切好的「按住 说话」界面（同一个会话）。
        // 如果不在了，走一遍同样的进会话流程保底。
        if wx.buttons["按住 说话"].firstMatch.waitForExistence(timeout: 3) == false {
            wx.swipeDown(); Thread.sleep(forTimeInterval: 0.8)
            wx.swipeDown(); Thread.sleep(forTimeInterval: 1.2)
            for (n, y) in [0.22, 0.30, 0.38, 0.46].enumerated() {
                if n > 0 {
                    let a = wx.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                    let b = wx.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
                    a.press(forDuration: 0.05, thenDragTo: b)
                    Thread.sleep(forTimeInterval: 1.5)
                }
                wx.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: CGFloat(y))).tap()
                Thread.sleep(forTimeInterval: 1.6)
                if wx.textViews.count > 0 || wx.textFields.count > 0 { break }
            }
            wx.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.945)).tap()
            Thread.sleep(forTimeInterval: 1.6)
        }

        let holdBtn = wx.buttons["按住 说话"].firstMatch
        guard holdBtn.waitForExistence(timeout: 6) else {
            NSLog("WTAR2 🚨 没找到「按住 说话」按钮，键盘可能换回去了")
            for i in 0..<min(wx.buttons.count, 40) {
                let b = wx.buttons.element(boundBy: i)
                if b.exists, !b.label.isEmpty { NSLog("WTAR2   按钮[%d] \"%@\"", i, b.label) }
            }
            return
        }

        NSLog("WTAR2 按住之前：微信=%d", wx.state.rawValue)
        // 真实的「按住说话」手势：按下、保持 3 秒（模拟说了一句话）、松开
        holdBtn.press(forDuration: 3.0)
        NSLog("WTAR2 ✅ 已经按住说了 3 秒并松开 —— 接下来 20 秒【绝不再碰任何东西】，只看状态")

        for t in 1...20 {
            Thread.sleep(forTimeInterval: 1)
            NSLog("WTAR2 t=%2ds 微信=%d", t, wx.state.rawValue)
            if t == 2 || t == 5 || t == 10 || t == 20 {
                let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                s.name = String(format: "WTAR2_%02d", t); s.lifetime = .keepAlways; add(s)
            }
        }
    }
}
