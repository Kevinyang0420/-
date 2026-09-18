import XCTest

/// 资料下拉：「地区」从两个并排的选择列表换成**钻取导航**，职业保持选择列表。
///
/// 规格：`_规格_用户资料结构化下拉_20260918.md`。0 09-18 二订打回骨架版
/// （三个并排 actionSheet），要的是「不需要既有国家地区又有省份……进到广东省
/// 还可以再点一下」——`CountryListViewController` → `RegionListViewController`
/// 两级 push，选完 pop 回账户页，上一级能返回改。
///
/// 🚨🚨 级联过滤那段纯逻辑（`ProfileCodes.regions(of:)`）在 `ProfileCodes.selfTest()`
///    里跟网络无关地验过了，这条 UI 测试不重复验；这条只验证**导航本身走得通**：
///    有省州的国家会钻进省份列表，没有省州的国家直接收工不弹空列表。
///
/// 🚨 保存到服务端这一步验不到——`/api/profile` POST 要真登录才 200，
///    `TRANSLESS_SEED_CARD` 只是装本地"已登录"绕过客户端那道门，服务端不认这个
///    设备，会拿到 `401 未登录`（探针实测过，不是猜的）。这跟速成那次"commit
///    进宿主文本框验不到"是同一类环境边界，不是产品缺陷——所以这条测试断言
///    停在"导航走对了、回到账户页了"，不断言"账户页显示的值真的更新了"。
final class ProfileDropdownSpec: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func launchToAccount() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_SEED_CARD"] = "1"
        app.launchEnvironment["TRANSLESS_PAGE"] = "account"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        return app
    }

    /// 有省州的国家：地区 → 国家列表 → 选中国大陆 → 钻进省份列表 → 选广东省 → 回账户页。
    func testCountryWithRegionsDrillsDownThenReturnsToAccount() throws {
        let app = launchToAccount()

        let areaRow = app.descendants(matching: .any)
            .matching(identifier: "profile_area").firstMatch
        XCTAssertTrue(areaRow.waitForExistence(timeout: 8), "🚨 找不到「地区」那一行")
        areaRow.tap()
        Thread.sleep(forTimeInterval: 1.0)
        shot("01_国家列表")

        // 🚨 判据是"这是钻取列表页不是 actionSheet"——有搜索框（骨架版没有）。
        XCTAssertTrue(app.textFields["country.search"].waitForExistence(timeout: 5),
                      "🚨 国家列表页没有搜索框——是不是还在走旧的 actionSheet")

        // 🚨🚨 09-18 四订③：0 把判据从「12+ 行」钉死成「≥17 行」（iPhone 15/16
        //    类）。**数可见格数，不数公式算出来的理论值**——`isHittable` 只对
        //    真正落在屏幕可见区域内、能被点到的 cell 为真，跟眼睛看到的一致。
        let visibleRows = app.cells.allElementsBoundByIndex.filter { $0.isHittable }.count
        XCTAssertGreaterThanOrEqual(visibleRows, 17,
            "🚨 一屏可见行数只有 \(visibleRows)，没达到 0 钉死的 ≥17 行判据")

        // 🚨🚨 09-18 四订⑤：常用区不再是写死的 6 国，改成系统区域推断+最近
        //    选过两槽——这台模拟器的系统区域解出来是香港不是大陆，「中国大陆」
        //    不再保证不滚动就能看见（这是对的：它现在跟着设备区域走，不是
        //    测试环境凑巧对不上）。**用搜索框找**，跟下面「南极洲」那条
        //    测试同一个套路，不假设常用区里有什么。
        let search = app.textFields["country.search"]
        search.tap()
        search.typeText("中国大陆")
        Thread.sleep(forTimeInterval: 0.5)
        let cn = app.staticTexts["中国大陆"].firstMatch
        XCTAssertTrue(cn.waitForExistence(timeout: 5), "🚨 搜索「中国大陆」之后列表里没有它")
        cn.tap()
        Thread.sleep(forTimeInterval: 1.0)
        shot("02_钻进省份列表")

        // ── 中国大陆有省州数据，应该钻进省份列表，不该直接弹回账户页 ──
        let gd = app.staticTexts["广东省"].firstMatch
        XCTAssertTrue(gd.waitForExistence(timeout: 5),
                      "🚨 选了中国大陆之后没有钻进省份列表（没看到「广东省」）——"
                      + "级联跟导航没接上")
        // 🚨 反向对照：日本的地址不该混进中国的省份列表。
        XCTAssertFalse(app.staticTexts["东京都"].exists,
                       "🚨 中国的省份列表里混进了「东京都」——级联过滤没生效")
        gd.tap()
        Thread.sleep(forTimeInterval: 1.5)
        shot("03_选完省份回到账户页")

        // ── 选完省份应该一路 pop 回账户页（标题"我的账户"），不是停在某个中间页 ──
        XCTAssertTrue(app.navigationBars["我的账户"].waitForExistence(timeout: 6),
                      "🚨 选完省份没有回到账户页——pop 链没接对，可能停在了省份列表")
        // 保存会因为没真登录被服务端 401，弹出的失败提示不是断言对象，点掉即可。
        if app.alerts.firstMatch.waitForExistence(timeout: 2) {
            app.alerts.firstMatch.buttons.firstMatch.tap()
        }
    }

    /// 没有省州的国家（南极洲）：选了直接收工，**不弹空列表**、不停在省份页。
    func testCountryWithoutRegionsSkipsStraightBack() throws {
        let app = launchToAccount()

        let areaRow = app.descendants(matching: .any)
            .matching(identifier: "profile_area").firstMatch
        XCTAssertTrue(areaRow.waitForExistence(timeout: 8), "🚨 找不到「地区」那一行")
        areaRow.tap()
        Thread.sleep(forTimeInterval: 1.0)

        // 南极洲在骨架数据里没有任何省州条目——用搜索框缩小范围，
        // 249 项的列表里直接找"南极洲"三个字可能因为没滚到而找不到。
        let search = app.textFields["country.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "🚨 国家列表页没有搜索框")
        search.tap()
        search.typeText("南极洲")
        Thread.sleep(forTimeInterval: 0.8)
        shot("04_搜索南极洲")

        let aq = app.staticTexts["南极洲"].firstMatch
        XCTAssertTrue(aq.waitForExistence(timeout: 5), "🚨 搜索「南极洲」之后列表里没有它")
        aq.tap()
        Thread.sleep(forTimeInterval: 1.5)
        shot("05_选完南极洲直接回账户页")

        // 🚨 没有省州数据 → 直接收工回账户页，不该停在一个空的省份列表页。
        XCTAssertTrue(app.navigationBars["我的账户"].waitForExistence(timeout: 6),
                      "🚨 选了没有省州数据的国家之后没有直接回账户页——"
                      + "可能停在了一个空的省份列表，或者弹出了提示框")
        if app.alerts.firstMatch.waitForExistence(timeout: 2) {
            app.alerts.firstMatch.buttons.firstMatch.tap()
        }
    }

    /// 职业选"其他"要能弹文本输入。
    ///
    /// 🚨 09-18 三订：职业从 actionSheet 换成跟国家/省州同款的紧凑
    ///    `UITableView` 列表页（Kevin「27 条都嫌长」）。
    /// 🚨 09-18 四订①：Grok 审出「27 条全屏 push 列表」才是结构根因，
    ///    再换一版——半高 sheet + 双列 chip（见 `JobListViewController`
    ///    类注释），不再是 push 到新页面。候选还是 `staticTexts`（chip
    ///    里是 `UILabel`，跟表格行一样能被 XCUITest 认出来），但断言要
    ///    多加一条：sheet 弹出时「我的账户」导航栏**必须还在**——这是区分
    ///    「半高 sheet 盖在上面」和「整页 push 走掉」的硬证据，不是猜的。
    func testJobOtherStillPromptsFreeText() throws {
        let app = launchToAccount()

        let jobRow = app.descendants(matching: .any)
            .matching(identifier: "profile_job").firstMatch
        XCTAssertTrue(jobRow.waitForExistence(timeout: 8), "🚨 找不到职业那一行")
        jobRow.tap()
        Thread.sleep(forTimeInterval: 1.0)

        XCTAssertFalse(app.alerts.firstMatch.textFields.firstMatch.exists,
                       "🚨 职业行点了之后直接是文本输入框——没有选择列表")
        // 🚨 半高 sheet 的硬证据：账户页导航栏还在（没有整页 push 走）。
        XCTAssertTrue(app.navigationBars["我的账户"].exists,
                      "🚨 职业选择器弹出后「我的账户」导航栏不见了——像是整页 push"
                      + "走了，不是半高 sheet 盖上去")
        shot("06_职业半高sheet双列chip")
        // 抽查首项，确认整张 27 项表真的渲染出来了，不是只挂了个空壳。
        XCTAssertTrue(app.staticTexts["学生"].firstMatch.waitForExistence(timeout: 5),
                      "🚨 职业列表第一项「学生」没出现")
        // 🚨🚨 09-18 四订①真机实测发现：27 项两列在 58% 半高 sheet 里装不满
        //    （最后一两行在折叠线以下），"其他"是第 27 项、排最后，不滑不可见
        //    ——**这是真实布局约束，不是测试环境的意外**。sheet 挂了
        //    `.large()` 第二档，`prefersScrollingExpandsWhenScrolledToEdge`
        //    默认开着，往上一划会把 sheet 拉到全屏，露出全部 27 项。
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        let other = app.staticTexts["其他"].firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 5), "🚨 职业列表里没有「其他」")
        other.tap()
        Thread.sleep(forTimeInterval: 1.0)

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "🚨 选「其他」之后没弹文本输入框")
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), "🚨 「其他」的弹窗里没有输入框")
        field.tap()
        field.typeText("开滑板店的")
        alert.buttons["保存"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        if app.alerts.firstMatch.waitForExistence(timeout: 3) {
            app.alerts.firstMatch.buttons.firstMatch.tap()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5),
                      "🚨 走完「其他」输入流程之后 App 掉了")
    }
}
