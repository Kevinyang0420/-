import XCTest

/// 续 WeTypeAutoReturn：Kevin 09-13 纠正——真正会触发"跳主App再跳回来"的是
/// 微信输入法键盘**右上角那个麦克风图标**，不是"按住 说话"那条（那个是纯本地
/// 语音转文字，从不离开）。这次专门找右上角的麦克风按钮，点它，然后**完全不再
/// 碰任何东西**，看微信状态会不会自己经历"离开又回来"。
final class WeTypeAutoReturn3: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testWeTypeTopRightMic() throws {
        let wx = XCUIApplication(bundleIdentifier: "com.tencent.xin")
        wx.activate()
        XCTAssertTrue(wx.wait(for: .runningForeground, timeout: 20), "微信没起来")
        Thread.sleep(forTimeInterval: 2)

        // 确保停在微信输入法键盘上（可能还停在上次的"按住说话"条形界面）
        if wx.buttons["下一个键盘"].firstMatch.waitForExistence(timeout: 3) == false
            && wx.buttons["按住 说话"].firstMatch.waitForExistence(timeout: 2) == false {
            wx.swipeDown(); Thread.sleep(forTimeInterval: 0.8)
            wx.swipeDown(); Thread.sleep(forTimeInterval: 1.2)
            for (n, y) in [0.22, 0.30, 0.38, 0.46].enumerated() {
                if n > 0 {
                    let a = wx.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                    let b = wx.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
                    a.press(forDuration: 0.05, thenDragTo: b)
                    Thread.sleep(forTimeInterval: 1.5)
                }
                wx.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: CGFloat(y))).tap()
                Thread.sleep(forTimeInterval: 1.6)
                if wx.textViews.count > 0 || wx.textFields.count > 0 { break }
            }
            wx.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.945)).tap()
            Thread.sleep(forTimeInterval: 1.6)
        }

        // 如果现在停在"按住 说话"条形界面，先切回普通键盘视图（点键盘图标）
        if wx.buttons["按住 说话"].firstMatch.exists {
            let kbIcon = wx.buttons.matching(NSPredicate(format: "identifier CONTAINS %@", "keyboard"))
                .firstMatch
            if kbIcon.exists { kbIcon.tap(); Thread.sleep(forTimeInterval: 1.0) }
        }

        let shot0 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot0.name = "WTAR3_00_keyboard_state"; shot0.lifetime = .keepAlways; add(shot0)

        // 把当前键盘上所有按钮连同坐标打出来，专门找"右上角"区域的麦克风图标
        let scr = wx.frame
        NSLog("WTAR3 当前键盘按钮清单：")
        var candidates: [(XCUIElement, CGFloat, CGFloat, String)] = []
        for i in 0..<min(wx.buttons.count, 60) {
            let b = wx.buttons.element(boundBy: i)
            guard b.exists else { continue }
            let f = b.frame
            let nx = (f.midX - scr.minX) / scr.width
            let ny = (f.midY - scr.minY) / scr.height
            let s = b.label + "/" + b.identifier
            if s != "/" {
                NSLog("WTAR3   \"%@\" 中心(%.2f,%.2f)", s, nx, ny)
                candidates.append((b, nx, ny, s))
            }
        }
        // 右上角区域：ny 在键盘区上半、nx 靠右（键盘大约占屏幕下半部分，
        // "键盘右上角"換算成整屏大约 ny 0.6~0.8、nx > 0.7）
        let topRight = candidates.filter { $0.1 > 0.65 && $0.2 > 0.55 && $0.2 < 0.85 }
        NSLog("WTAR3 右上角区域候选：%@", topRight.map { $0.3 }.joined(separator: " ｜ "))

        guard let picked = topRight.first(where: { $0.3.lowercased().contains("mic")
                                                  || $0.3.contains("语音") || $0.3.contains("麦") })
                        ?? topRight.first else {
            NSLog("WTAR3 🚨 右上角区域没找到候选按钮，本轮到此为止")
            return
        }
        NSLog("WTAR3 选中按钮：%@｜按之前：微信=%d", picked.3, wx.state.rawValue)
        picked.0.tap()
        NSLog("WTAR3 ✅ 点了右上角那个 —— 接下来 20 秒【绝不再碰任何东西】，只看状态")

        for t in 1...20 {
            Thread.sleep(forTimeInterval: 1)
            NSLog("WTAR3 t=%2ds 微信=%d", t, wx.state.rawValue)
        }
        let shotEnd = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shotEnd.name = "WTAR3_99_end"; shotEnd.lifetime = .keepAlways; add(shotEnd)
    }
}
