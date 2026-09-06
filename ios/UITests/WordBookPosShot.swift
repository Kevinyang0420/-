import XCTest

/// **单词本里的卡片也要有词性** —— Kevin 2026-09-06 20:1x：
/// > 「你是在查词界面里有了动词和名词，但我是在**常用词进去的单词本**里看的，
/// >   单词本那个地方就只有一个动词」
/// > 「它最新的**连动词也没了，完全没标是动词还是名词**」
///
/// 🚨 查词卡对了 ≠ 单词本卡对了 —— **两个界面读的是两份数据**：
///    查词卡读后端刚返回的 `DictEntry`；单词本读**收藏那一刻落盘的 JSON**。
///    今天就是只修了前者。
final class WordBookPosShot: XCTestCase {

    func testSavedCardKeepsPosSections() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_SEED_CARD"] = "1"   // 装成已登录
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        // ① 先查一次 commute 并收藏 —— 走的是他真实的路径
        let entry = app.buttons["app.try"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8), "首页找不到入口")
        entry.tap()
        Thread.sleep(forTimeInterval: 1.2)
        let dict = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "查词", "Look up")).firstMatch
        XCTAssertTrue(dict.waitForExistence(timeout: 6), "🚨 找不到查词入口")
        dict.tap()
        Thread.sleep(forTimeInterval: 1.2)

        let field = app.textFields["dict.field"].exists
            ? app.textFields["dict.field"] : app.textViews["dict.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 6), "🚨 找不到输入框")
        field.tap()
        field.typeText("commute")
        app.buttons["dict.search"].tap()
        XCTAssertTrue(app.staticTexts["dict.word"].waitForExistence(timeout: 40),
                      "🚨 后端没回，这条没测到东西")
        Thread.sleep(forTimeInterval: 1.5)

        let addBtn = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "单词本")).firstMatch
        XCTAssertTrue(addBtn.waitForExistence(timeout: 6), "🚨 找不到「+ 单词本」")
        addBtn.tap()
        Thread.sleep(forTimeInterval: 2.0)

        // ② 进单词本 —— 🚨 **入口在「设置」里，不是「常用词」tab**。
        //    第一版我点了常用词 tab，那是 chips 列表、点了不进详情，
        //    判据于是红在"没有词性"上 —— **而真相是根本没进到那一屏**。
        //    （`MainTabController:18`：「单词本不是最 key 的…所以单词本放设置里」）
        let tabSet = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "设置", "Settings")).firstMatch
        XCTAssertTrue(tabSet.waitForExistence(timeout: 8), "🚨 找不到设置 tab")
        tabSet.tap()
        Thread.sleep(forTimeInterval: 1.5)
        // 🚨 设置里那一行是 `UIControl` 不是 `UIButton`（`AppDelegate:3171`），
        //    所以按**文字**找；UILabel 不接触摸，点击会穿透到那个 UIControl。
        let wbRow = app.staticTexts.matching(NSPredicate(
            format: "label == %@ OR label == %@",
            "单词本", "Word book")).firstMatch
        if !wbRow.waitForExistence(timeout: 6) {
            app.swipeUp()          // 设置页长，可能要滚一下
            Thread.sleep(forTimeInterval: 1.0)
        }
        XCTAssertTrue(wbRow.waitForExistence(timeout: 8), "🚨 设置里找不到单词本那一行")
        wbRow.tap()
        Thread.sleep(forTimeInterval: 2.5)
        let row = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@", "commute")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8),
                      "🚨 单词本里没有 commute —— 收藏那步没成，后面白测")
        row.tap()
        Thread.sleep(forTimeInterval: 3.0)

        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "WBPOS_01_单词本卡片"; a.lifetime = .keepAlways; add(a)

        // 🚨 判据：卡片正文里要同时出现 v. 和 n. 两个分节标题。
        //    用 staticTexts 全文扫 —— 单词本这一屏是拼好的文本块，没有独立标识。
        let all = app.staticTexts
        var texts: [String] = []
        for i in 0..<min(all.count, 80) where all.element(boundBy: i).exists {
            texts.append(all.element(boundBy: i).label)
        }
        let joined = texts.joined(separator: "｜")
        XCTAssertTrue(joined.contains("v."),
                      "🚨 单词本卡片里没有动词那节 —— 他说的「连动词也没了」"
                      + "｜读到 \(texts.count) 段文字")
        XCTAssertTrue(joined.contains("n."),
                      "🚨 单词本卡片里没有名词那节 —— 他说的「只有一个动词」"
                      + "｜读到 \(texts.count) 段文字")
    }
}
