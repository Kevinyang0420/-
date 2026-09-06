import XCTest

/// **随手翻译那屏的选语言面板**（Kevin 2026-09-05 晚拍板「要改」）。
///
/// 原来是系统 `UIMenu`：两段（最近用过 / 全部语言）**长得一模一样**，
/// 都是一行行文字、只有一条细线隔开 —— 同一门语言出现两次时看着像重复，
/// 而那正是他早上实拍报障的观感。
///
/// 🚨 判据跟**键盘那屏同一套**（`KbLangPickerShot`）：
///    两屏共用 `LangPanel` / `LangChips`，判据不同的话会各绿各的。
final class SpeakLangPanel: XCTestCase {

    func testPanelIsChipsPlusList() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "speak"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_SEED_RECENT"] = "ja,fr,en"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        let langBtn = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "译成")).firstMatch
        XCTAssertTrue(langBtn.waitForExistence(timeout: 10), "🚨 语言钮不在")
        langBtn.tap()
        Thread.sleep(forTimeInterval: 1.2)

        // ① 是**自绘面板**，不是系统菜单了
        let panel = app.descendants(matching: .any)["lang.panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 6),
                      "🚨 面板没出来 —— 还是系统菜单？还是点了没反应？")

        // ② 「最近用过」是 chips，不是列表行 —— 丙的核心
        let chips = app.descendants(matching: .any).matching(identifier: "lang.chip")
        // ③ 「全部语言」完整保留
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "lang.row."))
        // ④ 勾只画一次（chips 那段用描边表达选中，列表行不再打勾）
        let checked = app.descendants(matching: .any)
            .matching(NSPredicate(format: "selected == true"))

        let report = "chips=\(chips.count) rows=\(rows.count) checked=\(checked.count)"
        XCTAssertGreaterThanOrEqual(chips.count, 1,
            "🚨 一个 chip 都没有 —— 两段还是同样的列表（\(report)）")
        XCTAssertGreaterThanOrEqual(rows.count, 3,
            "🚨 「全部语言」应完整保留（\(report)）")
        XCTAssertLessThanOrEqual(checked.count, 1,
            "🚨 打勾的行不止一个 —— 他实拍报的就是这个（\(report)）")

        // 🚨🚨 **判据改了（第三次）—— 前一版量错了对象。**
        //
        //    我原来写 `最后一门语言.isHittable`，它红了、报 `y=1580`，
        //    我据此判"面板长到屏幕外了"，改了裁剪、改了底边约束，**坐标一动没动**。
        //
        // 🚨 真相：`col` 钉在 `scroll.contentLayoutGuide` 上，
        //    那些行的坐标是**内容坐标系**里的。`y=1580` 是**内容里的位置**，
        //    不是屏幕位置。而滚动区域外的内容 `isHittable` **本来就是 false** ——
        //    **哪怕滚动完全正常，用户滑一下就能点到。**
        //    → **我量的对象（内容坐标 / 当前可点）跟我想问的问题
        //      （能不能用得上）不是一回事。** 今天第 N 次。
        //
        //    换成真正能分辨"坏"和"要滑一下"的做法：**先滑到底，再看点不点得到**。
        //    · 滑完还点不到 → 真的坏（被盖住 / 布局崩了）
        //    · 滑完能点到   → 正常，滚动在工作
        let rowsAll = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "lang.row."))
        XCTAssertGreaterThanOrEqual(rowsAll.count, 3, "🚨 一行语言都没有")
        panel.swipeUp()
        panel.swipeUp()
        Thread.sleep(forTimeInterval: 0.8)
        let lastNow = rowsAll.allElementsBoundByIndex.last
        if let l = lastNow {
            XCTAssertTrue(l.isHittable,
                "🚨 **滑到底之后**最后一门语言还是点不到 —— 这才是真坏。frame=\(l.frame)")
        }

        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "随手翻译_选语言面板"; a.lifetime = .keepAlways; add(a)

        // ⑤ 🚨 **点空白要能收掉** —— 自绘面板必须自己做这一样，
        //    漏了的表现是"面板关不掉"，而且不报任何错。
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertFalse(panel.exists, "🚨 点空白之后面板还在 —— 关不掉")
    }
}
