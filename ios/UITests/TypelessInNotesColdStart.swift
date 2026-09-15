import XCTest

/// Kevin 09-14："他们每次关掉后台，也是可以跳回到原 APP 的"——现场验证这句话，
/// 不是再讨论。在【备忘录】（不是微信，也不在任何候选表逻辑里）里，确认 Typeless
/// 主 App 没在跑（真冷启动）的前提下，切到 Typeless 键盘、按它的听写按钮，
/// 逐秒记录 备忘录/Typeless 的前后台状态，看它到底跳不跳、跳完落在哪。
final class TypelessInNotesColdStart: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testTypelessColdStartInNotes() throws {
        let notes = XCUIApplication(bundleIdentifier: "com.apple.mobilenotes")
        let tl = XCUIApplication(bundleIdentifier: "com.typeless.mobile")
        tl.terminate()
        Thread.sleep(forTimeInterval: 1.5)
        NSLog("TLNC 已确认终止 Typeless 主App，确保冷启动")

        notes.terminate()
        Thread.sleep(forTimeInterval: 1.0)
        notes.activate()
        XCTAssertTrue(notes.wait(for: .runningForeground, timeout: 20), "备忘录没起来")
        Thread.sleep(forTimeInterval: 2)

        // 新建一篇备忘录，进入编辑状态召出键盘
        let addBtn = notes.buttons["New Note"].exists ? notes.buttons["New Note"] : notes.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'new' OR label CONTAINS[c] '新建'")).firstMatch
        if addBtn.exists {
            addBtn.tap()
        } else {
            notes.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.95)).tap()
        }
        Thread.sleep(forTimeInterval: 1.5)
        // 点一下正文区域确保键盘弹出
        notes.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        Thread.sleep(forTimeInterval: 1.5)

        // 长按地球键弹出键盘选择菜单，切到 Typeless
        var found = false
        for n in 0..<3 {
            let g = notes.buttons["下一个键盘"]
            if !g.exists {
                NSLog("TLNC 🚨 第%d轮找不到「下一个键盘」键", n)
                break
            }
            g.press(forDuration: 1.3)
            Thread.sleep(forTimeInterval: 1.5)
            let row = notes.cells.matching(NSPredicate(format: "label BEGINSWITH[c] 'Typeless'")).firstMatch
            if row.waitForExistence(timeout: 3) {
                row.tap()
                Thread.sleep(forTimeInterval: 2.5)
                found = true
                break
            } else {
                notes.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
                Thread.sleep(forTimeInterval: 1.0)
            }
        }
        NSLog("TLNC 切到Typeless键盘了吗=%d", found ? 1 : 0)
        guard found else {
            NSLog("TLNC 🚨 没切到Typeless键盘，本轮作废"); return
        }

        let shot0 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot0.name = "TLNC_00_before_tap"; shot0.lifetime = .keepAlways; add(shot0)

        // 🚨🚨 09-14 第三次：前两版都在打"点击说话"这个无障碍元素——第二版查出它的
        //    frame 是 {{12,665},{406,16}}，高度只有16pt，跟截图里那个约100pt高的
        //    黑色圆角按钮对不上，是个隐藏的/位置对不上的无障碍标签，不是真正的触摸层。
        //    Kevin说得对：截图核实过按钮的真实屏幕位置是 y≈0.648（黑色圆角矩形+
        //    麦克风图标，文案"点击说话"在它上方），这次直接对屏幕坐标发触摸，
        //    完全不查无障碍树，跟真手指盲点一个已知位置等价。
        // 🚨 09-14 第五次：Kevin质疑"为什么总要我做"，说得对，再自己逼一步再问他。
        //    两个还没排除的可能：①键盘刚切换完，自定义手势识别器可能还没接好，
        //    切完立刻点可能点在"半初始化"的状态上——这次多等5秒让它彻底稳定；
        //    ②系统麦克风权限弹窗——如果弹了会被 SpringBoard 接管，这次专门查一遍。
        Thread.sleep(forTimeInterval: 5.0)
        NSLog("TLNC 再等5秒确保键盘完全稳定：备忘录=%d Typeless=%d", notes.state.rawValue, tl.state.rawValue)
        let shot0b = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot0b.name = "TLNC_00b_before_tap_recheck"; shot0b.lifetime = .keepAlways; add(shot0b)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let screenCoord = notes.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.648))
        screenCoord.tap()
        NSLog("TLNC ✅ 点了Typeless的黑色麦克风按钮（多等5秒稳定后再点）")
        Thread.sleep(forTimeInterval: 0.5)
        if springboard.alerts.count > 0 {
            let a = springboard.alerts.firstMatch
            NSLog("TLNC 🚨 弹出系统弹窗：%@ ｜ 按钮=%@", a.label,
                  a.buttons.allElementsBoundByIndex.map { $0.label }.joined(separator: ","))
        } else {
            NSLog("TLNC 没有系统弹窗（不是权限问题）")
        }

        for t in 1...15 {
            Thread.sleep(forTimeInterval: 1)
            NSLog("TLNC t=%2ds 备忘录=%d Typeless=%d", t, notes.state.rawValue, tl.state.rawValue)
        }
        let shotEnd = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shotEnd.name = "TLNC_99_end"; shotEnd.lifetime = .keepAlways; add(shotEnd)
    }
}
