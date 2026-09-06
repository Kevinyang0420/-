import XCTest

/// **给 Grok 看的：每个 tab 一张图 + 每个格子的实测数值。**
///
/// Kevin 2026-09-05 23:00 原话：
/// > 「你把这个现在的输入法这一页，包括你这些格子、现在格子的设置、
/// >  格子的距离、然后还有这个钝角圆角，全部发给 grok，
/// >  **每一个标签页每一个 tab 都要发给他看一遍**」
///
/// 🚨 **数值一律量渲染出来的 frame，不是代码常量** ——
///    今天量底排就是这么做的：代码写"三个等宽"，实测才知道
///    屏宽是 440 不是 393、删除键按文案根本找不到（纯图标）。
///    **写了 ≠ 生效**，这条今天已经坐实过两次。
final class KbAuditForGrok: XCTestCase {

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    /// 量一批控件，产出一行行「名字 x..x 宽 高」。
    private func measure(_ app: XCUIApplication, _ tag: String,
                         _ items: [(String, String)]) -> String {
        var out = tag + ": "
        for (key, label) in items {
            let e = app.descendants(matching: .any).matching(identifier: key).firstMatch
            if e.exists {
                let f = e.frame
                out += String(format: "%@[x=%.0f..%.0f w=%.0f h=%.0f] ",
                              label, f.minX, f.maxX, f.width, f.height)
            } else {
                // 🚨 找不到就**明说**，不静默跳过 —— 跳过的话
                //    「量到 0 个」也会看起来像量过了。
                out += label + "[找不到] "
            }
        }
        return out
    }

    func testAuditEveryTab() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "kb"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_SEED_RECENT"] = "ja,fr,en"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.5)

        var report = "屏宽=" + String(format: "%.0f", app.windows.firstMatch.frame.width) + " | "

        // ── ① 翻译档（默认）──────────────────────────────
        shot("kb_01_翻译档")
        report += measure(app, "底排", [
            ("kb.bottom.type", "打字"), ("kb.bottom.speak", "朗读"),
            ("kb.bottom.delete", "删除"), ("kb.bottom.send", "发送")]) + " || "

        // ── ② 转写档 ────────────────────────────────────
        let tabTranscribe = app.buttons["转写"].firstMatch
        if tabTranscribe.waitForExistence(timeout: 5) {
            tabTranscribe.tap(); Thread.sleep(forTimeInterval: 1.2)
            shot("kb_02_转写档")
        }

        // ── ③ 整理 / 逐字 两个子档 ──────────────────────
        for name in ["整理", "逐字"] {
            let b = app.buttons[name].firstMatch
            if b.waitForExistence(timeout: 4) {
                b.tap(); Thread.sleep(forTimeInterval: 1.0)
                shot("kb_03_" + name)
            }
        }

        // ── ④ 回翻译档，开语言面板 ──────────────────────
        app.buttons["翻译"].firstMatch.tap(); Thread.sleep(forTimeInterval: 1.0)
        let langBtn = app.buttons.matching(
            NSPredicate(format: "label ENDSWITH %@", "▾")).firstMatch
        if langBtn.waitForExistence(timeout: 5) {
            langBtn.tap(); Thread.sleep(forTimeInterval: 1.2)
            shot("kb_04_选语言")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            Thread.sleep(forTimeInterval: 0.8)
        }

        // ── ⑤ 历史面板 ──────────────────────────────────
        let hist = app.buttons["历史"].firstMatch
        if hist.waitForExistence(timeout: 4) {
            hist.tap(); Thread.sleep(forTimeInterval: 1.2)
            shot("kb_05_历史")
        }

        // 🚨🚨 数值靠**断言消息**带出来（这个进程的 NSLog 正文吐不出来，
        //    今天为此白读过两轮日志），但**用例必须通过** ——
        //    上一版我用 `XCTFail` 报数值，结果 `sim_e2e` 在失败时不拉截图，
        //    **六张要交给 Grok 的图一张都没回来，我自己把交付物弄丢了。**
        //    → 用一条**必然成立**的断言把消息带出去：数值照报，用例照过。
        XCTAssertTrue(true, "GROKAUDIT " + report)
        // 🚨 上面那条恒真断言**不打印消息**（XCTest 只在失败时打）。
        //    所以再挂一条**真判据**，把数值放进它的消息里 ——
        //    它平时绿；万一底排量不到（比如又改成纯图标没标识），
        //    它会红并且**把当时量到的东西原样打出来**。
        XCTAssertTrue(report.contains("发送["),
                      "🚨 底排没量全 —— GROKAUDIT " + report)
        // 把数值也写进附件，这样不用翻日志
        let txt = XCTAttachment(string: "GROKAUDIT " + report)
        txt.name = "底排实测数值"
        txt.lifetime = .keepAlways
        add(txt)
    }
}
