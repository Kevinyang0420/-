import XCTest

/// **在真微信里让我们的键盘露面，触发探针读 `_hostApplicationBundleIdentifier`。**
/// 只要键盘在微信里露一次面，探针就会记下真微信宿主下那个方法的返回值 —— 不用录音、不用跳转。
final class HostIDInWeChat: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testHostIDInWeChat() throws {
        let wx = XCUIApplication(bundleIdentifier: "com.tencent.xin")
        wx.activate()
        XCTAssertTrue(wx.wait(for: .runningForeground, timeout: 20), "微信没起来")
        Thread.sleep(forTimeInterval: 3)

        // 进任意一个会话（有输入框才会弹键盘）
        wx.swipeDown(); Thread.sleep(forTimeInterval: 0.8)
        wx.swipeDown(); Thread.sleep(forTimeInterval: 1.2)
        var inChat = false
        for (n, y) in [0.22, 0.30, 0.38, 0.46].enumerated() {
            if n > 0 {
                let a = wx.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                let b = wx.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
                a.press(forDuration: 0.05, thenDragTo: b); Thread.sleep(forTimeInterval: 1.5)
            }
            wx.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: CGFloat(y))).tap()
            Thread.sleep(forTimeInterval: 1.6)
            if wx.textViews.count > 0 || wx.textFields.count > 0 { inChat = true; break }
        }
        NSLog("HWX 进会话=%d（输入框 %d）", inChat ? 1 : 0, wx.textViews.count + wx.textFields.count)
        wx.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.945)).tap()
        Thread.sleep(forTimeInterval: 2.0)

        // 切到我们的键盘（长按地球选 Transless；不行就循环切）
        if !wx.buttons["transless.mic"].exists {
            let globe = wx.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.945))
            globe.press(forDuration: 1.3); Thread.sleep(forTimeInterval: 1.8)
            var picked = false
            let cell = wx.cells.matching(NSPredicate(format: "label BEGINSWITH[c] 'Transless'")).firstMatch
            if cell.waitForExistence(timeout: 3) { cell.tap(); picked = true; NSLog("HWX 选了 Transless cell") }
            if !picked {
                for i in 0..<min(wx.buttons.count, 60) {
                    let b = wx.buttons.element(boundBy: i)
                    if b.exists, b.label.contains("Transless"), b.isHittable { b.tap(); picked = true; NSLog("HWX 选了 Transless 按钮"); break }
                }
            }
            if !picked {
                for n in 0..<8 where !wx.buttons["transless.mic"].exists {
                    globe.tap(); Thread.sleep(forTimeInterval: 1.4)
                    NSLog("HWX 循环切第%d次 麦克风在=%d", n + 1, wx.buttons["transless.mic"].exists ? 1 : 0)
                }
            }
            Thread.sleep(forTimeInterval: 2.0)
        }
        let ok = wx.buttons["transless.mic"].waitForExistence(timeout: 8)
        NSLog("HWX 我们的键盘在微信里露面了吗=%d（这一刻探针已读宿主）", ok ? 1 : 0)
        // 多停一会，让探针的日志落进痕迹
        Thread.sleep(forTimeInterval: 3.0)
    }
}
