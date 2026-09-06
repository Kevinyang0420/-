import XCTest

/// 切档时浮层必须收掉 —— Kevin 2026-09-06 亲口。
///
/// > 「我在随手翻译这边把语言拉出来…然后跳去转写，**这时候语言菜单还是开着的，
/// >   而且被归到了左边**。因为跳到转写其实不涉及语言，这个菜单就应该自动关上。」
///
/// 🚨 判据挂在**面板还在不在**上（`lang.panel` 这个标识），
///    不挂在截图上 —— 截图要人看，这条能自己红。
final class PanelDismissShot: XCTestCase {

    func testPanelClosesWhenSwitchingTab() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        // 首页 → 随手翻译
        let cta = app.buttons["app.try"]
        XCTAssertTrue(cta.waitForExistence(timeout: 8), "首页找不到随手翻译入口")
        cta.tap()
        Thread.sleep(forTimeInterval: 1.5)

        // 🚨 **先把档位钉回「翻译」**。
        //    `setMode` 会把档位写进 UserDefaults，**上一轮测试停在哪一档，
        //    下一轮启动就是哪一档** —— 停在转写档时语言钮是隐藏的，
        //    这条测试会红在「找不到语言钮」上，而那是**假红**：
        //    红了，但不是因为被测的缺陷。坏样本注入时我就撞到了这个。
        let toTranslate = app.buttons["翻译"]
        XCTAssertTrue(toTranslate.waitForExistence(timeout: 5), "找不到翻译档")
        toTranslate.tap()
        Thread.sleep(forTimeInterval: 1.0)

        // 打开语言下拉
        let langBtn = app.buttons["app.lang"]
        XCTAssertTrue(langBtn.waitForExistence(timeout: 5), "找不到语言下拉钮")
        langBtn.tap()
        Thread.sleep(forTimeInterval: 1.2)

        let panel = app.otherElements["lang.panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 4),
                      "🚨 面板压根没打开 —— 后面那条判据会变成假绿")

        // 🚨 切到「转写」
        let transcribe = app.buttons["转写"]
        XCTAssertTrue(transcribe.waitForExistence(timeout: 4), "找不到转写档")
        transcribe.tap()
        Thread.sleep(forTimeInterval: 1.5)

        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "PANEL_01_切到转写之后"
        a.lifetime = .keepAlways
        add(a)

        XCTAssertFalse(panel.exists,
                       "🚨 切到转写之后语言面板还开着 —— 而且会跟着塌掉的锚点挪到左边")
    }
}
