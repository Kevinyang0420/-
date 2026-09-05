import XCTest

/// **在微信里按 Typeless 的麦克风，看它跳不跳、以及它把谁拉起来。**
///
/// 🚨 背景：2026-08-30 已经验死了我们这边的所有路 ——
///    键盘扩展录不了（`2003329396`）、后台的 App 拿不到输入路由（`输入源 0 个`）、
///    推送能把 App 拉起来但拉起来也架不上。
///    **Kevin 一直在说的那句话是对的：Typeless 能做，就说明有路。**
///    这个测试就是去拍它到底走哪条。
///
/// 判据（外面的脚本同时在数进程）：
/// · 按完之后微信还在前台（state=4）→ **它不跳**，那它必有我没找到的机制
/// · 微信掉出前台 → 它也跳，那"不跳"这件事本身就不成立
final class TypelessInWeChat: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    func testTypelessMic() throws {
        let wx = XCUIApplication(bundleIdentifier: "com.tencent.xin")
        let tl = XCUIApplication(bundleIdentifier: "com.typeless.mobile")
        wx.activate()
        XCTAssertTrue(wx.wait(for: .runningForeground, timeout: 20), "微信没起来")
        Thread.sleep(forTimeInterval: 3)

        // 进第一条会话（沿用已跑通的那套：多试几行 + 肯定判据）
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
        NSLog("TLWX 进会话了吗=%d", inChat ? 1 : 0)
        wx.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.945)).tap()
        Thread.sleep(forTimeInterval: 1.6)

        // 循环切键盘，直到**既不是我们的、也不是系统的**——那就是 Typeless
        // 🚨🚨 **地球键要按名字拿，不要按坐标。**
        //    前三轮都按 (0.07,0.945)，那个位置在中文键盘上是「布局」键 ——
        //    长按弹出来的是「默认布局/右手布局/左手布局」，根本不是切键盘的列表，
        //    所以 12 次循环一次都没切走。而元素树里明明白白有一个
        //    **`"下一个键盘"`** 按钮且可点。**能按名字就别按坐标。**
        var found = false
        for n in 0..<12 {
            let g = wx.buttons["下一个键盘"]
            guard g.exists, g.isHittable else {
                NSLog("TLWX 🚨 第%d轮找不到「下一个键盘」键，停", n); break
            }
            g.tap()
            Thread.sleep(forTimeInterval: 3.0)   // 第三方键盘首次加载慢
            var labels: [String] = []
            for i in 0..<min(wx.buttons.count, 60) {
                let b = wx.buttons.element(boundBy: i)
                let s = b.label + "/" + b.identifier
                if s != "/" { labels.append(s) }
            }
            let sys = labels.contains { $0.contains("听写") || $0.contains("dictation")
                                     || $0.contains("聽寫") || $0.contains("布局") }
            let ours = labels.contains { $0.contains("transless.mic") }
            NSLog("TLWX 切第%d次：系统=%d ours=%d 键数=%d｜%@", n + 1, sys ? 1 : 0,
                  ours ? 1 : 0, labels.count, labels.prefix(10).joined(separator: " ｜ "))
            if !sys && !ours { found = true; break }
        }
        NSLog("TLWX 切到第三方（非我们）键盘了吗=%d", found ? 1 : 0)
        guard found else {
            NSLog("TLWX 🚨 没切到，本轮作废（不许按下去凑结论）"); return
        }

        // 摸清它键盘上每个元素的位置，别拍脑袋按坐标
        let scr = wx.frame
        for i in 0..<min(wx.buttons.count, 40) {
            let b = wx.buttons.element(boundBy: i)
            guard b.exists else { continue }
            let f = b.frame
            NSLog("TLWX   按钮[%d] \"%@\"/\"%@\" 中心(%.2f,%.2f) 大小%.0fx%.0f",
                  i, b.label, b.identifier,
                  (f.midX - scr.minX) / scr.width, (f.midY - scr.minY) / scr.height,
                  f.width, f.height)
        }
        for i in 0..<min(wx.otherElements.count, 40) {
            let e = wx.otherElements.element(boundBy: i)
            guard e.exists, e.frame.height > 30, e.frame.height < 400 else { continue }
            let f = e.frame
            NSLog("TLWX   其它[%d] \"%@\" 中心(%.2f,%.2f) 大小%.0fx%.0f", i, e.label,
                  (f.midX - scr.minX) / scr.width, (f.midY - scr.minY) / scr.height,
                  f.width, f.height)
        }

        NSLog("TLWX 按之前：微信=%d  Typeless主App=%d", wx.state.rawValue, tl.state.rawValue)
        // 按它的麦克风：不知道它的 identifier，用"最大的那个按钮"以外的办法不可靠，
        // 所以按键盘区正中偏下（各家语音键盘的录音键都在那儿），并把按到的东西打出来
        let mic = wx.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.86))
        mic.tap()
        NSLog("TLWX ✅ 按了（0.50,0.86）")
        for t in 1...12 {
            Thread.sleep(forTimeInterval: 1)
            NSLog("TLWX t=%ds 微信=%d Typeless主App=%d", t, wx.state.rawValue, tl.state.rawValue)
        }
    }
}
