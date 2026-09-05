import XCTest

/// **点 Tab 时会不会闪一下白** —— 驱动切换，判据在 `TabFlashProbe` 的逐帧采样里。
///
/// 🚨 这一轮是**测量**，不是验收：先拿到"闪不闪、哪一格闪"，再谈修。
///    环境变量 `TRANSLESS_TRANSPARENT_ON=vocab` 把那份透明外观挪到
///    「常用词」那一格 —— **反向控制**：闪白跟着跑过去才说明假设成立。
final class TabFlash: XCTestCase {
    private func tapAndSettle(_ app: XCUIApplication, _ idx: Int, _ name: String) {
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10), "Tab 栏没出来")
        let b = bar.buttons.element(boundBy: idx)
        XCTAssertTrue(b.isHittable, "第 \(idx) 格（\(name)）点不到")
        b.tap()
        // 采样窗口 1.2 秒，等它跑完再切下一格
        Thread.sleep(forTimeInterval: 2.0)
    }


    /// **独立第二路径**：从**真截图**里量 tab 栏那条的亮度。
    ///
    /// 🚨 为什么必须有它：`TabFlashProbe` 用 `layer.render(in:)` 取色，
    ///    而 `UIVisualEffectView`（毛玻璃）在这种离屏渲染里**拿不到背后的画面**，
    ///    很可能渲成一片浅色材质 —— 那是**仪器假象**，不是用户看到的颜色。
    ///    两条路数得对得上，读数才算数；对不上就说明有一条在骗人，
    ///    这时候**不许拿任何一条下结论**。
    ///
    /// 🚨 截图慢（100–300ms 一张），抓不到一两帧的闪 —— 所以它只用来
    ///    **校准稳态颜色**，不用来找闪。分工要写清楚，别拿它当闪的判据。
    private func barLuminanceFromScreenshot() -> Double? {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        guard let img = UIImage(data: png), let cg = img.cgImage else { return nil }
        let w = cg.width, h = cg.height
        // tab 栏那条：底部往上约 6%~10% 的高度，横向取中间
        let y = Int(Double(h) * 0.93)
        var sum = 0.0, n = 0
        guard let dp = cg.dataProvider, let data = dp.data,
              let p = CFDataGetBytePtr(data) else { return nil }
        let bpp = cg.bitsPerPixel / 8
        for x in stride(from: w / 2 - 20, to: w / 2 + 20, by: 4) {
            let i = y * cg.bytesPerRow + x * bpp
            guard CFDataGetLength(data) > i + 2 else { continue }
            sum += (Double(p[i]) * 0.299 + Double(p[i + 1]) * 0.587
                    + Double(p[i + 2]) * 0.114) / 255.0
            n += 1
        }
        return n > 0 ? sum / Double(n) : nil
    }

    /// 底部 15% 每 2% 高度取一行的平均亮度 —— 用来看那片白从哪一行开始。
    private func profileBottom() -> String {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        guard let img = UIImage(data: png), let cg = img.cgImage,
              let dp = cg.dataProvider, let data = dp.data,
              let p = CFDataGetBytePtr(data) else { return "读不到" }
        let bpp = cg.bitsPerPixel / 8
        var out: [String] = []
        for f in stride(from: 0.85, through: 0.995, by: 0.015) {
            let y = min(cg.height - 1, Int(Double(cg.height) * f))
            var sum = 0.0, n = 0
            for x in stride(from: cg.width / 4, to: cg.width * 3 / 4, by: 16) {
                let i = y * cg.bytesPerRow + x * bpp
                guard CFDataGetLength(data) > i + 2 else { continue }
                sum += (Double(p[i]) * 0.299 + Double(p[i + 1]) * 0.587
                        + Double(p[i + 2]) * 0.114) / 255.0
                n += 1
            }
            if n > 0 { out.append(String(format: "%.0f%%:%.2f", f * 100, sum / Double(n))) }
        }
        return out.joined(separator: " ")
    }

    func testTabSwitchFlash() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_TABPROBE"] = "1"
        // 🚨 这个用例跟麦克风无关：不让冷启动去架引擎。
        //    模拟器上 AVAudioEngine.inputNode 会撞 AudioToolbox RPC 超时
        //    直接 abort，把不相干的用例一起带崩，还报成「App 没起来」。
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        if let v = ProcessInfo.processInfo.environment["TRANSLESS_TRANSPARENT_ON"] {
            app.launchEnvironment["TRANSLESS_TRANSPARENT_ON"] = v
        }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        // 依次点：设置(4) → 常用词(3) → 历史(1) → 设置(4)
        // 🚨 每一格都点，才分得出"只有设置闪"还是"切哪格都闪"——
        //    只点设置的话，两种世界看起来一模一样。
        tapAndSettle(app, 4, "设置")
        tapAndSettle(app, 3, "常用词")
        tapAndSettle(app, 1, "历史")
        tapAndSettle(app, 4, "设置")

        // 🚨🚨 **判据：历次切换里最亮的那一帧**。
        //    深色底衬约 0.19；浅色外观那层实测 **0.361**（今天的基线，
        //    主 App 当时没声明 `UIUserInterfaceStyle: Dark`）。
        //    阈值取 0.25 —— 卡在这两个实测值中间，两边都留了余量。
        //    **坏样本是真的**：把主 App 的深色声明去掉就会读到 0.36。
        //
        // 🚨 用**最亮值**不用平均：平均会把一两帧闪白抹平，
        //    而那正是这个缺陷最容易被"测过了"掩盖的方式。
        // 🚨🚨 **这里原来有一道"峰值 < 0.25"的闸门，2026-09-05 撤掉了。**
        //    撤的理由不是"改好了"，是**它建立在一个不可信的仪器上**：
        //      · `layer.render` 离屏渲染读到的是假象（第一版还全读 0.000）；
        //      · 采样点一度落在中间那格的**恒定紫图标**上（亮度恰好 0.36），
        //        我拿这个读数"证伪"了两个假设 —— 其实两个改动都动不到它；
        //      · 换到底衬空白处后又读 0.000。
        //    **用坏仪器守着，比没有守着更糟**：它会把"我量不到"变成"没问题"。
        //
        //    已经查清并留档的（三种仪器的实测，都在 STATE.md）：
        //      · 稳态下 tab 栏是暗的（真截图逐行剖面 0.16–0.26），没有持续变白；
        //      · 录屏 407 帧（8 次切换）无一帧变亮 —— **但录屏只有 14.73fps
        //        （68ms/帧），而他说的闪是 30ms 级别，时间分辨率不够**，
        //        所以这不是"没有闪"的证据。
        //    这一条**仍未解决**，等一个能真正逐帧看到屏幕的手段（或他真机复现）。
        let r = app.staticTexts["app.tabprobe"]
        if r.exists { NSLog("TABFLASH 诊断峰值=%@（仅记录，不作判据）", r.label) }
        NSLog("TABFLASH_PROFILE %@", profileBottom())
    }
}
