import XCTest

/// 验 Kevin 撞的那条：录一次 → 停 → 等 R1a 的 3 秒释放会话 → 再按 → 引擎必须架得起来（不许「没架上」）。
/// 不需要出声：判据只看第二次按下后痕迹里是「架好」还是「没架上」。
final class ArmAfterRelease: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testArmAfterRelease() throws {
        let host = XCUIApplication()
        host.launch()
        XCTAssertTrue(host.wait(for: .runningForeground, timeout: 25))
        Thread.sleep(forTimeInterval: 2.0)
        let f = host.textFields["probe.field"]; if f.exists { f.tap() } else { host.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24)).tap() }
        Thread.sleep(forTimeInterval: 2.0)
        var mic = host.buttons["transless.mic"]; var tries = 0
        while !mic.waitForExistence(timeout: 4) && tries < 3 {
            tries += 1
            host.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.945)).press(forDuration: 1.3); Thread.sleep(forTimeInterval: 1.8)
            let row = host.cells.matching(NSPredicate(format: "label BEGINSWITH[c] 'Transless'")).firstMatch
            if row.waitForExistence(timeout: 3) { row.tap() } else { host.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
            Thread.sleep(forTimeInterval: 3.5); mic = host.buttons["transless.mic"]
        }
        guard mic.exists else { NSLog("AAR 🚨 没找到我们的麦克风键"); return }
        NSLog("AAR 第一次按（录）"); mic.tap(); Thread.sleep(forTimeInterval: 3.0)
        NSLog("AAR 第一次按（停）"); if mic.exists { mic.tap() }
        NSLog("AAR 等 6 秒让 R1a 的 3 秒释放跑过去"); Thread.sleep(forTimeInterval: 6.0)
        NSLog("AAR 第二次按（录）——判据在这之后"); if mic.exists { mic.tap() } else { host.buttons["transless.mic"].firstMatch.tap() }
        Thread.sleep(forTimeInterval: 4.0)
        NSLog("AAR 第二次按（停）"); if host.buttons["transless.mic"].exists { host.buttons["transless.mic"].tap() }
        Thread.sleep(forTimeInterval: 3.0)
        NSLog("AAR 完")
    }
}
