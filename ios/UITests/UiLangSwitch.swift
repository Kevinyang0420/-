import XCTest

/// **界面语言到底接没接线。**
///
/// 🚨 Kevin 2026-09-05 实机报：选 English 后整个界面还是中文。
///    根因两处（缺一不可）：
///      ① `Strings.swift` 的 `code` 只读 `Bundle.main.preferredLocalizations`
///         —— **全文件 `Lang.` 命中数是 0**，App 内那个设置项它根本不看。
///      ② `code`/`isEn`/`isHant` 都是 `static let`，**每进程只算一次**，
///         就算接上来源，切完也要等重启才变。
///
/// 🚨 判据照 2.1 的四条，**每条都要能失败**：
///    只截一张英文图的话，"永远返回英文"这种写死实现会全绿。
final class UiLangSwitch: XCTestCase {

    /// 全类型搜文案 —— **不限定 staticTexts**。
    /// 🚨 首页改成方案丙之后，「随手翻译」那行字是**按钮里的子视图**，
    ///    `app.staticTexts[...]` 找不到它（上一轮就栽在这儿，
    ///    报出来是"基线不是中文"，看起来像功能坏了）。
    private func has(_ app: XCUIApplication, _ text: String, _ t: TimeInterval) -> Bool {
        let q = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", text))
        return q.firstMatch.waitForExistence(timeout: t)
    }

    /// 失败时把**当时看得见的文案**打出来，下次不用猜。
    private func dump(_ app: XCUIApplication) -> String {
        let all = app.descendants(matching: .staticText).allElementsBoundByIndex
        return "当时可见：" + all.prefix(12).map { $0.label }.joined(separator: " / ")
    }

    private func shot(_ n: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = n; a.lifetime = .keepAlways; add(a)
    }

    /// 系统语言保持中文，App 内切 English → 三屏都要变；再切回来 → 都要变回去。
    func testSwitchAndSwitchBack() throws {
        let app = TestApp.launch(nil, env: ["TRANSLESS_UILANG_RESET": "1"])
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        // 基线：中文
        XCTAssertTrue(has(app, "随手翻译", 10),
                      "🚨 基线不是中文，后面的对比不成立")
        shot("01_中文基线")

        pick("English", app)
        // ① 首页要变 —— **不是只有设置页那一行**
        XCTAssertTrue(has(app, "Translate as you go", 8),
                      "🚨 切成 English 之后首页还是中文（这正是他报的现象）")
        XCTAssertFalse(has(app, "随手翻译", 1), "🚨 中文文案还在")
        shot("02_英文_首页")

        // 🚨 ② 反向控制：切回中文必须变回去。
        //    没有这一条的话，"永远返回英文"的写死实现也会全绿。
        pick("简体中文", app)
        XCTAssertTrue(has(app, "随手翻译", 8),
                      "🚨 切回简体中文之后没变回来")
        shot("03_切回中文")
    }

    /// 🚨 ③ 不重启也要生效 —— 专打 `static let` 那个每进程缓存。
    ///    上面两条其实已经覆盖（全程没重启），这里单独把判据写明白，
    ///    免得以后有人把用例改成"切完重启再看"而不自知地把它测没了。
    private func pick(_ label: String, _ app: XCUIApplication) {
        // 🚨 **按序号找，不按文案** —— 切成英文之后这个 Tab 就叫 "Settings"，
        //    按文案找的话第二次切换必然找不到，而那看起来像"功能坏了"。
        //    Tab 栏的按钮要走 `app.tabBars.buttons`，不是全局 `app.buttons`。
        app.tabBars.buttons.element(boundBy: 4).tap()
        Thread.sleep(forTimeInterval: 1.0)
        let row = app.descendants(matching: .any).matching(
            // 🚨 **文案照 `Strings.swift:363` 抄，不许猜** ——
            //    我第一版写了 "Interface language"，真实文案是 "App language"，
            //    于是切回中文那一步找不到行、报得像功能坏了。
            //    三种界面语言的写法全列上（繁体那版也不一样）。
            NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@ OR label CONTAINS %@",
                        "界面语言", "App language", "界面語言")).firstMatch
        // 🚨 **不许 `if exists { tap() }`** —— 找不到就悄悄跳过的话，
        //    弹窗根本没开，失败会推迟到"找不到 English 按钮"，
        //    而那个报错**看不出根因**。在这里就断言掉。
        XCTAssertTrue(row.waitForExistence(timeout: 8),
                      "🚨 设置页找不到「界面语言」那一行；" + dump(app))
        row.tap()
        Thread.sleep(forTimeInterval: 0.8)
        let opt = app.buttons[label].firstMatch
        XCTAssertTrue(opt.waitForExistence(timeout: 6),
                      "🚨 弹窗里没有「\(label)」；" + dump(app))
        opt.tap()
        Thread.sleep(forTimeInterval: 2.0)      // 等 rebuildUI 的过场动画
    }
}
