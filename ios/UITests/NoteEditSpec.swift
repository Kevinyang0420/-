import XCTest

/// **他能不能真的写一条笔记** —— 2.1 方案里的 `note` 字段。
///
/// 🚨 存储层昨晚就做好了：`WordCard.withNote` / `noteOf` /
///    `merged(fromServer:keepingNoteOf:)`，重取时笔记会原样搬回去，
///    `NoteSurvivesTests` 也是绿的。**而他手机上什么都没多** ——
///    字段能存能读能保住，**没有任何地方能写**。
///    这正是他那条铁规的形态：「功能做出来了」≠「他点得到」。
///
/// 所以这条测的**不是存储**（那条已经有测了），是**入口**：
/// 看得见 → 打得进去 → 退出去再进来**还在**。
///
/// 🚨 最后那一步是关键。只验"保存后屏幕上有这行字"的话，
///    我改的要是内存里那个 label、根本没落盘，测试照样绿 ——
///    而他明天打开就发现笔记没了。**判据必须跨一次重进。**
final class NoteEditSpec: XCTestCase {

    private let note = "跟 commuter 别搞混：这个是动词"

    func testHeCanWriteAndKeepANote() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_SEED_CARD"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        try openCommuteDetail(app)

        // ① 入口在不在 —— 🚨 **没写过笔记时也必须在**。
        //    只在有笔记时才画的话，他永远不知道可以写。
        let edit = app.buttons["wb.note.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8),
                      "🚨 单词本卡片上没有写笔记的入口 —— 存储层做好了他也写不了")
        let shot1 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot1.name = "NOTE_01_空态入口"; shot1.lifetime = .keepAlways; add(shot1)
        edit.tap()
        Thread.sleep(forTimeInterval: 2.0)

        // ② 打字
        let editor = app.textViews["wb.note.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8), "🚨 笔记编辑框没出来")
        editor.tap()
        editor.typeText(note)
        let shot2 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot2.name = "NOTE_02_打字中"; shot2.lifetime = .keepAlways; add(shot2)

        let save = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "保存", "Save")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 6), "🚨 找不到保存")
        save.tap()
        Thread.sleep(forTimeInterval: 2.5)

        XCTAssertTrue(bodyTexts(app).contains(where: { $0.contains(note) }),
                      "🚨 保存后卡片上没有这条笔记")

        // ③ 🚨 **退出去再进来** —— 这一步才分得出「落盘了」和「只改了屏幕上那个 label」。
        let back = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "返回", "Back")).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 6), "🚨 找不到返回")
        back.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let row = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "commute")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "🚨 退回列表后找不到那一条")
        row.tap()
        Thread.sleep(forTimeInterval: 3.0)

        let shot3 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot3.name = "NOTE_03_重进还在"; shot3.lifetime = .keepAlways; add(shot3)
        XCTAssertTrue(bodyTexts(app).contains(where: { $0.contains(note) }),
                      "🚨 重新进来笔记没了 —— 只改了屏幕、没落盘")
        // 入口这时该变成「编辑」，不再是「写」。
        XCTAssertTrue(app.buttons["wb.note.edit"].exists, "🚨 重进后入口消失了")
    }

    // MARK: - 走到那一屏

    /// 🚨 入口在**设置**里，不是「常用词」tab（`MainTabController:18`）。
    ///    点错 tab 的话判据会红在"没有笔记入口"上，
    ///    而真相是**根本没进到那一屏** —— 那种红比不红更糟。
    private func openCommuteDetail(_ app: XCUIApplication) throws {
        let tabSet = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "设置", "Settings")).firstMatch
        XCTAssertTrue(tabSet.waitForExistence(timeout: 8), "🚨 找不到设置 tab")
        tabSet.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let wbRow = app.staticTexts.matching(NSPredicate(
            format: "label == %@ OR label == %@",
            "单词本", "Word book")).firstMatch
        if !wbRow.waitForExistence(timeout: 6) {
            app.swipeUp(); Thread.sleep(forTimeInterval: 1.0)
        }
        XCTAssertTrue(wbRow.waitForExistence(timeout: 8), "🚨 设置里找不到单词本")
        wbRow.tap()
        Thread.sleep(forTimeInterval: 2.5)
        let row = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "commute")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8),
                      "🚨 单词本里没有 commute —— 种子没生效，后面白测")
        row.tap()
        Thread.sleep(forTimeInterval: 3.0)
    }

    private func bodyTexts(_ app: XCUIApplication) -> [String] {
        let all = app.staticTexts
        var out: [String] = []
        for i in 0..<min(all.count, 120) where all.element(boundBy: i).exists {
            out.append(all.element(boundBy: i).label)
        }
        return out
    }
}
