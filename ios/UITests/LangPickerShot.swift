import XCTest

/// **给 2.1 出图用**：深色生效后、语言下拉打开、看得见「最近用过 / 全部语言」两段。
///
/// 🚨 2.1 要的是"真实的 31 门"，但**真实语言表现在还是 9 门** ——
///    31 门归 1.1 改 `engine.py` 的 `LANGS`，还没落地。
///    所以这里按 31 注入，出图时必须标清「注入」，
///    不能让人当成已经上线的样子（把某时刻为真的当成此刻为真，是常犯的那一族）。
final class LangPickerShot: XCTestCase {
    func testShotForPM() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "speak"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_FAKE_LANGS"] = "31"
        // 种「最近用过」：日语 / 法语 / 英文（最新的在前）
        app.launchEnvironment["TRANSLESS_SEED_RECENT"] = "ja,fr,en"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        let langBtn = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "译成")).firstMatch
        XCTAssertTrue(langBtn.waitForExistence(timeout: 10), "🚨 语言钮不在")
        langBtn.tap()
        Thread.sleep(forTimeInterval: 1.8)

        // 🚨🚨 **判据换了**（2026-09-05 下午）。
        //
        //    原来是「『日语』出现 ≥2 次」—— 拿**重复**来证明两段结构存在。
        //    🚨 而"同一门语言出现两次"**正是 Kevin 报的那个 bug**
        //    （输入法那屏拼平后变成重复行、还双勾）。
        //    去重修好之后这条立刻红了 —— **它守的是缺陷本身。**
        //
        //    换成直接查两个**分段标题**在不在。标题是两段结构的直接证据，
        //    重复只是它在旧实现下的副作用。
        //    （`.displayInline` 的小标题在这一屏是能查到的 —— 下面这两条
        //      2026-09-05 早上跑过 PASS，不是猜的。）
        let recentTitle = app.descendants(matching: .any)["最近用过"]
        let allTitle = app.descendants(matching: .any)["全部语言"]
        XCTAssertTrue(recentTitle.waitForExistence(timeout: 6),
                      "🚨 「最近用过」标题不在")
        XCTAssertTrue(allTitle.exists, "🚨 「全部语言」标题不在")

        // 🚨🚨 **这条判据 2026-09-05 下午翻了面**（Kevin 拍板方案丙）。
        //
        //    上午我按"重复＝bug"写的是「日语 ≤ 1 次」。
        //    丙定的是**「全部语言」完整不删**，靠把「最近用过」做成 chips 来分层 ——
        //    所以同一门语言出现两次（chips 一次 + 完整列表一次）**就是正确行为**，
        //    旧判据反而成了守着"错误产品意图"的那种绿。
        //
        // 🚨 我在给新用例写注释时说过"产品意图变了判据要跟着翻面"，
        //    **然后只在新文件里翻了、忘了改这一条** —— 两条判据互相打架，
        //    构建当场红。**说过的规矩没按每个出口落地，跟没说一样。**
        let ja = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "日语"))
        NSLog("SHOT 日语出现 %d 次", ja.count)
        XCTAssertGreaterThanOrEqual(ja.count, 2,
            "🚨 「日语」只出现 \(ja.count) 次 —— 丙要求「全部语言」完整保留，是不是又被去重了？")

        // 🚨🚨 **同一门语言最多只有一行带勾**（Kevin 2026-09-05 报「两个中文」）。
        //
        // 🚨 我原来那条判据是「两个分段标题都必须在」—— **它抓不到这个缺陷**：
        //    标题在，它照样绿，而界面是坏的（同一门语言两处都打勾）。
        //    **判据缺了一整个维度** —— 今天归纳的第②种假绿。
        //
        // 判据挂在**带勾的行数**上：`isSelected` 为真的元素最多 1 个。
        // 坏样本：把 `checkedOnce` 那个闸去掉，当前语言在两段各画一个勾 → 立刻 2 个。
        let checked = app.descendants(matching: .any)
            .matching(NSPredicate(format: "selected == true"))
        NSLog("SHOT 带勾的行 %d 个", checked.count)
        // 🚨🚨 判据写成**恰好 1 个**，不是「最多 1 个」。
        //    写「≤1」的话，万一 `selected == true` 在 `UIMenu` 上根本匹配不到东西，
        //    `count` 就是 0 —— **断言恒过，而它什么都没验**。
        //    写「==1」它就能证伪自己：0 说明这个谓词没用（判据本身要换），
        //    2 说明双勾还在。**两种失败我都想知道，而「≤1」把前一种藏起来了。**
        XCTAssertEqual(checked.count, 1,
            "🚨 带勾的行 \(checked.count) 个：0=这个谓词量不到东西（判据没用），2=双勾还在")

        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "语言下拉_31门_深色"; a.lifetime = .keepAlways; add(a)
    }
}
