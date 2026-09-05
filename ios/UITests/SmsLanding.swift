import XCTest

/// **端到端：在「短信」里按我们的麦克风（主 App 已杀 → 必然跳），看他被送回哪儿。**
///
/// 🚨 这是唯一的真实路径：只有键盘的 `openURL` 才会把主 App **拉到前台**，
///    而 `_deactivateForReason:` 能不能把他送回去，前提就是「被别人打开过」。
///    用 devicectl 启动是后台启动，走不到这条。
///
/// 🚨🚨 **判据不用 `XCUIApplication.state`** —— 实测它会让短信和我们
///    **同时报 4（前台）**，用它得出的 0/1 全是噪音，我已经据此误报过一次"成了"。
///    改成看**屏幕上实际是什么**：
///      · 桌面 → SpringBoard 的 App 图标可点
///      · 短信 → 有输入框、没有一堆图标
///    这是「量的对象要跟结论说的对象一致」——结论说的是"他眼前是什么"，
///    那就去量他眼前是什么。
final class SmsLanding: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    /// 现在屏幕上是什么：`"桌面"` / `"短信"` / `"我们"` / `"说不准"`
    private func whatIsOnScreen() -> String {
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let sms = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        let us = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        // 我们自己的界面有个很特别的标识
        if us.staticTexts["transless.home.title"].exists { return "我们" }
        if sms.textViews.count > 0 || sms.textFields.count > 0 { return "短信" }
        // 桌面：SpringBoard 上一堆可点图标
        if sb.icons.count > 6 { return "桌面" }
        return "说不准"
    }

    func testLandAfterJump() throws {
        let sms = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        sms.activate()
        XCTAssertTrue(sms.wait(for: .runningForeground, timeout: 20), "短信没起来")
        Thread.sleep(forTimeInterval: 3)

        var inChat = false
        for (n, y) in [0.22, 0.30, 0.38].enumerated() {
            if n > 0 {
                let a = sms.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                let b = sms.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
                a.press(forDuration: 0.05, thenDragTo: b)
                Thread.sleep(forTimeInterval: 1.5)
            }
            sms.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: CGFloat(y))).tap()
            Thread.sleep(forTimeInterval: 1.6)
            if sms.textViews.count > 0 || sms.textFields.count > 0 { inChat = true; break }
        }
        NSLog("SMSLAND 进会话了吗=%d", inChat ? 1 : 0)
        sms.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.94)).tap()
        Thread.sleep(forTimeInterval: 1.6)

        let globe = sms.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.945))
        for n in 0..<8 where !sms.buttons["transless.mic"].exists {
            globe.tap(); Thread.sleep(forTimeInterval: 1.5)
            NSLog("SMSLAND 切第%d次，麦克风键在不在=%d", n + 1,
                  sms.buttons["transless.mic"].exists ? 1 : 0)
        }
        guard sms.buttons["transless.mic"].waitForExistence(timeout: 6) else {
            NSLog("SMSLAND 🚨 没切到我们的键盘 —— 本轮作废，不许凑结论")
            return
        }
        NSLog("SMSLAND 按之前屏幕上是：%@", whatIsOnScreen())
        NSLog("SMSLAND ✅ 按麦克风（主App已杀 → 会跳）")
        sms.buttons["transless.mic"].tap()

        // 🚨 采样要比事件快：他描述 Typeless 是「闪一下就回去」，
        //    每秒一次的采样会整段错过（上一轮就是这么报出 0 的）。
        var seen: [String] = []
        for _ in 1...120 {
            Thread.sleep(forTimeInterval: 0.25)
            let w = whatIsOnScreen()
            if seen.last != w { seen.append(w); NSLog("SMSLAND 屏幕 → %@", w) }
            if seen.count >= 3 && seen.contains("我们") && w == "短信" { break }
        }
        let jumped = seen.contains("我们")
        let backHome = seen.last == "桌面"
        let backSms = seen.last == "短信"
        NSLog("SMSLAND 【判据】跳出来过=%d；最后停在=%@ → %@",
              jumped ? 1 : 0, seen.last ?? "?",
              (jumped && backSms) ? "🎉 回到原App了"
                : (backHome ? "🚨 落桌面" : "🚨 没跳或说不准"))
        NSLog("SMSLAND 屏幕变化序列：%@", seen.joined(separator: " → "))
    }
}
