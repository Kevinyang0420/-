import XCTest

/// 一次性：在设置里把「微信输入法」(com.tencent.wetype) 加进已启用键盘列表，
/// 这样后面才能在微信里切到它、真机验证 Kevin 说的"系统自己带回去"到底是不是真的零点击。
final class EnableWeType: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testEnableWeTypeKeyboard() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 15), "设置没打开")
        Thread.sleep(forTimeInterval: 1.5)

        func tapCell(_ name: String, timeout: TimeInterval = 8) -> Bool {
            let cell = settings.staticTexts[name].firstMatch
            guard cell.waitForExistence(timeout: timeout) else {
                NSLog("ENWT 🚨 找不到「%@」", name); return false
            }
            cell.tap(); Thread.sleep(forTimeInterval: 1.2)
            return true
        }

        XCTAssertTrue(tapCell("通用"), "没找到「通用」")
        XCTAssertTrue(tapCell("键盘"), "没找到「通用」里的「键盘」")
        // 🚨 这一页标题也叫「键盘」，页面里那一行显示成「键盘  7  >」——
        //    精确匹配 "键盘" 会打在别的地方，改成找一个同时含"键盘"和数字的可点 cell。
        let kbRow = settings.cells.containing(
            NSPredicate(format: "label CONTAINS %@", "键盘")).firstMatch
        XCTAssertTrue(kbRow.waitForExistence(timeout: 6), "没找到「键盘 N」这一行")
        kbRow.tap()
        Thread.sleep(forTimeInterval: 1.2)

        let shot0 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot0.name = "ENWT_00_keyboards_list"; shot0.lifetime = .keepAlways; add(shot0)

        // 已经启用就不用再加一次
        if settings.staticTexts["微信输入法"].firstMatch.exists {
            NSLog("ENWT 微信输入法已经在启用列表里了，不用再加")
            return
        }

        XCTAssertTrue(tapCell("添加新键盘..."), "没找到「添加新键盘...」")
        Thread.sleep(forTimeInterval: 1.0)

        let shot1 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot1.name = "ENWT_01_add_keyboard_list"; shot1.lifetime = .keepAlways; add(shot1)

        let weTypeCell = settings.staticTexts["微信输入法"].firstMatch
        guard weTypeCell.waitForExistence(timeout: 6) else {
            NSLog("ENWT 🚨 第三方键盘列表里没有「微信输入法」——把可点到的行都打出来看看")
            for i in 0..<min(settings.cells.count, 40) {
                let c = settings.cells.element(boundBy: i)
                if c.exists { NSLog("ENWT   行[%d] \"%@\"", i, c.label) }
            }
            return
        }
        weTypeCell.tap()
        Thread.sleep(forTimeInterval: 1.5)
        NSLog("ENWT ✅ 已点「微信输入法」去启用")

        let shot2 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot2.name = "ENWT_02_after_enable"; shot2.lifetime = .keepAlways; add(shot2)

        // 回到键盘列表页确认它真的进去了
        if settings.navigationBars["键盘"].firstMatch.waitForExistence(timeout: 3) {
            settings.navigationBars.buttons.firstMatch.tap()
            Thread.sleep(forTimeInterval: 1.0)
        }
        let confirmed = settings.staticTexts["微信输入法"].firstMatch.exists
        NSLog("ENWT 【判据】微信输入法现在在已启用列表里吗=%d", confirmed ? 1 : 0)
    }
}
