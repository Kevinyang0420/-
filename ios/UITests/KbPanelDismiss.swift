import XCTest

/// **键盘那一屏**的浮层 —— Kevin 在随手翻译上撞到「切到转写、语言菜单还开着」，
/// 让我查「其他地方是不是也有类似问题」。这条用例是那次排查的产物。
///
/// ## 🚨 查出来的事实：**键盘上这条路径走不到**
/// 实测（诊断进断言消息，不进 NSLog —— NSLog 在这条链路上读不到）：
/// ```
/// 语言面板 frame = (0, 706, 440, 250)
/// 转写钮   frame = (239, 714, 92.7, 34)   → 完全落在面板里，isHittable = false
/// ```
/// 键盘的面板是**全宽浮层，一开就盖住整个顶排**。用户点不到档位钮，
/// 只能选一门语言或点空白收掉。**所以键盘上不会出现他撞的那一幕。**
///
/// 🚨 那就**不许**把用例改成"绕过遮挡强行点" —— 那是绕开用户真正走的路，
///    绕出来的绿证明不了任何事。改成断言这条路径**当前确实不可达**：
///    哪天面板变小、顶排露出来，这条会红，提醒回来真验一次 `dismissPanels()`。
///
/// 📌 `KeyboardViewController.setMode` 里的 `dismissPanels()` 因此是**防御性的**，
///    在当前布局下**没有被真实验证过**。别对外说"键盘也验过了"。
final class KbPanelDismiss: XCTestCase {

    private func launchKb() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "kb"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_SEED_RECENT"] = "ja,fr,en"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.5)
        return app
    }

    /// 🚨 前置条件要钉死：`setMode` 把档位写进 UserDefaults，
    ///    **上一轮停在哪一档，下一轮启动就是哪一档**；停在转写档时语言钮是隐藏的，
    ///    用例会红在"找不到语言钮"上 —— 那是假红。
    private func pinToTranslate(_ app: XCUIApplication) {
        let t = app.buttons["翻译"]
        if t.waitForExistence(timeout: 6) { t.tap(); Thread.sleep(forTimeInterval: 1.0) }
    }

    private func assertCoversTopRow(_ app: XCUIApplication,
                                    _ panel: XCUIElement,
                                    _ which: String) {
        let transcribe = app.buttons["转写"]
        XCTAssertTrue(transcribe.waitForExistence(timeout: 4), "找不到转写档")
        let diag = "\(which)面板=\(panel.frame) 转写钮=\(transcribe.frame)"

        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "KBPANEL_\(which)_盖住顶排"; a.lifetime = .keepAlways; add(a)

        XCTAssertFalse(
            transcribe.isHittable,
            "🚨 转写钮现在点得到了 —— 说明\(which)面板不再盖住顶排，"
            + "「切档要收面板」这条路径在键盘上变成**可达**的了。"
            + "把这条用例改回真的点一下、验 `dismissPanels()` 有没有生效。｜" + diag)
    }

    func testLangPanelCoversTopRow() throws {
        let app = launchKb()
        pinToTranslate(app)

        let langBtn = app.buttons.matching(
            NSPredicate(format: "label ENDSWITH %@", "▾")).firstMatch
        XCTAssertTrue(langBtn.waitForExistence(timeout: 10), "🚨 键盘上的语言钮不在")
        langBtn.tap()
        Thread.sleep(forTimeInterval: 1.2)

        let panel = app.otherElements["kb.lang.panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 4),
                      "🚨 面板压根没打开 —— 后面那条判据会变成假绿")
        assertCoversTopRow(app, panel, "语言")
    }

    /// 历史面板 —— 同一个毛病的**兄弟字段**，不挂它就是"只挂出事那个"。
    func testHistoryPanelCoversTopRow() throws {
        let app = launchKb()
        pinToTranslate(app)

        let hist = app.buttons["kb.hist"]
        XCTAssertTrue(hist.waitForExistence(timeout: 6),
                      "🚨 找不到历史钮 —— 这条用例什么都没测到")
        hist.tap()
        Thread.sleep(forTimeInterval: 1.2)

        let panel = app.otherElements["kb.hist.panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 4),
                      "🚨 历史面板压根没打开 —— 后面那条判据会变成假绿")
        assertCoversTopRow(app, panel, "历史")
    }
}
