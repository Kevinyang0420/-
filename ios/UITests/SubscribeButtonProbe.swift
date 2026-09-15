import XCTest

/// 0要的判据：真机点一次订阅，看走的是「拿不到purchase_uuid」还是
/// 「Product.products(for:) 返回空」——不加解读，只把 KbBridge.note 原文贴出来。
final class SubscribeButtonProbe: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testTapSubscribe() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.terminate()
        Thread.sleep(forTimeInterval: 1.0)
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "App 没起来")
        Thread.sleep(forTimeInterval: 2)

        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "没有底部 tab 栏")
        bar.buttons.element(boundBy: 4).tap()
        Thread.sleep(forTimeInterval: 1.0)

        let proRow = app.descendants(matching: .any).matching(identifier: "account.row.pro").firstMatch
        if !proRow.waitForExistence(timeout: 5) {
            NSLog("SBP 🚨 没找到account.row.pro，改点账户文字行")
            app.staticTexts["账户"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
        let proRow2 = app.descendants(matching: .any).matching(identifier: "account.row.pro").firstMatch
        XCTAssertTrue(proRow2.waitForExistence(timeout: 5), "账户页里没找到会员行")
        proRow2.tap()
        Thread.sleep(forTimeInterval: 2.5)

        let shot0 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot0.name = "SBP_00_subscribe_page"; shot0.lifetime = .keepAlways; add(shot0)

        // 找订阅按钮（没有 accessibilityIdentifier，按可见按钮里"非返回"的那个找）
        let buttons = app.buttons.allElementsBoundByIndex
        NSLog("SBP 订阅页按钮列表：%@", buttons.map { "\($0.label)/enabled=\($0.isEnabled)" }.joined(separator: " | "))
        let staticTexts = app.staticTexts.allElementsBoundByIndex
        NSLog("SBP 订阅页文字列表：%@", staticTexts.map { $0.label }.joined(separator: " | "))

        // 找标题含"订阅/月/￥/$"字样、看起来是主按钮的那个
        let mainBtn = buttons.first { $0.label.contains("订阅") || $0.label.contains("Subscribe") }
        if let btn = mainBtn {
            NSLog("SBP 找到订阅按钮：label=%@ enabled=%d", btn.label, btn.isEnabled ? 1 : 0)
            if btn.isEnabled {
                btn.tap()
                NSLog("SBP ✅ 点了订阅按钮")
                Thread.sleep(forTimeInterval: 3)
            } else {
                NSLog("SBP 🚨 按钮是禁用状态，点了也不会有反应（这可能就是 Kevin 说的'一点反应也没有'）")
            }
        } else {
            NSLog("SBP 🚨 没找到订阅按钮")
        }

        let shot1 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot1.name = "SBP_01_after_tap"; shot1.lifetime = .keepAlways; add(shot1)
    }
}
