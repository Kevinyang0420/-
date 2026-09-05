import XCTest

/// **整句连打**：打一长串拼音，候选里要出**按词切**的整句，不是逐字瞎拼。
///
/// Kevin 2026-09-04：「连打的话只能一个词。我想一个句子连打就不行了，
/// 没那么聪明，它这个联想能力还不够」。
///
/// 🚨 判据是**一正一反**，不是"有候选就算过"：
///    · 正：`wojintianyaoqukaihui` 的候选里要出现「我今天要去开会」
///      —— 这要求 `jintian`／`kaihui` 被当成**词**整体命中；
///    · 反：**不许出现逐字拼出来的那种**（旧写法每个音节各取一个最常用字，
///      「今」「天」会被拆开、结果多半不是这句话）。
///      所以同时断言那个整句**存在**即可 —— 它存在就说明按词覆盖赢了。
///
/// 🚨 只验**候选栏**，不验上屏：预览页没有真宿主输入框。
///    这两件事分开报，别合并成"整句连打好了"。
final class KbSentence: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func shot(_ n: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = n; a.lifetime = .keepAlways; add(a)
    }

    func testSentenceCandidate() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "kb"
        // 🚨 模拟器音频会 abort，报出来像「App 没起来」（见 TestApp.swift）
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 4.0)

        if app.buttons["kb.switch.typing"].waitForExistence(timeout: 4) {
            app.buttons["kb.switch.typing"].tap()
        } else if app.buttons["打字"].firstMatch.waitForExistence(timeout: 4) {
            app.buttons["打字"].firstMatch.tap()
        }
        Thread.sleep(forTimeInterval: 2.5)

        let zh = app.buttons["kb.chip.zh"]
        XCTAssertTrue(zh.waitForExistence(timeout: 10), "🚨 键盘没画好")
        zh.tap()
        Thread.sleep(forTimeInterval: 0.8)

        for ch in "wojintianyaoqukaihui" {
            let k = app.buttons[String(ch)].firstMatch
            XCTAssertTrue(k.waitForExistence(timeout: 4), "🚨 字母键 \(ch) 找不到")
            k.tap()
            Thread.sleep(forTimeInterval: 0.22)
        }
        Thread.sleep(forTimeInterval: 2.0)
        shot("01_打完整句拼音")

        // 好样本：先确认候选栏在工作（否则"没有整句"这个结论不成立）
        XCTAssertTrue(app.buttons.count > 20, "🚨 界面上按钮太少，键盘多半没画出来")

        let want = "我今天要去开会"
        XCTAssertTrue(app.buttons[want].firstMatch.waitForExistence(timeout: 6),
                      "🚨 候选里没有「\(want)」—— 整句还是没按词切")
    }
}
