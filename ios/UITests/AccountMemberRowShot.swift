import XCTest

/// 快速视觉核对：会员行搬进账户页之后长什么样，设置页里那一行真的消失了没有。
final class AccountMemberRowShot: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testShotAccountAndPrefs() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "App 没起来")
        Thread.sleep(forTimeInterval: 2)

        // 底部 tab 栏最后一个是设置
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "没有底部 tab 栏")
        bar.buttons.element(boundBy: 4).tap()
        Thread.sleep(forTimeInterval: 1.0)

        let proRowInPrefs = app.descendants(matching: .any)
            .matching(identifier: "prefs.row.pro").firstMatch
        NSLog("AMRS 设置页里还有没有会员行=%d（应该是 0）", proRowInPrefs.exists ? 1 : 0)
        let shot0 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot0.name = "AMRS_00_prefs_no_member_row"; shot0.lifetime = .keepAlways; add(shot0)

        // 点"账户"那一行 -> 账户页
        let acctRow = app.staticTexts[L_account_title].firstMatch
        if acctRow.waitForExistence(timeout: 5) {
            acctRow.tap()
        } else {
            NSLog("AMRS 🚨 没找到「账户」文字行，改点左上角小人")
            app.buttons.element(boundBy: 0).tap()
        }
        Thread.sleep(forTimeInterval: 1.5)

        let proRowInAccount = app.descendants(matching: .any)
            .matching(identifier: "account.row.pro").firstMatch
        NSLog("AMRS 账户页里有没有会员行=%d（应该是 1）", proRowInAccount.exists ? 1 : 0)
        let shot1 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot1.name = "AMRS_01_account_with_member_row"; shot1.lifetime = .keepAlways; add(shot1)

        if proRowInAccount.exists {
            proRowInAccount.tap()
            Thread.sleep(forTimeInterval: 1.5)
            let shot2 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot2.name = "AMRS_02_after_tap_subscribe"; shot2.lifetime = .keepAlways; add(shot2)
            NSLog("AMRS 点了会员行之后的导航标题=%@", app.navigationBars.firstMatch.identifier)
        }
    }
}

private let L_account_title = "账户"
