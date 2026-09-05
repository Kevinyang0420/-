import XCTest

/// **只做一件事：把 Transless 键盘顶出来，然后举着 100 秒。**
///
/// 🚨 为什么需要它：键盘扩展只在真的被调出来时才有进程。
///    要在**干净条件**（主 App 已死、没人握麦克风）下测「键盘能不能自己录音」，
///    就得有人把键盘举着 —— 外面的脚本趁这段时间杀主 App、发 `debug.kbmic`。
///
/// 这个测试**不做任何判断**，判断在外面的脚本里（读手机痕迹）。
/// 它只负责制造现场，所以不该有断言。
final class HoldKeyboardUp: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    func testHoldUp() throws {
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
        NSLog("HOLD 进会话了吗=%d", inChat ? 1 : 0)
        wx.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.945)).tap()
        Thread.sleep(forTimeInterval: 1.6)

        // 不是我们的键盘就循环切
        let globe = wx.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.945))
        for n in 0..<10 where !wx.buttons["transless.mic"].exists {
            globe.tap()
            Thread.sleep(forTimeInterval: 1.5)
            NSLog("HOLD 切第%d次，麦克风键在不在=%d", n + 1,
                  wx.buttons["transless.mic"].exists ? 1 : 0)
        }
        let up = wx.buttons["transless.mic"].exists
        NSLog("HOLD 键盘顶出来了吗=%d —— 外面的脚本从现在开始有 100 秒", up ? 1 : 0)
        // 🚨 只举着，不点。点了就会起录，那会把"谁握着麦克风"这个条件弄脏。
        Thread.sleep(forTimeInterval: 100)
        NSLog("HOLD 举完了")
    }
}
