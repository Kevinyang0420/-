import XCTest

/// 验苹果录屏第 7/9 镜「路通不通」（0 派的活，09-15）——**不录像**，
/// 只证明：审核账号能真登进去，登进去之后 Membership 显示的是什么。
///
/// 🚨 这条不是拿代码里"有这个账号"当证据——`auth_store.py` 那三个环境变量
///   默认全空，源码里的常量证明不了线上真配了。**唯一算数的证据是真登一次。**
///   同理第 9 镜（权益）是另一个开关（`device_store.py:487`），两条要连着验：
///   只登进去不算过，Membership 那行显示的文案才是最终判据。
final class ReviewAccountShot: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testReviewAccountLoginAndMembership() throws {
        // 🚨 裸 `XCUIApplication()` 在这个 target 里默认目标是 TransProbe（另一个
        //    bundle），不是 Transless 主 App——跟 `TranslessInMessages.swift` 一样
        //    必须显式给 bundleIdentifier，否则连登录页都起不来。
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "login"
        app.launch()

        let emailField = app.textFields.firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: 8), "登录页没起来——第 7 镜第一步就卡")
        emailField.tap()
        emailField.typeText("apple-review@transless.net")

        let sendBtn = app.buttons["获取验证码"]
        XCTAssertTrue(sendBtn.waitForExistence(timeout: 5), "找不到「获取验证码」按钮")
        sendBtn.tap()
        NSLog("RVW 已点发送验证码")

        // 🚨🚨 09-15 实测踩坑：`app.textFields.element(boundBy: 1)` 打偏了——
        //    键入的 "583920" splice 进了邮箱框（读回 "apple-review@transless583920.net"），
        //    说明 boundBy 索引在这个场景下不可靠（codeField 刚从 isHidden 翻出来，
        //    XCUITest 那一刻的元素排序跟视图层级顺序对不上）。改用 placeholder 定位，
        //    跟这个项目 `feedback_ui_automation_locators` 那条记忆一致：按类型/文案定位，
        //    不按位置索引。
        let codeField = app.textFields.matching(
            NSPredicate(format: "placeholderValue == %@", "6 位验证码")).firstMatch
        XCTAssertTrue(codeField.waitForExistence(timeout: 15), "验证码输入框没出现——send 没成功")
        codeField.tap()
        codeField.typeText("583920")
        let typed = (codeField.value as? String) ?? ""
        NSLog("RVW 验证码框实际读回=%@", typed)
        XCTAssertEqual(typed, "583920", "验证码框没打对——不继续点登录，免得报错误信息误导判断")

        let loginBtn = app.buttons["登录"]
        XCTAssertTrue(loginBtn.waitForExistence(timeout: 5), "找不到「登录」按钮")
        loginBtn.tap()
        NSLog("RVW 已点登录，等待结果")

        // 登录成功后会 push 完善资料页或直接 pop 回首页——两种情况登录页本身都会消失。
        let loginGone = NSPredicate(format: "exists == false")
        let stillHere = expectation(for: loginGone, evaluatedWith: loginBtn, handler: nil)
        let waitResult = XCTWaiter.wait(for: [stillHere], timeout: 15)
        NSLog("RVW 第7镜:登录按钮消失了吗=%d (消失=成功走完)", waitResult == .completed ? 1 : 0)
        if waitResult != .completed {
            // 没消失就把当前 hint 提示文字读出来，方便判断卡在哪一步。
            let texts = app.staticTexts.allElementsBoundByIndex.map { $0.label }.joined(separator: " | ")
            NSLog("RVW 第7镜:登录未走完,当前屏幕文字=%@", texts)
            return
        }

        // 第 9 镜：直达账户页（跟 openAccount() 同一分流），读会员行副标题。
        app.terminate()
        Thread.sleep(forTimeInterval: 1.0)
        let app2 = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app2.launchEnvironment["TRANSLESS_PAGE"] = "account"
        app2.launch()

        let proRow = app2.otherElements["account.row.pro"]
        XCTAssertTrue(proRow.waitForExistence(timeout: 8), "账户页没起来,或者没走到已登录分支(说明第7镜其实没登进去)")
        let subtitleTexts = proRow.staticTexts.allElementsBoundByIndex.map { $0.label }
        NSLog("RVW 第9镜:会员行文字=%@", subtitleTexts.joined(separator: " | "))

        let delBtn = app2.buttons["account.delete"]
        NSLog("RVW 第8镜附带核实:注销入口在不在=%d", delBtn.waitForExistence(timeout: 3) ? 1 : 0)

        // 第 9 镜后半：点会员行，订阅页能不能开、StoreKit 价格能不能真的拉回来。
        // 🚨 不点到底（不真的走购买）——只看价格文案是不是从 "加载中" 变成了真数字。
        proRow.tap()
        Thread.sleep(forTimeInterval: 2.5)   // 给 StoreKit Product.products(for:) 留时间
        let subTexts = app2.staticTexts.allElementsBoundByIndex.map { $0.label }
        NSLog("RVW 第9镜(订阅页):当前屏幕文字=%@", subTexts.joined(separator: " | "))
    }

    /// 验第 2 镜——**只装不点过**的一次性系统权限弹窗。要求本方法在
    /// 一次干净重装后、任何别的测试碰过麦克风之前跑（09-15 这轮是紧跟着
    /// `xcrun devicectl device uninstall/install` 之后手动串的，`Auth`/`ProStatus`
    /// 那些网络调用不摸麦克风，不会把这个"没决定过"的状态提前消耗掉）。
    ///
    /// 🚨🚨 09-15 动手前查代码发现：0 转述的"麦克风+语音识别两个系统弹窗"
    ///    这句話对**这份 App**不成立——全仓库 grep `SFSpeechRecognizer` /
    ///    `requestAuthorization` 只有 `RemindScheduler`（提醒通知权限，
    ///    不是语音识别），`ci-workflow.yml:124` 自己的注释写着「转写改到
    ///    后端后不再需要 NSSpeechRecognitionUsageDescription」——但那把钥匙
    ///    （`project.yml:139/559`）还留在 Info.plist 里，只是从没被代码
    ///    用过。所以真机上按这颗按钮只会弹**一个**系统框（麦克风），
    ///    不会有第二个"语音识别"框——这条要报回 0，不是我瞎测出来的错，
    ///    是架构早就换了（转写走火山引擎服务端），只是这句口径没同步。
    func testMicPermissionPromptOnlyOne() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "setup"
        // 🚨 系统权限弹窗是 springboard 的 UI，不在我们这个 App 的进程里，
        //    XCUITest 要用 interruption monitor 才能拦到、点掉。
        let monitor = addUIInterruptionMonitor(withDescription: "麦克风权限弹窗") { alert in
            NSLog("RVW 第2镜:系统弹窗出现了,文案=%@", alert.label)
            if alert.buttons["好"].exists { alert.buttons["好"].tap(); return true }
            if alert.buttons["OK"].exists { alert.buttons["OK"].tap(); return true }
            if alert.buttons["允许"].exists { alert.buttons["允许"].tap(); return true }
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            return false
        }
        app.launch()

        let micRow = app.staticTexts["允许录音"]
        XCTAssertTrue(micRow.waitForExistence(timeout: 8), "引导页第3步(允许录音)没找到")
        micRow.tap()
        // interruption monitor 只在 App 自己产生一次 UI 交互查询时才会被系统轮询到，
        // 用一次无害的查询"戳"一下，逼系统检查有没有弹窗待处理。
        for _ in 0..<6 {
            Thread.sleep(forTimeInterval: 0.5)
            _ = app.staticTexts.count
        }
        removeUIInterruptionMonitor(monitor)
        NSLog("RVW 第2镜:流程跑完(弹窗出现与否见上面那行日志,没有该行=只想到的是根本没弹)")
    }
}
