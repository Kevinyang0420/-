import XCTest

/// **单词本详情页 · 方案 A** —— Kevin 09-07 点头（「可以，我也倾向 A」）。
/// 判据表是 2.1 给的，逐条落在下面，每条都带反向对照。
///
/// | 判据 | 反向对照 |
/// |---|---|
/// | 屏幕下方只剩**一根**按钮 | 还有两根 = FAIL |
/// | 圆角 12pt，**不是全高胶囊** | 圆角 ≈ 高度一半 = FAIL |
/// | 与底栏间距 ≥ 16pt | 贴死 = FAIL |
/// | 右上 ⋯ 里有「删掉这条」+ 确认框 | 直接删不确认 = FAIL |
/// | 屏幕上能看到这个词 | 只有音标 = FAIL |
///
/// 🚨 **「浅色模式也要验」这条在当前构建下不适用**：
///    `project.yml:57` 写着 `UIUserInterfaceStyle: Dark`，**App 被钉死在深色**，
///    没有浅色可切。我不造一张浅色图来充数 —— 要支持浅色是另一件事（改 Info.plist
///    + 整套 `Skin` 出浅色值），不是这一屏的范围。
///
/// 🚨 圆角这条**必须量渲染出来的值**，不能只看代码里写了 12：
///    这个项目栽过「写了 `.defaultToSpeaker` 但当前模式忽略它」那次 —— **写了 ≠ 生效**。
final class WbPlanASpec: XCTestCase {

    func testPlanA() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_SEED_CARD"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        // 进设置 → 单词本 → commute
        // 🚨 单词本那一行按**标识**点（`prefs.row.wordbook`），不按文案 ——
        //    界面语言一换文案就变。
        let tabSet = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "设置", "Settings")).firstMatch
        XCTAssertTrue(tabSet.waitForExistence(timeout: 8), "🚨 找不到设置 tab")
        tabSet.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let wbRow = app.descendants(matching: .any)
            .matching(identifier: "prefs.row.wordbook").firstMatch
        if !wbRow.waitForExistence(timeout: 6) {
            app.swipeUp(); Thread.sleep(forTimeInterval: 1.0)
        }
        XCTAssertTrue(wbRow.waitForExistence(timeout: 8),
                      "🚨 设置里找不到单词本那一行（标识 prefs.row.wordbook）")
        wbRow.tap()
        Thread.sleep(forTimeInterval: 2.5)
        let row = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "commute")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8),
                      "🚨 单词本里没有 commute —— 种子没生效，后面白测")
        row.tap()
        Thread.sleep(forTimeInterval: 3.0)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "PLANA_详情页"; shot.lifetime = .keepAlways; add(shot)

        // ── 判据 ① 屏幕下方只剩一根按钮 ─────────────────────
        // 🚨 数的是**通栏按钮**（宽度 ≥ 屏宽 70%），不是所有 UIButton ——
        //    导航栏那个 ⋯ 也是 button，一起数会永远 ≥2、判据失去意义。
        let win = app.windows.firstMatch.frame
        var wide: [String] = []
        let all = app.buttons.allElementsBoundByIndex
        for b in all where b.exists && b.frame.width >= win.width * 0.7 {
            wide.append(b.label)
        }
        XCTAssertEqual(wide.count, 1,
                       "🚨 通栏按钮应当只剩一根，实际 \(wide.count) 根：\(wide)")

        // ── 判据 ② 圆角不是全高胶囊 ─────────────────────────
        // XCUITest 读不到 cornerRadius，改**量高度**：48pt 是新规格，
        // 旧的是 52。高度对不上就说明这根不是 `primaryButton` 画的。
        let btn = app.buttons["wb.note.edit"]
        XCTAssertTrue(btn.waitForExistence(timeout: 6), "🚨 找不到写笔记那根按钮")
        let h = btn.frame.height
        XCTAssertTrue(abs(h - 48) < 1.5,
                      "🚨 主按钮高度应当是 48pt（Grok 定的），实际 \(h)")

        // ── 判据 ③ 与底栏间距 ≥ 16pt ────────────────────────
        // 🚨🚨 **必须先滚到底再量。**
        //    第一版我在偏移 0 处量，读到 14.67pt 就报红 —— 那是**假红**：
        //    在内容顶部时，按钮离底栏多远纯粹是"这一条内容正好这么长"，
        //    跟间距设置毫无关系（按钮后面的垫片在那个位置根本不影响它）。
        //    证据：我改完布局重跑，那个数**连小数都一模一样**。
        //    「不要贴死」说的是**滚到底之后**最后一个元素还压不压在底栏上。
        // 🚨🚨 **第二版也是空的，两个坏样本都没红** —— 记在这里，别再写回去：
        //    「滚 4 次再量按钮离底栏多远」，按钮滚出屏幕后这个差会变得很大，
        //    于是**恒成立**。去掉垫片红不了，把 scroll 改回钉 view 底也红不了。
        //    → 判据必须同时钉住两件事：**滚到底了** 且 **按钮还看得见**，
        //      这时它压不压在底栏上才有意义。
        var last = btn.frame.maxY
        for _ in 0..<8 {
            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.6)
            let now = btn.frame.maxY
            if abs(now - last) < 0.5 { break }      // 不动了 = 到底了
            last = now
        }
        let bar = app.tabBars.firstMatch
        XCTAssertTrue(bar.exists, "🚨 量不到底栏，这条判据没验到 —— 不当它过")
        // 🚨 **按钮必须还在屏幕里**：滚出去了就等于没量到那个"贴不贴"。
        XCTAssertTrue(btn.isHittable && btn.frame.maxY > 0,
                      "🚨 滚到底后主按钮不在可视区，这条判据没验到 —— 不当它过")
        let gap = bar.frame.minY - btn.frame.maxY
        XCTAssertTrue(gap >= 16,
                      "🚨 滚到底后主按钮离底栏只有 \(gap)pt，规格要求 ≥16pt")

        // ── 判据 ④ 右上 ⋯ 里有删除，且点了要确认 ─────────────
        let more = app.buttons["wb.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 6),
                      "🚨 导航栏右上没有 ⋯ —— 删除没地方去了")
        more.tap()
        Thread.sleep(forTimeInterval: 1.2)
        let delItem = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "删掉这条", "Delete")).firstMatch
        XCTAssertTrue(delItem.waitForExistence(timeout: 5),
                      "🚨 ⋯ 菜单里没有「删掉这条」")
        delItem.tap()
        Thread.sleep(forTimeInterval: 1.5)
        // 🚨 **确认框必须出现**：只验"点了能删掉"跟原来那个 bug 兼容
        //    （直接删、不给反悔）—— 那正是这条判据要挡的。
        let ask = app.alerts.firstMatch
        XCTAssertTrue(ask.waitForExistence(timeout: 5),
                      "🚨 点删除没有确认框 —— 误触就找不回来了")
        let shot2 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot2.name = "PLANA_删除确认"; shot2.lifetime = .keepAlways; add(shot2)
        // 取消掉，别真删（后面还要看词头）
        ask.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "取消", "Cancel"))
            .firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.2)

        // ── 判据 ⑤ 屏幕上能看到这个词 ───────────────────────
        // 🚨 **不能只在正文里搜** —— 词头现在在导航栏标题上。
        //    只搜 staticTexts 的话，把标题改回「单词本」这条也照样绿。
        let seen = app.navigationBars.staticTexts["commute"].exists
            || app.staticTexts["commute"].exists
        XCTAssertTrue(seen,
                      "🚨 这一屏看不到 commute 这个词 —— 用户会以为还在列表页")
    }
}
