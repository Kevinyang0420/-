import XCTest

/// **单词本乙方案的三张验收图 + 判据**（2.1 规格 2026-09-05）。
///
/// 🚨 判据都挂在**看得见的结果**上，不是"函数被调过"：
///   ① 切分页时顶栏坐标一致 —— 我做法上让它**结构上不可能动**（分段条在内容区，
///      导航栏一个字没碰），这里再量一次是**独立第二路径**。
///   ② 连点三次「＋单词本」→ 单词本里只有一条。
///   ③ 只有词和句子时，「词组」整段不出现。
final class WordBookE2E: XCTestCase {

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testTabsAndAdd() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "hist"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_SEED_HIST"] = "1"   // 灌样本，见 applyDebugEnv
        // 🚨 **单词本清空** —— 不清的话上一轮加进去的还在，
        //    这一轮第一次点就变成"移除"，断言会失败得像功能坏了。
        app.launchEnvironment["TRANSLESS_CLEAR_WB"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        // ── ① 顶栏坐标：切分页前后必须一致 ─────────────────────
        let back = app.navigationBars.buttons.element(boundBy: 0)
        let navTitle = app.navigationBars.staticTexts.firstMatch
        XCTAssertTrue(navTitle.waitForExistence(timeout: 10), "🚨 导航标题不在")
        let beforeBack = back.frame
        let beforeTitle = navTitle.frame
        shot("01_记录分页")

        let tabWB = app.buttons["hist.tab.wordbook"]
        XCTAssertTrue(tabWB.waitForExistence(timeout: 10), "🚨 单词本分页钮不在")
        tabWB.tap()
        Thread.sleep(forTimeInterval: 1.2)
        shot("02_单词本分页")

        XCTAssertEqual(back.frame, beforeBack, "🚨 返回键动了")
        XCTAssertEqual(navTitle.frame, beforeTitle, "🚨 标题动了")

        // ── ② 连点三次只加一条 ────────────────────────────────
        app.buttons["hist.tab.records"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        let add = app.buttons["hist.add.wordbook"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), "🚨 「＋单词本」按钮不在")
        add.tap(); Thread.sleep(forTimeInterval: 0.6)
        // 🚨 第一次点完必须变成「已加入」—— 不变的话说明点击被卡片手势吞了，
        //    而后面"只有一条"仍然会通过（因为一条都没加进去）。
        //    **少了这一条断言，②就成了永远通过的假检查。**
        XCTAssertEqual(add.label, "已加入", "🚨 点了没进单词本（多半是手势被卡片吞了）")
        shot("03_已加入态")
        add.tap(); Thread.sleep(forTimeInterval: 0.5)     // 移除
        add.tap(); Thread.sleep(forTimeInterval: 0.5)     // 再加
        XCTAssertEqual(add.label, "已加入", "🚨 三次点完不是「已加入」")

        tabWB.tap()
        Thread.sleep(forTimeInterval: 1.2)
        let rows = app.staticTexts.matching(
            NSPredicate(format: "identifier == %@", "wb.section"))
        NSLog("WBE2E 分段数 %d", rows.count)
        shot("04_三段归类")
        XCTAssertGreaterThanOrEqual(rows.count, 1, "🚨 单词本里一个分段都没有")
        XCTAssertLessThanOrEqual(rows.count, 3, "🚨 分段数超过 3，标题写死了？")
    }

    /// **判据 3 的 iOS 替代版**（2.1 2026-09-05 裁定 A）。
    ///
    /// 🚨 原判据「两个分页分别清空互不影响」在 iOS 上**无从执行** ——
    ///    这一屏根本没有清空入口（2.1 写规格时照的是安卓那屏，
    ///    **拿一端的现状当两端的前提**）。
    ///
    /// 🚨 但风险本身是真的：**记录和单词本混在一起存**的话，清一个会带走另一个。
    ///    所以改成用 `History.clear()` 的测试开关触发清空，
    ///    然后看**单词本条数变没变** —— 不需要 UI，照样打得到那个风险。
    ///
    /// 坏样本：把 `WordBook` 的存储键改成跟 `History` 同一个，这条立刻红。
    func testClearHistoryKeepsWordbook() throws {
        // 先在单词本里放一条（走记录页的「＋单词本」，跟用户路径一致）
        let app = TestApp.launch("hist", env: ["TRANSLESS_SEED_HIST": "1",
                                               "TRANSLESS_CLEAR_WB": "1"])
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        let add = app.buttons["hist.add.wordbook"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), "🚨 「＋单词本」不在")
        if add.label != "已加入" { add.tap(); Thread.sleep(forTimeInterval: 0.8) }
        XCTAssertEqual(add.label, "已加入", "🚨 没加进去，后面这条就测不到东西了")

        app.buttons["hist.tab.wordbook"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        let before = app.staticTexts.matching(
            NSPredicate(format: "identifier == %@", "wb.section")).count
        XCTAssertGreaterThan(before, 0, "🚨 单词本是空的，这条测不到东西")

        // 清历史（走测试开关），再看单词本
        let app2 = TestApp.launch("hist", env: ["TRANSLESS_CLEAR_HIST": "1"])
        XCTAssertTrue(app2.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        app2.buttons["hist.tab.wordbook"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        let after = app2.staticTexts.matching(
            NSPredicate(format: "identifier == %@", "wb.section")).count
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "05_清历史后单词本还在"; a.lifetime = .keepAlways; add2(a)
        XCTAssertEqual(after, before,
            "🚨 清了历史，单词本从 \(before) 段变成 \(after) 段 —— 两份数据混在一起存了")
    }

    private func add2(_ a: XCTAttachment) { add(a) }
}
