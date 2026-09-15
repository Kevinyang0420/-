import XCTest

/// 一次性诊断：随便说点啥屏，种一条结果，截图 + 读按钮文案有没有被截断。
/// 验完可以删——不是长期回归测试。
final class SpeakButtonsShot: XCTestCase {
    func testShot() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_PAGE"] = "speak"
        app.launchEnvironment["TRANSLESS_SEED_CARD"] = "1"
        app.launchEnvironment["TRANSLESS_UILANG_RESET"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20), "App 没起来")
        Thread.sleep(forTimeInterval: 3)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "SBS_speak_with_result"; shot.lifetime = .keepAlways; add(shot)

        for i in 0..<min(app.buttons.count, 60) {
            let b = app.buttons.element(boundBy: i)
            if b.exists, !b.label.isEmpty {
                NSLog("SBS 按钮[%d] label=%@ frame=%@", i, b.label, NSCoder.string(for: b.frame))
            }
        }
    }
}
