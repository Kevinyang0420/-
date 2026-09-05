import XCTest

/// **真机 UI 测试：我自己去点键盘，而不是让 Kevin 点。**
///
/// 🚨 他 2026-08-30 的原话：
/// > 「你自己做完之后，找一个**微信的聊天对话**去试着调用这个输入法，看看能不能用。
/// >   你能用了，再告诉我可以用。**不要什么都没有做，然后就说可以。**」
///
/// 🚨🚨 **一律用坐标，不用无障碍标签。**
///    微信的会话 cell 时有时无（同一台机器上一次 `isHittable` 全 false、
///    上一次又能点），地球键的标签也认不到（`地球键在不在=0`）。
///    **靠不住的定位让测试变成随机数**，而随机数分不清"产品坏了"和"测试没点到"。
final class KeyboardUITests: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    private func tap(_ app: XCUIApplication, _ x: CGFloat, _ y: CGFloat,
                     _ why: String) {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
        NSLog("UITEST 点了 %@ (%.2f,%.2f)", why, x, y)
        Thread.sleep(forTimeInterval: 1.6)
    }

    func testWeChatMic() throws {
        let wx = XCUIApplication(bundleIdentifier: "com.tencent.xin")
        wx.activate()
        XCTAssertTrue(wx.wait(for: .runningForeground, timeout: 20), "微信没起来")
        Thread.sleep(forTimeInterval: 3)

        // ① 回到会话列表顶部再进第一条会话（坐标：列表第一行大约在 22% 高度）
        wx.swipeDown(); Thread.sleep(forTimeInterval: 0.8)
        wx.swipeDown(); Thread.sleep(forTimeInterval: 1.2)
        // 🚨🚨 **进会话这一步会随微信当时的界面状态失败**（2026-08-30 实测：
        //    上一次跑完停在别的页面，下一次点同样的坐标就进不去了，
        //    表现是 `输入框 0 个`，产品**根本没被跑到**，而我差点把它读成产品坏了）。
        //    → 多试几行，每次先从左边缘滑回去回到列表；**进没进去要有肯定判据**
        //      （底部有输入框），不能默认"点了就是进了"。
        var inChat = false
        for (n, y) in [0.22, 0.30, 0.38, 0.46].enumerated() {
            if n > 0 {
                // 从左边缘往右滑 = 返回；回到会话列表再试下一行
                let a = wx.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                let b = wx.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
                a.press(forDuration: 0.05, thenDragTo: b)
                Thread.sleep(forTimeInterval: 1.5)
            }
            tap(wx, 0.5, CGFloat(y), "会话第 \(n + 1) 行")
            if wx.textViews.count > 0 || wx.textFields.count > 0 { inChat = true; break }
        }
        NSLog("UITEST 进会话了吗=%d（输入框 %d 个）", inChat ? 1 : 0,
              wx.textViews.count + wx.textFields.count)

        // ② 点输入框把键盘唤出来（坐标：底部输入条）
        tap(wx, 0.45, 0.945, "输入框")

        // ③ 不是我们的键盘就切。地球键在键盘左下角，**长按**出列表。
        if !wx.buttons["transless.mic"].exists {
            NSLog("UITEST 当前不是 Transless，去切键盘")
            let globe = wx.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.945))
            globe.press(forDuration: 1.3)
            Thread.sleep(forTimeInterval: 1.8)
            var picked = false
            for i in 0..<min(wx.buttons.count, 60) {
                let b = wx.buttons.element(boundBy: i)
                if b.exists, b.label.contains("Transless"), b.isHittable {
                    b.tap(); picked = true
                    NSLog("UITEST 从列表切到了 %@", b.label)
                    break
                }
            }
            if !picked {
                // 列表没出来就点着循环切，最多 8 次
                for n in 0..<8 where !wx.buttons["transless.mic"].exists {
                    globe.tap()
                    Thread.sleep(forTimeInterval: 1.4)
                    NSLog("UITEST 循环切第 %d 次，麦克风键在不在=%d", n + 1,
                          wx.buttons["transless.mic"].exists ? 1 : 0)
                }
            }
            Thread.sleep(forTimeInterval: 1.5)
        }

        let mic = wx.buttons["transless.mic"]
        guard mic.waitForExistence(timeout: 8) else {
            NSLog("UITEST 🚨 始终没切到 Transless；键盘按钮数=%d", wx.keyboards.buttons.count)
            for i in 0..<min(wx.keyboards.buttons.count, 14) {
                NSLog("UITEST   键盘按钮[%d]=%@", i,
                      wx.keyboards.buttons.element(boundBy: i).label)
            }
            return
        }

        // 🚨 **先记下输入框原来有什么。** 上一轮测试留在里面的文字
        //    会把读回污染掉 —— 我因此把一次"没采到声音"读成了"采到了"。
        //    判据改成**差量**：按之后新增的那段里有没有已知答案。
        let before = (wx.textViews.firstMatch.value as? String) ?? ""
        NSLog("UITEST 按之前输入框已有 %d 字", before.count)

        // ④ 按下麦克风 —— **这一刻就是 Kevin 要的那一下**
        mic.tap()
        NSLog("UITEST ✅ 按下了麦克风键")
        Thread.sleep(forTimeInterval: 2)

        // 🚨🚨 **这是本次唯一真正的判据**：按完之后**还在不在微信**。
        //    在 = 不跳转成功；不在 = 又被拽走了（他明确不接受）。
        let still = wx.state == .runningForeground
        NSLog("UITEST 【判据】按完麦克风后还在微信里吗=%d（state=%d）",
              still ? 1 : 0, wx.state.rawValue)

        // 🚨 说话窗口。外面的脚本会在这段时间里让**手机自己念**一句已知的话
        //    （`debug.speakonly`），所以这里要留够：念 5.3 秒 + 前后余量。
        //    留 5 秒的话念到一半就被按停了，转写自然不完整。
        NSLog("UITEST 说话窗口开始（外部会让手机念一句）")
        Thread.sleep(forTimeInterval: 30)
        if wx.buttons["transless.mic"].exists {
            wx.buttons["transless.mic"].tap()
            NSLog("UITEST 按了停止，等出稿")
        } else {
            NSLog("UITEST 停止时找不到麦克风键（可能已被拽到主 App）")
        }
        Thread.sleep(forTimeInterval: 16)
        let tv = wx.textViews.firstMatch
        let after = (tv.value as? String) ?? ""
        let delta = after.hasPrefix(before) && after.count > before.count
            ? String(after.dropFirst(before.count)) : after
        NSLog("UITEST 输入框内容=%@", after.isEmpty ? "空" : after)
        NSLog("UITEST 本次新增=%@", delta.isEmpty ? "（一个字都没新增）" : delta)
        NSLog("UITEST 结束时还在微信吗=%d", wx.state == .runningForeground ? 1 : 0)
    }
}
