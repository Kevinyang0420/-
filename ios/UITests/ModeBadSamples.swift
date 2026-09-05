import XCTest

/// 两个坏样本（2.1 要求「痕迹/判据要能红」）。
final class ModeBadSamples: XCTestCase {
    override func setUp() { continueAfterFailure = true }
    private func btn(_ app: XCUIApplication, id: String, label: String) -> XCUIElement {
        let b = app.buttons[id]; if b.exists { return b }
        return app.buttons[label]   // 旧包没有 id，退回按标题找
    }

    /// 反向持久改档：逐字 → 点反向 → 再点反向关掉。之后由外部（Mac）读 App Group 偏好 vime.mode：
    /// 旧包应是 en（红）、修后应仍是 raw（绿）。这里只负责把动作做出来并打日志。
    func testReverseMustNotPersistMode() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        // 🚨 模拟器音频会 abort，报出来像「App 没起来」（见 TestApp.swift）
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch(); XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25)); Thread.sleep(forTimeInterval: 2.5)
        let raw = btn(app, id: "app.mode.raw", label: "逐字"); guard raw.waitForExistence(timeout: 6) else { NSLog("MBS 🚨 找不到逐字按钮"); return }
        raw.tap(); Thread.sleep(forTimeInterval: 0.8); NSLog("MBS 点了逐字")
        let rev = btn(app, id: "app.rev", label: "⇄ 我说"); guard rev.waitForExistence(timeout: 6) else { NSLog("MBS 🚨 找不到反向按钮（标题可能不同）"); return }
        rev.tap(); Thread.sleep(forTimeInterval: 0.8); NSLog("MBS 点了反向（开）")
        rev.tap(); Thread.sleep(forTimeInterval: 0.8); NSLog("MBS 点了反向（关）")
        NSLog("MBS 完 —— 由 Mac 读 vime.mode：旧包应 en（红）/ 修后应 raw（绿）")
    }

    /// 档位两源不一致：TransProbe 里召出键盘（内存档=高亮）→ 切到主 App 点「逐字」（真实写入者）→
    /// 回 TransProbe 同一键盘实例按麦克风 → 痕迹必须出现「档位不一致：高亮=… 偏好=raw」。
    func testModeDesyncNoteMustFire() throws {
        let host = XCUIApplication(); host.launch(); XCTAssertTrue(host.wait(for: .runningForeground, timeout: 25)); Thread.sleep(forTimeInterval: 2.0)
        let f = host.textFields["probe.field"]; if f.exists { f.tap() } else { host.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24)).tap() }
        Thread.sleep(forTimeInterval: 2.0)
        var tries = 0
        while !host.buttons["transless.mic"].waitForExistence(timeout: 4) && tries < 3 {
            tries += 1
            host.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.945)).press(forDuration: 1.3); Thread.sleep(forTimeInterval: 1.8)
            let row = host.cells.matching(NSPredicate(format: "label BEGINSWITH[c] 'Transless'")).firstMatch
            if row.waitForExistence(timeout: 3) { row.tap() } else { host.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
            Thread.sleep(forTimeInterval: 3.5)
        }
        guard host.buttons["transless.mic"].exists else { NSLog("MBS 🚨 召不出键盘"); return }
        // 键盘上先把档位点成「整理」（内存=zh，偏好=zh）
        if host.buttons["整理"].exists { host.buttons["整理"].tap(); Thread.sleep(forTimeInterval: 0.6); NSLog("MBS 键盘点了整理") }
        // 切到主 App，用它的按钮把偏好改成 raw（不重建键盘实例）
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless"); app.activate(); Thread.sleep(forTimeInterval: 2.5)
        let raw = btn(app, id: "app.mode.raw", label: "逐字"); if raw.waitForExistence(timeout: 6) { raw.tap(); NSLog("MBS 主App 点了逐字（偏好→raw）") } else { NSLog("MBS 🚨 主App 找不到逐字") }
        Thread.sleep(forTimeInterval: 1.0)
        host.activate(); Thread.sleep(forTimeInterval: 2.0)
        if !host.buttons["transless.mic"].exists { NSLog("MBS ⚠️ 回来后键盘重建了（会重读偏好，不一致不会出现，本样本不成立）"); return }
        NSLog("MBS 回到同一键盘实例，按麦克风 → 痕迹应有「档位不一致：高亮=zh 偏好=raw」")
        host.buttons["transless.mic"].tap(); Thread.sleep(forTimeInterval: 3.0)
        if host.buttons["transless.mic"].exists { host.buttons["transless.mic"].tap() }
        Thread.sleep(forTimeInterval: 3.0); NSLog("MBS 完")
    }
}
