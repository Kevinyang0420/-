import XCTest

/// **阿拉伯语界面必须整体镜像** —— Kevin 2026-09-06：
/// > 「阿语什么时候变成小市场了？我什么时候说放弃阿语这个小市场啊？要做的呀」
///
/// 🚨 判据不是「看图觉得对」。RTL 的典型病是**不崩、但错位**，
///    而"错位"要能被机械判定才防得住回归。
///    这里量的是**语气钮和语言钮的左右关系**：
///    · LTR（中文）：语气在左、语言在右
///    · RTL（阿语）：必须**反过来**
///    两边各跑一次，**反向对照天然在场** —— 只测阿语的话，
///    "两边都不镜像"和"两边都镜像"都会绿，等于没测。
final class RtlMirrorSpec: XCTestCase {

    /// 进随手翻译、钉在翻译档，返回（语气钮中心 x，语言钮中心 x，屏宽）
    private func paramRowOrder(_ app: XCUIApplication) -> (CGFloat, CGFloat, CGFloat) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        let cta = app.buttons["app.try"]
        XCTAssertTrue(cta.waitForExistence(timeout: 10), "首页找不到随手翻译入口")
        cta.tap()
        Thread.sleep(forTimeInterval: 1.5)
        // 🚨 钉回翻译档：只有翻译档同时有语气和语言两个钮。
        //    档位存在 UserDefaults 里，上一轮停在哪档下一轮就是哪档。
        let t = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "app.mode.en", "翻译")).firstMatch
        if t.waitForExistence(timeout: 5) { t.tap(); Thread.sleep(forTimeInterval: 1.2) }

        let tone = app.buttons["app.tone"]
        let lang = app.buttons["app.lang"]
        XCTAssertTrue(tone.waitForExistence(timeout: 6), "🚨 找不到语气钮")
        XCTAssertTrue(lang.waitForExistence(timeout: 6), "🚨 找不到语言钮")
        let w = app.windows.firstMatch.frame.width
        XCTAssertGreaterThan(w, 100, "🚨 读不到窗口宽度，判据没有参照")
        return (tone.frame.midX, lang.frame.midX, w)
    }

    func testParamRowMirrorsUnderRtl() throws {
        // ① LTR 基准（中文）—— 没有它，下面那条不知道"反过来"是相对什么
        let ltr = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        ltr.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        ltr.launchEnvironment["TRANSLESS_UI_LANG"] = "zh"
        ltr.launch()
        let (tone0, lang0, w0) = paramRowOrder(ltr)
        var a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "RTL_01_中文基准"; a.lifetime = .keepAlways; add(a)
        XCTAssertLessThan(tone0, lang0,
                          "🚨 中文界面下语气就不在语言左边了 —— 基准本身是坏的，"
                          + "后面那条'反过来'无从谈起｜语气x=\(tone0) 语言x=\(lang0) 宽=\(w0)")
        ltr.terminate()
        Thread.sleep(forTimeInterval: 1.5)

        // ② RTL（阿语）—— UIKit 的强制方向开关 + App 自己的界面语言
        let rtl = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        rtl.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        rtl.launchEnvironment["TRANSLESS_UI_LANG"] = "ar"
        rtl.launchArguments += [
            "-AppleTextDirection", "YES",
            "-NSForceRightToLeftWritingDirection", "YES",
            "-AppleLanguages", "(ar)",
            "-AppleLocale", "ar_SA",
        ]
        rtl.launch()
        let (tone1, lang1, w1) = paramRowOrder(rtl)
        a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "RTL_02_阿语镜像"; a.lifetime = .keepAlways; add(a)

        XCTAssertGreaterThan(tone1, lang1,
                             "🚨 阿语下没有镜像 —— 语气还在语言左边。"
                             + "RTL 的病就是**不崩、但错位**，用户看到的是一整排反的"
                             + "｜语气x=\(tone1) 语言x=\(lang1) 宽=\(w1)")
    }
}
