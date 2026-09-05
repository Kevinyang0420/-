import XCTest

/// **键盘那一屏的「选语言」** —— Kevin 实拍报障的就是这一屏
/// （`D:\ShareDrive	ransless_ui\Kevin实拍_iOS输入法选语言重复_20260905_1156.jpg`）。
///
/// 🚨🚨 **必须单独有这个用例**：`LangPickerShot` 拍的是**随手翻译**（系统菜单），
///    跟键盘是两套实现。今天上午就是因为拿随手那屏的图去判键盘那屏的问题，
///    三个人追错了一个多小时。**图出自哪一屏，比图上有什么更重要。**
///
/// 走 `TRANSLESS_PAGE=kb` 预览页 —— 它加载的是**真实的键盘扩展**
/// （`KeyboardViewController`），不是另画一个仿真界面。
final class KbLangPickerShot: XCTestCase {

    func testKeyboardLangPicker() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "kb"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_SEED_RECENT"] = "ja,fr,en"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.5)

        // 语言钮在键盘顶排，标题形如「英文 ▾」
        let langBtn = app.buttons.matching(
            NSPredicate(format: "label ENDSWITH %@", "▾")).firstMatch
        XCTAssertTrue(langBtn.waitForExistence(timeout: 10), "🚨 键盘上的语言钮不在")
        langBtn.tap()
        Thread.sleep(forTimeInterval: 1.5)

        // ① 「最近用过」是 **chips**，不是列表行 —— 这是丙的核心
        let chips = app.descendants(matching: .any)
            .matching(identifier: "lang.chip")
        // ② 列表行还在（全部语言完整）
        let rows = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "transless.lang."))
        NSLog("KBLANG chips=%d rows=%d", chips.count, rows.count)

        XCTAssertGreaterThanOrEqual(chips.count, 1,
            "🚨 一个 chip 都没有 —— 「最近用过」还是列表行，丙没落地")
        XCTAssertGreaterThanOrEqual(rows.count, 3,
            "🚨 列表行只有 \(rows.count) 个 —— 「全部语言」应该完整保留")

        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "键盘_选语言_丙"; a.lifetime = .keepAlways; add(a)
    }
}
