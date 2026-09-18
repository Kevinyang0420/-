import XCTest

/// ④「录音不设 cap」：Kevin 拍板不设上限之后，`Voice.swift` 的 `capTimer`
/// 改成分段模式（`onSegment != nil`）下**不排任何定时器**。这条测的是
/// 用户真正会经历的那件事——录过旧的单句上限（`MAX_DURATION` 60 秒）
/// 之后录音**没有被系统自动切断**，计时器还在正常往上跳。
///
/// 🚨 不验证转写内容（现场是安静的会议室，说不出真人声音），只验证
/// 「过了 60 秒还在录、计时器数字在涨」——这正是这次改动要保的那条行为，
/// 转写准不准是另一条早就有的链，不是这次改动碰的东西。
final class RecordingNoCapSpec: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    func testRecordingSurvivesPastOldSixtySecondCap() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "speak"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 2.0)

        let mic = app.buttons["app.mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 8), "🚨 找不到麦克风按钮")
        mic.tap()
        Thread.sleep(forTimeInterval: 1.0)
        shot("01_起录")

        // 🚨🚨 旧上限是 60 秒（`Voice.MAX_DURATION`）——等到 70 秒，
        //    过旧上限之后再抽查，才是这条测试真正要证的事。
        Thread.sleep(forTimeInterval: 70.0)
        shot("02_过了70秒还在录")

        // 判据：这时候屏上应该有一个形如 "1:1x" 的计时文本（分:秒，分钟数 ≥ 1），
        // 不是回到了空闲态（那样就说明被自动切断了）。
        let texts = app.staticTexts.allElementsBoundByIndex.map { $0.label }
        let elapsedPattern = texts.first { t in
            guard let colon = t.firstIndex(of: ":") else { return false }
            let minPart = t[t.startIndex..<colon]
            return Int(minPart) != nil && Int(minPart)! >= 1 && t.count <= 6
        }
        XCTAssertNotNil(elapsedPattern,
            "🚨 过了 70 秒屏上没找到 ≥1 分钟的计时文本（现有文本：\(texts.prefix(20))）"
            + "——可能被旧的 60 秒上限切断了")

        // 收尾：停止录音，确认没有卡死/崩溃（不断言转写内容，安静环境下
        // 大概率是"没说话"失败提示，那是预期内的，不是这条测试要验的）。
        mic.tap()
        Thread.sleep(forTimeInterval: 2.0)
        shot("03_停止后")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10),
                      "🚨 停止录音之后 App 掉了")
        if app.alerts.firstMatch.waitForExistence(timeout: 2) {
            app.alerts.firstMatch.buttons.firstMatch.tap()
        }
    }
}
