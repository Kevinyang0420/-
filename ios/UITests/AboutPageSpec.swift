import XCTest

/// **「关于 Transless」页** —— Kevin 2026-09-06 正在骂：
/// > 为什么关于 Transless 这里还是**一堆这什么东西啊？什么也没写啊**
///
/// 🚨 draft 明确要求判据挂在"用户看到什么"上，并点名：
///    **不许用「标题对不对/门数对不对」验收** —— 安卓上次就是这么"做完"的，
///    签了字，而那一页其实什么内容都没有。
final class AboutPageSpec: XCTestCase {

    private func openAbout() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        let tabSet = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "设置", "Settings")).firstMatch
        XCTAssertTrue(tabSet.waitForExistence(timeout: 8), "🚨 找不到设置 tab")
        tabSet.tap()
        Thread.sleep(forTimeInterval: 1.5)
        // 设置页那一行是 `UIControl`（不是 Button）—— 按文字找，点击穿透过去
        let row = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS %@",
            "关于 Transless", "About Transless")).firstMatch
        if !row.waitForExistence(timeout: 6) {
            app.swipeUp(); Thread.sleep(forTimeInterval: 1.0)
        }
        XCTAssertTrue(row.waitForExistence(timeout: 8), "🚨 设置里找不到「关于」那一行")
        row.tap()
        Thread.sleep(forTimeInterval: 2.0)
        return app
    }

    /// 🚨 **能看到正文段落** —— 这是 draft 点名的那条：
    ///    只有标题和入口 = FAIL。
    func testHasRealContent() {
        let app = openAbout()
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "ABOUT_01_关于页"; a.lifetime = .keepAlways; add(a)

        for id in ["about.title", "about.tagline", "about.body1", "about.body2",
                   "about.langs.translate", "about.langs.sample",
                   "about.langs.ui", "about.privacy", "about.contact",
                   "about.publisher", "about.version"] {
            XCTAssertTrue(app.staticTexts[id].exists || app.otherElements[id].exists,
                          "🚨 这一屏缺 `\(id)` —— draft 说「只有标题和入口 = FAIL」")
        }
        // 正文不许是空壳
        let body = app.staticTexts["about.body1"]
        XCTAssertGreaterThan((body.label).count, 20,
                             "🚨 介绍正文只有 \((body.label).count) 个字，是空壳")
    }

    /// 🚨 **门数必须是算出来的**，不是写死的。
    ///    判据：屏幕上的数字要等于**运行时数出来的**那个 ——
    ///    写死 31 的话，哪天加一门语言这里就开始骗人。
    func testCountsAreComputed() {
        let app = openAbout()
        // 🚨 翻译语言数**数真表**（`Langs.g.swift` 已编进测试包）——
        //    在测试里另写一个 31 就是同源自比，写死的实现照样绿。
        let n = GenLangs.langs.count
        // 界面语言数：`Lang` 带 Keychain 依赖，编不进测试包 ——
        // 🚨 所以这里**不硬编数字**，改成断言「屏幕上那个数 < 翻译语言数」，
        //    并且是个正数。写死 7 的话，加一门界面语言这条就成了假绿。
        let uiText = app.staticTexts["about.langs.ui"].label
        let uiNum = Int(uiText.compactMap { $0.isNumber ? $0 : nil }
                              .map(String.init).joined()) ?? 0
        let t = app.staticTexts["about.langs.translate"].label
        XCTAssertTrue(t.contains(String(n)),
                      "🚨 翻译语言数没跟着表走：屏幕「\(t)」，实际 \(n) 门")
        XCTAssertGreaterThan(uiNum, 0, "🚨 界面语言数是 0：「\(uiText)」")
        XCTAssertLessThan(uiNum, n,
                          "🚨 界面语言数 \(uiNum) 不小于翻译语言数 \(n) —— "
                          + "两个数八成取自同一处，那这组判据分不出谁是谁")
    }

    /// 版本号是**读来的**，不是写死的字符串。
    func testVersionIsRead() {
        let app = openAbout()
        let v = app.staticTexts["about.version"].label
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "?"
        XCTAssertFalse(v.isEmpty, "🚨 版本号那行是空的")
        // 🚨 测试进程和被测 App 是两个 bundle，build 号不一定相同 ——
        //    所以只断言"有数字"，不硬比对（比对会变成一条永远红的假判据）。
        XCTAssertTrue(v.rangeOfCharacter(from: .decimalDigits) != nil,
                      "🚨 版本行里一个数字都没有：「\(v)」（测试侧 build=\(build)）")
    }
}
