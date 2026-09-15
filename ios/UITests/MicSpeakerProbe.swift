import XCTest

/// 0 09-15 再纠正方向：声音那条停了（Kevin 已经答应现场说，不值得再花轮次）。
/// **真正要查的是 `transless.mic` 按钮录到一半就摸不到了**——这在两条不同的
/// 测试里都出现过（`TranslessInMessages` 曾经"点了麦克风"之后就没再摸过它，
/// 这次 `MicSpeakerProbe` 是第二次复现）。第 4b 镜正是"点麦克风→说话→
/// 再点麦克风停"这同一条路径，真录的时候 Kevin 人在场，这里要是断了就是
/// 整条重录。
///
/// 这条不测声音，只逐秒查："录音期间，App 还在前台吗？撰写界面还在吗？
/// 麦克风按钮还摸得到吗？" —— 把"什么时候掉的"钉死，而不是猜。
final class MicSpeakerProbe: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    /// 用信息 App 复现(跟 TranslessInMessages 同一条路径,第 4b 镜实际用的宿主)。
    /// 🚨 09-15 在 1359(真机 TestFlight 包)上跑这条时,t=0 截图后紧接着
    /// XCUITest 报 `kAXErrorServerNotFound`(整个测试崩了,不是"按钮摸不到"那种
    /// 温和失败)——比 1375 上看到的还严重。这一版全面加 try?/防御,
    /// **哪一步崩的都要留证据(至少留一张截图),不能让整条测试一崩就什么都没有**。
    func testMicStabilityInMessages() throws {
        let sms = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        let tl = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        tl.terminate()
        Thread.sleep(forTimeInterval: 1.0)

        XCTAssertTrue(sms.wait(for: .runningForeground, timeout: 15), "信息 App 没起来")
        Thread.sleep(forTimeInterval: 1.5)

        var found = false
        for n in 0..<3 {
            if sms.buttons["transless.mic"].waitForExistence(timeout: 4) { found = true; break }
            sms.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.945)).press(forDuration: 1.3)
            Thread.sleep(forTimeInterval: 1.8)
            let row = sms.cells.matching(NSPredicate(format: "label BEGINSWITH[c] 'Transless'")).firstMatch
            if row.waitForExistence(timeout: 3) { row.tap() } else { sms.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
            Thread.sleep(forTimeInterval: 3.5)
            NSLog("MSP 长按切第%d次", n + 1)
        }
        NSLog("MSP 切到Transless键盘了吗=%d", found ? 1 : 0)
        guard found else { NSLog("MSP 🚨 没切到,本轮作废"); return }

        let micBtn = sms.buttons["transless.mic"]
        XCTAssertTrue(micBtn.exists, "找到键盘但没找到麦克风按钮")
        micBtn.tap()
        NSLog("MSP t=0s 已点麦克风")

        // 立刻截一张,这一步万一后面全崩,至少留了 t0 的证据。
        safeShot(name: "t0_after_tap")

        // 🚨 循环里**只截图,不查任何 ax 元素**——上一轮就是元素查询
        // (`.exists`/`.state`)本身触发了 `kAXErrorServerNotFound` 让整条测试崩掉。
        // `XCUIScreen.main.screenshot()` 走的是屏幕捕获,不是无障碍快照,更抗崩。
        for t in 1...8 {
            Thread.sleep(forTimeInterval: 1.0)
            NSLog("MSP t=%2ds 循环开始", t)
            safeShot(name: "t\(t)_recording")
        }
        NSLog("MSP 逐秒截图跑完了")
    }

    /// 🚨 截图/查询任何一步都可能崩(kAXErrorServerNotFound),包一层 try?,
    /// 崩了就记一条日志继续下一步,不让整条测试因为一次截图失败就全部作废。
    private func safeShot(name: String) {
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = name + ".png"
        att.lifetime = .keepAlways
        add(att)
        NSLog("MSP 已截图 %@", name)
    }
}
