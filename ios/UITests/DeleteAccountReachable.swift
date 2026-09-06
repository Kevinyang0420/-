import XCTest

/// **「删除账号」在 App 里点得到** —— 0 台账 #72，**卡 iOS 提交**。
///
/// App Store 明确要求 App 内提供账号删除入口；网页那条（已上线）不算。
///
/// 🚨 **判据是"点得到并走到那一屏"，不是"代码里有这个类"。**
///    0 的原话：今晚我们已经在「写好了没接上」这一族上栽过四次
///    （`apply_overrides()` / `p_lang` / `menu.try` / 我那批按旧文案定位的用例）——
///    **它们全都不报错**。所以这条从设置一路点进去。
///
/// 🚨 **这条测不到"真能删"**：发码要真发短信，我不发。
///    能验的是「入口可达 + 那一屏的控件齐全 + 服务端说没开时如实告诉他」。
///    真删一次要拿真号走，那一步在 Kevin 或 4 手上。**我不把「写了」说成「验了」。**
final class DeleteAccountReachable: XCTestCase {

    func testEntryIsReachableFromSettings() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_SEED_CARD"] = "1"   // 装成已登录
        app.launchEnvironment["TRANSLESS_UILANG_RESET"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        // 设置 → 我的账户 → 删除账号
        let tabSet = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "设置", "Settings")).firstMatch
        XCTAssertTrue(tabSet.waitForExistence(timeout: 8), "🚨 找不到设置 tab")
        tabSet.tap()
        Thread.sleep(forTimeInterval: 1.5)

        let acct = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS %@",
            "账户", "Account")).firstMatch
        if !acct.waitForExistence(timeout: 6) { app.swipeUp() }
        XCTAssertTrue(acct.waitForExistence(timeout: 8), "🚨 设置里找不到账户那一行")
        acct.tap()
        Thread.sleep(forTimeInterval: 2.0)

        let del = app.buttons["account.delete"]
        XCTAssertTrue(del.waitForExistence(timeout: 8),
                      "🚨 账户页上没有「删除账号」—— App Store 会因为这个拒收")
        del.tap()
        Thread.sleep(forTimeInterval: 2.0)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "DEL_删除账号页"; shot.lifetime = .keepAlways; add(shot)

        // 那一屏该有的东西
        XCTAssertTrue(app.staticTexts["del.body"].waitForExistence(timeout: 6),
                      "🚨 没有说清后果 —— 只放一个红按钮不合格")
        XCTAssertTrue(app.textFields["del.target"].exists, "🚨 没有账号输入框")
        XCTAssertTrue(app.buttons["del.send"].exists, "🚨 没有发送验证码")
        XCTAssertTrue(app.textFields["del.code"].exists, "🚨 没有验证码输入框")
        XCTAssertTrue(app.buttons["del.confirm"].exists, "🚨 没有确认删除")

        // 🚨 **反向对照**：不填验证码点确认，必须给出提示，
        //    **不许静默** —— 静默和"点了没反应"分不开。
        app.buttons["del.confirm"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        let hint = app.staticTexts["del.hint"]
        XCTAssertTrue(hint.exists && !hint.label.isEmpty,
                      "🚨 没填验证码就点确认，提示行是空的 —— 他分不出是没反应还是没填")
    }
}
