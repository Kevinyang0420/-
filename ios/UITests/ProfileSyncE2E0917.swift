import XCTest

/// 一次性 e2e：真实登录 → 完善资料页填昵称 → 保存，验证
/// `Auth.saveProfile` 真的发出了 POST（0 派活 09-17，判据是库里有没有，
/// 不是代码看起来对不对）。
///
/// 🚨 验证码走真实收发：`tapSend()` 之后停下来，**用文件做投递箱**
/// （`/tmp/ios_e2e_code.txt`），轮询等外部把码写进去——0 在 Gmail
/// 里实时读码，我通过另一条 SSH 把码写进这个文件，不用改任何
/// 生产代码、不用塞假 token。
///
/// 这个文件跑完这一次就该删掉，不是常驻测试——`TEST_EMAIL`/
/// `TEST_NICKNAME` 都是硬编码这一次性的值，不具备复用价值。
final class ProfileSyncE2E0917: XCTestCase {

    func testRealLoginThenSaveNickname() throws {
        // 🚨 裸 `XCUIApplication()` 在这个 scheme 下默认起的是 `TransProbe`
        //    （这个工程的另一个 target，探针用），不是 Transless——真跑才
        //    从 `app.debugDescription` 里看出 `label: 'TransProbe'`。
        //    跟 `NotesE2E.swift` 同一个写法，显式给 bundle id。
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_UILANG_RESET"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 2.0)

        // ① 点首页右上角账号胶囊（未登录态标题含"登录"/"Sign in"）进登录页。
        let acctChip = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
            "登录", "Sign in")).firstMatch
        if !acctChip.waitForExistence(timeout: 10) {
            print("E2E_TREE_DUMP_BEGIN")
            print(app.debugDescription)
            print("E2E_TREE_DUMP_END")
        }
        XCTAssertTrue(acctChip.exists, "找不到账号入口")
        print("E2E_MARK: tapping account chip")
        acctChip.tap()
        Thread.sleep(forTimeInterval: 1.5)

        // ② 邮箱是默认 tab，直接填邮箱（只有一个文本框可见，codeField 还藏着）。
        let emailField = app.textFields.firstMatch
        XCTAssertTrue(emailField.waitForExistence(timeout: 10), "找不到邮箱输入框")
        emailField.tap()
        let email = "kevinyang5425+ios0917@gmail.com"
        emailField.typeText(email)
        print("E2E_MARK: typed email \(email)")

        // ③ 点发送验证码——这一刻真实触发短信/邮箱发码。
        let sendBtn = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
            "获取验证码", "Send code")).firstMatch
        XCTAssertTrue(sendBtn.waitForExistence(timeout: 5), "找不到发送验证码按钮")
        sendBtn.tap()
        // 🚨 这一行是给外部脚本认的锚点——看到它就该去发"码发了"的消息。
        print("E2E_MARK: CODE_SENT")

        // ④ 轮询等外部把验证码写进这个文件（0 从 Gmail 读码后写入）。
        let codePath = "/tmp/ios_e2e_code.txt"
        var code = ""
        let deadline = Date().addingTimeInterval(9 * 60)
        while Date() < deadline {
            if let s = try? String(contentsOfFile: codePath, encoding: .utf8) {
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { code = trimmed; break }
            }
            Thread.sleep(forTimeInterval: 3)
        }
        XCTAssertFalse(code.isEmpty, "9 分钟内没等到验证码文件——码没送到或没人写文件")
        print("E2E_MARK: got code, length=\(code.count)")

        // ⑤ 验证码框这时候才出现，填码登录。
        let codeField = app.textFields.element(boundBy: 1)
        XCTAssertTrue(codeField.waitForExistence(timeout: 5), "验证码框没出现")
        codeField.tap()
        codeField.typeText(code)
        let loginBtn = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
            "登录", "Sign in")).element(boundBy: 1)
        loginBtn.tap()
        print("E2E_MARK: tapped login")
        Thread.sleep(forTimeInterval: 3.0)

        // ⑥ 这个邮箱地址服务端从没存过昵称，B1/B3 会自动判定"没填过"并
        //    跳到完善资料页（`ProfileViewController`）——不用我再手动导航。
        let nickField = app.textFields.firstMatch
        XCTAssertTrue(nickField.waitForExistence(timeout: 15),
                      "没跳到完善资料页——可能验证码错了或登录失败")

        // 清空预填的邮箱前缀，换成一个能在库里认出来的字符串。
        nickField.tap()
        if let existing = nickField.value as? String, !existing.isEmpty {
            let deleteStr = String(repeating: XCUIKeyboardKey.delete.rawValue,
                                   count: existing.count)
            nickField.typeText(deleteStr)
        }
        let nickname = "e2e-ios-0917-\(Int(Date().timeIntervalSince1970))"
        nickField.typeText(nickname)
        print("E2E_MARK: NICKNAME=\(nickname)")

        let doneBtn = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@",
            "完成", "Done")).firstMatch
        XCTAssertTrue(doneBtn.waitForExistence(timeout: 5), "找不到完成按钮")
        XCTAssertTrue(doneBtn.isEnabled, "完成按钮是灰的")
        doneBtn.tap()
        print("E2E_MARK: tapped done, POST should have fired")
        Thread.sleep(forTimeInterval: 3.0)
        print("E2E_MARK: TEST_COMPLETE")
    }
}
