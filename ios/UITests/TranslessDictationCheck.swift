import XCTest

/// **核心问题**：`hasDictationKey = true` 已经在 Transless 键盘上设了两周，
/// 但从没人验过它有没有真的让系统在我们键盘上画出听写按钮。今天切到微信输入法
/// 观察到它有一个"语音输入"类的按钮能在不跳转的情况下真转写文字——如果我们的
/// `hasDictationKey` 真的生效，苹果应该会在我们键盘上也画一个系统听写图标
/// （通常在空格键右边或键盘角落）。这条只做**观察**：切到我们自己的键盘，
/// 把所有按钮连坐标打出来，看有没有一个明显是"听写"/麦克风样式的系统按钮，
/// 有就点它看会发生什么，全程记录微信前后台状态。
final class TranslessDictationCheck: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testLookForSystemDictationButton() throws {
        let wx = XCUIApplication(bundleIdentifier: "com.tencent.xin")
        let tl = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        tl.terminate()   // 冷启动，跟 Kevin 真实场景一致
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
        NSLog("TDCK 进会话了吗=%d", inChat ? 1 : 0)
        XCTAssertTrue(inChat)
        wx.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.945)).tap()
        Thread.sleep(forTimeInterval: 1.6)

        // 长按下一个键盘，点名切到 Transless
        let globe = wx.buttons["下一个键盘"]
        XCTAssertTrue(globe.waitForExistence(timeout: 6), "没找到下一个键盘按钮")
        globe.press(forDuration: 1.0)
        Thread.sleep(forTimeInterval: 1.0)

        let translessItem = wx.buttons["Transless"].firstMatch.exists
            ? wx.buttons["Transless"].firstMatch : wx.staticTexts["Transless"].firstMatch
        guard translessItem.waitForExistence(timeout: 4) else {
            NSLog("TDCK 🚨 长按菜单里没有「Transless」")
            for i in 0..<min(wx.buttons.count, 30) {
                let b = wx.buttons.element(boundBy: i)
                if b.exists, !b.label.isEmpty { NSLog("TDCK   菜单项[%d] \"%@\"", i, b.label) }
            }
            return
        }
        translessItem.tap()
        Thread.sleep(forTimeInterval: 3.0)
        NSLog("TDCK ✅ 已切到 Transless 键盘")

        let shot0 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot0.name = "TDCK_00_transless_kb"; shot0.lifetime = .keepAlways; add(shot0)

        let scr = wx.frame
        NSLog("TDCK Transless 键盘上所有按钮：")
        for i in 0..<min(wx.buttons.count, 60) {
            let b = wx.buttons.element(boundBy: i)
            guard b.exists else { continue }
            let f = b.frame
            let s = b.label + "/" + b.identifier
            if s != "/" {
                NSLog("TDCK   \"%@\" 中心(%.2f,%.2f)", s,
                      (f.midX - scr.minX) / scr.width, (f.midY - scr.minY) / scr.height)
            }
        }

        let dictBtn = wx.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@", "dictat", "dictat")).firstMatch
        if dictBtn.exists {
            NSLog("TDCK ✅ 找到疑似系统听写按钮，点它｜按之前微信=%d", wx.state.rawValue)
            dictBtn.tap()
            for t in 1...10 {
                Thread.sleep(forTimeInterval: 1)
                NSLog("TDCK t=%2ds 微信=%d Transless主App=%d", t, wx.state.rawValue,
                      XCUIApplication(bundleIdentifier: "com.kevin.transless").state.rawValue)
            }
        } else {
            NSLog("TDCK 🚨 按钮清单里没有明显的「听写」按钮——hasDictationKey=true 没有让系统画出这个按钮")
        }
        let shotEnd = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shotEnd.name = "TDCK_99_end"; shotEnd.lifetime = .keepAlways; add(shotEnd)
    }
}
