import XCTest

/// 🚨🚨 P0（0 09-15）：苹果手上审的是 1359，不是我们现在装的 1375。
/// 要判定"苹果那版会不会也崩"，必须从 TestFlight 真装 1359 覆盖过去测，
/// **不许 rebuild 一个"应该等于 1359"的包**——那不是 1359。
/// 这条先只做一件事：把 TestFlight 当前屏幕内容念出来，看清楚要点哪里。
final class TestFlightInstallProbe: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testDumpTestFlightScreen() throws {
        let tf = XCUIApplication(bundleIdentifier: "com.apple.TestFlight")
        XCTAssertTrue(tf.wait(for: .runningForeground, timeout: 15), "TestFlight没起来")
        Thread.sleep(forTimeInterval: 2.0)
        let texts = tf.staticTexts.allElementsBoundByIndex.prefix(40).map { $0.label }
        NSLog("TFP 首屏文字=%@", texts.joined(separator: " | "))
        let btns = tf.buttons.allElementsBoundByIndex.prefix(40).map { $0.label }
        NSLog("TFP 首屏按钮=%@", btns.joined(separator: " | "))
        let cells = tf.cells.allElementsBoundByIndex.prefix(20).map { $0.label }
        NSLog("TFP 首屏cell=%@", cells.joined(separator: " | "))
    }

    /// 找到了:"此 App 已经安装。你要用测试版本来替换 App 的当前版本吗？"
    /// 这个系统级确认框——之前那轮点了"安装"之后一直卡在这没进展。点"安装"确认替换。
    func testConfirmReplace() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let confirmBtn = springboard.buttons["安装"]
        let found = confirmBtn.waitForExistence(timeout: 5)
        NSLog("TFP 找到替换确认框里的'安装'按钮吗=%d", found ? 1 : 0)
        if found {
            confirmBtn.tap()
            NSLog("TFP 已点确认框'安装'")
        } else {
            let tf = XCUIApplication(bundleIdentifier: "com.apple.TestFlight")
            let confirmBtn2 = tf.buttons["安装"]
            if confirmBtn2.waitForExistence(timeout: 3) {
                confirmBtn2.tap()
                NSLog("TFP 已点TestFlight内的确认'安装'")
            }
        }
        for t in 1...40 {
            Thread.sleep(forTimeInterval: 2.0)
            let tf = XCUIApplication(bundleIdentifier: "com.apple.TestFlight")
            let btns = tf.buttons.allElementsBoundByIndex.prefix(15).map { $0.label }
            NSLog("TFP t=%2ds 按钮=%@", t * 2, btns.joined(separator: " | "))
            if btns.contains(where: { $0.contains("打开") || $0.contains("Open") }) {
                NSLog("TFP 安装完成(出现'打开'按钮)")
                break
            }
        }
    }

    func testScreenshotNow() throws {
        let tf = XCUIApplication(bundleIdentifier: "com.apple.TestFlight")
        _ = tf.wait(for: .runningForeground, timeout: 8)
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = "tf_now.png"
        att.lifetime = .keepAlways
        add(att)
        NSLog("TFP 已截图tf_now.png")
    }

    /// 点"安装"，把 1359 真装上去(会覆盖现在装的开发签名 1375)。
    func testInstallBuild1359() throws {
        let tf = XCUIApplication(bundleIdentifier: "com.apple.TestFlight")
        XCTAssertTrue(tf.wait(for: .runningForeground, timeout: 15), "TestFlight没起来")
        Thread.sleep(forTimeInterval: 1.5)

        // 🚨 首屏可能盖着隐私同意提示("崩溃日志、使用信息和反馈…"),挡住下面的
        // "安装"按钮点不到——先把它点掉。
        let continueBtn = tf.buttons["继续"]
        if continueBtn.waitForExistence(timeout: 3) {
            continueBtn.tap()
            NSLog("TFP 已点掉隐私同意提示('继续')")
            Thread.sleep(forTimeInterval: 1.0)
        }

        let installBtn = tf.buttons["安装"].firstMatch
        XCTAssertTrue(installBtn.waitForExistence(timeout: 8), "找不到'安装'按钮")
        installBtn.tap()
        NSLog("TFP 已点'安装'")

        // 安装需要时间,轮询按钮文字变化(安装中... → 打开/更新完成之类)。
        for t in 1...30 {
            Thread.sleep(forTimeInterval: 2.0)
            let btns = tf.buttons.allElementsBoundByIndex.prefix(15).map { $0.label }
            NSLog("TFP t=%2ds 按钮=%@", t * 2, btns.joined(separator: " | "))
            if btns.contains(where: { $0.contains("打开") || $0.contains("Open") }) {
                NSLog("TFP 安装完成(出现'打开'按钮)")
                break
            }
        }
    }
}
