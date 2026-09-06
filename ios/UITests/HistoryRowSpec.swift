import XCTest

/// **键盘历史面板三条**（Kevin 2026-09-06，经 2.1 转述）：
/// > 1. 「收藏到底收藏到哪里去了？…好像是加到了单词本里，但感觉很不直观」
/// > 2. 「普通的同语言转写本来也不需要收藏，不如直接把这个收藏按钮关掉，
/// >     现在放这里有点鸡肋」
/// > 3. 「历史记录里也不需要给每一条都加个朗读的小图标。主输入法界面上本来就有
/// >     朗读键，用户可以先把内容重新上屏，再去点主界面的朗读」
///
/// 🚨 **第 3 条的替代路径在补一行之前是坏的**：`insertHistory` 插了文字却没更新
///    `lastOut`，而主界面朗读键读的正是它 → 念的是**上一次**那段，
///    **不报错、就念错的那段**。照着"删掉就行"做，等于删掉一个能用的按钮、
///    换来一条静默错的路。所以顺序是：先补 `lastOut`，再删 🔊。
final class HistoryRowSpec: XCTestCase {

    private func openHistory() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "kb"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_SEED_HIST"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.5)
        let hist = app.buttons["kb.hist"]
        XCTAssertTrue(hist.waitForExistence(timeout: 8), "🚨 找不到历史钮")
        hist.tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(app.otherElements["kb.hist.panel"].waitForExistence(timeout: 4),
                      "🚨 历史面板没开 —— 下面每条判据都会变成假绿")
        return app
    }

    /// ③ 每行不再有 🔊。
    func testNoSpeakerIconPerRow() {
        let app = openHistory()
        let speakers = app.descendants(matching: .any)
            .matching(identifier: "transless.hist.speak")
        XCTAssertEqual(speakers.count, 0,
                       "🚨 历史每行还挂着 🔊（\(speakers.count) 个）—— 他说不需要")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "HIST_01_每行无朗读图标"; a.lifetime = .keepAlways; add(a)
    }

    /// ② 同语言转写那条**不显示**收藏钮；翻译那条要有。
    ///
    /// 🚨 反向对照必须在场：只测"转写没有"的话，把所有行的按钮都删掉也全绿，
    ///    而那等于功能没了。
    func testKeepShownOnlyForCrossLang() {
        let app = openHistory()
        let keeps = app.descendants(matching: .any)
            .matching(identifier: "transless.hist.keep")
        // 种子里：en 3 条、zh 1 条、raw 若干 —— 收藏钮只该出现在 en 那几条上
        let rows = app.buttons.matching(
            NSPredicate(format: "identifier == %@", "transless.hist.row"))
        XCTAssertGreaterThan(rows.count, 1, "🚨 历史行没铺出来，这条什么都没测到")
        XCTAssertGreaterThan(keeps.count, 0,
                             "🚨 一个收藏钮都没有 —— 翻译档那几条也被砍了")
        XCTAssertLessThan(keeps.count, rows.count,
                          "🚨 每一行都有收藏钮 —— 同语言转写那条没被排除")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "HIST_02_收藏钮只在翻译档"; a.lifetime = .keepAlways; add(a)
    }

    /// ① 点历史上屏之后，**主界面朗读键要念的就是这一条**。
    ///
    /// 🚨 判据挂在 `lastOut`（经由朗读键的无障碍值暴露），不挂在"有没有报错"上
    ///    —— 这个坑的形态就是**不报错、念错的那段**。
    func testInsertHistoryUpdatesSpeakTarget() {
        let app = openHistory()
        let rows = app.buttons.matching(
            NSPredicate(format: "identifier == %@", "transless.hist.row"))
        XCTAssertGreaterThan(rows.count, 2, "🚨 历史行不够，点不到第 3 条")
        let third = rows.element(boundBy: 2)
        let want = third.value as? String ?? ""
        XCTAssertFalse(want.isEmpty, "🚨 读不到第 3 条的内容，判据没有期望值")

        third.tap()
        Thread.sleep(forTimeInterval: 1.5)

        let speak = app.buttons["kb.bottom.speak"]
        XCTAssertTrue(speak.waitForExistence(timeout: 4), "🚨 找不到主界面朗读键")
        let got = speak.value as? String ?? ""
        XCTAssertEqual(got, want,
                       "🚨 点了第 3 条上屏，朗读键要念的却是别的 —— "
                       + "他会以为朗读坏了，而这个错**不报任何错**｜"
                       + "要念=\(got.prefix(40)) 应念=\(want.prefix(40))")
    }
}
