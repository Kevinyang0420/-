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
        // 🚨 出图专用：键盘预览页那身绿底和「预览：真实键盘扩展（…）」横幅
        //    是调试脚手架，**不能出现在上架图里**（09-07 交过一次，被 0 拦下）。
        app.launchEnvironment["TRANSLESS_STORE_SHOT"] = "1"
        if seedCard {
            app.launchEnvironment["TRANSLESS_SEED_CARD"] = "1"
            // 🚨 **真查一次，不用写死中文的假数据。**
            //    Kevin 09-07 看日语版：「例文里面也是用中文去写」——
            //    那张卡片是种子里写死的中文。真实链路是对的
            //    （`ui_lang` 已经在传，后端按语言给），错的是假数据。
            //    这张图要送日本区 App Store，不能拿"只是测试数据"糊过去。
            app.launchEnvironment["TRANSLESS_LIVE_CARD"] = "1"
        }
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
        // 🚨 文件名跟着功能名走：Kevin 09-07 把「随手翻译」改成「随便说点啥」，
        //    七门上架图上印的还是旧名（2.1 抓的）。**改标签重跑即可，不用重设计构图。**
        shot("03_随便说点啥")

        // ④ 单词本卡片 —— 要有内容才好看，种一条进去再点开
        //
        // 🚨 **走设置里那一行进去，不走深链。**
        //    我原来加过 `TRANSLESS_PAGE=wb` 直达 —— 它**绕过了登录门**，
        //    `gate_wordbook_copy.py` 当场红，还连带把安卓的包判成失败、
        //    推不到他手机上。闸门判得对：**单词本只许有一个入口，就是带门的那个**。
        //    这里按标识 `prefs.row.wordbook` 点，不按文案（文案随语言变）。
        let wb = launch("prefs", seedCard: true)
        let wbRow = wb.descendants(matching: .any)
            .matching(identifier: "prefs.row.wordbook").firstMatch
        if !wbRow.waitForExistence(timeout: 6) {
            wb.swipeUp(); Thread.sleep(forTimeInterval: 1.0)
        }
        XCTAssertTrue(wbRow.waitForExistence(timeout: 8),
                      "🚨 [\(lang)] 设置里找不到单词本那一行")
        wbRow.tap()
        Thread.sleep(forTimeInterval: 2.5)
        let row = wb.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "commute")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8),
                      "🚨 [\(lang)] 单词本里没有 commute —— 种子没生效，"
                      + "这张会是空本子")
        row.tap()
        // 🚨 真查要等网络回来（详情页会转一下「正在取卡片…」）。
        //    等不够就截到"正在取"，而那张图看起来只是"排版空"，
        //    不像"没等到" —— 又一个安静的坏。
        Thread.sleep(forTimeInterval: 9.0)
        // 🚨🚨 **判据必须看得出语言真换了**，不是"有内容就行"。
        //    上一轮我交的 35 张全过了「尺寸/张数/md5 互不相同」，
        //    而**七门语言跑出来的全是中文** —— md5 不同只是因为时钟在变。
        //    这里按脚本判：日语要有假名、阿语要有阿拉伯字母、
        //    德/西要有拉丁字母且**不含汉字**。
        let texts = wb.staticTexts.allElementsBoundByIndex
            .prefix(120).filter { $0.exists }.map { $0.label }.joined()
        func has(_ range: ClosedRange<UInt32>) -> Bool {
            texts.unicodeScalars.contains { range.contains($0.value) }
        }
        let han = has(0x4E00...0x9FFF)
        switch lang {
        case "ja":
            XCTAssertTrue(has(0x3040...0x30FF),
                          "🚨 [ja] 卡片里一个假名都没有 —— 释义多半还是中文")
        case "ar":
            XCTAssertTrue(has(0x0600...0x06FF),
                          "🚨 [ar] 卡片里没有阿拉伯字母 —— 释义没跟界面语言走")
        case "de", "es":
            XCTAssertFalse(han,
                           "🚨 [\(lang)] 卡片里出现汉字 —— 释义还是中文")
        case "en":
            XCTAssertFalse(han,
                           "🚨 [en] 卡片里出现汉字 —— 释义还是中文")
        default:
            // zh / hant：中文本来就该有汉字，这条判据在这两门上分辨不了，
            // 🚨 **如实跳过**，不假装验过。
            break
        }
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
