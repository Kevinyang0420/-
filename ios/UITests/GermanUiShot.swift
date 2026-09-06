import XCTest

/// **切到德文，看整屏是不是真的德文** —— 终点判据在他屏幕上，不在我这边。
///
/// 🚨 Kevin 2026-09-06：「德文、西班牙文那些出来了，**但我点进去之后，
///    发现它的界面语言还是英文**。」
///    根因是每条文案只有 zh/en/hant 三个键，`m["de"]` 取不到就按设计落 `en` ——
///    **回落逻辑在正确工作，缺的是数据。**
///
/// 🚨 **不能靠"我合并跑过了"交差**：合并这种活的典型失败是**部分合上**，
///    抽样对了只证明那一条对。条数由闸门查，**这一屏查的是"他真的能看到"**。
final class GermanUiShot: XCTestCase {

    func testShotGerman() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        // 🚨 直接把界面语言偏好设成 de —— 走 App 自己那套 `Lang`，
        //    不是改系统语言：我们这套本来就不读系统 locale（09-05 修过）。
        app.launchEnvironment["TRANSLESS_UI_LANG"] = "de"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "DE_01_首页"
        a.lifetime = .keepAlways
        add(a)

        // 设置页：行多、字多，最容易看出有没有漏译
        let bar = app.tabBars.firstMatch
        if bar.waitForExistence(timeout: 8) {
            let b = bar.buttons.element(boundBy: 4)
            if b.exists, b.isHittable {
                b.tap()
                Thread.sleep(forTimeInterval: 1.2)
                let c = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                c.name = "DE_02_设置"
                c.lifetime = .keepAlways
                add(c)
            }
        }
    }
}
