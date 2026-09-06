import XCTest

/// **单词本卡片上要有例句，而且是全部几条** —— Kevin 2026-09-06：
/// > 「但是你这个又太简略了吧？**这个单词没有例句，什么都没了呀！**」
///
/// 这条链有三段，之前每一段都单独修过，但**没有一段是在这一屏上验的**：
/// 1. 后端给几条 —— `probe_lookup_examples.py` 实测每个词 3 条 ✅
/// 2. `DictParse` 收几条 —— 原来 `arr.first` 只取第一条，已改成收全 ✅
/// 3. **单词本这一屏画几条** —— 🚨 **从来没验过**
///
/// 🚨 第 3 段之所以一直是盲区：种子里那条 commute **一条例句都没有**，
///    于是截图上不出现例句段看起来"正常"，测试也永远碰不到这段代码。
///    **整类对象从没进过检查范围** —— 这是假检查里最难发现的一种：
///    检查写得对、也会失败，就是没人把这类东西喂给它。
final class WbExamplesSpec: XCTestCase {

    /// 种子里 commute 的三条例句（`AppDelegate` 里那份的一半，
    /// 🚨 只对英文那半 —— 中译要是漏了，下面「成对出现」那条会抓）。
    private let wanted = ["I commute two hours a day.",
                          "She commutes by train.",
                          "His sentence was commuted to ten years."]

    func testWordBookCardShowsAllExamples() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_SEED_CARD"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        let tabSet = app.buttons.matching(NSPredicate(
            format: "label == %@ OR label == %@", "设置", "Settings")).firstMatch
        XCTAssertTrue(tabSet.waitForExistence(timeout: 8), "🚨 找不到设置 tab")
        tabSet.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let wbRow = app.staticTexts.matching(NSPredicate(
            format: "label == %@ OR label == %@", "单词本", "Word book")).firstMatch
        if !wbRow.waitForExistence(timeout: 6) {
            app.swipeUp(); Thread.sleep(forTimeInterval: 1.0)
        }
        XCTAssertTrue(wbRow.waitForExistence(timeout: 8), "🚨 设置里找不到单词本")
        wbRow.tap()
        Thread.sleep(forTimeInterval: 2.5)
        let row = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "commute")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8),
                      "🚨 单词本里没有 commute —— 种子没生效，后面白测")
        row.tap()
        Thread.sleep(forTimeInterval: 3.0)

        // 🚨 卡片长，例句在下半截 —— **滚到底再读**。
        //    不滚的话读到的是上半屏，判据会红在"没有例句"上，
        //    而真相是它在屏幕外面。（「滚不到的地方＝不存在」那条的反面：
        //    这里是**测试**够不着，不是用户够不着。）
        app.swipeUp(); Thread.sleep(forTimeInterval: 1.0)
        app.swipeUp(); Thread.sleep(forTimeInterval: 1.5)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "WBEX_例句"; shot.lifetime = .keepAlways; add(shot)

        let all = app.staticTexts
        var texts: [String] = []
        for i in 0..<min(all.count, 160) where all.element(boundBy: i).exists {
            texts.append(all.element(boundBy: i).label)
        }
        let joined = texts.joined(separator: "｜")

        // ① 例句这一段在不在
        XCTAssertTrue(joined.contains("例句") || joined.contains("Examples"),
                      "🚨 单词本卡片上没有例句这一段 —— 他原话「这个单词没有例句」"
                      + "｜读到 \(texts.count) 段文字")

        // ② 🚨 **几条都要在**。只验"有例句"的话，`arr.first` 那种
        //    只画第一条的写法照样绿 —— 而那正是被修掉的那个 bug。
        for w in wanted {
            XCTAssertTrue(joined.contains(w),
                          "🚨 少了这条例句：\(w) —— 多条例句被砍成一条了"
                          + "｜读到 \(texts.count) 段文字")
        }

        // ③ 英文和中译**成对出现**。只画英文的话他看不懂，
        //    而那种缺失在截图上很像"排版紧凑"，不专门查就发现不了。
        XCTAssertTrue(joined.contains("我每天通勤两小时。"),
                      "🚨 例句只有英文、没有中译")
    }
}
