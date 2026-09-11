import XCTest

/// **查词卡词性要逐条标出来** —— Kevin 09-06 18:44 亲口＋带图：
/// > 「commute 既有动词也有名词，但这里只给了动词（v）的介绍，名词（n）没写上来。」
///
/// 🚨 **读代码时已经发现这条像是修过了**：`DictParse.swift` 那个"取第一条义项
/// 词性当整卡标题"的 fallback 已经不在了（注释用过去式讲它、说 1.1 建议删掉）；
/// `DictViewController.swift` 的渲染循环也在按 `sn.pos` 变化插入分节标题
/// （`dict.pos.section`），逻辑跟安卓那边的修法一致。
/// **但"读代码像是修好了"不等于"修好了"** —— 这条要用真机/模拟器打一次真实的
/// 查词请求验一遍，不能只凭读代码结案。
final class DictPosSectionSpec: XCTestCase {

    func testCommuteShowsBothVerbAndNounSections() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_UILANG_RESET"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 2.0)

        let dict = app.buttons["app.dict"]
        XCTAssertTrue(dict.waitForExistence(timeout: 10), "首页没有查词卡")
        dict.tap()

        let field = app.textFields["dict.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "没进到查词页")
        field.tap()
        field.typeText("commute")
        field.typeText("\n")   // 走 textFieldShouldReturn -> search()

        // 🚨 真实网络请求，给够时间；轮询查分节标题，别死等一个固定秒数。
        let deadline = Date().addingTimeInterval(25)
        var headers: [String] = []
        while Date() < deadline {
            let els = app.staticTexts.matching(identifier: "dict.pos.section").allElementsBoundByIndex
            headers = els.map { $0.label }
            if headers.count >= 2 { break }
            Thread.sleep(forTimeInterval: 1.0)
        }

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "DICT_POS_commute"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertTrue(headers.contains(where: { $0.contains("v") }),
                      "🚨 没看到动词分节标题，读到的标题是：\(headers)")
        XCTAssertTrue(headers.contains(where: { $0.contains("n") && !$0.contains("v") }),
                      "🚨 没看到独立的名词分节标题——Kevin 09-06 报的那个 bug 复现了，"
                      + "读到的标题是：\(headers)")
        // 🚨 反向对照：**不能变成"每条都标、哪怕词性没变"**——
        //    Grok 点过这是噪音；连续同词性只应该起一次标题，不是逐条重复。
        XCTAssertLessThanOrEqual(headers.count, 3,
                                 "🚨 分节标题数超过了义项种类数的合理上限，"
                                 + "疑似同词性也在重复起标题：\(headers)")
    }
}
