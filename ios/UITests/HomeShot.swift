import XCTest

/// **只做一件事：在真机上把主 App 的首页截下来。**
///
/// 🚨 为什么单独写一个：2.1 要拿**真机图**给 Kevin 过目底部 Tab 的图标，
///    他自己渲的那版失真（房子像上箭头、齿轮像朵花）——
///    「他否掉的会是我的画工，不是那个风格」。所以只认真机截图。
///
/// 🚨 我一度跟 Kevin 说「真机截图我做不了」，那是错的：
///    我只查了 `devicectl` 有没有 screenshot 子命令（没有），
///    **没去清点手上已经有的工具** —— `XCUIScreen.main.screenshot()`
///    在 `TypelessInProbe` 里用了好几年了。
///    真正挡路的只是设备上的 `Enable UI Automation` 开关，他一开就通。
final class HomeShot: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testShotHome() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        // 🚨 模拟器音频会 abort，报出来像「App 没起来」（见 TestApp.swift）
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        // 🚨 等一拍再截：`runningForeground` 只说进程到前台了，
        //    这一刻 Tab 栏和凸起圆钮可能还没布局完 —— 截到半成品比没截更误导。
        Thread.sleep(forTimeInterval: 3.0)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "HOME"
        a.lifetime = .keepAlways
        add(a)
        NSLog("HOMESHOT 截好了")
    }
}
