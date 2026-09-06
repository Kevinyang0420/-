import XCTest

/// **随手翻译两档的视觉底稿** —— 2.3 要它对齐安卓（方案 F），
/// 同时也是 Kevin 2026-09-06 01:40 那四条「三个下拉框统一」的量图底稿。
///
/// 🚨 出三张：翻译档 / 转写档 / 语气下拉展开（**语气那个是标准答案**，
///    2.1 定：「照抄，不是重新设计」，所以必须把它单独截清楚）。
final class SpeakShot0906: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func shot(_ n: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = n; a.lifetime = .keepAlways; add(a)
    }

    func testShotSpeakModes() throws {
        let app = TestApp.launch("speak")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        // 🚨 等一拍再截：`runningForeground` 只说进程到前台了，
        //    这一刻布局可能还没完 —— 截到半成品比没截更误导（照抄 HomeShot 那条）。
        Thread.sleep(forTimeInterval: 2.5)
        shot("S1_随手翻译_翻译档")

        // 切到转写档
        let tr = app.buttons["转写"].firstMatch
        if tr.waitForExistence(timeout: 6) {
            tr.tap()
            Thread.sleep(forTimeInterval: 1.2)
            shot("S2_随手翻译_转写档")
        } else {
            XCTFail("🚨 找不到「转写」—— 底稿缺一张，2.3 会照着不全的图做")
        }

        // 切回翻译档，展开语气下拉（**标准答案那个**）
        let tn = app.buttons["翻译"].firstMatch
        if tn.exists { tn.tap(); Thread.sleep(forTimeInterval: 1.0) }
        // 参数行那三个钮：语气 / 语言。语气是 2.1 定的参照物。
        let tone = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "语气")).firstMatch
        if tone.waitForExistence(timeout: 6) {
            tone.tap()
            Thread.sleep(forTimeInterval: 1.2)
            shot("S3_语气下拉_标准答案")
        } else {
            XCTFail("🚨 找不到语气下拉 —— 那是 2.1 指定的参照物，没有它没法逐条量")
        }
    }
}
