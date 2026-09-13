import XCTest

/// **核心问题**：Kevin 坚持「微信输入法不管在哪个 App 里用，按完麦克风系统会自己
/// 把你带回原 App，不用你自己点」。用长按"下一个键盘"弹出选择菜单直接点名切过去
/// （短按循环那条路 15 次都没轮到它，另一条测试已证实），
/// 切到之后按它的语音输入按钮，然后**全程不再碰任何东西**，只看微信状态。
final class WeTypeAutoReturn: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testWeTypeReturnsAutomatically() throws {
        let wx = XCUIApplication(bundleIdentifier: "com.tencent.xin")
        wx.activate()
        XCTAssertTrue(wx.wait(for: .runningForeground, timeout: 20), "微信没起来")
        Thread.sleep(forTimeInterval: 3)

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
        NSLog("WTAR 进会话了吗=%d", inChat ? 1 : 0)
        XCTAssertTrue(inChat)
        wx.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.945)).tap()
        Thread.sleep(forTimeInterval: 1.6)

        // 长按"下一个键盘"弹出选择菜单，直接点名找「微信输入法」
        let globe = wx.buttons["下一个键盘"]
        XCTAssertTrue(globe.waitForExistence(timeout: 6), "没找到下一个键盘按钮")
        globe.press(forDuration: 1.0)
        Thread.sleep(forTimeInterval: 1.0)

        let shotMenu = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shotMenu.name = "WTAR_00_picker_menu"; shotMenu.lifetime = .keepAlways; add(shotMenu)

        let weTypeItem = wx.buttons["微信输入法"].firstMatch.exists
            ? wx.buttons["微信输入法"].firstMatch
            : wx.staticTexts["微信输入法"].firstMatch
        guard weTypeItem.waitForExistence(timeout: 4) else {
            NSLog("WTAR 🚨 长按菜单里没有「微信输入法」——把菜单项打出来看看")
            for i in 0..<min(wx.buttons.count, 30) {
                let b = wx.buttons.element(boundBy: i)
                if b.exists, !b.label.isEmpty { NSLog("WTAR   菜单项[%d] \"%@\"", i, b.label) }
            }
            return
        }
        weTypeItem.tap()
        Thread.sleep(forTimeInterval: 3.0)
        NSLog("WTAR ✅ 已切到微信输入法")

        let shot0 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot0.name = "WTAR_01_wetype_shown"; shot0.lifetime = .keepAlways; add(shot0)

        // 把它键盘上的按钮全打出来，找语音输入那个键（别猜坐标）
        var labels: [String] = []
        for i in 0..<min(wx.buttons.count, 60) {
            let b = wx.buttons.element(boundBy: i)
            let s = b.label + "/" + b.identifier
            if s != "/" { labels.append(s) }
        }
        NSLog("WTAR 微信输入法按钮：%@", labels.joined(separator: " ｜ "))

        let micNames = ["语音", "按住说话", "语音输入", "voice", "speech", "mic"]
        var micBtn: XCUIElement? = nil
        for i in 0..<min(wx.buttons.count, 60) {
            let b = wx.buttons.element(boundBy: i)
            if micNames.contains(where: { b.label.lowercased().contains($0.lowercased())
                                        || b.identifier.lowercased().contains($0.lowercased()) }) {
                micBtn = b; break
            }
        }
        guard let mic = micBtn else {
            NSLog("WTAR 🚨 没找到语音相关按钮，本轮到此为止（上面已经打出全部按钮名）")
            return
        }
        NSLog("WTAR 按之前：微信=%d", wx.state.rawValue)
        mic.tap()
        NSLog("WTAR ✅ 按了微信输入法的语音键 —— 接下来 20 秒【绝不再碰任何东西】，只看状态")

        // 🚨 关键：这之后一次都不再合成任何点击/按键，纯观察。
        for t in 1...20 {
            Thread.sleep(forTimeInterval: 1)
            NSLog("WTAR t=%2ds 微信=%d", t, wx.state.rawValue)
        }
        let shotEnd = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shotEnd.name = "WTAR_99_end"; shotEnd.lifetime = .keepAlways; add(shotEnd)
    }
}
