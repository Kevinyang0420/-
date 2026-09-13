import XCTest

/// 一次性探针：列出他手机上真机切键盘循环里出现过的每一个键盘的按钮标签，
/// 用来确认「微信输入法」这个第三方键盘到底装没装、叫什么。
final class ListKeyboards: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testListAllKeyboards() throws {
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
        NSLog("LSKB 进会话了吗=%d", inChat ? 1 : 0)
        XCTAssertTrue(inChat)
        wx.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.945)).tap()
        Thread.sleep(forTimeInterval: 1.6)

        for n in 0..<15 {
            let g = wx.buttons["下一个键盘"]
            guard g.exists, g.isHittable else {
                NSLog("LSKB 第%d轮找不到「下一个键盘」键，停（大概率转完一圈了）", n); break
            }
            var labels: [String] = []
            for i in 0..<min(wx.buttons.count, 80) {
                let b = wx.buttons.element(boundBy: i)
                let s = b.label + "/" + b.identifier
                if s != "/" { labels.append(s) }
            }
            NSLog("LSKB 第%d个键盘｜键数=%d｜%@", n + 1, labels.count, labels.prefix(15).joined(separator: " ｜ "))
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = String(format: "LSKB_%02d", n); shot.lifetime = .keepAlways; add(shot)
            g.tap()
            Thread.sleep(forTimeInterval: 2.5)
        }
    }
}
