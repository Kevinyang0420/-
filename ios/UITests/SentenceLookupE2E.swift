import XCTest

/// **查一整句 → 出句子卡 → 能加进单词本**，走真后端。
///
/// Kevin 09-07 原话：
/// > 我把一段句子发给它，它能帮我分析这段句子是什么意思、它的结构，
/// > 以及有什么可参考的句式等…**同时也要支持我加入到单词本**。
///
/// 🚨 **上一轮我明说过这条"端到端没验过"** —— 那时后端还没上线 `kind` 分流，
///    我只有夹具自测（`CardSectionsTests`），并且说了不拿夹具绿冒充通过。
///    1.1 09-07 上线了，所以这一条现在能真跑，**这就是那次补验**。
///
/// 🚨 判据要**两个方向都验**：
///    · 整句 → 必须出句子卡（意思/结构/换个说法/搭配）
///    · 单词 → 必须**仍然**是词卡（这条最容易在改分流时被改坏）
///    只验前者的话，我可能把所有查询都推成句子卡而不自知。
final class SentenceLookupE2E: XCTestCase {

    private let sentence = "Could you send me the proposal by Friday?"
    private let word = "commute"

    func testSentenceRendersSentenceCardAndCanBeSaved() throws {
        let app = launch("speak")
        try lookup(app, sentence)

        // ① 句子卡的标识在不在
        XCTAssertTrue(app.staticTexts["dict.sentence"].waitForExistence(timeout: 30),
                      "🚨 查整句没出句子卡 —— 要么分流没走到，要么后端没给 kind")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "SENT_01_句子卡"; shot.lifetime = .keepAlways; add(shot)

        // ② 四段里至少要有「结构拆解」那段的内容 —— 「可参考的句式」他专门提的
        let all = texts(app)
        XCTAssertTrue(all.contains { $0.contains("Could you") },
                      "🚨 结构拆解里没有原句的块 —— breakdown 没画出来")

        // ③ 🚨 **不是第二份译文**：note 里要有句式指导，不是把英文再说一遍
        //    （判据放宽到"出现任一指导信号"，1.1 自己也说 meaning 那条判据是宽的）
        let hints = ["语气", "可替换", "结构", "场合", "用在", "适合", "委婉"]
        XCTAssertTrue(hints.contains { h in all.contains { $0.contains(h) } },
                      "🚨 拆解里一条句式指导都没有 —— 那就只是又翻译了一遍")

        // ④ 加进单词本，**退出去再进来还在**（只看当场变色分不出有没有落盘）
        // 🚨 别叫 add —— 会遮住 XCTestCase.add(_:)，截图那行当场编不过。
        let addBtn = app.buttons["dict.add.wordbook"]
        XCTAssertTrue(addBtn.waitForExistence(timeout: 8), "🚨 句子卡上没有加入单词本的按钮")
        addBtn.tap()
        Thread.sleep(forTimeInterval: 2.0)
        let shot2 = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot2.name = "SENT_02_已加入"; shot2.lifetime = .keepAlways; add(shot2)

        app.terminate()
        Thread.sleep(forTimeInterval: 1.5)
        let app2 = launch("", seed: false)
        try openWordBook(app2)
        XCTAssertTrue(app2.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "proposal")).firstMatch
            .waitForExistence(timeout: 10),
            "🚨 重进单词本找不到那句 —— 没落盘")
    }

    /// 🚨 反向对照：单词**必须仍然**走词卡。
    ///    只验句子的话，把所有查询都推成句子卡我也发现不了。
    func testWordStillRendersWordCard() throws {
        let app = launch("speak")
        try lookup(app, word)
        XCTAssertTrue(app.staticTexts["dict.word"].waitForExistence(timeout: 30),
                      "🚨 查单词没出词卡 —— 分流把词也推成句子了")
        XCTAssertFalse(app.staticTexts["dict.sentence"].exists,
                       "🚨 单词被当成句子渲染了")
    }

    // MARK: - 走到那一屏

    /// `seed` = 要不要种子。
    ///
    /// 🚨🚨 **验"落盘了没有"的那一次必须不种子** —— `TRANSLESS_SEED_CARD`
    ///    第一句就是「把单词本清空再种」（那是为了给用例一个确定的起点）。
    ///    重进时再种一次，等于**我自己把刚存的那句擦了**，
    ///    然后判据红在「没落盘」上 —— **看起来像存储坏了，其实是测试自己删的**。
    private func launch(_ page: String = "", seed: Bool = true) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        // 🚨 `speak` = 「随手翻译」那屏（`MainViewController`），
        //    「查词」就挂在它的导航栏右上角（`AppDelegate:3791`）。
        //    我前面连猜三次它在哪（常用词页 / 那页的导航栏 / 全 App 搜），
        //    每次报出来都像"按钮没了" —— **停下来查了一次源码就定了**。
        if !page.isEmpty { app.launchEnvironment["TRANSLESS_PAGE"] = page }
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        // 🚨 `launchEnvironment` **设不了 UserDefaults** —— 我第一版写了一行
        //    `launchEnvironment["transless.auth.userId"] = "probe"`，那是无效的。
        //    登录标记由种子那一次写进 UserDefaults，**重启后仍在**，
        //    所以第二次不种子也照样是已登录。
        if seed { app.launchEnvironment["TRANSLESS_SEED_CARD"] = "1" }
        // 🚨🚨 **把界面语言清回跟随系统** —— 上一轮出上架图的用例
        //    把模拟器留在了阿拉伯语，于是这条按「常用词」找 tab 当场找不到，
        //    报出来是「找不到常用词 tab」，**看起来像 tab 没了**。
        //    实际是**用例之间共享了持久化状态、这条没有确定的起点**。
        //    （`AppDelegate` 里为这个坑专门留过注释，我照样踩了。）
        app.launchEnvironment["TRANSLESS_UILANG_RESET"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        return app
    }

    private func lookup(_ app: XCUIApplication, _ q: String) throws {
        // 🚨 「查词」是**首页右上角**的导航按钮（`AppDelegate:3791`），
        //    不在「常用词」tab 里 —— 我连着猜错两次（先猜常用词页、
        //    再猜它的导航栏），每次报出来都像"按钮没了"。
        //    改成**在整个 App 里按文案找**，不假设它挂在哪一屏。
        let openDict = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "查词", "Look up")).firstMatch
        XCTAssertTrue(openDict.waitForExistence(timeout: 10),
                      "🚨 找不到「查词」入口 —— 它在「随手翻译」那屏的右上角")
        openDict.tap()
        Thread.sleep(forTimeInterval: 2.0)
        let field = app.textFields["dict.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "🚨 找不到查词输入框")
        field.tap()
        field.typeText(q)
        // 🚨 走页面上那颗搜索键，不指望键盘上的 return ——
        //    模拟器键盘的 return 键 label 随语言变。
        let go = app.buttons["dict.search"]
        if go.exists { go.tap() } else { app.keyboards.buttons.firstMatch.tap() }
    }

    private func openWordBook(_ app: XCUIApplication) throws {
        let tabSet = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "设置", "Settings")).firstMatch
        XCTAssertTrue(tabSet.waitForExistence(timeout: 8), "🚨 找不到设置 tab")
        tabSet.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let row = app.staticTexts.matching(NSPredicate(
            format: "label == %@ OR label == %@", "单词本", "Word book")).firstMatch
        if !row.waitForExistence(timeout: 6) { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 8), "🚨 设置里找不到单词本")
        row.tap()
        Thread.sleep(forTimeInterval: 2.5)
    }

    private func texts(_ app: XCUIApplication) -> [String] {
        let all = app.staticTexts
        var out: [String] = []
        for i in 0..<min(all.count, 140) where all.element(boundBy: i).exists {
            out.append(all.element(boundBy: i).label)
        }
        return out
    }
}
