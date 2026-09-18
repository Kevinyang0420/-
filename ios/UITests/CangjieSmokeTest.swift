import XCTest

/// 速成/倉頡合一档的第一条冒烟检查：**打首尾码能出候选，候选按钮能点**。
///
/// 规格：`_规格_速成输入法调研_20260918.md`；0 09-18 拍板的验收范围
/// （"打首尾两码 → 出候选 → 能选中上屏"这一步做完就停，别做完整套）。
///
/// 🚨 **"上屏"这一半在预览环境里验不到，这不是这次新出的坑**：
///    `KbPinyinChain.swift` 已经踩过一次同一个环境限制并写清楚了——预览页
///    （`TRANSLESS_PAGE=kb`）里 `textDocumentProxy` 是空的，选词后"吃掉缓冲、
///    真正把字交给宿主文本框"这一段链路走不完整，**这是量具的限制，不是产品的**。
///    真机上是完整的宿主环境，这一段能走通。
///    所以这条测试验到"候选按钮存在、可点、点了不崩"为止——
///    再往后（真的进了文本框）留给 0 说的"我自己上真机按一次"。
final class CangjieSmokeTest: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testFirstLastCodeShowsCandidate() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "kb"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 4.0)

        for id in ["kb.switch.typing"] where app.buttons[id].waitForExistence(timeout: 4) {
            app.buttons[id].tap()
        }
        if app.buttons["打字"].firstMatch.waitForExistence(timeout: 3) {
            app.buttons["打字"].firstMatch.tap()
        }
        Thread.sleep(forTimeInterval: 2.5)

        let zh = app.buttons["kb.chip.zh"]
        XCTAssertTrue(zh.waitForExistence(timeout: 10), "🚨 中英芯片没出来，键盘没画好")
        zh.tap()
        Thread.sleep(forTimeInterval: 1.0)

        // ── 循环切到速成档：拼音 → 五笔 → 速成（`kb.immode` 按钮点两次） ──
        let modeBtn = app.buttons["kb.immode"]
        XCTAssertTrue(modeBtn.waitForExistence(timeout: 8), "🚨 找不到档位切换按钮 kb.immode")
        modeBtn.tap()   // 拼音 → 五笔
        Thread.sleep(forTimeInterval: 0.5)
        modeBtn.tap()   // 五笔 → 速成
        Thread.sleep(forTimeInterval: 0.5)
        shot("01_切到速成档")

        // 🚨 判据挂按钮**标题**上（`imMode.label`＝`L.kb_cangjie_s`＝「速」），
        //    不是猜"点两下就一定是它"——顺序变了这条能立刻抓出来。
        XCTAssertEqual(modeBtn.label, "速",
                       "🚨 点两次档位按钮后标题不是「速」，实际「\(modeBtn.label)」——"
                       + "说明 IMMode 循环顺序跟测试假设的不一致")

        // ── 打「日」的完整倉頡码「a」（1.1 给的 50 字子集：a→日）──
        let a = app.buttons["a"].firstMatch
        XCTAssertTrue(a.waitForExistence(timeout: 5), "🚨 字母键 a 找不到")
        a.tap()
        Thread.sleep(forTimeInterval: 1.2)
        shot("02_打了a")

        // ── 候选里必须有「日」──
        let ri = app.buttons["日"].firstMatch
        XCTAssertTrue(ri.waitForExistence(timeout: 6),
                      "🚨 打了「a」候选里没有「日」——速成档没有真的接上码表")

        // ── 点一下候选按钮，只验「点了不崩、按钮还在响应」──
        //    真正commit进文本框那一段留给真机（见文件头注释）。
        ri.tap()
        Thread.sleep(forTimeInterval: 1.0)
        shot("03_点了日之后")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5),
                      "🚨 点候选之后 App 掉了")
    }
}
