import XCTest

/// **端到端：我自己点，不推给 Kevin。**
///
/// 🚨 立这个文件的原因是他 2026-09-04 的原话：
///    「你有没有真的是端到端测过呀？现在那个面对面翻译，我点的那个录音按钮
///     根本没有效果，没反应啊！」以及
///    「不要把端侧的这个事情给我，你自己有能力做就自己做」。
///
///    在这之前我"验收"只做到「App 起得来」—— **从没点进过任何一个功能**。
///    起得来和能用是两件事，正如编过和跑得起来是两件事。
///
/// 🚨 前提：设备上的 **Enable UI Automation** 已打开（他 09-04 开的）。
///    没开的话 xcodebuild 会报 `Timed out while enabling automation mode`，
///    那是**跑不了**，不是**测过了**——别把它读成绿。
final class E2EHome: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        NSLog("E2E shot=%@", name)
    }

    func testHomeAndFaceToFace() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        // 🚨 模拟器音频会 abort，报出来像「App 没起来」（见 TestApp.swift）
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        shot(app, "01_home")

        // ── 底部五 Tab：逐个点过去，每个都要真的切过去 ──
        // 🚨 判据是**点完之后那一格被选中**，不是"点得到" ——
        //    点得到但没切过去，用户看到的就是"点了没反应"。
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "底部 Tab 栏没出来")
        NSLog("E2E tabcount=%d", bar.buttons.count)
        XCTAssertEqual(bar.buttons.count, 5, "🚨 应该是五格")
        shot(app, "02_tabbar")

        // 🚨🚨 **每一格都要点进去截一张。**
        //    「空 Tab 是红线」这条约束以前**从没被任何自动检查覆盖过** ——
        //    测试只点了中间那颗凸起，另外三格（历史/常用词/设置）
        //    一次都没被打开过。约束写在注释里、检查里没有，等于没有。
        //
        // 🚨 判据是**点完那一格 `isSelected` 为真**，不是"点得到"：
        //    点得到但没切过去，用户看到的就是"点了没反应"。
        for (i, name) in [(0, "历史前的首页"), (1, "历史"),
                          (3, "常用词"), (4, "设置")] {
            let b = bar.buttons.element(boundBy: i)
            XCTAssertTrue(b.isHittable, "🚨 第 \(i) 格点不到（\(name)）")
            b.tap()
            Thread.sleep(forTimeInterval: 1.8)
            XCTAssertTrue(b.isSelected, "🚨 点了第 \(i) 格（\(name)）但没切过去")
            shot(app, String(format: "02%d_tab_%@", i + 1, name))
        }

        // ── 中间那颗凸起圆钮（面对面）──
        // 🚨 它**不是 tabBar 的子视图**，是盖在上面的独立按钮，
        //    所以要按 identifier 找，不能从 `bar.buttons` 里挑。
        let bump = app.buttons["tab.center.f2f"]
        XCTAssertTrue(bump.waitForExistence(timeout: 10), "🚨 凸起圆钮找不到")
        XCTAssertTrue(bump.isHittable, "🚨 凸起圆钮点不到（命中区被挡住了）")
        bump.tap()
        Thread.sleep(forTimeInterval: 2.5)
        shot(app, "03_f2f")

        // ── 面对面的录音钮：**真按一下，看它有没有起录** ──
        let mic = app.buttons["transless.f2f.mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 10), "🚨 面对面录音钮找不到")
        XCTAssertTrue(mic.isHittable, "🚨 面对面录音钮点不到")
        mic.tap()
        // 起录要一点时间（让麦、配会话）。**等状态变，不是等固定时长**做不到时，
        // 至少等够并把结果截下来 —— 判据在外面读诊断日志。
        Thread.sleep(forTimeInterval: 4.0)
        shot(app, "04_f2f_mic_tapped")
        NSLog("E2E 录音钮已点，看诊断日志判断有没有真起录")

        // 再点一次停（避免把麦克风一直占着）
        if mic.exists && mic.isHittable { mic.tap() }
        Thread.sleep(forTimeInterval: 2.0)
        shot(app, "05_f2f_after_stop")
    }
}
