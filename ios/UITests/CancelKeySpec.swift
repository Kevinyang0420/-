import XCTest

/// **录音取消 ✕** —— Kevin 2026-09-06 亲口：
/// > 「录到一半不想录、不上传了，希望能有个地方**按叉退出**。目前录了一半想退出不行，
/// >  **必须点停止录音然后上传，强行走完这一步**。」
/// > 「上传不成功时出来叹号，**只能再点停止录音键继续重试上传，也没有退出录音的入口**。」
///
/// 规格：`voice_ime/_规格_录音取消_20260906.md`
///
/// 🚨 ✕ **不可撤销**（键盘里弹不了 `UIAlertController`，做不了撤销条），
///    所以「防误触」是判据的一部分，不是装饰。
final class CancelKeySpec: XCTestCase {

    private func launchKb(forceRetry: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "kb"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        if forceRetry {
            // 失败态：真机上要真失败一次才亮，模拟器用这个开关点亮
            app.launchEnvironment["TRANSLESS_KB_FORCE_RETRY"] = "1"
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.5)
        return app
    }

    /// 空闲、没存货 → ✕ **不出现**。没有可放弃的东西。
    /// 🚨 这条是反向对照：没有它的话，"永远显示 ✕" 也会让下面几条全绿。
    func testHiddenWhenIdleAndNoStock() {
        let app = launchKb()
        let x = app.buttons["kb.cancel"]
        XCTAssertFalse(x.exists && x.isHittable,
                       "🚨 空闲无存货也出现 ✕ —— 没有可放弃的东西，"
                       + "而它是个不可撤销的键")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "CANCEL_01_空闲无存货"; a.lifetime = .keepAlways; add(a)
    }

    /// 失败态（叹号亮）→ ✕ **出现**，这是他说的第 2 条。
    func testShownWhenRetryBadgeOn() {
        let app = launchKb(forceRetry: true)
        let x = app.buttons["kb.cancel"]
        XCTAssertTrue(x.waitForExistence(timeout: 6),
                      "🚨 叹号亮着却没有退出入口 —— 他原话：「也没有退出录音的入口」")
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "CANCEL_02_失败态有叉"; a.lifetime = .keepAlways; add(a)
    }

    /// 🚨 **规格第 6 条坏样本**：✕ 贴着麦克风放要能被量出来。
    ///    不可撤销的键贴着主键 = 必然误触，而这种毛病肉眼看图容易放过。
    func testGapFromMicIsEnough() {
        let app = launchKb(forceRetry: true)
        let x = app.buttons["kb.cancel"]
        XCTAssertTrue(x.waitForExistence(timeout: 6), "🚨 找不到 ✕")
        let mic = app.buttons["transless.mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 6), "🚨 找不到麦克风，量不了间隙")
        let gap = mic.frame.minX - x.frame.maxX
        XCTAssertGreaterThanOrEqual(gap, 8,
            "🚨 ✕ 跟麦克风只隔 \(gap)pt —— 一个不可撤销的键贴着主键放，必然误触"
            + "｜✕=\(x.frame) 麦=\(mic.frame)")
        // 反向对照：也不该离得太远跑到别的控件上去
        XCTAssertLessThan(gap, 60, "🚨 间隙 \(gap)pt 太大，✕ 跑到别处去了")
    }

    /// ✕ 比麦克风小一圈 —— 视觉上就不是主操作。
    func testSmallerThanMic() {
        let app = launchKb(forceRetry: true)
        let x = app.buttons["kb.cancel"]
        XCTAssertTrue(x.waitForExistence(timeout: 6), "🚨 找不到 ✕")
        let mic = app.buttons["transless.mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 6), "🚨 找不到麦克风")
        XCTAssertLessThan(x.frame.width, mic.frame.width * 0.6,
            "🚨 ✕ 跟麦克风差不多大，看起来像并列的主操作"
            + "｜✕ 宽=\(x.frame.width) 麦 宽=\(mic.frame.width)")
        XCTAssertGreaterThanOrEqual(x.frame.width, 32,
            "🚨 ✕ 只有 \(x.frame.width)pt，低于可点尺寸下限")
    }

    /// 🚨 **规格第 1/3 条**：失败态点 ✕ → 叹号灭、✕ 自己收起、**输入框一个字都没多**。
    func testTapDiscardsAndInsertsNothing() {
        let app = launchKb(forceRetry: true)
        let x = app.buttons["kb.cancel"]
        XCTAssertTrue(x.waitForExistence(timeout: 6), "🚨 找不到 ✕")
        x.tap()
        Thread.sleep(forTimeInterval: 1.5)

        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "CANCEL_03_按下之后"; a.lifetime = .keepAlways; add(a)

        // 🚨 判据挂在**输入框内容**上，不挂在"没报错"上 ——
        //    「点了取消却把字插进去」正是他最不能接受的那种失败，而它不报错。
        let field = app.textViews.firstMatch.exists
            ? app.textViews.firstMatch : app.textFields.firstMatch
        if field.exists {
            let t = (field.value as? String) ?? ""
            XCTAssertTrue(t.isEmpty,
                          "🚨 点了 ✕ 却往输入框插了字：\(t.prefix(40))")
        }
        XCTAssertFalse(x.isHittable,
                       "🚨 放弃完了 ✕ 还杵在那儿 —— 已经没有可放弃的东西了")
    }
}
