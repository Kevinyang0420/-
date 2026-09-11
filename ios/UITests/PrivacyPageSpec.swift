import XCTest

/// **隐私政策端内页** —— Kevin 09-07 #97① 和他退回的那两条。
///
/// 他的原话：
/// > 现在点进去会在浏览器打开新窗口，不要这么搞…**不要跳出 App**。
/// > 那个隐私政策为什么还是这黑底呀？**不能跟 APP 的主题色保持一致吗**？
/// > **你至少这里面要分两个格子吧**：1. 一个是同步的开关 2. 另一个才是具体的隐私政策
///
/// 🚨 **这一屏原来一条判据都没有** —— #97 我做完就报了，靠的是"我读了代码"。
///    他退回的两条（黑底、没分格）都是**看一眼就发现**的东西，
///    而我没有任何东西在看。这条用例补的是这个洞。
///
/// 🚨 **能验的和不能验的分开写**（别让通过显得比实际更有分量）：
///    能验：两格的标题在不在、返回键在不在、点进去没离开 App
///    不能验：底色好不好看、表格塌没塌 —— 出图，人看
final class PrivacyPageSpec: XCTestCase {

    func testPrivacyIsInAppWithTwoSections() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_UILANG_RESET"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        // 进设置：底部 tab 最后一个
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "没有底部 tab 栏")
        let prefsTab = bar.buttons.element(boundBy: 4)
        XCTAssertTrue(prefsTab.exists, "设置那个 tab 不在")
        prefsTab.tap()
        Thread.sleep(forTimeInterval: 1.5)

        // 🚨 **按标识点，不按文案** —— 文案会跟着界面语言变，
        //    按文案的话切成日语用例就红，而失败信息会指到错的地方。
        let row = app.descendants(matching: .any)
            .matching(identifier: "prefs.row.privacy").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "设置里没有隐私政策那一行")
        row.tap()
        Thread.sleep(forTimeInterval: 3.0)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "PRIVACY_01_端内页"
        shot.lifetime = .keepAlways
        add(shot)

        // ① 还在自己的 App 里（跳浏览器的话这个进程就不在前台了）
        XCTAssertEqual(app.state, .runningForeground,
                       "🚨 点隐私政策把 App 切走了 —— 又跳出去了")

        // ② 第 2 格的标题在 —— 这是"分了两个格子"的可验证部分
        XCTAssertTrue(app.staticTexts["privacy.head.doc"]
                        .waitForExistence(timeout: 8),
                      "🚨 没有『隐私政策』那一格的标题 —— 又变回一整页正文了")

        // ③ 🚨 **能返回** —— 这一屏从设置推进来，
        //    `gate_pushed_screen_has_back.py` 只盯 `*FromHome`，守不到它。
        //    09-07 刚在查词页栽过：「点进去没有返回按钮，怎么返回呢？」
        XCTAssertTrue(app.navigationBars.buttons.firstMatch.exists,
                      "🚨 导航栏上没有返回键 —— 进得来出不去")

        // ④ 反向对照：**没开过同步的人看不到第 1 格**。
        //    （默认状态就是没开过，所以这里应当查不到那个标题。）
        //    🚨 没有这一条的话，"两个格子都在"会把"取消入口漏给所有人"
        //       也判成通过 —— 而他定过那个入口要"难找"。
        XCTAssertFalse(app.staticTexts["privacy.head.sync"].exists,
                       "🚨 没开过同步却看得到上云那一格 —— 取消入口漏出来了")

        // ⑤ 🚨🚨 **正文必须真的占着版面** —— 这条是补上来的。
        //    第一次跑，上面四条**全绿而页面是空白的**：`syncBox` 是空 stack
        //    又没有高度约束，Auto Layout 把它拉满、把正文压成 0 高，
        //    **每一条约束都满足**。我验了标题和返回键，
        //    **没验正文有没有显示** —— 判据挂在跟结论不是同一个对象的东西上。
        //    判据取"超过屏幕一半"：正文是整页文档，占不到一半就是塌了。
        let screenH = app.frame.height
        // 🚨 **先判"在不在"，再判"多高"** —— 上一轮这里直接取 frame，
        //    而 WebView 压根不在无障碍树里，报的是
        //    「No matches found for Descendants matching type WebView」。
        //    那条信息**指错层**：看起来像用例写错了，实际是正文没显示。
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 8),
                      "🚨 这一屏根本没有正文视图 —— 不是「高度不够」，是压根没有")
        let docH = app.webViews.firstMatch.frame.height
        XCTAssertGreaterThan(docH, screenH * 0.5,
                             String(format: "🚨 正文只有 %.0f 高、屏幕 %.0f —— "
                                    + "被压扁了，页面等于空白", docH, screenH))

        app.navigationBars.buttons.firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(app.descendants(matching: .any)
                        .matching(identifier: "prefs.row.privacy").firstMatch
                        .waitForExistence(timeout: 8),
                      "🚨 点返回没回到设置页")
    }
}
