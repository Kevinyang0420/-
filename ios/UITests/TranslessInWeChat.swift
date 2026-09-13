import XCTest

/// **在真实微信里按我们自己的麦克风，全程录屏截图，看跳出去之后到底发生了什么。**
///
/// 🚨 09-13 Kevin 真机实测「还是不行」之后写的——不再让他一遍遍手动试，
///    这条自动做同一件事：进微信真实会话 → 切到 Transless 键盘 → 按麦克风 →
///    每一步截图 + 记前后台状态，尤其是**跳到 Transless 那一刻左上角有没有
///    系统画的「‹ 返回」按钮**（这是本机代码現在唯一还没验证过的关键问题）。
///
/// 复用 `TypelessInWeChat` 已经验证能用的微信导航逻辑（进会话/切键盘循环），
/// 只把目标从"切到第三方、非我们的键盘"换成"切到我们自己的键盘"。
final class TranslessInWeChat: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    func testTranslessMicInWeChat() throws {
        let wx = XCUIApplication(bundleIdentifier: "com.tencent.xin")
        let tl = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        // 🚨 09-13：先把 Transless 杀干净，确保这次按麦克风走的是**冷启动+真跳转**
        //    那条路，不是"引擎本来就架着"的短路径——否则测不到 Kevin 真正撞上的那个坑。
        tl.terminate()
        Thread.sleep(forTimeInterval: 1.0)
        NSLog("TLWX2 已终止 Transless，确保冷启动")
        wx.activate()
        XCTAssertTrue(wx.wait(for: .runningForeground, timeout: 20), "微信没起来")
        Thread.sleep(forTimeInterval: 3)

        wx.swipeDown(); Thread.sleep(forTimeInterval: 0.8)
        wx.swipeDown(); Thread.sleep(forTimeInterval: 1.2)
        var inChat = false
        for (n, y) in [0.22, 0.30, 0.38, 0.46].enumerated() {
            if n > 0 {
                let a = wx.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                let b = wx.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
                a.press(forDuration: 0.05, thenDragTo: b)
                Thread.sleep(forTimeInterval: 1.5)
            }
            wx.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: CGFloat(y))).tap()
            Thread.sleep(forTimeInterval: 1.6)
            if wx.textViews.count > 0 || wx.textFields.count > 0 { inChat = true; break }
        }
        NSLog("TLWX2 进会话了吗=%d", inChat ? 1 : 0)
        XCTAssertTrue(inChat, "没能进到一个会话——没法继续，别硬按下去凑结论")
        wx.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.945)).tap()
        Thread.sleep(forTimeInterval: 1.6)

        // 循环切键盘，直到看见我们自己的麦克风键（identifier 含 "transless.mic"）
        var found = false
        for n in 0..<12 {
            let g = wx.buttons["下一个键盘"]
            guard g.exists, g.isHittable else {
                NSLog("TLWX2 🚨 第%d轮找不到「下一个键盘」键，停", n); break
            }
            var labels: [String] = []
            for i in 0..<min(wx.buttons.count, 60) {
                let b = wx.buttons.element(boundBy: i)
                let s = b.label + "/" + b.identifier
                if s != "/" { labels.append(s) }
            }
            let ours = labels.contains { $0.contains("transless.mic") }
            NSLog("TLWX2 切第%d次：ours=%d 键数=%d｜%@", n + 1, ours ? 1 : 0,
                  labels.count, labels.prefix(10).joined(separator: " ｜ "))
            if ours { found = true; break }
            g.tap()
            Thread.sleep(forTimeInterval: 3.0)
        }
        NSLog("TLWX2 切到我们自己的键盘了吗=%d", found ? 1 : 0)
        guard found else {
            NSLog("TLWX2 🚨 没切到，本轮作废（不许按下去凑结论）"); return
        }

        let shot0 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot0.name = "TLWX2_00_before_tap"; shot0.lifetime = .keepAlways; add(shot0)

        let micBtn = wx.buttons.matching(NSPredicate(
            format: "identifier CONTAINS %@", "transless.mic")).firstMatch
        XCTAssertTrue(micBtn.exists, "找到了键盘但没找到麦克风按钮本体")
        NSLog("TLWX2 按之前：微信=%d Transless主App=%d", wx.state.rawValue, tl.state.rawValue)
        micBtn.tap()
        NSLog("TLWX2 ✅ 按了麦克风")

        // 逐秒记录 + 每秒截一张图，重点看「跳到 Transless 那一刻」画面长什么样
        for t in 1...15 {
            Thread.sleep(forTimeInterval: 1)
            let w = wx.state.rawValue, o = tl.state.rawValue
            NSLog("TLWX2 t=%2ds 微信=%d Transless=%d", t, w, o)
            if o == 4 {   // Transless 这一刻在前台——截图看画面上到底有什么
                let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                s.name = String(format: "TLWX2_%02d_transless_foreground", t)
                s.lifetime = .keepAlways; add(s)
            }
        }
        let shotEnd = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shotEnd.name = "TLWX2_99_end"; shotEnd.lifetime = .keepAlways; add(shotEnd)
    }
}
