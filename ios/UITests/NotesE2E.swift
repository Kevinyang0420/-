import XCTest

/// **记事本第一步：从说话记录「留下来」→ 记事本列表里能找到它。**
///
/// 规格 `_规格_记事本_20260907.md`（Kevin 09-07 批「三步同步走」）。
///
/// 🚨 判据是**点得到并走得通**，不是「代码里有这个类」——
///    这摊活在「写好了没接上」那一族上已经栽过五次，它们全都不报错。
///
/// 🚨 这条**跨了一次杀进程重启**：只看"点完按钮变成已留下"分不出
///    到底落盘没有。存储写失败时界面照样变。
final class NotesE2E: XCTestCase {

    func testKeepFromHistoryThenFindItInNotes() throws {
        var app = launch()

        // ① 说话记录里点「留下来」
        try openHistory(app)
        let keep = app.buttons["hist.keep.note"].firstMatch
        XCTAssertTrue(keep.waitForExistence(timeout: 10),
                      "🚨 说话记录上没有「留下来」—— 记事本第一步的入口不在")
        keep.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "NOTE_01_留下来"; shot.lifetime = .keepAlways; add(shot)

        // ② 🚨 **杀进程重启** —— 这一步才分得出"落盘了"和"只改了屏幕"
        app.terminate()
        Thread.sleep(forTimeInterval: 1.5)
        app = launch(seed: false)

        // ③ 设置 → 记事本，应当能找到它
        try openNotes(app)
        let shot2 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot2.name = "NOTE_02_记事本"; shot2.lifetime = .keepAlways; add(shot2)
        // 🚨🚨 **这条原来是假绿**：我写成
        //    `note.row 存在 || 任何非空文字存在` —— 后半个 `||` 让**空态那句话**
        //    也算通过，于是"一条都没留下"被判成了"落盘了"。
        //    第 ④ 步搜到的关键词是「到这儿。」（空态文案的结尾）才暴露出来。
        //    **兜底的 `||` 就是这么把判据掏空的。**
        XCTAssertTrue(app.otherElements["note.row"].firstMatch
            .waitForExistence(timeout: 8),
            "🚨 重启后记事本里一条都没有 —— 没落盘")
        XCTAssertFalse(app.staticTexts["note.empty"].exists,
                       "🚨 记事本显示的是空态 —— 那条根本没留下来")

        // ④ 🚨 **搜索要搜得到原话**（规格判据：只搜标题 = FAIL）
        //    用那条记录里靠后的字去搜 —— 标题只截前 24 字，
        //    只搜标题的实现在这里必红。
        let f = app.textFields["note.search"]
        XCTAssertTrue(f.waitForExistence(timeout: 6), "🚨 记事本没有搜索框")
        // 🚨 **关键词要从这条笔记的正文里取**。
        //    我第一版拿的是"历史页第一个非空文字"，那是**页面标题「说话记录」**——
        //    判据红了，但红的原因是我取错了对象，不是搜索坏了。
        //    这里取记事本这一屏最长的那段文字（正文比标题长），
        //    再取它的**末尾**几个字 —— 标题只截前 24 字，
        //    只搜标题的实现在这里必红。
        let said = app.staticTexts.allElementsBoundByIndex
            .prefix(40).map { $0.label }
            .filter { !$0.isEmpty }
            .max(by: { $0.count < $1.count }) ?? ""
        let needle = String(said.suffix(4))
        if !needle.isEmpty {
            f.tap(); f.typeText(needle)
            Thread.sleep(forTimeInterval: 1.5)
            let shot3 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot3.name = "NOTE_03_搜到"; shot3.lifetime = .keepAlways; add(shot3)
            XCTAssertFalse(app.staticTexts["note.empty"].exists,
                           "🚨 用原话里的词搜不到 —— 搜索没覆盖正文｜搜的是「\(needle)」")
        }
    }

    private func launch(seed: Bool = true) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_UILANG_RESET"] = "1"
        // 🚨 种子会清空并重种说话记录 —— 重启那次**不能再种**，
        //    否则我自己把刚留下的那条的来源清了。
        //    （同一晚我在句子卡那条上正好栽过这个：种子每次启动清空单词本。）
        if seed { app.launchEnvironment["TRANSLESS_SEED_CARD"] = "1" }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        return app
    }

    private func openHistory(_ app: XCUIApplication) throws {
        let tab = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "历史", "History")).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 8), "🚨 找不到历史 tab")
        tab.tap()
        Thread.sleep(forTimeInterval: 2.0)
    }

    private func openNotes(_ app: XCUIApplication) throws {
        let tabSet = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "设置", "Settings")).firstMatch
        XCTAssertTrue(tabSet.waitForExistence(timeout: 8), "🚨 找不到设置 tab")
        tabSet.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let row = app.otherElements["prefs.row.notes"]
        if !row.waitForExistence(timeout: 6) { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 8),
                      "🚨 设置里找不到记事本那一行")
        row.tap()
        Thread.sleep(forTimeInterval: 2.0)
    }
}
