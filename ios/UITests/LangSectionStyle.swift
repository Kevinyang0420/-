import XCTest

/// **方案丙：两段一眼看上去不是同一种东西**（Kevin 2026-09-05 拍板）。
///
/// 🚨🚨 **这个用例只能验丙的一半，另一半必须人眼。先说清界限，别假装覆盖了全部。**
///
/// | 丙要的 | 能不能机检 |
/// |---|---|
/// | 「最近用过」用的是 chips 控件、不是列表行 | ✅ 标识不同（`lang.chip` vs `transless.lang.*`） |
/// | 「全部语言」完整不删（含最近用过那几门） | ✅ 数条目 |
/// | 选中只画一个勾 | ✅ `isSelected` 计数 |
/// | **chips 更扁、描边不填充、看上去不同类** | ❌ **XCUI 读不到高度和填充色** —— 靠截图人眼 |
///
/// 🚨 最后一条我**没有硬凑一个机检判据** —— 凑出来的那种（比如"chip 的 frame 高度 < 行高"）
///    在 XCUI 里量的是可点击区域不是视觉高度，**量的对象跟结论说的对象不是一个**。
///    宁可写明"这一条靠人眼"，也不要一个看起来绿、其实没验的判据。
final class LangSectionStyle: XCTestCase {

    func testRecentIsChipsNotRows() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "speak"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_SEED_RECENT"] = "ja,fr,en"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        let langBtn = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "译成")).firstMatch
        XCTAssertTrue(langBtn.waitForExistence(timeout: 10), "🚨 语言钮不在")
        langBtn.tap()
        Thread.sleep(forTimeInterval: 1.5)

        // ① 选中只画一个勾（这条早前就有，保留）
        let checked = app.descendants(matching: .any)
            .matching(NSPredicate(format: "selected == true"))
        XCTAssertEqual(checked.count, 1,
            "🚨 带勾的行 \(checked.count) 个：0=谓词量不到（判据没用），2=双勾回来了")

        // ② 「全部语言」**完整不删** —— 丙跟我上午做的去重相反，
        //    所以这一条要能抓到"有人又去重了"。
        //    判据：菜单里「英文」出现次数 ≥2（最近用过一次 + 全部语言一次）。
        //    🚨 注意这条**跟去重版的判据正好相反** —— 09-05 上午我按"重复=bug"
        //    写过一条「≤1」，Kevin 拍丙之后它就成了守着错误产品意图的判据。
        //    **产品意图变了，判据要跟着翻面，不是留着两条互相打架。**
        let en = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "英文"))
        NSLog("STYLE 英文出现 %d 次；带勾 %d 个", en.count, checked.count)
        XCTAssertGreaterThanOrEqual(en.count, 2,
            "🚨 「英文」只出现 \(en.count) 次 —— 丙要求「全部语言」完整保留，是不是又被去重了？")

        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "丙_两段分层"; a.lifetime = .keepAlways; add(a)
    }
}
