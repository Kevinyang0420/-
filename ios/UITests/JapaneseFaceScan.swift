import XCTest

/// **切日语之后，面对面那一屏还有没有中文残留**（2.1 派）。
///
/// 🚨 判据不是"看图觉得没问题"，是**把整屏的可见文字抓下来，逐个查有没有汉字**。
///    日文本身有汉字，所以不能简单查"有没有 CJK" ——
///    要查的是**只在中文里出现、日文界面不该出现的那些字**。
///
/// 🚨 反向对照必须在场：同一屏在中文界面下**必须**命中这些词。
///    只测"日语下没有"的话，一个把整屏文字都读不到的实现也会绿。
final class JapaneseFaceScan: XCTestCase {

    /// 只在简体中文界面出现、日文界面不该有的词。
    /// 🚨 挑的是**面对面那屏真实用到的**文案，不是随便找几个汉字。
    private let zhOnly = ["面对面", "开始", "设置", "常用词", "历史", "首页",
                          "语气", "翻译", "转写", "查词"]

    private func visibleTexts(_ app: XCUIApplication) -> [String] {
        var out: [String] = []
        for kind in [XCUIElement.ElementType.staticText,
                     .button, .navigationBar, .tabBar] {
            let all = app.descendants(matching: kind)
            for i in 0..<min(all.count, 60) {
                let e = all.element(boundBy: i)
                guard e.exists else { continue }
                let s = e.label.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { out.append(s) }
            }
        }
        return out
    }

    private func openFaceToFace(_ app: XCUIApplication) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        // 面对面是底部中间那个凸起的 tab —— 🚨 它**不在** `tabBars.buttons` 里
        //    （之前按位置点过，静默点空）。按标识找。
        let f2f = app.buttons["app.tab.face"].exists
            ? app.buttons["app.tab.face"]
            : app.buttons.matching(NSPredicate(
                format: "label == %@ OR label == %@", "面对面", "対面")).firstMatch
        XCTAssertTrue(f2f.waitForExistence(timeout: 8), "🚨 找不到面对面入口")
        f2f.tap()
        Thread.sleep(forTimeInterval: 2.0)
    }

    func testFaceToFaceHasNoChineseLeftovers() throws {
        // ① 反向对照：中文界面下这些词**必须**出现，否则说明我根本没读到文字
        let zh = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        zh.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        zh.launchEnvironment["TRANSLESS_UI_LANG"] = "zh"
        zh.launch()
        openFaceToFace(zh)
        let zhTexts = visibleTexts(zh)
        var a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "JASCAN_01_中文基准"; a.lifetime = .keepAlways; add(a)
        let hitZh = zhOnly.filter { w in zhTexts.contains { $0.contains(w) } }
        XCTAssertGreaterThanOrEqual(hitZh.count, 3,
            "🚨 中文界面下只命中 \(hitZh.count) 个中文词 —— 我八成根本没读到这屏的文字，"
            + "那么下面「日语下没有中文」就是假绿｜读到 \(zhTexts.count) 条")
        zh.terminate()
        Thread.sleep(forTimeInterval: 1.5)

        // ② 日语界面：这些词一个都不该有
        let ja = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        ja.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        ja.launchEnvironment["TRANSLESS_UI_LANG"] = "ja"
        ja.launch()
        openFaceToFace(ja)
        let jaTexts = visibleTexts(ja)
        a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "JASCAN_02_日语"; a.lifetime = .keepAlways; add(a)

        var leftover: [String] = []
        for w in zhOnly {
            if let hit = jaTexts.first(where: { $0.contains(w) }) {
                leftover.append("\(w)（出现在「\(hit.prefix(24))」）")
            }
        }
        XCTAssertTrue(leftover.isEmpty,
            "🚨 切到日语后面对面屏还有中文没跟着变：\n  "
            + leftover.joined(separator: "\n  ")
            + "\n（这屏一共读到 \(jaTexts.count) 条文字）")
    }
}
