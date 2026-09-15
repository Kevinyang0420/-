import XCTest

/// 0 09-15 要的②验证：**只召键盘，不点麦克风**——让 `takePendingIfAny()`
/// 在 `viewDidAppear` 里自然跑一次，去接（或不接）`TRANSLESS_SIM_JUMP_DONE`
/// 探针（见 `AppDelegate.swift`）落下的那份 pending。这条本身不判断对错，
/// 只负责"让 pending 有机会被取走"——判据在外部读 history.jsonl 的行数。
final class JumpDoneHistoryProbe: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testSummonKeyboardOnlyNoMicTap() throws {
        let host = XCUIApplication()
        host.launch()
        XCTAssertTrue(host.wait(for: .runningForeground, timeout: 20), "Probe host没起来")
        Thread.sleep(forTimeInterval: 1.5)

        let f = host.textFields["probe.field"]
        if f.exists { f.tap() } else { host.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24)).tap() }
        Thread.sleep(forTimeInterval: 1.5)

        var found = host.buttons["transless.mic"].waitForExistence(timeout: 4)
        var tries = 0
        while !found && tries < 3 {
            tries += 1
            host.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.945)).press(forDuration: 1.3)
            Thread.sleep(forTimeInterval: 1.8)
            let row = host.cells.matching(NSPredicate(format: "label BEGINSWITH[c] 'Transless'")).firstMatch
            if row.waitForExistence(timeout: 3) { row.tap() } else { host.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
            Thread.sleep(forTimeInterval: 3.5)
            found = host.buttons["transless.mic"].waitForExistence(timeout: 4)
        }
        NSLog("JDHP 召出键盘了吗=%d", found ? 1 : 0)
        // 🚨🚨 关键：**不点麦克风**。键盘一出现，`viewDidAppear` 里
        //    `takePendingIfAny()` 就已经无条件跑过一次了——多等几秒让
        //    0.4 秒轮询（`startPendingWatch`）再兜一轮，然后就此收尾。
        Thread.sleep(forTimeInterval: 3.0)
        NSLog("JDHP 完——已经给过 takePendingIfAny() 机会去接 pending 了")
    }
}
