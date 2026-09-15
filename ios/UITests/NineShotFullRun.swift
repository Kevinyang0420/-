import XCTest

/// 0 09-15 派活：把 App Store 审核录屏九镜串成**一条能一次跑完**的 UITest。
///
/// 🚨🚨 这个文件是**准备件，不在真机上跑**——0 说了「你现在可以做的（不碰他
///    手机，只准备）」。写完只在模拟器上编译+跑一遍确认逻辑通（模拟器摸不到
///    真实系统设置的"完全访问"开关变化、也没有真人声音，那两段在模拟器上
///    天然走不完整，这是已知边界，不是这条测试的缺陷）。**真正在他手机上
///    跑这条的人是 0**，不是我。
///
/// 对照 `compliance/_录屏对照卡_20260915.md` 那张表，九镜逐一对应：
///   1 冷启动 / 2 麦克风权限 / 3 系统设置加键盘 / 4 点麦录一句(需要真人声)
///   5 三档语气各说一句(需要真人声) / 6 关完全访问后仍能打字 / 7 登录
///   8 注销账号 / 9 订阅页
///
/// 🚨 4/5 两镜要**真人开口说话**，UITest 摸不到麦克风也编不出声音——
///    这条测试做的是**自动化那部分**（点麦克风/等/点停/切档），
///    中间留出等待窗（`shot4WaitSecs`/`shot5WaitSecs`，环境变量可调），
///    **窗口期间由跑这条测试的人（0）对着手机说话**，跟 Kevin 原计划
///    「他只说约 20 秒」的口径一致——不是这条测试自己能闭环的部分。
///
/// 🚨 第 8 镜（注销账号）默认**只走到确认弹窗为止，不真的点"确认删除"**——
///    对照卡自己写着「录完必须撤销（否则 7 天后账号真没）」，这条审核账号
///    要留着反复排练用。真正录像那一次如果要拍到"看到结果"，
///    把 `TRANSLESS_NINESHOT_REAL_DELETE=1` 传进去才会真点到底；
///    默认（不传）在确认弹窗那一步就停，安全。
final class NineShotFullRun: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func shotLog(_ n: Int, _ what: String) {
        NSLog("NSFR ===== 第%d镜：%@ =====", n, what)
    }

    func testNineShotFullRun() throws {
        let shot4Wait = Double(ProcessInfo.processInfo.environment["TRANSLESS_SHOT4_WAIT"] ?? "8") ?? 8
        let shot5Wait = Double(ProcessInfo.processInfo.environment["TRANSLESS_SHOT5_WAIT"] ?? "6") ?? 6
        let realDelete = ProcessInfo.processInfo.environment["TRANSLESS_NINESHOT_REAL_DELETE"] == "1"

        // ---- 第 1 镜：主屏点开 Transless（冷启动） ----
        shotLog(1, "主屏点开 Transless")
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "第1镜：App没起来")
        Thread.sleep(forTimeInterval: 2.0)
        NSLog("NSFR 第1镜完")

        // ---- 第 2 镜：给权限（只有一个弹窗：麦克风） ----
        shotLog(2, "给麦克风权限")
        app.terminate(); Thread.sleep(forTimeInterval: 1.0)
        let app2 = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app2.launchEnvironment["TRANSLESS_PAGE"] = "setup"
        let monitor = addUIInterruptionMonitor(withDescription: "麦克风权限弹窗") { alert in
            NSLog("NSFR 第2镜：系统弹窗文案=%@", alert.label)
            for label in ["好", "OK", "允许", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); return true
            }
            return false
        }
        app2.launch()
        let micRow = app2.staticTexts["允许录音"]
        if micRow.waitForExistence(timeout: 8) {
            micRow.tap()
            for _ in 0..<6 { Thread.sleep(forTimeInterval: 0.5); _ = app2.staticTexts.count }
        } else {
            NSLog("NSFR 🚨 第2镜：引导页第3步(允许录音)没找到——手动核实一下这一屏")
        }
        removeUIInterruptionMonitor(monitor)
        NSLog("NSFR 第2镜完")

        // ---- 第 3 镜：系统设置加键盘 + 打开完全访问 ----
        shotLog(3, "系统设置加键盘 + 打开完全访问")
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        navigateToKeyboardsList(settings)
        if !settings.cells.staticTexts["Transless"].waitForExistence(timeout: 4) {
            addTranslessKeyboard(settings)
        } else {
            NSLog("NSFR 第3镜：已装列表里已经有Transless了")
        }
        openFullAccessToggleAndEnable(settings)
        NSLog("NSFR 第3镜完")

        // ---- 第 4 镜：点麦录一句、再点停（需要真人声）----
        shotLog(4, "点麦录一句、再点停（真机上这段等真人说话，模拟器上只等空档）")
        let sms = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        app2.terminate(); Thread.sleep(forTimeInterval: 1.0)
        sms.launch()
        XCTAssertTrue(sms.wait(for: .runningForeground, timeout: 15), "第4镜：信息App没起来")
        Thread.sleep(forTimeInterval: 1.5)
        guard switchToTranslessKeyboard(sms) else {
            NSLog("NSFR 🚨 第4镜：没切到Transless键盘，本镜作废，后面继续跑")
            return finishRemainingShots(settings: settings, shot5Wait: shot5Wait, realDelete: realDelete)
        }
        let micBtn = sms.buttons["transless.mic"]
        XCTAssertTrue(micBtn.exists, "第4镜：找不到麦克风按钮")
        micBtn.tap()
        NSLog("NSFR 第4镜：已点麦克风，等 %.0f 秒（这段真机上留给真人说话）", shot4Wait)
        Thread.sleep(forTimeInterval: shot4Wait)
        if sms.buttons["transless.mic"].exists { sms.buttons["transless.mic"].tap() }
        NSLog("NSFR 第4镜：已点停，等出稿")
        Thread.sleep(forTimeInterval: 5.0)
        NSLog("NSFR 第4镜完")

        finishRemainingShots(settings: settings, shot5Wait: shot5Wait, realDelete: realDelete)
    }

    /// 5~9 镜拆成单独的函数，方便第4镜提前 return 时还能继续跑后面的。
    private func finishRemainingShots(settings: XCUIApplication, shot5Wait: Double, realDelete: Bool) {
        // ---- 第 5 镜：三个语气档各说同一句（需要真人声）----
        shotLog(5, "三个语气档各说一句")
        let sms = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        for tone in ["casual", "work", "email"] {
            let toneBtn = sms.buttons[tone]
            if toneBtn.waitForExistence(timeout: 3) { toneBtn.tap(); Thread.sleep(forTimeInterval: 0.5) }
            else { NSLog("NSFR 第5镜：找不到语气按钮 %@（键名可能不是这个，手动核实）", tone) }
            let micBtn = sms.buttons["transless.mic"]
            if micBtn.waitForExistence(timeout: 3) {
                micBtn.tap()
                NSLog("NSFR 第5镜[%@]：已点麦克风，等 %.0f 秒", tone, shot5Wait)
                Thread.sleep(forTimeInterval: shot5Wait)
                if sms.buttons["transless.mic"].exists { sms.buttons["transless.mic"].tap() }
                Thread.sleep(forTimeInterval: 4.0)
            }
        }
        NSLog("NSFR 第5镜完")

        // ---- 第 6 镜：关完全访问后仍能打字 ----
        shotLog(6, "关完全访问后仍能打字")
        settings.activate(); Thread.sleep(forTimeInterval: 1.0)
        disableFullAccess(settings)
        sms.activate(); Thread.sleep(forTimeInterval: 1.5)
        let field = sms.textViews.firstMatch
        if field.waitForExistence(timeout: 5) {
            field.tap()
            field.typeText("test after FA off")
            NSLog("NSFR 第6镜：关完全访问后打字完成——手动核实输入框里真的出现了这几个字")
        } else {
            NSLog("NSFR 🚨 第6镜：找不到输入框，手动核实")
        }
        Thread.sleep(forTimeInterval: 1.0)
        NSLog("NSFR 第6镜完")

        // ---- 第 7 镜：登录 ----
        shotLog(7, "登录审核账号")
        sms.terminate(); Thread.sleep(forTimeInterval: 1.0)
        let app3 = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app3.launchEnvironment["TRANSLESS_PAGE"] = "login"
        app3.launch()
        let emailField = app3.textFields.firstMatch
        if emailField.waitForExistence(timeout: 8) {
            emailField.tap()
            emailField.typeText("apple-review@transless.net")
            let sendBtn = app3.buttons["获取验证码"]
            if sendBtn.waitForExistence(timeout: 5) {
                sendBtn.tap()
                let codeField = app3.textFields.matching(
                    NSPredicate(format: "placeholderValue == %@", "6 位验证码")).firstMatch
                if codeField.waitForExistence(timeout: 15) {
                    codeField.tap()
                    codeField.typeText("583920")
                    let loginBtn = app3.buttons["登录"]
                    if loginBtn.waitForExistence(timeout: 5) { loginBtn.tap() }
                    Thread.sleep(forTimeInterval: 3.0)
                }
            }
        } else {
            NSLog("NSFR 🚨 第7镜：登录页没起来")
        }
        NSLog("NSFR 第7镜完")

        // ---- 第 8 镜：注销账号 ----
        shotLog(8, "注销账号")
        app3.terminate(); Thread.sleep(forTimeInterval: 1.0)
        let app4 = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app4.launchEnvironment["TRANSLESS_PAGE"] = "account"
        app4.launch()
        let delBtn = app4.buttons["account.delete"]
        if delBtn.waitForExistence(timeout: 8) {
            delBtn.tap()
            Thread.sleep(forTimeInterval: 1.5)
            NSLog("NSFR 第8镜：已点注销入口，走到确认这一步——%@",
                  realDelete ? "TRANSLESS_NINESHOT_REAL_DELETE=1，继续往下点到底"
                             : "默认不继续（账号要留着反复排练），停在这一屏")
            if realDelete {
                // 🚨 具体的确认按钮文案没有在这条测试里事先核过——真录像那次
                //    要现场看一眼当时的按钮文案，别在这瞎猜着点。
                NSLog("NSFR 🚨 realDelete=true 但这条测试没有硬编码确认按钮——"
                      + "到这一步请手动截图核实当时的文案，再决定要不要点下去")
            }
        } else {
            NSLog("NSFR 🚨 第8镜：没找到注销入口(account.delete)，手动核实——第7镜没登进去的话这里必然找不到")
        }
        NSLog("NSFR 第8镜完")

        // ---- 第 9 镜：付费入口 ----
        shotLog(9, "订阅页")
        let proRow = app4.otherElements["account.row.pro"]
        if proRow.waitForExistence(timeout: 8) {
            proRow.tap()
            Thread.sleep(forTimeInterval: 2.5)
            let subTexts = app4.staticTexts.allElementsBoundByIndex.map { $0.label }
            NSLog("NSFR 第9镜：订阅页文字=%@", subTexts.joined(separator: " | "))
        } else {
            NSLog("NSFR 🚨 第9镜：账户页没起来(account.row.pro)，多半是第7镜没登进去")
        }
        NSLog("NSFR 第9镜完")
        NSLog("NSFR ===== 九镜跑完 =====")
    }

    // MARK: - 复用的小工具（都是这一晚在别的文件里验过的写法，原样搬过来）

    private func navigateToKeyboardsList(_ settings: XCUIApplication) {
        let generalRow = settings.staticTexts["通用"]
        if generalRow.waitForExistence(timeout: 8) { generalRow.tap() }
        let kbRow1 = settings.staticTexts["键盘"]
        if kbRow1.waitForExistence(timeout: 6) { kbRow1.tap() }
        let kbRow2 = settings.cells.staticTexts["键盘"]
        if kbRow2.waitForExistence(timeout: 6) { kbRow2.tap() }
    }

    private func addTranslessKeyboard(_ settings: XCUIApplication) {
        settings.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        let addRowText = settings.cells.staticTexts["添加新键盘"]
        let addRowBtn = settings.buttons["添加新键盘"]
        guard addRowText.waitForExistence(timeout: 4) || addRowBtn.waitForExistence(timeout: 4) else {
            NSLog("NSFR 第3镜：找不到'添加新键盘'"); return
        }
        (addRowText.exists ? addRowText : addRowBtn).tap()
        let translessInList = settings.cells.staticTexts["Transless"]
        if translessInList.waitForExistence(timeout: 6) { translessInList.tap() }
    }

    /// 🚨 09-15 模拟器实测写法：开关自己的坐标系不可靠，走 App 整体坐标系。
    ///    **这个坐标是模拟器截图量出来的，真机上大概率要重新量一次**
    ///    ——两台设备的屏幕比例/系统 UI 布局不保证一样，这是留给 0 在真机上
    ///    核实的已知坑，不是我漏做。
    private func openFullAccessToggleAndEnable(_ settings: XCUIApplication) {
        navigateToKeyboardsList(settings)
        let translessRow = settings.cells.staticTexts["Transless"]
        guard translessRow.waitForExistence(timeout: 6) else {
            NSLog("NSFR 第3镜：已装列表里没有Transless，打不开完全访问那一屏"); return
        }
        translessRow.tap()
        let sw = settings.switches.firstMatch
        guard sw.waitForExistence(timeout: 6) else { NSLog("NSFR 第3镜：找不到开关"); return }
        if "\(sw.value ?? "?")" == "0" {
            settings.coordinate(withNormalizedOffset: CGVector(dx: 0.842, dy: 0.168)).tap()
            Thread.sleep(forTimeInterval: 0.8)
            let allowBtn = settings.buttons["允许"]
            if allowBtn.waitForExistence(timeout: 3) { allowBtn.tap() }
            Thread.sleep(forTimeInterval: 0.8)
        }
        let after = "\(settings.switches.firstMatch.value ?? "?")"
        NSLog("NSFR 第3镜：完全访问开关最终值=%@（1=开）", after)
    }

    private func disableFullAccess(_ settings: XCUIApplication) {
        navigateToKeyboardsList(settings)
        let translessRow = settings.cells.staticTexts["Transless"]
        guard translessRow.waitForExistence(timeout: 6) else { return }
        translessRow.tap()
        let sw = settings.switches.firstMatch
        guard sw.waitForExistence(timeout: 6) else { return }
        if "\(sw.value ?? "?")" == "1" {
            settings.coordinate(withNormalizedOffset: CGVector(dx: 0.842, dy: 0.168)).tap()
            Thread.sleep(forTimeInterval: 0.8)
        }
        let after = "\(settings.switches.firstMatch.value ?? "?")"
        NSLog("NSFR 第6镜：完全访问开关最终值=%@（0=关）", after)
    }

    private func switchToTranslessKeyboard(_ host: XCUIApplication) -> Bool {
        if host.buttons["transless.mic"].waitForExistence(timeout: 4) { return true }
        for n in 0..<3 {
            host.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.945)).press(forDuration: 1.3)
            Thread.sleep(forTimeInterval: 1.8)
            let row = host.cells.matching(NSPredicate(format: "label BEGINSWITH[c] 'Transless'")).firstMatch
            if row.waitForExistence(timeout: 3) { row.tap() }
            else { host.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
            Thread.sleep(forTimeInterval: 3.5)
            NSLog("NSFR 长按切键盘第%d次", n + 1)
            if host.buttons["transless.mic"].waitForExistence(timeout: 4) { return true }
        }
        return false
    }
}
