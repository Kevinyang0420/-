import XCTest

/// **历史页截图** —— 两件事一次拍完。
///
/// ## ① 2.1 要的：中文界面、要看得到档位 chip
/// 他要拿真实截图做效果图给 Kevin 看，再决定改不改档名
/// （档位现在叫「整理中文」，而引擎写死 KEEP THE SPEAKER'S OWN LANGUAGE ——
/// 德国人说德语出德语，档名却写着"中文"）。**我不改档名，只给图。**
///
/// ## ② 我自己要的：`hist_monthday` 在德语下**月日有没有对调**
/// 2.1 09-07 提醒：四门旧值是非定位式 `%d.%d.`，没有换位能力，
/// **月日对调且不报错**。他已改成 `de %2$d.%1$d.`。
///
/// 🚨 **他要我自己核，别照抄安卓的写法**（iOS 的格式串语法跟安卓不同）。
///    读代码读到的是：
///    ```
///    History.swift:336  String(format: L.hist_monthday, md.month, md.day)   // 先月后日
///    Strings.swift:459  de = "%2$d.%1$d."                                    // 先打日再打月
///    ```
///    → 方向应该是对的。**但这是推的，不是量的** ——
///    `String(format:)` 到底认不认 `%1$d` 这种定位式，只有真跑一次才知道。
///    这一屏就是那次实跑。
final class HistoryShot: XCTestCase {

    func testHistoryShot() throws {
        let lang = ProcessInfo.processInfo.environment["TRANSLESS_UILANG"] ?? "zh"
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_PAGE"] = "hist"
        app.launchEnvironment["TRANSLESS_SEED_CARD"] = "1"
        app.launchEnvironment["TRANSLESS_UILANG"] = lang
        app.launchEnvironment["TRANSLESS_UILANG_RESET"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 4.0)

        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "HIST_" + lang
        a.lifetime = .keepAlways
        add(a)

        // 🚨 判据只挂在**能读出来**的东西上。日期那条我不在这里断言 ——
        //    今天几月几日会变，写死一个期望值就是把测试绑在日历上。
        //    德语那张图我自己看：`日.月.` 才对，`月.日.` 就是对调了。
        let texts = app.staticTexts.allElementsBoundByIndex
            .prefix(80).filter { $0.exists }.map { $0.label }
        XCTAssertFalse(texts.isEmpty, "🚨 历史页一个字都没有 —— 多半没进到这一屏")
    }
}
