import XCTest

/// **英文档下，左下角那个「拼音／五笔」键必须消失。**
///
/// Kevin 2026-09-04 原话：「如果我选的是英文键盘，为什么左下角还显示拼音？
/// 英文没有拼音。中文才需要在拼音和五笔之间切换，英文的话这些选项就不该存在。」
///
/// 🚨 判据是**两态对比**，不是"英文档下找不到它"：
///    单看"找不到"分不清「正确地隐藏了」和「整个键盘没画出来／我找错了控件」——
///    后者会让这个测试在键盘彻底坏掉时**照样绿**。
///    所以先在中文档确认它**在**，再切英文确认它**不在**。
///
/// 🚨 跑在 `TRANSLESS_PAGE=kb` 预览页上，那页嵌的是**真的
///    `KeyboardViewController`**（不是我自己摆的假页面 —— 2026-08-26 那次
///    假页面让每一次"验过"都是白验）。
///    它跟真扩展仍有两处不同，**能验版面，不能验上屏**。
final class KbEnglishNoIM: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testImKeyHiddenInEnglish() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "kb"
        // 🚨 模拟器音频会 abort，报出来像「App 没起来」（见 TestApp.swift）
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 4.0)

        // 预览页开在语音面板，先切到打字键盘
        let toType = app.buttons["kb.switch.typing"].firstMatch
        if toType.waitForExistence(timeout: 4) {
            toType.tap()
        } else if app.staticTexts["打字"].firstMatch.waitForExistence(timeout: 4) {
            app.staticTexts["打字"].firstMatch.tap()
        } else if app.buttons["打字"].firstMatch.waitForExistence(timeout: 4) {
            app.buttons["打字"].firstMatch.tap()
        }
        Thread.sleep(forTimeInterval: 2.5)
        shot("01_打字键盘_中文档")

        let imKey = app.buttons["kb.immode"]
        let zh = app.buttons["kb.chip.zh"]
        let en = app.buttons["kb.chip.en"]

        // ── 好样本：中文档下它必须在 ──
        // 🚨 这一条不是凑数：它挡住「键盘根本没画出来」——
        //    那种情况下"英文档找不到它"照样成立，测试会假绿。
        XCTAssertTrue(zh.waitForExistence(timeout: 10), "🚨 中英芯片没出来，键盘没画好")
        XCTAssertTrue(imKey.exists, "🚨 中文档下输入法键就不在 —— 键盘没画出来，这一轮不算数")
        // 🚨 空格/完成的**键面**也跟打字档走（Kevin 09-04：「你都发现这个问题了，
        //    就一起改了吧」）。同样是两态对比：中文档下先确认它是中文的。
        XCTAssertTrue(app.buttons["空格"].exists,
                      "🚨 中文档下空格键上不是「空格」—— 键盘没画好或键面规矩变了")

        // ── 切英文 ──
        XCTAssertTrue(en.exists, "🚨 找不到「英」芯片")
        en.tap()
        Thread.sleep(forTimeInterval: 2.0)
        shot("02_打字键盘_英文档")
        XCTAssertFalse(imKey.exists,
                       "🚨 英文档下左下角那个拼音/五笔键**还在** —— 正是他报的那条")
        // 🚨 英文档下键面必须换成英文，且**中文那个不能还在**。
        //    只断言「有 space」是不够的：两个键面同时存在时它照样成立
        //    （比如我只加了新键、没换掉旧的）。**一正一反才分得开。**
        XCTAssertTrue(app.buttons["space"].exists,
                      "🚨 英文档下空格键上没写 space")
        XCTAssertFalse(app.buttons["空格"].exists,
                       "🚨 英文档下空格键上**还写着「空格」** —— 正是他让一起改的那条")
        XCTAssertFalse(app.buttons["完成"].exists,
                       "🚨 英文档下「完成」还是中文")

        // ── 切回中文，它要回来（防"一切就永久没了"）──
        zh.tap()
        Thread.sleep(forTimeInterval: 2.0)
        shot("03_切回中文档")
        XCTAssertTrue(imKey.exists, "🚨 切回中文后输入法键没回来 —— 隐藏成了单向的")
        XCTAssertTrue(app.buttons["空格"].exists,
                      "🚨 切回中文后空格键面没跟着回来 —— 键面刷新是单向的")
    }
}
