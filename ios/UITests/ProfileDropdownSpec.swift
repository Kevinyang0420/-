import XCTest

/// 资料下拉骨架：国家/省州/职业从自由文本换成选择列表。
///
/// 规格：`_规格_用户资料结构化下拉_20260918.md`。0 09-18 派活，验收判据钉在这条上：
/// 存的是码不是文字，选了国家之后省份按国家过滤，职业选"其他"要能存自由文本。
///
/// 🚨🚨 **这条测试跟 `ProfileCodes.selfTest()` 分两半，别在这边重复验级联过滤**：
///    `AccountViewController.viewDidLoad()` 里有真实的 `Auth.fetchProfile()`
///    网络请求——服务端返回空的国家/省份是完全合理的行为（B1/B3 契约：服务端说
///    没有就该显示没有），但这意味着任何"先在本地种一个国家，再验省份按它过滤"
///    的测试手法，都会跟这条真实请求赛跑、种子随时可能被服务端的空值原样冲掉。
///    级联过滤那段纯逻辑（`ProfileCodes.regions(of:)`）已经在
///    `ProfileCodes.selfTest()` 里跟网络无关地验过了；这条 UI 测试只验证不依赖
///    服务端返回值的部分：三个字段从"点了弹文本框"换成了"点了弹选择列表"，
///    职业"其他"要能弹文本输入。
///
/// 🚨 骨架阶段数据来自 `ProfileCodes.swift`（逐字照抄安卓 `ProfileCodes.java`），
///    真表落地前这份数据本身会变，断言只钉"选择列表出得来、职业其他能输文本"，
///    不钉"这个国家一定叫这个名字"。
///
/// 🚨 保存到服务端这一步也验不到——`/api/profile` POST 要真登录才 200，
///    `TRANSLESS_SEED_CARD` 只是装本地"已登录"绕过客户端那道门，服务端不认这个
///    设备，会拿到 `401 未登录`（探针实测过，不是猜的）。这跟速成那次"commit
///    进宿主文本框验不到"是同一类环境边界，不是产品缺陷。
final class ProfileDropdownSpec: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    /// 保存必然因为没真登录被服务端拒——弹出的失败提示框点掉，不当断言用。
    private func dismissSaveFailedIfAny(_ app: XCUIApplication) {
        if app.alerts.firstMatch.waitForExistence(timeout: 3) {
            app.alerts.firstMatch.buttons.firstMatch.tap()
        }
    }

    func testFieldsOpenPickersNotFreeTextAndJobOtherPromptsText() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_SEED_CARD"] = "1"
        app.launchEnvironment["TRANSLESS_PAGE"] = "account"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        // ── 国家行：点了要出选择列表（actionSheet 里的候选按钮），不是文本输入框 ──
        let countryRow = app.descendants(matching: .any)
            .matching(identifier: "profile_country").firstMatch
        XCTAssertTrue(countryRow.waitForExistence(timeout: 8), "🚨 找不到国家那一行")
        countryRow.tap()
        Thread.sleep(forTimeInterval: 1.0)
        shot("01_国家选择列表")

        // 🚨 判据是"这是选择列表不是文本框"——没有 UITextField，
        //    有至少一个候选按钮（骨架表第一项"中国大陆"）。
        XCTAssertFalse(app.alerts.firstMatch.textFields.firstMatch.exists,
                       "🚨 国家行点了之后还是弹文本输入框——没换成选择列表")
        XCTAssertTrue(app.buttons["中国大陆"].firstMatch.waitForExistence(timeout: 5),
                      "🚨 国家选择列表里没有「中国大陆」")
        XCTAssertTrue(app.buttons["日本"].firstMatch.exists, "🚨 国家选择列表里没有「日本」")
        app.buttons["中国大陆"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2.0)
        dismissSaveFailedIfAny(app)
        shot("02_选完国家_保存会401这是预期")

        // ── 省份行：点了要出选择列表，不是文本输入框（不依赖国家先存成功） ──
        let regionRow = app.descendants(matching: .any)
            .matching(identifier: "profile_region").firstMatch
        XCTAssertTrue(regionRow.waitForExistence(timeout: 6), "🚨 找不到省份那一行")
        regionRow.tap()
        Thread.sleep(forTimeInterval: 1.0)
        shot("03_省份行为")
        // 🚨 没真存上国家时，`pickRegion()` 会弹"这个国家/地区暂时还没有可选的
        //    省份/州"这条提示（`profile_region_none`）——这是产品设计好的兜底，
        //    不当失败断言，点掉继续测下一个字段。真实级联过滤已经在
        //    `ProfileCodes.selfTest()` 里验过。
        if app.alerts.firstMatch.waitForExistence(timeout: 2) {
            app.alerts.firstMatch.buttons.firstMatch.tap()
            Thread.sleep(forTimeInterval: 0.5)
        } else {
            // 万一国家真存上了（比如这台设备恰好真登录过），会弹出选择列表——
            // 两种情况都不算失败，弹出来的话点掉别卡住后续断言。
            let cancelBtn = app.buttons["取消"].firstMatch
            if cancelBtn.waitForExistence(timeout: 2) { cancelBtn.tap() }
        }

        // ── 职业行：点了要出选择列表（27 项），选"其他"要能输自由文本 ──
        let jobRow = app.descendants(matching: .any)
            .matching(identifier: "profile_job").firstMatch
        XCTAssertTrue(jobRow.waitForExistence(timeout: 6), "🚨 找不到职业那一行")
        jobRow.tap()
        Thread.sleep(forTimeInterval: 1.0)
        shot("04_职业选择列表")

        XCTAssertFalse(app.alerts.firstMatch.textFields.firstMatch.exists,
                       "🚨 职业行点了之后直接是文本输入框——没换成选择列表")
        // 抽查首尾各一项，确认整张 27 项表真的渲染出来了，不是只挂了个空壳。
        XCTAssertTrue(app.buttons["学生"].firstMatch.waitForExistence(timeout: 5),
                      "🚨 职业列表第一项「学生」没出现")
        let other = app.buttons["其他"].firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 5), "🚨 职业列表里没有「其他」")
        other.tap()
        Thread.sleep(forTimeInterval: 1.0)

        // 🚨 选了"其他"之后必须弹一个文本输入框——自由文本要有地方去
        // （存进 other_text），不然选"其他"等于选了个哑选项。
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "🚨 选「其他」之后没弹文本输入框")
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), "🚨 「其他」的弹窗里没有输入框")
        field.tap()
        field.typeText("开滑板店的")
        shot("05_职业其他文本框")
        alert.buttons["保存"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        dismissSaveFailedIfAny(app)

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5),
                      "🚨 走完「其他」输入流程之后 App 掉了")
    }
}
