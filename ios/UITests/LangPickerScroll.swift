import XCTest

/// **语言选择器：40 门也要能滚到最后一门。**（2.1 2026-09-05 判据①④）
///
/// 🚨 Kevin 要把目标语言从 9 门扩到 23+ 门：
///    「你选择器不要一下子展示那么多嘛，加个下拉，就可以支持我滑动去选了嘛，
///     所以 32 项又怎么样嘛」。
///
/// 🚨 **坏样本用 `TRANSLESS_FAKE_LANGS=40` 注入**，不等语言表真的扩了再测 ——
///    等真数据来了再测，等于让缺陷先上线一轮。
///    注入的是**输入数据**（语言清单），被测的选择器本身没被碰过。
final class LangPickerScroll: XCTestCase {
    func testFortyLanguagesReachable() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "speak"
        app.launchEnvironment["TRANSLESS_FAKE_LANGS"] = "40"
        // 🚨 这个用例跟麦克风无关：不让冷启动去架引擎。
        //    模拟器上 AVAudioEngine.inputNode 会撞 AudioToolbox RPC 超时
        //    直接 abort，把不相干的用例一起带崩，还报成「App 没起来」。
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        // 语言钮：参数行里那颗「译成 …」
        let langBtn = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "译成")).firstMatch
        XCTAssertTrue(langBtn.waitForExistence(timeout: 10), "🚨 语言钮不在")
        langBtn.tap()
        Thread.sleep(forTimeInterval: 1.5)

        // 判据③：当前项要有明确标记。
        // 🚨 **必须在滚动之前查** —— 滚到第 40 门之后「英文」已经出屏，
        //    `exists` 为假。上一轮就是这么红的：**测试写错了，不是 App 错了**。
        XCTAssertTrue(app.descendants(matching: .any)["英文"].exists,
                      "🚨 当前语言项不在列表里")

        // 🚨 判据是**最后一门**，不是"菜单弹出来了" ——
        //    弹出来但只显示前 10 门，正是他抱怨的那个形态。
        let last = app.descendants(matching: .any)["测试语言39"]
        var tries = 0
        while !last.exists || !last.isHittable {
            if tries >= 12 { break }
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.4)
            tries += 1
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "语言下拉_40门"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(last.exists && last.isHittable,
                      "🚨 滚了 \(tries) 次仍够不到第 40 门 —— 长列表装不下")
    }
}
