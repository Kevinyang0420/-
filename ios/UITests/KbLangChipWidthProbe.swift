import XCTest

/// **键盘那颗语言 chip 实际能占多少宽** —— 2.1 要这个数去送 Grok。
///
/// 上一条（`KbLangLabelWidthTests`）量的是**文字要多宽**：
/// ```
/// 现状最宽 127pt  Português (Brasil) ▾
/// 常见     105pt  中文 → English ▾
/// 异常最宽 260pt  Português (Brasil) → Bahasa Indonesia ▾
/// ```
/// 这一条量的是**版面给多宽**。两个数放一起才判得了
/// 「260pt 那类要不要退化、退化到什么程度」。
///
/// 🚨 **我只出数，不下"放得下"的结论** —— 那是版面取舍，归 2.1 和 Grok。
final class KbLangChipWidthProbe: XCTestCase {

    func testMeasureLangChipAvailableWidth() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_PAGE"] = "kb"      // 键盘预览页
        app.launchEnvironment["TRANSLESS_UILANG"] = "zh"
        app.launchEnvironment["TRANSLESS_UILANG_RESET"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        let chip = app.buttons["kb.lang"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10),
                      "🚨 找不到键盘的语言 chip（标识 kb.lang）")

        // 同一行上的邻居，用来算"这一行还剩多少给它"
        let hist = app.buttons["kb.hist"]
        let screenW = app.windows.firstMatch.frame.width

        var lines: [String] = []
        lines.append(String(format: "屏宽            %.0f pt", screenW))
        lines.append(String(format: "chip 当前宽     %.0f pt   (x=%.0f..%.0f)",
                            chip.frame.width, chip.frame.minX, chip.frame.maxX))
        if hist.exists {
            lines.append(String(format: "同行「历史」钮  %.0f pt   (x=%.0f..%.0f)",
                                hist.frame.width, hist.frame.minX, hist.frame.maxX))
        }
        // 🚨 「还能长多少」＝ 这一行右边到屏幕边缘还剩多少。
        //    这是**上界**，不是承诺 —— 真扩上去还要看这一行别的控件让不让。
        let roomRight = screenW - chip.frame.maxX
        lines.append(String(format: "右侧余量        %.0f pt（上界，不是承诺）", roomRight))
        lines.append(String(format: "chip 可达上界   %.0f pt = 当前宽 + 右侧余量",
                            chip.frame.width + roomRight))
        lines.append("—— 对照文字需求：常见 105 / 现状最宽 127 / 异常最宽 260")
        lines.append("🚨 我只出数。放不放得下、异常组合怎么退化，归版面判。")

        let a = XCTAttachment(string: lines.joined(separator: "\n"))
        a.name = "键盘语言chip可用宽度"
        a.lifetime = .keepAlways
        add(a)
        for l in lines { print("KBCHIP " + l) }

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "KBCHIP_键盘那一行"; shot.lifetime = .keepAlways; add(shot)

        XCTAssertGreaterThan(chip.frame.width, 0,
                             "🚨 chip 宽度读成 0 —— 多半没进到键盘预览页")
    }
}
