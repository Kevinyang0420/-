import XCTest

/// **第三阶段（处理中）圆钮里到底数不数秒。**
///
/// 🚨 Kevin 2026-09-05：「它没有倒数。不是有三个阶段嘛，在第三个阶段
///    它没有那个数数，就还是很不统一。」
///    随手那一屏当时只有一个**静态**的「…」——
///    而"数字在涨"正是他判断"是不是卡死了"的信号。
///
/// 🚨 判据是**秒数会变**，不是"有个标题"：
///    「…」永远在也算有标题，那是恒真的假检查。
///    所以先读一次、等 2.5 秒再读一次，**两次必须不同且后一次是 Ns**。
final class BusyCountdown: XCTestCase {
    func testThirdPhaseCountsSeconds() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "speak"
        app.launchEnvironment["TRANSLESS_FAKE_PHASE"] = "thinking"
        // 🚨 这个用例跟麦克风无关：不让冷启动去架引擎。
        //    模拟器上 AVAudioEngine.inputNode 会撞 AudioToolbox RPC 超时
        //    直接 abort，把不相干的用例一起带崩，还报成「App 没起来」。
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        let mic = app.buttons["app.mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 10), "🚨 麦克风钮不在")
        let first = mic.label
        Thread.sleep(forTimeInterval: 2.6)
        let second = mic.label
        NSLog("BUSY 第一次=%@ 第二次=%@", first, second)

        XCTAssertNotEqual(first, second,
            "🚨 圆钮文字两次一样（都是 \(first)）—— 秒数没在走，跟卡死没区别")
        XCTAssertTrue(second.hasSuffix("s"),
            "🚨 第三阶段圆钮显示 \(second)，不是「N s」")
        let a2 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a2.name = "处理中_秒数"; a2.lifetime = .keepAlways; add(a2)
    }
}
