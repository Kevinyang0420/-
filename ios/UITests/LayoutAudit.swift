import XCTest

/// **把随手翻译这一屏的真实几何量出来** —— 送 Grok 之前先有事实。
///
/// Kevin 2026-09-05：「你看，你的高度都没对齐，翻译和转写输入框的高度都不对。
/// 而且转写是『整理』和『逐字』在上面，翻译的『语气』和『英文』在下面，
/// 搞得乱七八糟的，一点都不统一。」
///
/// 🚨 **量，不描述**：我对着截图说"看着像"没有用，Grok 拿到的必须是数。
final class LayoutAudit: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func dump(_ app: XCUIApplication, _ tag: String) {
        let win = app.windows.firstMatch.frame
        func f(_ e: XCUIElement, _ name: String) {
            guard e.exists else { NSLog("AUDIT %@ %@ = 不在", tag, name); return }
            let r = e.frame
            NSLog("AUDIT %@ %@ y=%.0f..%.0f h=%.0f x=%.0f..%.0f w=%.0f",
                  tag, name, r.minY, r.maxY, r.height, r.minX, r.maxX, r.width)
        }
        NSLog("AUDIT %@ screen h=%.0f", tag, win.height)
        f(app.buttons["翻译"].firstMatch, "翻译")
        f(app.buttons["转写"].firstMatch, "转写")
        f(app.buttons["整理"].firstMatch, "整理")
        f(app.buttons["逐字"].firstMatch, "逐字")
        f(app.buttons["app.mic"], "麦克风")
        f(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "语气")).firstMatch, "语气")
        f(app.otherElements["app.paramRow"], "参数行")
        f(app.textViews.firstMatch, "结果框")
    }

    /// **方案 F 保真度闸门** —— 量的是"跟他批准的那张预览图一不一样"。
    ///
    /// 🚨🚨 立这个闸的原因：上一版我只搬了参数行、**没搬麦克风**，
    ///    然后拿"两档零位移"当验收报给他。两档确实一致 ——
    ///    **但整体不是方案 F**。判据挂在了「一致性」上，
    ///    而他要的是「保真度」，**整个维度没被任何检查覆盖过**。
    ///
    /// 坏样本是现成的：**上一版真机构建 20260905.1084**
    ///    （麦克风 y=174..250、结果框 y=367..906）——
    ///    第 1 条和第 2 条都会红。不用我编一个假的。
    private func checkPlanF(_ app: XCUIApplication, _ tag: String) {
        let screenH = app.windows.firstMatch.frame.height
        let mic = app.buttons["app.mic"]
        let card = app.textViews.firstMatch
        let seg = app.buttons["转写"].firstMatch
        // 🚨 量**参数行本身**，不靠"哪个按钮在场"猜它在哪。
        let row = app.otherElements["app.paramRow"]
        guard mic.exists, card.exists, seg.exists else {
            XCTFail("🚨 \(tag) 关键控件不在，量不了"); return
        }
        let m = mic.frame, c = card.frame, sg = seg.frame

        // ① 麦克风在结果框**下面**（图上就是这样；上一版正好反过来）
        XCTAssertGreaterThan(m.minY, c.maxY,
            "🚨 \(tag) 麦克风(\(Int(m.minY)))没在结果框(底 \(Int(c.maxY)))下面 —— 又搬回顶上了")

        // ② 麦克风**贴底**：离屏幕底不超过 120pt（图上 bottom:28 + 安全区）
        let toBottom = screenH - m.maxY
        XCTAssertLessThan(toBottom, 120,
            "🚨 \(tag) 麦克风离底 \(Int(toBottom))pt，太高了")

        // ③ 参数行紧贴分段条下方（结果框那张卡从这里起）
        XCTAssertTrue(row.exists, "🚨 \(tag) 参数行不在 —— 闸门量不到就不算量过")
        let head = row.frame
        XCTAssertLessThan(head.minY - sg.maxY, 70,
            "🚨 \(tag) 参数行离分段条 \(Int(head.minY - sg.maxY))pt，中间空着")

        // ④ 结果框要**铺满中间**，不是压在下半屏（他说的"太空"）
        XCTAssertGreaterThan(c.height, 300,
            "🚨 \(tag) 结果框只有 \(Int(c.height))pt 高")
        // ⑤ 参数行**文案**也要跟图一致（「译成 英文 ▾」不是「英文 ▾」）。
        //    🚨 这条是补的：几何全对、文案被另一处代码盖回旧版，
        //    光量坐标看不出来 —— 判据缺了一整个维度。
        if tag.contains("翻译") {
            let want = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", "译成")).firstMatch
            XCTAssertTrue(want.exists, "🚨 \(tag) 语言钮不是「译成 …」，被别处的旧文案盖了")
        }
        NSLog("PLANF %@ mic离底=%.0f 框高=%.0f 头部间隙=%.0f",
              tag, toBottom, c.height, head.minY - sg.maxY)
    }

    func testBothModes() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "speak"
        app.launchEnvironment["TRANSLESS_CLEAR_HIST"] = "1"
        // 🚨 这个用例跟麦克风无关：不让冷启动去架引擎。
        //    模拟器上 AVAudioEngine.inputNode 会撞 AudioToolbox RPC 超时
        //    直接 abort，把不相干的用例一起带崩，还报成「App 没起来」。
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.5)

        // 🚨 **显式切到转写档再量** —— 上一版我以为默认就是转写，
        //    结果两次量到的是同一档（档位是记在偏好里的，上次停在哪就是哪）。
        //    「我以为它现在是 X」是最容易混进读数的假设。
        app.buttons["转写"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        dump(app, "转写档")
        checkPlanF(app, "转写档")
        let a1 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a1.name = "A_转写档"; a1.lifetime = .keepAlways; add(a1)

        app.buttons["翻译"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        dump(app, "翻译档")
        checkPlanF(app, "翻译档")
        let a2 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a2.name = "B_翻译档"; a2.lifetime = .keepAlways; add(a2)
    }
}
