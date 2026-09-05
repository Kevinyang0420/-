import XCTest

/// 随手翻译那一屏 —— Kevin 2026-09-04 点名的三条（语气下拉、等宽、最近历史）。
///
/// 🚨 版式对不对最终要他看图，所以这里**以截图为主、断言为辅**；
///    但每条断言都是**能失败**的，且带一条**反向控制**（规格第四节第 4 条）。
final class SpeakScreen: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func shot(_ n: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = n; a.lifetime = .keepAlways; add(a)
    }

    private func open(seedHistory: Bool) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "speak"
        // 🚨 不种历史时**主动清空** —— 同一台模拟器上前一个用例种下的历史
        //    会留到后一个用例，那样反向控制会因为测试串味而误报。
        if seedHistory { app.launchEnvironment["TRANSLESS_SEED_HIST"] = "1" }
        else { app.launchEnvironment["TRANSLESS_CLEAR_HIST"] = "1" }
        // 🚨 模拟器音频会 abort，报出来像「App 没起来」（见 TestApp.swift）
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.5)
        return app
    }

    /// ① 有历史时：进屏就该看见「最近」和历史行。
    /// ② 语气钮：点一下要**弹菜单**，不是当场轮换掉。
    func testRecentAndToneMenu() throws {
        let app = open(seedHistory: true)
        shot("01_空态_只有一个空框")

        // 🚨🚨 **回退 C 方案之后的判据**（Kevin 2026-09-05）：
        //    「最近」和历史整块不该出现，**哪怕历史里有 5 条**。
        //    种子特意是 5 条 —— 这是坏样本：打的是"只把数量改成 0、
        //    却没把渲染删掉"那种改法（数据少时看不出，多了才露馅）。
        XCTAssertFalse(app.staticTexts["最近"].firstMatch.exists,
                       "🚨 「最近」还在 —— C 方案没删干净")
        let rows = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "今天")).count
        XCTAssertEqual(rows, 0,
                       "🚨 历史里有 5 条，界面却显示了 \(rows) 条 —— 渲染没删")

        // 🚨 空框底边要贴到安全区：删了下面的东西却不把框拉到底，
        //    就是他 08-29 骂过的「下面半屏全空」。
        let card = app.textViews.firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 6), "🚨 空框不在")
        let win = app.windows.firstMatch.frame
        let slack = win.maxY - card.frame.maxY
        NSLog("CARDMEASURE bottom=%.1f screen=%.1f slack=%.1f",
              card.frame.maxY, win.height, slack)
        XCTAssertLessThan(slack, 90,
                          "🚨 空框底下还空着 \(slack)pt —— 没贴到安全区")

        // 语气/语言只属于**翻译**档，先切过去（转写档下它们本来就不该出现）
        let toTranslate = app.buttons["翻译"].firstMatch
        XCTAssertTrue(toTranslate.waitForExistence(timeout: 6), "🚨 找不到「翻译」档")
        toTranslate.tap()
        Thread.sleep(forTimeInterval: 1.2)
        shot("02_翻译档_语气语言两钮")

        // 🚨🚨 **量麦克风上下的留白，用控件坐标，不从截图数像素。**
        //    Kevin 09-04：「麦克风上面那块空档有什么意义呢」→ 要**上下等距**。
        //    我先用图像分析量过一轮，**认错了对象**（把「翻译」那个紫色胶囊
        //    当成了麦克风，它俩同色、高度还接近）。
        //    `frame` 是系统给的精确值，没有"认错"这回事。
        let mic = app.buttons["app.mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 6), "🚨 找不到录音钮")
        let above = app.buttons["翻译"].firstMatch
        let below = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "语气")).firstMatch
        if above.exists && below.exists {
            let gapUp = mic.frame.minY - above.frame.maxY
            let gapDown = below.frame.minY - mic.frame.maxY
            NSLog("GAPMEASURE up=%.1f down=%.1f diff=%.1f",
                  gapUp, gapDown, abs(gapUp - gapDown))
        }

        let tone = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "语气")).firstMatch
        XCTAssertTrue(tone.waitForExistence(timeout: 6), "🚨 翻译档下找不到语气按钮")
        let before = tone.label
        tone.tap()
        Thread.sleep(forTimeInterval: 1.5)
        shot("03_语气下拉菜单")
        // 🚨 这一条才是判据：点完**标题不许变** ——
        //    变了就说明还是"点一下轮换"，那正是他抱怨的。
        XCTAssertEqual(tone.label, before,
                       "🚨 点一下就把语气换掉了 —— 还是轮换，不是下拉菜单")
    }

    /// 🚨 **反向控制**（规格第四节第 4 条）：一条历史都没有时，
    ///    界面**不该**出现「最近」两个字。
    ///    这条防的是"标题写死"—— 那种 bug 平时看不出来，只有清空历史才现形。
    func testNoRecentWhenEmpty() throws {
        let app = open(seedHistory: false)
        shot("04_无历史")
        XCTAssertFalse(app.staticTexts["最近"].firstMatch.exists,
                       "🚨 没有历史却出现了「最近」标题 —— 标题写死了")
    }
}
