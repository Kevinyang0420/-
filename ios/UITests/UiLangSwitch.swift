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


    /// 那颗主入口**当前显示的文字**。
    ///
    /// 🚨 `app.buttons["app.try"].label` 是**空的** —— 它是自绘视图，
    ///    文字在子标签里（09-07 实测：断言当场红在「基线读到空文案」）。
    ///    读不到就如实返回空串，让判据自己红，不要静默退回按文案找。
    private func ctaText(_ app: XCUIApplication) -> String {
        let b = app.buttons["app.try"]
        if !b.label.isEmpty { return b.label }
        let inner = b.staticTexts.allElementsBoundByIndex
            .map { $0.label }.filter { !$0.isEmpty }
        return inner.first ?? ""
    }

    /// 系统语言保持中文，App 内切 English → 三屏都要变；再切回来 → 都要变回去。
    func testSwitchAndSwitchBack() throws {
        let app = TestApp.launch(nil, env: ["TRANSLESS_UILANG_RESET": "1"])
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        // 🚨🚨 **不再钉死具体文案**（09-07 改）。
        //    原来三条断言写的都是「随手翻译」—— Kevin 09-07 把它改名成
        //    「随便说点啥」之后，第 52 行那条 `XCTAssertFalse(has(…"随手翻译"…))`
        //    **因为错误的原因通过了**：文案是被改名改没的，不是切了语言。
        //    这条断言从此测不出它本来要测的东西，而且**没有任何东西会报错**。
        //
        //    改成读**同一个标识**（`app.try`，不随文案和语言变）的 label：
        //    切语言前后**必须不同**，切回来**必须回到原值**。
        //    这样任何改名都不会让它假绿，而"永远返回英文"的写死实现仍然会红。
        let cta = app.buttons["app.try"]
        XCTAssertTrue(cta.waitForExistence(timeout: 10),
                      "🚨 首页找不到那颗主入口（标识 app.try）")
        let zhLabel = ctaText(app)
        XCTAssertFalse(zhLabel.isEmpty, "🚨 基线读到空文案，后面的对比不成立")
        shot("01_中文基线")

        pick("English", app)
        Thread.sleep(forTimeInterval: 1.5)
        let enLabel = ctaText(app)
        XCTAssertNotEqual(enLabel, zhLabel,
                          "🚨 切成 English 之后首页没变（这正是他报的现象）"
                          + "｜前=\(zhLabel) 后=\(enLabel)")
        // 英文界面下这颗按钮不该还是中文 —— 用字符集判，不钉具体词。
        XCTAssertFalse(enLabel.unicodeScalars.contains {
            (0x4E00...0x9FFF).contains($0.value) },
            "🚨 英文界面下主入口仍是中文：\(enLabel)")
        shot("02_英文_首页")

        // 🚨 ② 反向控制：切回中文必须变回去。
        //    没有这一条的话，"永远返回英文"的写死实现也会全绿。
        pick("简体中文", app)
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertEqual(ctaText(app), zhLabel,
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
