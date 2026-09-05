import XCTest

/// **把 `HomeStatsCore` / `KpiWords` 的纯逻辑自测真的跑起来。**
///
/// 🚨🚨 立这个文件是因为：那两份 selfTest 写得很细（好样本 + 一串坏样本），
///    可全项目 grep 下来**零调用点** —— 从建起来那天就没跑过一次。
///    「检查写对了」跟「检查在跑」是两件事，后者没有的话前者等于零。
///
/// 判据：隐形标签上的字必须是 `OK`。任何一条自测不过，那里会是失败原因原文。
final class KpiSelfTest: XCTestCase {
    func testPureLogicSelfTestsPass() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_SELFTEST"] = "1"
        // 🚨 纯逻辑自测跟麦克风无关，别让模拟器的音频服务把它带崩
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        let r = app.staticTexts["app.selftest"]
        XCTAssertTrue(r.waitForExistence(timeout: 10),
                      "🚨 自测标签不在 —— 说明这一轮根本没跑自测，别读成绿")
        NSLog("SELFTEST %@", r.label)
        XCTAssertEqual(r.label, "OK", "🚨 纯逻辑自测没过：\(r.label)")
    }
}
