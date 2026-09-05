import XCTest

/// 自动点灵动岛上的「点这里开始录音」按钮（AudioRecordingIntent）—— 替 Kevin 点，测「用户点岛能不能换来后台麦克风」。
/// 目标是 SpringBoard：先长按灵动岛展开，再点那个按钮。找不到就把无障碍树打出来学结构。
final class TapIsland: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testTapIslandButton() throws {
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        sb.activate()
        Thread.sleep(forTimeInterval: 2.0)

        // 直接按 label 找（有些系统版本灵动岛按钮在树里可直接命中）
        func findBtn() -> XCUIElement {
            sb.buttons.matching(NSPredicate(format: "label CONTAINS[c] '开始录音'")).firstMatch
        }
        var btn = findBtn()
        if !btn.waitForExistence(timeout: 3) {
            // 长按灵动岛（顶部中央）展开
            NSLog("TAPI 直接没找到，长按灵动岛展开")
            sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.013)).press(forDuration: 0.9)
            Thread.sleep(forTimeInterval: 1.6)
            btn = findBtn()
        }
        if btn.waitForExistence(timeout: 4) {
            NSLog("TAPI ✅ 找到按钮，点它：%@", btn.label)
            btn.tap()
            Thread.sleep(forTimeInterval: 1.0)
            // 说话由外部设备念；这里多停让后台录音跑起来
            Thread.sleep(forTimeInterval: 8.0)
        } else {
            NSLog("TAPI 🚨 展开后仍没按钮。把 SpringBoard 顶部区域的树打出来学结构：")
            NSLog("TAPI TREE %@", sb.debugDescription)
            // 兜底：也许在锁屏/通知中心，拉一下通知中心再找
            sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.0)).press(forDuration: 0.1, thenDragTo: sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
            Thread.sleep(forTimeInterval: 1.5)
            let b2 = findBtn()
            if b2.waitForExistence(timeout: 3) { NSLog("TAPI ✅ 通知中心里找到，点它"); b2.tap(); Thread.sleep(forTimeInterval: 8.0) }
            else { NSLog("TAPI 🚨 通知中心也没有。树：%@", sb.debugDescription) }
        }
    }
}
