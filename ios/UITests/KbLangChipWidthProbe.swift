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

        let screenW = app.windows.firstMatch.frame.width
        // 🚨🚨 **不许量到屏幕边缘就当"余量"**。
        //    我第一版就是这么算的：`屏宽 - chip.maxX = 239pt`，
        //    **而那一片上坐着「历史」钮**（x=338..430）——
        //    239 里有一大半根本不是空的。
        //    量的对象比结论说的对象大一圈，这是我今晚反复栽的那一类。
        //    → 改成**把那一行的控件全列出来**，余量只算到最近的邻居。
        let rowY = chip.frame.midY
        var neighbours: [(String, CGRect)] = []
        let all = app.buttons.allElementsBoundByIndex
        for b in all where b.exists {
            let f = b.frame
            guard f.width > 1, f.height > 1 else { continue }
            // 同一行 = 垂直中心相差不到半个 chip 高
            guard abs(f.midY - rowY) < chip.frame.height / 2 else { continue }
            let id = b.identifier.isEmpty ? b.label : b.identifier
            neighbours.append((id.isEmpty ? "(无名)" : id, f))
        }
        neighbours.sort { $0.1.minX < $1.1.minX }

        var lines: [String] = []
        lines.append(String(format: "屏宽 %.0f pt ｜ chip 当前 %.0f pt (x=%.0f..%.0f)",
                            screenW, chip.frame.width,
                            chip.frame.minX, chip.frame.maxX))
        lines.append("同一行上的控件（按 x 排）：")
        for (id, f) in neighbours {
            lines.append(String(format: "   %-18@ x=%.0f..%.0f  宽 %.0f",
                                id as NSString, f.minX, f.maxX, f.width))
        }
        // 右邻居的左边缘 —— 没有右邻居才用屏幕边缘
        let rightEdge = neighbours.first { $0.1.minX >= chip.frame.maxX - 1 }?
            .1.minX ?? screenW
        let leftEdge = neighbours.last { $0.1.maxX <= chip.frame.minX + 1 }?
            .1.maxX ?? 0
        lines.append(String(format: "左邻居右缘 %.0f ｜ 右邻居左缘 %.0f",
                            leftEdge, rightEdge))
        lines.append(String(format: "🚨 chip 真实可扩上界 %.0f pt（挤到两侧邻居为止）",
                            rightEdge - leftEdge))
        lines.append("—— 对照文字需求：常见 105 / 现状最宽 127 / 异常最宽 260")
        lines.append("🚨 这仍是**上界**：挤满等于两边贴死，没有间距。"
                     + "放不放得下、异常组合怎么退化，归版面判，我只出数。")

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
