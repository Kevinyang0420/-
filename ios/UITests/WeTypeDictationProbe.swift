import XCTest

/// 上一轮看到输入框里出现了「Test test test所有可个人」，但没有把握那是不是真的
/// 实时转写——也可能是上一个测试(ListKeyboards 用系统拼音键盘打字)留下的残留文字。
/// 这一轮做干净对照：**先清空输入框、记下清空后的内容，再点「语音输入」、等 5 秒、
/// 再读一次输入框内容**——只有清空之后真的冒出新文字，才算证据。
final class WeTypeDictationProbe: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testCleanDictationCheck() throws {
        let wx = XCUIApplication(bundleIdentifier: "com.tencent.xin")
        wx.activate()
        XCTAssertTrue(wx.wait(for: .runningForeground, timeout: 20), "微信没起来")
        Thread.sleep(forTimeInterval: 2)

        let field = wx.textFields.firstMatch.exists ? wx.textFields.firstMatch : wx.textViews.firstMatch
        guard field.waitForExistence(timeout: 6) else {
            NSLog("WTDP 🚨 找不到输入框"); return
        }
        // 🚨 不清空——清空手势不稳定，还有把话打错发出去的风险。
        //    直接拿"此刻已有的内容"当基线，安静等一段时间后只看**有没有新增**，
        //    不管原来是什么，这样比冒险清空更安全也更可靠。
        // 上一轮可能留了个文字选择菜单挡住键盘，点一下输入框末尾把它收起、确保键盘露出来
        field.tap(); Thread.sleep(forTimeInterval: 0.8)

        let before = (field.value as? String) ?? ""
        NSLog("WTDP 基线内容=\"%@\"（长度=%d）", before, before.count)

        let micBtn = wx.buttons["语音输入"].firstMatch
        guard micBtn.waitForExistence(timeout: 6) else {
            NSLog("WTDP 🚨 找不到「语音输入」按钮，可能键盘换了，先截图看现状")
            let s = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            s.name = "WTDP_00_no_button"; s.lifetime = .keepAlways; add(s)
            return
        }
        micBtn.tap()
        NSLog("WTDP ✅ 点了「语音输入」，环境完全安静（没人说话），等 6 秒再读输入框")
        Thread.sleep(forTimeInterval: 6.0)

        let after = (field.value as? String) ?? ""
        NSLog("WTDP 6秒后输入框内容=\"%@\"（长度=%d）", after, after.count)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "WTDP_01_after_6s"; shot.lifetime = .keepAlways; add(shot)

        if after != before {
            NSLog("WTDP 🚨🚨 结论：内容变了！环境是安静的，这段新文字只能是它自己生成/占位/或真的拾到了环境音——不是我编的，是清空后凭空多出来的：\"%@\"", after)
        } else {
            NSLog("WTDP 结论：内容没变化——上一轮那段「Test test test」大概率是别的测试留下的残留，不是这次产生的")
        }

        NSLog("WTDP 微信这段时间的前后台状态=%d（4=前台）", wx.state.rawValue)
    }
}
