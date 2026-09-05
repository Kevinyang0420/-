import XCTest

/// **量底排四个键的真实渲染尺寸**（Kevin 2026-09-05 13:23：
/// 「发送按钮太大，删除按钮太小，经常点错」）。
///
/// 🚨🚨 **量渲染出来的 frame，不是代码里的常量。**
///    这个项目栽过「写了 `.defaultToSpeaker` 但 `.measurement` 模式忽略它」那一次 ——
///    **写了 ≠ 生效**。约束写着"三个等宽"，实际是不是等宽要量了才知道
///    （hugging / compression 优先级、内容宽度都可能把它掰弯）。
final class KbBottomRowAudit: XCTestCase {

    func testMeasureBottomRow() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "kb"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.5)

        let win = app.windows.firstMatch.frame
        NSLog("KBROW 屏宽=%.0f", win.width)

        // 🚨 按**文案**找，因为这四个键没有 accessibilityIdentifier。
        //    找不到就大声说找不到 —— 不许 `if exists` 静默跳过
        //    （那样一个都没量到也会绿）。
        // 🚨 **量到的值写进断言消息，不靠 NSLog** ——
        //    这个测试进程的 NSLog 正文吐不出来（日志里只有 "KBROW" 前缀，
        //    后面全被吞掉），我为此白读了两轮日志。
        //    **断言消息是 xcodebuild 一定会原样打出来的**，比日志可靠。
        // 🚨 按**标识**找，不按文案 —— 「删除」是纯图标键，按文案永远找不到
        //    （量现状那次就栽在这儿，46 是从相邻坐标反推的）。
        var w: [String: CGFloat] = [:]
        var x: [String: CGFloat] = [:]
        var report = ""
        for (key, name) in [("kb.bottom.type", "打字"), ("kb.bottom.speak", "朗读"),
                            ("kb.bottom.delete", "删除"), ("kb.bottom.send", "发送")] {
            let b = app.descendants(matching: .any).matching(identifier: key).firstMatch
            if b.waitForExistence(timeout: 4) {
                w[name] = b.frame.width
                x[name] = b.frame.minX
                report += String(format: "%@=%.0f ", name, b.frame.width)
            } else {
                report += name + "=找不到 "
            }
        }
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "键盘底排现状"; a.lifetime = .keepAlways; add(a)

        // 🚨 **故意让它红一次**，好把量到的值打出来 —— 量尺用例的产出是**数据**，
        //    绿不绿不重要。等拿到数、方案定了，这条再改成真正的回归判据。
        // ── 判据（方案乙）──────────────────────────────
        // 🚨 每条都能失败：数字写死在这里，改回现状任何一条都会红。
        XCTAssertEqual(w.count, 4, "🚨 只量到 \(report) —— 量不全就不算验过")
        XCTAssertEqual(w["删除"] ?? 0, 88, accuracy: 1,
            "🚨 删除应为 88（现状 46）—— 他要求「删除调大」，\(report)")
        XCTAssertEqual(w["发送"] ?? 0, 88, accuracy: 1,
            "🚨 发送应为 88（现状 117）—— 他要求「发送调小」，\(report)")
        XCTAssertEqual(w["朗读"] ?? 0, 88, accuracy: 1,
            "🚨 朗读应为 88（现状 117）—— 他要求「朗读调小」，\(report)")

        // 🚨🚨 **乙的那一条：删除↔发送要拉开** —— 这是直接治「经常点错」的。
        //    判据用**两键之间的空隙**，不是"我设了 setCustomSpacing"：
        //    设了不等于生效（`bottom.spacing` 是整行统一的，会盖掉它）。
        let gap = (x["发送"] ?? 0) - ((x["删除"] ?? 0) + (w["删除"] ?? 0))
        XCTAssertEqual(gap, 20, accuracy: 2,
            "🚨 删除↔发送的空隙是 \(Int(gap))，应为 20 —— 是不是被 bottom.spacing 盖掉了？")
    }
}
