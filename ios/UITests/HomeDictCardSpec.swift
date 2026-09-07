import XCTest

/// **首页那张「查词」卡** —— Kevin 09-07 亲口：
/// > 「iOS 的首页只有『随便说点啥』，但是安卓的首页还多了一个『查词』…
/// >   那你就首页多加一个『查词』功能了」
///
/// 🚨 **三条判据，缺一条都会让错的实现全绿**（0 提的反向判据，我认）：
/// 1. 首页有查词卡
/// 2. **主 CTA 仍在** —— 只验第 1 条的话，把主 CTA 换成查词也会绿
/// 3. **点进去后底部 tab 栏仍在** —— 做成盖住 tab 的全屏页也会绿
/// 另加一条我自己要的：
/// 4. **随手翻译页右上角那个查词按钮仍在** —— 他 09-05 单独定的，
///    这次是"多加一个"不是"挪过去"。做没了也会让第 1 条绿。
final class HomeDictCardSpec: XCTestCase {

    func testDictCardAddedWithoutBreakingAnythingElse() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_UILANG_RESET"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "DICT_01_首页"; shot.lifetime = .keepAlways; add(shot)

        // ① 查词卡在
        let dict = app.buttons["app.dict"]
        XCTAssertTrue(dict.waitForExistence(timeout: 10),
                      "🚨 首页没有查词卡")

        // ② 🚨 主 CTA 仍在 —— 没有这条，"把主 CTA 换成查词"也会绿
        let tryCta = app.buttons["app.try"]
        XCTAssertTrue(tryCta.exists, "🚨 主 CTA 没了 —— 我把它换掉了？")
        // 查词卡不该比主 CTA 高（安卓：72 vs 88，玻璃底不抢主 CTA）
        XCTAssertLessThan(dict.frame.height, tryCta.frame.height,
                          "🚨 查词卡比主 CTA 还高 —— 抢了主次")

        // ③ 🚨 点进去后**底部 tab 栏仍在**
        //    Kevin 说过至少两遍「要合在一起，跟那四个 tab 一样合在一个窗口」。
        dict.tap()
        Thread.sleep(forTimeInterval: 2.5)
        let shot2 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot2.name = "DICT_02_点进去"; shot2.lifetime = .keepAlways; add(shot2)
        XCTAssertTrue(app.textFields["dict.field"].waitForExistence(timeout: 8),
                      "🚨 点查词卡没进到查词页")
        let anyTab = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "设置", "Settings")).firstMatch
        XCTAssertTrue(anyTab.exists,
                      "🚨 进查词后底部 tab 栏没了 —— 做成盖住 tab 的全屏页了")
    }
}
