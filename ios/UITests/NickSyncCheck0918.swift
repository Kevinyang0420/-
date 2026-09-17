import XCTest

/// 🚨🚨 THROWAWAY —— 09-18 一次性验证用，不进共享仓库，跑完就删。
///    目的：0 要核 iOS 账户页改昵称保存的 POST 路径是否真的到库——
///    我这边跑通登录→账户页改昵称→保存，把填的字符串打进日志，
///    0 拿这串去查库。
final class NickSyncCheck0918: XCTestCase {

    func test0918NickSync() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launch()

        // 首页那颗账户 chip —— 未登录时文案含"登录"。
        let chip = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '登录' OR label CONTAINS 'Sign in'")
        ).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 20), "首页账户入口没找到")
        chip.tap()

        // 登录页：邮箱框
        let emailField = app.textFields.firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "邮箱框没出现")
        emailField.tap()
        // 🚨 第一版这里判断`!v.isEmpty`再点"Clear text"——真机上空文本框的
        //    `.value`会读到占位符文本而不是真空，条件判成true但那个按钮
        //    根本不存在，直接崩。App冷启动这个框本来就是空的，不用清，
        //    直接打字最稳。
        emailField.typeText("kevinyang5425+ios0917@gmail.com")

        let sendBtn = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '获取验证码' OR label CONTAINS '重新获取' "
                        + "OR label CONTAINS 'Send code' OR label CONTAINS 'Resend'")
        ).firstMatch
        XCTAssertTrue(sendBtn.waitForExistence(timeout: 10), "发送验证码按钮没找到")
        sendBtn.tap()

        print("E2E_MARK: CODE_SENT kevinyang5425+ios0917@gmail.com")

        // 轮询 /tmp/ios_e2e_code.txt，最多 9 分钟。
        let codePath = "/tmp/ios_e2e_code.txt"
        var code: String?
        let deadline = Date().addingTimeInterval(540)
        while Date() < deadline {
            if let raw = try? String(contentsOfFile: codePath, encoding: .utf8) {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count == 6 {
                    code = trimmed
                    break
                }
            }
            Thread.sleep(forTimeInterval: 3)
        }
        guard let realCode = code else {
            XCTFail("E2E_MARK: CODE_TIMEOUT 9分钟没等到码")
            return
        }
        print("E2E_MARK: CODE_RECEIVED \(realCode)")

        let codeField = app.textFields.element(boundBy: 1)
        XCTAssertTrue(codeField.waitForExistence(timeout: 10), "验证码框没出现")
        codeField.tap()
        codeField.typeText(realCode)

        let loginBtn = app.buttons["登录"]
        XCTAssertTrue(loginBtn.waitForExistence(timeout: 5), "登录按钮没找到")
        loginBtn.tap()

        print("E2E_MARK: LOGIN_TAPPED")
        Thread.sleep(forTimeInterval: 4)

        // 不管登录后自动跳到哪个页，先弹回首页——这次只测账户页那条路径，
        // 不碰引导页那条（那条 09-17 已经测过一轮）。
        for _ in 0..<5 {
            let backBtn = app.navigationBars.buttons.element(boundBy: 0)
            if backBtn.exists && backBtn.isHittable {
                backBtn.tap()
                Thread.sleep(forTimeInterval: 0.8)
            } else {
                break
            }
        }

        // 首页 chip 现在应该已登录（不再含"登录"字样），再点一次进账户页。
        Thread.sleep(forTimeInterval: 1)
        let chip2 = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '👤'")
        ).firstMatch
        XCTAssertTrue(chip2.waitForExistence(timeout: 10), "登录后首页账户入口没找到")
        chip2.tap()

        let nickRow = app.descendants(matching: .any)["profile_nick"]
        XCTAssertTrue(nickRow.waitForExistence(timeout: 10), "账户页昵称行没找到")
        nickRow.tap()

        let editField = app.alerts.textFields.firstMatch
        XCTAssertTrue(editField.waitForExistence(timeout: 5), "改昵称弹窗没出现")
        editField.tap()
        // 🚨 不信`.value`读到的长度（真机上空/占位符文本会混在一起读错）——
        //    固定打够多退格键，够清掉任何合理长度的昵称就行，多退几下
        //    在空文本框上是安全的（没内容可删）。
        let del = String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40)
        editField.typeText(del)
        let stamp = Int(Date().timeIntervalSince1970)
        let newNick = "e2e-ios-0918-\(stamp)"
        editField.typeText(newNick)

        let saveBtn = app.alerts.buttons["保存"]
        XCTAssertTrue(saveBtn.waitForExistence(timeout: 5), "保存按钮没找到")
        saveBtn.tap()

        Thread.sleep(forTimeInterval: 3)
        print("E2E_MARK: NICK_SAVED \(newNick)")
    }
}
