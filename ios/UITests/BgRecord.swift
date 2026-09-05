import XCTest

/// **录音中切到别的 App，录音还在不在？** —— Kevin 2026-09-04 的新需求。
///
/// 他的原话（2.1 转）：「打开转写或翻译并开始录音后，切到别的窗口查资料
/// 再回来，录音要能继续；停止后正常上传处理。目前切走会导致录音自动停止。」
///
/// ## 🚨 判据不是"没报错"，也不是"录音状态还在"
///
/// 判据是**后台那段时间里，音频 tap 还在不在收帧** ——
/// 看 `KbBridge` 痕迹里的「录音心跳：第 N 秒｜累计帧=…｜后台」。
///
/// 为什么必须是帧数：
///   · 「界面还显示在录」可能只是 UI 状态没更新，底下早断了；
///   · 「最后没出文字」可能是断了，也可能是录着但没上传 ——
///     **两种坏法长得一样，修法完全不同**；
///   · 帧数是**音频 tap 真收到数据才会涨**的，它涨 = 真的还在收音（肯定判据）。
///
/// ## 🚨 模拟器上跑出来的结果要打折
///
/// 模拟器的后台策略跟真机**不一样**：
///   · 模拟器上**过了不算过**（真机的后台限制更严）；
///   · 模拟器上**不过也不算不过**（可能只是模拟器自己不给麦克风）。
/// 它的价值是：**先把"我们自己代码里有没有主动停"这一类原因排掉**。
/// 真结论只能在他手机上得。
final class BgRecord: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testKeepsRecordingInBackground() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        // 🚨 这个用例**真的要录音**（后台录音验证），故意不关音频。
        //    它在模拟器上会撞 AudioToolbox 超时，只能在真机跑。
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        // 首页 →「随手翻译」（那一屏才有录音钮）
        let entry = app.buttons["app.try"].firstMatch
        if entry.waitForExistence(timeout: 5) {
            entry.tap()
        } else {
            // 🚨 找不到就按文字找，**但不静默跳过** —— 跳过等于这一轮什么都没测。
            let byText = app.staticTexts["随手翻译"].firstMatch
            XCTAssertTrue(byText.waitForExistence(timeout: 10),
                          "🚨 首页上找不到「随手翻译」入口，这一轮没测到东西")
            byText.tap()
        }
        Thread.sleep(forTimeInterval: 2.5)

        let mic = app.buttons["app.mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 10), "🚨 随手翻译的录音钮找不到")
        XCTAssertTrue(mic.isHittable, "🚨 录音钮点不到")
        mic.tap()
        NSLog("BGREC 已起录，先在前台录 6 秒")
        Thread.sleep(forTimeInterval: 6.0)      // 前台先攒够 1 条心跳，做对照

        // ── 真的切走 ──
        // 🚨 用 `XCUIDevice.press(.home)`，不是 `app.terminate()`：
        //    终止是"杀进程"，跟他说的"切到别的窗口"完全不是一件事。
        XCUIDevice.shared.press(.home)
        NSLog("BGREC 已按 Home，在后台停 30 秒")
        Thread.sleep(forTimeInterval: 30.0)     // 2.1 的验收判据就是 ≥30 秒

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "切不回来")
        Thread.sleep(forTimeInterval: 2.0)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "01_回到前台"
        a.lifetime = .keepAlways
        add(a)

        // 停止（再点一下），让它走完上传那条路
        if mic.exists && mic.isHittable { mic.tap() }
        Thread.sleep(forTimeInterval: 6.0)
        let b = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        b.name = "02_停止之后"
        b.lifetime = .keepAlways
        add(b)
        NSLog("BGREC 跑完，判据看痕迹里的「录音心跳…后台」有没有连着涨")
    }
}
