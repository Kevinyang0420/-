import XCTest

/// **面对面那屏的语言下拉：点开之后到底撑不撑得开。**
///
/// 🚨 Kevin 2026-09-05 08:33：「随时面对面翻译的那一个语言框调不出来，
///    点了之后是个扁的，看不到语言。」
///
/// 🚨🚨 这条判据以前**整个维度都没被查过**：
///    我上一版给这个面板套了滚动（治"23 门滚不到底"），
///    验的是"能不能滚"，**没验"面板还撑不撑得开"** ——
///    而套滚动恰恰剪断了撑高度的那条链。
///    **只查我刚改的那件事，会漏掉我改坏的那件事。**
///
/// 坏样本是现成的：把 `hFit` 那三行删掉，高度立刻塌回 ~8pt。
final class F2FLangPanel: XCTestCase {
    func testDropdownOpensTall() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "f2f"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        // 左边那个语言钮（「⇄ 对方说」那侧）
        let btn = app.buttons["f2f.lang.left"]
        XCTAssertTrue(btn.waitForExistence(timeout: 10), "🚨 语言钮不在")
        btn.tap()
        Thread.sleep(forTimeInterval: 1.2)

        // 🚨 判据是**看得见几门语言**，不是"面板存在"。
        //    面板塌成 8pt 时它照样"存在"，那正是他看到的样子。
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "label IN %@", ["英文", "中文", "日语", "法语", "德语"]))
        NSLog("F2FPANEL 可见语言行 %d 个", rows.count)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "面对面_语言下拉"; a.lifetime = .keepAlways; add(a)

        XCTAssertGreaterThanOrEqual(rows.count, 3,
            "🚨 只看得到 \(rows.count) 门语言 —— 面板是扁的，高度链又断了")

        // 🚨🚨 **第二个维度：分段看不看得懂。**
        //    上一轮 12 门可见、闸门全绿，**但两段之间没有标题** ——
        //    用户看到「英文…英文」「日语…日语」重复出现而没有任何解释。
        //    是我看截图发现的，不是闸门抓的：
        //    **判据只查了「有没有内容」，缺了「分不分得清」这一整个维度。**
        //    坏样本：把 `sectionHeader(...)` 两行删掉，这两条立刻红。
        let recent = app.descendants(matching: .any)["最近用过"]
        let all = app.descendants(matching: .any)["全部语言"]
        NSLog("F2FPANEL 分段标题 最近用过=%@ 全部语言=%@",
              String(recent.exists), String(all.exists))
        XCTAssertTrue(recent.exists, "🚨 「最近用过」标题不在 —— 重复项没有解释")
        XCTAssertTrue(all.exists, "🚨 「全部语言」标题不在")
    }
}
