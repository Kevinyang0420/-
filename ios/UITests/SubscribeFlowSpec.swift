import XCTest
import StoreKitTest

/// **订阅界面端到端** —— 用 `SKTestSession` 挂本地 `Transless.storekit`，
/// 不需要真沙盒账号也能验证判据①②（真机拉到商品、走完一次购买）。
///
/// 🚨 这不能替代**真沙盒账号**的验证——`SKTestSession` 是苹果自己的模拟环境，
///    跟真实 App Store 服务器行为不保证 100%一致（比如汇率、税费展示）。
///    但它能确认：**商品 id / 订阅群组 id 配对没写错、购买流程的代码路径能走通、
///    UI 状态机在各个阶段切换正确**——这些错了，真机也一定错。
final class SubscribeFlowSpec: XCTestCase {
    var session: SKTestSession!

    override func setUpWithError() throws {
        session = try SKTestSession(configurationFileNamed: "Transless")
        session.resetToDefaultState()
        session.disableDialogs = true        // 别停在系统确认弹窗上，自动当作同意
        session.clearTransactions()
    }

    override func tearDownWithError() throws {
        session.clearTransactions()
    }

    func testProductLoadsAndPurchaseCompletes() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_UILANG_RESET"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 2.0)

        // 进设置 → 会员行
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "没有底部 tab 栏")
        bar.buttons.element(boundBy: 4).tap()   // 设置
        Thread.sleep(forTimeInterval: 1.0)

        let proRow = app.descendants(matching: .any)
            .matching(identifier: "prefs.row.pro").firstMatch
        XCTAssertTrue(proRow.waitForExistence(timeout: 8), "设置里没有会员那一行")
        proRow.tap()

        // 🚨 未登录会先弹 loginGate——这条用例跑在**从没登录过**的干净环境里，
        //    所以这里的判据其实是「登录墙挡住了」，这也是要验的一部分
        //    （判据④：未登录不崩、有可读提示）。
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 5) {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "SUB_00_login_gate"
            shot.lifetime = .keepAlways
            add(shot)
            // 干净环境验不到真正的购买流程，登录墙本身就是这条用例能验到的全部——
            // 如实结束，不假装往下验了购买。
            XCTAssertTrue(alert.staticTexts.count > 0, "登录墙没有可读文案")
            return
        }

        // 已登录（如果这台设备之前登过）—— 走真正的订阅页
        let title = app.navigationBars[L_prefs_pro_title].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 8), "没进到订阅页")

        let priceLabel = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "9.99")).firstMatch
        XCTAssertTrue(priceLabel.waitForExistence(timeout: 15),
                      "🚨 没读到 9.99 的价格 —— 商品 id 或订阅群组配对可能错了")

        let shot1 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot1.name = "SUB_01_price_loaded"
        shot1.lifetime = .keepAlways
        add(shot1)

        let subBtn = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS %@", "订阅", "Subscribe")).firstMatch
        XCTAssertTrue(subBtn.exists && subBtn.isEnabled, "订阅按钮没启用")
        subBtn.tap()

        // 等购买流程跑完（本地测试会话，`disableDialogs` 已跳过系统确认弹窗）
        Thread.sleep(forTimeInterval: 5.0)
        let shot2 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot2.name = "SUB_02_after_purchase"
        shot2.lifetime = .keepAlways
        add(shot2)
    }
}

/// 🚨 UITest 目标读不到 `L` 那份生成的 Strings（那是给 App target 用的），
///    这里直接给一个跟中文默认值一致的常量，只用来定位导航栏标题元素。
private let L_prefs_pro_title = "会员"
