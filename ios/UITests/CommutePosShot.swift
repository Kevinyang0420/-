import XCTest

/// **端到端查一次 commute，看词性有没有真的分节** —— Kevin 2026-09-06 报的那条。
///
/// 🚨 我之前只验了**解析层**（纯逻辑：三条义项各自带 v./n./v.）。
///    「解析对了」和「他在屏幕上看得见两节」是两件事 ——
///    今天这个形状已经出现过太多次，所以这条走真实查词、看真实界面。
///
/// 🚨 判据是**分节标题的个数 ≥ 2**，不是"有没有 n. 这两个字"：
///    n. 也可能出现在正文里，那样一个没分节的实现照样绿。
final class CommutePosShot: XCTestCase {

    func testCommuteShowsBothPosSections() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        // 进查词：随手翻译页右上角那个「查词」
        let entry = app.buttons["app.try"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8), "首页找不到入口")
        entry.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let dict = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "查词", "Look up")).firstMatch
        XCTAssertTrue(dict.waitForExistence(timeout: 6), "🚨 找不到查词入口")
        dict.tap()
        Thread.sleep(forTimeInterval: 1.5)

        let field = app.textFields["dict.field"].exists
            ? app.textFields["dict.field"] : app.textViews["dict.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 6), "🚨 找不到查词输入框")
        field.tap()
        field.typeText("commute")
        app.buttons["dict.search"].tap()

        // 🚨 等真实后端返回 —— 不是等固定秒数就断言
        let word = app.staticTexts["dict.word"]
        XCTAssertTrue(word.waitForExistence(timeout: 40),
                      "🚨 40 秒没出卡片（后端没回或网络不通），这条没测到东西")
        Thread.sleep(forTimeInterval: 2.0)

        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "COMMUTE_01_词性分节"; a.lifetime = .keepAlways; add(a)

        let sections = app.descendants(matching: .any)
            .matching(identifier: "dict.pos.section")
        let labels = (0..<sections.count).compactMap { i -> String? in
            let e = sections.element(boundBy: i)
            return e.exists ? e.label : nil
        }
        // 🚨 判据挂在**分节标题的个数**上，不挂在"页面里有没有 n."上 ——
        //    后者在一个完全没分节的实现上也会绿（n. 会出现在正文里）。
        XCTAssertGreaterThanOrEqual(sections.count, 2,
            "🚨 commute 只出了 \(sections.count) 个词性分节（期望 ≥2：v. 和 n.）"
            + "｜标题=\(labels) —— 他看到的就是「只给了动词」")
        XCTAssertTrue(labels.contains { $0.contains("n") },
                      "🚨 分节里没有名词那节：\(labels)")
    }
}
