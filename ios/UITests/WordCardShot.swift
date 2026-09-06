import XCTest

/// **把单词本卡片拍下来** —— Kevin 2026-09-06 问了三次「单词卡片在哪儿呢」。
///
/// 🚨 到现在为止我只证明了「代码写完了」：模型有字段、解析有用例、
///    取数有懒加载和重试。**但一张渲染出来的卡片图都没有。**
///    模拟器上单词本挡着登录门、本子又是空的 ——
///    **「代码写完了」和「他能看到那张卡」是两件事**，我只证明了前者。
///
/// 🚨 种子里那条查词卡的音标**故意带斜杠**（`/rɪˈzɪliənt/`）——
///    那是他手机上旧卡片的真实样子。用它验「渲染前剥斜杠」在**旧数据**上生效；
///    只拿新查的词验，那一半漏了也是绿的。
final class WordCardShot: XCTestCase {

    func testShotCards() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_SEED_CARD"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        func shot(_ n: String) {
            Thread.sleep(forTimeInterval: 1.0)
            let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            a.name = n
            a.lifetime = .keepAlways
            add(a)
        }

        // 设置 → 单词本（09-04 之后入口在设置里，不在首页）
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 8), "tab 栏没出来")
        bar.buttons.element(boundBy: 4).tap()
        Thread.sleep(forTimeInterval: 1.2)

        let wb = app.staticTexts["单词本"]
        XCTAssertTrue(wb.waitForExistence(timeout: 5), "设置里找不到单词本入口")
        wb.tap()
        Thread.sleep(forTimeInterval: 1.5)
        shot("CARD_01_列表")

        // 🚨 点进去才是卡片 —— 只截列表等于没截到他要看的东西
        let rows = app.otherElements.matching(identifier: "wb.row")
        XCTAssertGreaterThan(rows.count, 0, "🚨 列表里一条都没有，种子没进去")
        rows.element(boundBy: 0).tap()
        // 🚨 卡片是**收藏时就存好的**，不该有取数；等一拍确认不是在转圈
        Thread.sleep(forTimeInterval: 2.0)
        shot("CARD_02_详情_查词卡")

        // 返回再点第二条（句子卡，字段完全不同）
        // 🚨 详情是**同一个 VC 内的一种状态**（`mode = .detail`），不是新页面 ——
        //    点导航栏返回会把整个单词本弹掉，回不到列表。
        //    要点**页面里那个「返回」按钮**。
        //    （上一版就是这么丢了第三张图的：导航返回之后已经不在单词本里了，
        //     `wb.row` 一个都找不到，用例静默跳过，我只当"没拍到"。）
        app.buttons["返回"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        let rows2 = app.otherElements.matching(identifier: "wb.row")
        // 🚨 **断言，不许静默跳过** —— 上一版写的是 `if count > 1`，
        //    于是回不到列表时它一声不吭地过了，而我以为只是"没拍到"。
        //    **静默跳过的用例＝没有这条用例。**
        XCTAssertGreaterThan(rows2.count, 1, "🚨 回不到列表，或者种子只种了一条")
        rows2.element(boundBy: 1).tap()
        Thread.sleep(forTimeInterval: 2.0)
        shot("CARD_03_详情_句子卡")
    }
}
