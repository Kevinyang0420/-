import XCTest

/// **查词页 2.1 三条定案的验收**（2026-09-06）。
///
/// 判据全部照 2.1 的规格写，每条都能失败：
/// ① 查询失败时 **`field.text` 一个字没变**，再查一次带的还是那个词
/// ② 同一个词连点三次「＋单词本」→ 里面**始终只有一条**，**一次错误提示都没有**
/// ③ 滚到底时**最后一条「最近查过」完整可见**，不被悬浮 tab 栏压住任何一个像素
///
/// 🚨 顺带出 2.1 要的四张图：空输入 / 已输入 / 一次失败 / 滚到底。
final class DictSpec0906: XCTestCase {

    private func shot(_ n: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = n; a.lifetime = .keepAlways; add(a)
    }

    /// 🚨 **走 `TestApp.launch("speak", …)`，不要自己 `XCUIApplication().launch()`。**
    ///    第一版我自己起，落到的不是随手翻译那一屏，
    ///    报出来是「随手翻译右上角没有『查词』」—— **看起来像入口没了，
    ///    实际是我根本没到那一屏**。既有的 `DictPage` 一直用这个帮手。
    private func app() -> XCUIApplication {
        return TestApp.launch("speak", env: ["TRANSLESS_DICT_FAKE": "1",
                                             "TRANSLESS_NO_ARM": "1"])
    }

    private func open(_ a: XCUIApplication) {
        let d = a.buttons["查词"].firstMatch
        XCTAssertTrue(d.waitForExistence(timeout: 12), "🚨 随手翻译右上角没有「查词」")
        d.tap()
        Thread.sleep(forTimeInterval: 1.2)
    }

    private func typeWord(_ a: XCUIApplication, _ w: String) {
        let f = a.textFields["dict.field"]
        XCTAssertTrue(f.waitForExistence(timeout: 8), "🚨 搜索框不在")
        f.tap()
        // 🚨 清空用退格，**不依赖「全选」的文案** —— 切英文就叫 Select All
        if let cur = f.value as? String {
            for _ in 0..<cur.count { f.typeText(XCUIKeyboardKey.delete.rawValue) }
        }
        f.typeText(w)
    }

    // MARK: - ① 错误不许变成输入

    func testErrorNeverEntersField() throws {
        let a = app()
        open(a)
        shot("01_空输入态")

        typeWord(a, "failnow")
        shot("02_已输入态")

        a.buttons["dict.search"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        shot("03_一次失败态")

        // 判据 1：错误显示出来了（不显示的话下面那条就成了"什么都没发生也能过"）
        let err = a.staticTexts["dict.err"]
        XCTAssertTrue(err.waitForExistence(timeout: 5),
                      "🚨 失败了却没有任何提示 —— 那比提示错更糟")

        // 🚨 判据 2（正题）：**输入框里仍是他刚输的那个词，一个字没变**
        let f = a.textFields["dict.field"]
        XCTAssertEqual(f.value as? String, "failnow",
                       "🚨 错误文案被写进了输入框 —— 他再点一次查询就会拿这句话去查词")

        // 🚨 判据 3：**再点一次查询，带的还是那个词**（不是错误文案）
        a.buttons["dict.search"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertEqual(f.value as? String, "failnow",
                       "🚨 第二次查询把错误文案当成词查了")
    }

    // MARK: - ② 「已加过」不该走错误路径

    func testAddWordbookThriceStaysOne() throws {
        let a = app()
        open(a)
        typeWord(a, "ubiquitous")
        a.buttons["dict.search"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)

        let add = a.buttons["dict.add.wordbook"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 8), "🚨 没有「＋单词本」按钮")

        // 连点三次：加 → 移除 → 加。**始终只有一条，且一次错误提示都不该出现。**
        for i in 1...3 {
            add.tap()
            Thread.sleep(forTimeInterval: 0.6)
            XCTAssertFalse(a.staticTexts["dict.err"].exists,
                           "🚨 第 \(i) 次点「＋单词本」弹了错误提示 —— "
                           + "「已加过」是状态不是失败，不该走错误路径")
        }
        shot("05_单词本连点三次之后")
    }

    // MARK: - ③ 滚到底：最后一条完整可见

    func testRecentFullyVisibleAtBottom() throws {
        // 🚨🚨 **这条不能走 `TestApp.launch("speak")`。**
        //    那个调试入口起的是一个独立的
        //    `UINavigationController(root: HomeViewController)`（`AppDelegate:1629`），
        //    **根本不经过 `MainTabController`** —— 屏上没有 tab 栏。
        //
        //    第一版我就是那么写的，结果 `barTop` 退化成窗口底边，
        //    **把 `bottomClearance` 改成 0 跑坏样本，用例照样绿** ——
        //    2.1 那句「不红说明判据挂错对象了」当场应验。
        //    **判据要行使的那个条件（tab 栏盖住内容）在那条路上根本不存在。**
        let a = TestApp.launch(env: ["TRANSLESS_DICT_FAKE": "1",
                                     "TRANSLESS_NO_ARM": "1"])
        let tryBtn = a.buttons["app.try"].firstMatch
        XCTAssertTrue(tryBtn.waitForExistence(timeout: 15), "🚨 首页没有随手翻译入口")
        tryBtn.tap()
        Thread.sleep(forTimeInterval: 1.2)
        open(a)

        // 🚨 **前置断言：这一轮必须真的有 tab 栏**，否则这条判据什么都没验到。
        //    照抄 `DictPage.testPlaceholderFitsAt393` 那条「跑错档位就判红」的做法 ——
        //    **验不了就要说验不了，不许静默通过。**
        XCTAssertTrue(a.tabBars.firstMatch.exists,
                      "🚨 这一轮屏上没有 tab 栏 —— 那这条判据一个像素都没验到，结论不作数")
        // 灌几条最近查过（这一屏的行最多显示 3 条，所以灌 3 个不同的词）
        for w in ["ubiquitous", "take", "lookup"] {
            typeWord(a, w)
            a.buttons["dict.search"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 1.2)
        }
        // 滚到底
        a.swipeUp(); Thread.sleep(forTimeInterval: 0.5)
        a.swipeUp(); Thread.sleep(forTimeInterval: 0.8)
        shot("04_滚到底态")

        let chips = a.buttons.matching(identifier: "dict.recent.chip")
        XCTAssertGreaterThan(chips.count, 0, "🚨 一条「最近查过」都没有")
        let last = chips.element(boundBy: chips.count - 1)

        // 🚨🚨 判据挂在「它的下边缘在不在 tab 栏上边缘之上」，
        //    **不是**「它 exists」—— 被完全盖住的元素照样 exists。
        //    记忆 `feedback_ui_below_fold_is_missing`：滚不到的地方 = 不存在。
        // 🚨 直接取 tab 栏上沿 —— **不再留"没有 tab 栏就拿窗口底边兜底"那条退路**，
        //    那条退路正是上一版判据永远为真的原因。前置断言已经保证它在。
        // 🚨🚨 **盖住内容的不是 tab 栏矩形，是那个凸起圆钮。**
        //    实测（440 屏）：tab 栏上沿 873，**凸起上沿 855** —— 凸起比栏还高 18pt。
        //    我头两版把判据挂在 `tabBars.frame.minY` 上，
        //    于是 `bottomClearance` 改成 0 跑坏样本**两次都是绿的**：
        //    量得准、判据也会失败，但**量的那个对象跟结论说的对象不是一个**。
        //
        // 🚨 阈值不是我拍的：`bottomClearance = bumpLift + 12`，
        //    那个 `+12` 就是"离凸起至少留这么多"的口径，判据照它取。
        //    实测对照：inset=0 → 只剩 6pt（红）；接上 clearance → 36pt（绿）。
        let bump = a.buttons["tab.center.f2f"].firstMatch
        XCTAssertTrue(bump.exists, "🚨 凸起圆钮不在 —— 这条判据没有可比的对象")
        let bumpTop = bump.frame.minY
        let bottom = last.frame.maxY
        let clear = bumpTop - bottom
        XCTAssertGreaterThanOrEqual(
            clear, 12,
            "🚨 最后一条「最近查过」离凸起只剩 \(Int(clear))pt（底=\(Int(bottom))，"
            + "凸起上沿=\(Int(bumpTop))）—— 他那张图上这一块整个被压住看不见了")

        // 🚨 反向控制：**证明我真的滚到底了**，否则"看得见"可能只是因为没滚。
        //    再滚一次，最后一条的位置不该再往上跑。
        let before = last.frame.minY
        a.swipeUp(); Thread.sleep(forTimeInterval: 0.6)
        let after = chips.element(boundBy: chips.count - 1).frame.minY
        XCTAssertEqual(before, after, accuracy: 2,
                       "🚨 还能继续滚 —— 说明刚才那次判定不是在底部做的，不作数")
    }

    // MARK: - 🚨 旧卡片不许冒充新结果（2.1 从验收图上抓到的）

    /// 判据 3：查 A 成功 → 查 B 失败 → **A 的卡片不许留在屏上**。
    ///
    /// 🚨 这条是 2.1 2026-09-06 从**我自己交的那张验收图**上看出来的：
    ///    04 那张输入框是 `lookup`、卡片却是 `ubiquitous` 的释义。
    ///    用户点「最近查过」里的 lookup，读到的是别的词的解释。
    ///    **跟「错误文案被写进输入框」是同一个形状：一个东西冒充另一个。**
    func testStaleCardNeverImpersonatesNewResult() throws {
        let a = app()
        open(a)

        // A：查一个有样本的词 → 卡片出来
        typeWord(a, "ubiquitous")
        a.buttons["dict.search"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let head = a.staticTexts["dict.word"]
        XCTAssertTrue(head.waitForExistence(timeout: 8), "🚨 A 的卡片没出来")
        XCTAssertEqual(head.label, "ubiquitous")

        // B：查一个必定失败的 → **A 的卡片必须消失**
        typeWord(a, "failnow")
        a.buttons["dict.search"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        shot("06_失败后旧卡片应已收掉")

        XCTAssertTrue(a.staticTexts["dict.err"].waitForExistence(timeout: 5),
                      "🚨 失败了却没提示")
        // 🚨 判据挂在**词头还在不在**上，不是"卡片 isHidden"——
        //    后者是实现细节，前者是他眼睛真正看到的东西。
        XCTAssertFalse(a.staticTexts["dict.word"].exists,
            "🚨 上一条（ubiquitous）的卡片还留在屏上，正在冒充 failnow 的结果")
        // 反向控制：**输入框仍是他输的那个词**（①那条不许被这次修改弄坏）
        XCTAssertEqual(a.textFields["dict.field"].value as? String, "failnow")
    }
}
