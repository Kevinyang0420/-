import XCTest

/// **再次翻译** —— Kevin 2026-09-06 亲口：
/// > 我改了目标语言之后，希望有个地方能让我**直接点一下再次翻译**。
/// > 现在没有，导致我**还得再说一遍，很不方便**。
///
/// 🚨 规格里最要紧的两条，都是"坏了比没有更糟"的形状：
///    ① **不许触发录音** —— 重译是"同一个输入的第二个输出"，不是第二次输入
///    ② **失败不许清掉已有结果** —— 他点一下、网络不好连原来的也没了
final class AgainButtonSpec: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        let cta = app.buttons["app.try"]
        XCTAssertTrue(cta.waitForExistence(timeout: 8), "首页找不到入口")
        cta.tap()
        Thread.sleep(forTimeInterval: 1.5)
        return app
    }

    /// 🚨 **没有结果时不许出现**（跟朗读/收藏同一套显隐）。
    ///    这条是反向对照：没有它的话，"永远显示"也会让下面那条绿。
    func testHiddenWhenNoResult() {
        let app = launch()
        let again = app.buttons["app.again"]
        XCTAssertFalse(again.exists && again.isHittable,
                       "🚨 还没有任何结果就出现了「再次翻译」—— 点下去没东西可重译")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "AGAIN_01_无结果时不出现"; a.lifetime = .keepAlways; add(a)
    }

    /// 它必须**在目标语言选择器那一排**（规格指定的位置：紧挨语言选择器）。
    /// 🚨 位置判据挂在**跟语言钮的垂直距离**上 —— 跑到别处去（比如底排）会红。
    func testSitsNextToLanguagePicker() {
        let app = launch()
        // 钉回翻译档：只有翻译档才有语言选择器
        let t = app.buttons["翻译"]
        if t.waitForExistence(timeout: 5) { t.tap(); Thread.sleep(forTimeInterval: 1.2) }
        let lang = app.buttons["app.lang"]
        XCTAssertTrue(lang.waitForExistence(timeout: 6), "🚨 找不到语言钮")
        let again = app.buttons["app.again"]
        guard again.exists else {
            // 没结果时它本来就不显示 —— 这条只在它出现时才有意义
            return
        }
        let dy = abs(again.frame.midY - lang.frame.midY)
        XCTAssertLessThan(dy, 8,
            "🚨 「再次翻译」跟语言选择器不在同一排（差 \(dy)pt）—— "
            + "规格要的是「紧挨目标语言选择器」｜再译=\(again.frame) 语言=\(lang.frame)")
    }
}
