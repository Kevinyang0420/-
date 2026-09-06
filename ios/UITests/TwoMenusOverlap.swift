import XCTest

/// **语气菜单和语言菜单叠在一起** —— Kevin 2026-09-06 实机报：
/// > 「随手翻译里，我把『语气』点开之后有下拉菜单，然后『语言』这边又打开下拉菜单，
/// >   这两个菜单叠在一起了。这个要解决一下，不能叠在一起啊。」
///
/// 🚨 先复现、拍到图再动手 —— 语气是**系统 `UIMenu`**、语言是**自绘面板**，
///    两套东西的层级和定位规则不同，凭想的改法很可能改错对象。
final class TwoMenusOverlap: XCTestCase {

    func testOpenBothMenus() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        let cta = app.buttons["app.try"]
        XCTAssertTrue(cta.waitForExistence(timeout: 8), "首页找不到随手翻译入口")
        cta.tap()
        Thread.sleep(forTimeInterval: 1.5)

        // 钉回翻译档 —— 只有翻译档才同时有语气和语言两个钮
        let toTranslate = app.buttons["翻译"]
        XCTAssertTrue(toTranslate.waitForExistence(timeout: 5), "找不到翻译档")
        toTranslate.tap()
        Thread.sleep(forTimeInterval: 1.0)

        // 🚨 **顺序反过来才叠得起来**（实测）：
        //    先开语气（系统 `UIMenu`）时，系统会盖一层遮罩吞掉点击 ——
        //    语言钮 `isHittable=false`，第二个菜单**根本开不了**。
        //    反过来：语言面板是**自绘的、不吞点击**，它开着时照样点得到语气钮，
        //    系统菜单就压在它上面 → 这才是他手机上看到的那一幕。
        let langBtn = app.buttons["app.lang"]
        XCTAssertTrue(langBtn.waitForExistence(timeout: 5), "🚨 找不到语言钮")
        langBtn.tap()
        Thread.sleep(forTimeInterval: 1.2)
        let panel = app.otherElements["lang.panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 4),
                      "🚨 语言面板没开 —— 后面那条会变成假绿")

        let tone = app.buttons["app.tone"]
        XCTAssertTrue(tone.waitForExistence(timeout: 5), "🚨 找不到语气钮")
        XCTAssertTrue(tone.isHittable,
                      "🚨 语言面板开着时语气钮点不到 —— 那就叠不起来，用例白测")
        tone.tap()
        Thread.sleep(forTimeInterval: 1.5)

        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "OVERLAP_先语言后语气"; a.lifetime = .keepAlways; add(a)

        // 🚨 判据：语气菜单弹出来时，语言面板**必须已经收掉**。
        //    两个浮层不许同时在场 —— 这是他要的「不能叠在一起」。
        //    量的是"在不在"，不是"重不重叠几个像素" ——
        //    几何重叠会随字号/机型变，"同时在场"不会。
        XCTAssertFalse(panel.exists,
                       "🚨 语气菜单弹出来了，语言面板还在 —— 两个下拉叠在一起｜"
                       + "语言面板=\(panel.frame) 语气钮=\(tone.frame)")
    }
}
