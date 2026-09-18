import XCTest

/// 0 要的：iOS 面对面页面真机截图 + 三个高度数，给 Grok 跟安卓那张一起过。
/// 只截图、只量高度，不改任何东西。
final class F2FLayoutMeasureSpec: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testCaptureAndMeasure() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "f2f"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "面对面没起来")
        Thread.sleep(forTimeInterval: 1.5)

        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "f2f_真机截图"; a.lifetime = .keepAlways; add(a)

        let screenH = app.frame.height
        let elements = app.descendants(matching: .any).allElementsBoundByIndex
            .filter { $0.exists && $0.frame.height > 0 }
        var report = "SCREEN_H=\(screenH)\n"
        for el in elements.prefix(80) {
            let f = el.frame
            report += "\(el.elementType.rawValue)|\(el.identifier)|y=\(Int(f.minY))|h=\(Int(f.height))|label=\(el.label.prefix(24))\n"
        }
        let ra = XCTAttachment(string: report)
        ra.name = "f2f_元素坐标"; ra.lifetime = .keepAlways; add(ra)
    }
}
