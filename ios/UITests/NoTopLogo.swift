import XCTest

/// **随手翻译那屏不许有 logo**（Kevin 2026-09-05 23:0x）。
///
/// > 「我没有说键盘顶部那个删，就是**现在这个随手翻译这个 logo 删**就可以了」
///
/// 🚨🚨 **只查这一屏。键盘顶排那个是保留的。**
///    我上一版两处都删了 —— **删多了**。
///    起因是 0 转的描述说「在键盘顶排」，而我**没去分辨他实拍的到底是哪一屏**，
///    看到两处都有就都删了。
///    → **"两个地方都有同一个东西"不等于"两个都要删"。范围要问清，别自己扩大。**
///
/// 🚨 判据挂在**渲染出来的界面**上（数图片视图），不是"代码里删了" ——
///    他这次的处境正是「代码可能改了、他手机上还在」。
final class NoTopLogo: XCTestCase {

    func testSpeakScreenHasNoLogo() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "speak"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        // 🚨 用**图片视图数量**，不找 identifier —— 那个 logo 从来没有
        //    identifier，按名字找会永远查不到、永远绿。
        let imgs = app.images
        let n = imgs.count
        XCTAssertEqual(n, 0, "🚨 随手翻译屏还有 \(n) 个图片视图 —— logo 删干净了吗？")

        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "随手翻译_无logo"; a.lifetime = .keepAlways; add(a)
    }

    /// 🚨 **反向控制：键盘顶排那个必须还在。**
    ///    只查"随手翻译没了"的话，我把键盘那个也删掉照样全绿 ——
    ///    而那正是我上一版犯的错。**删多了跟删漏了一样是错。**
    func testKeyboardLogoStillThere() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "kb"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.5)

        XCTAssertGreaterThanOrEqual(app.images.count, 1,
            "🚨 键盘顶排的 logo 不见了 —— 他只要求删随手翻译那个，这个要留着")
    }
}
