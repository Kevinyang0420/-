import XCTest

/// **App Store 上架截图** —— 4 政府与合规的清单，2.2 出图。
///
/// 界面语言由 `TRANSLESS_UILANG` 指定（外面那个 runner 一门一门跑），
/// 顺序照 4 给的（首屏权重最高）：
///     ① 键盘说话转写 ② 面对面翻译 ③ 随手翻译 ④ 单词本卡片 ⑤ 多语言
///
/// 🚨 **每一屏各自冷启动 + 走深链**，不靠点文案导航 ——
///    界面语言一换文案就变，`tapText("随手翻译")` 这种在日语下必然点不到，
///    而"点不到"会安静地退化成"少了一张图"，7 门语言跑完才发现。
///
/// 🚨 **点不到就出声、并且让这一屏红**，不许 `if exists` 静默跳过：
///    上架材料少一张，是提审那天才发现的那种缺。
///
/// 🚨 尺寸：模拟器用 iPhone 16 Pro Max，截出来就是 **1320×2868**，
///    正好是苹果 2026 年起要求的 6.9 寸唯一尺寸（其余机型它自动缩放）。
///    换模拟器机型会连带把尺寸换掉 —— 这一条别改。
final class StoreShots: XCTestCase {

    private var lang = ""

    override func setUp() {
        continueAfterFailure = true      // 某一屏挂了也要把别的截完
        lang = ProcessInfo.processInfo.environment["TRANSLESS_UILANG"] ?? "zh"
    }

    /// 起一次 App，停在 `page` 这一屏。
    private func launch(_ page: String, seedCard: Bool = false)
        -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"   // 模拟器音频会 abort
        app.launchEnvironment["TRANSLESS_UILANG"] = lang
        app.launchEnvironment["TRANSLESS_PAGE"] = page
        if seedCard { app.launchEnvironment["TRANSLESS_SEED_CARD"] = "1" }
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25),
                      "🚨 [\(lang)] \(page) 这一屏 App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        return app
    }

    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 1.2)      // 转场动画跑完再截
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        // 🚨 名字里带语言码 —— 7 门语言的图会落到同一个目录，
        //    不带的话后面根本分不出哪张是哪门（而它们长得很像）。
        a.name = "STORE_\(lang)_\(name)"
        a.lifetime = .keepAlways
        add(a)
    }

    func testCaptureStoreShots() throws {
        // ① 键盘说话转写（首屏，权重最高）
        _ = launch("kb")
        shot("01_键盘")

        // ② 面对面翻译
        _ = launch("f2f")
        shot("02_面对面")

        // ③ 随手翻译
        _ = launch("speak")
        shot("03_随手翻译")

        // ④ 单词本卡片 —— 要有内容才好看，种一条进去再点开
        let wb = launch("wb", seedCard: true)
        let row = wb.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "commute")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8),
                      "🚨 [\(lang)] 单词本里没有 commute —— 种子没生效，"
                      + "这张会是空本子")
        row.tap()
        Thread.sleep(forTimeInterval: 2.5)
        shot("04_单词本卡片")

        // ⑤ 多语言 —— 面对面那屏的语言下拉，展开给看
        let f2f = launch("f2f")
        // 🚨 按**位置**取那两个语言钮（左边是源语言）：它们的文案就是语言名，
        //    随界面语言变，按文案找必然在别的语言下失手。
        let btns = f2f.buttons.allElementsBoundByIndex.filter { $0.isHittable }
        var opened = false
        for b in btns where b.frame.midY > f2f.windows.firstMatch.frame.height * 0.65 {
            b.tap()
            Thread.sleep(forTimeInterval: 1.2)
            // 展开了的判据：屏上同时出现两门以上的语言自称
            let hits = ["English", "日本語", "Deutsch", "Français", "한국어"]
                .filter { f2f.staticTexts[$0].exists }
            if hits.count >= 2 { opened = true; break }
        }
        XCTAssertTrue(opened,
                      "🚨 [\(lang)] 语言下拉没展开 —— 这张图会是没打开的面对面屏，"
                      + "跟第②张重复，而且看不出支持多少语言")
        shot("05_多语言")
    }
}
