import XCTest

/// 闲置周期(Kevin 定「用完几分钟后灯灭」,测试时 idle 临时 10s):
/// 录→停 → 按 Home 真闲置 16s(键盘不在,应放掉会话·灯灭)→ 回来重新召键盘 → 按(应跳一次·等前台·架好)→ 停 → 再按(应不跳直接录)→ 停。
/// 🚨 每次按都重新查按钮,不用旧引用(跳转回来后旧引用必失效)。
final class ArmAfterIdle: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func summonKeyboard(_ host: XCUIApplication) -> Bool {
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
        return host.buttons["transless.mic"].exists
    }
    private func mic(_ host: XCUIApplication) -> XCUIElement { host.buttons["transless.mic"] }

    func testArmAfterIdle() throws {
        let host = XCUIApplication()
        host.launch()
        XCTAssertTrue(host.wait(for: .runningForeground, timeout: 25))
        Thread.sleep(forTimeInterval: 2.0)
        guard summonKeyboard(host) else { NSLog("AAR 🚨 召不出我们的键盘"); return }

        NSLog("AAR 第一次按（录）"); mic(host).tap()
        // 冷启动会跳一趟再回来（≈2–3s），停要落在回来之后；回来后键盘可能重建，重新召
        Thread.sleep(forTimeInterval: 6.0)
        if !mic(host).exists { host.activate(); Thread.sleep(forTimeInterval: 1.5); _ = summonKeyboard(host) }
        NSLog("AAR 第一次按（停）—— 跳转回来之后"); if mic(host).exists { mic(host).tap() }
        Thread.sleep(forTimeInterval: 5.0)   // 等出稿、done()、保活重接

        NSLog("AAR 按 Home 真闲置 16 秒（键盘不在 45s → 看 iOS 会不会把静音待命的 App 挂起）")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 45.0)

        NSLog("AAR 回来重新召键盘")
        host.activate(); Thread.sleep(forTimeInterval: 2.0)
        guard summonKeyboard(host) else { NSLog("AAR 🚨 回来后召不出键盘"); return }
        NSLog("AAR 第二次按（录）——放掉后：应跳一次·等前台·架好"); mic(host).tap(); Thread.sleep(forTimeInterval: 5.0)
        // 跳转回来后键盘可能重建，重新找
        if !mic(host).exists { host.activate(); Thread.sleep(forTimeInterval: 1.5); _ = summonKeyboard(host) }
        NSLog("AAR 第二次按（停）"); if mic(host).exists { mic(host).tap() }
        Thread.sleep(forTimeInterval: 4.0)

        NSLog("AAR 第三次按（录）——刚录完、架着且保活在跑：应【不跳】直接录")
        if !mic(host).exists { _ = summonKeyboard(host) }
        mic(host).tap(); Thread.sleep(forTimeInterval: 3.0)
        NSLog("AAR 第三次按（停）"); if mic(host).exists { mic(host).tap() }
        Thread.sleep(forTimeInterval: 3.0)
        NSLog("AAR 完")
    }
}
