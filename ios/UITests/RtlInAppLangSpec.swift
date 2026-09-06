import XCTest

/// **在 App 内把界面语言选成阿语（系统仍是 LTR）时，版面要不要跟着镜像。**
///
/// ## 为什么单开一条 —— 现有那条测不到这个
/// `RtlMirrorSpec` 启动时带的是**系统级**开关：
/// ```
/// -NSForceRightToLeftWritingDirection YES
/// -AppleLanguages (ar)
/// ```
/// 那条**是绿的，而且它没错** —— 系统是 RTL 时我们确实镜像。
/// 但我们的 App **支持在设置里切界面语言**，用户手机是中文/英文、
/// 在 App 里选阿语时，UIKit 的 `semanticContentAttribute` 跟的是**系统语言**，
/// 不跟我们自己那个设置 —— 于是文字变阿语、**版面还是从左到右**。
///
/// 🚨 **这一整类条件从来没进过检查范围**：两条测试各测一半，
///    中间那一半（App 内切语言）谁都没测，而那恰恰是 2.1 09-07
///    在阿语上架截图上看到的现象。
///
/// ## 🚨 根因（我核过源码，不是猜的）
/// 全项目**没有任何一处**按自己的 `Lang` 去设 `semanticContentAttribute`：
/// ```
/// grep semanticContentAttribute → 只有 DictViewController:378 一处，
///                                  而且是给一个图标定位用的，跟语言无关
/// grep isRTL / rightToLeft      → 三处，读的都是 UIView 的**有效**方向
///                                  （＝跟系统走）
/// ```
/// → 要修的话是「App 内语言 → 布局方向」这条链，不是某个页面的约束写错了。
///
/// 🚨 **这条现在应当是红的。** 2.1 和 0 还在定这一轮做不做阿语上架；
///    在他们定之前我不动 UI（那是版面决策）。这条用例的作用是
///    **把缺陷钉住并给出判据**，修完之后它必须变绿。
final class RtlInAppLangSpec: XCTestCase {

    /// 进随手翻译、钉在翻译档，返回（语气钮中心 x，语言钮中心 x）。
    /// 🚨 跟 `RtlMirrorSpec` 同一套读法 —— 两条用例量同一个东西，
    ///    差别只在**怎么把界面变成阿语**。
    private func paramRow(_ app: XCUIApplication) -> (CGFloat, CGFloat) {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        let cta = app.buttons["app.try"]
        XCTAssertTrue(cta.waitForExistence(timeout: 10), "首页找不到主入口")
        cta.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let t = app.buttons.matching(NSPredicate(
            format: "identifier == %@", "app.mode.en")).firstMatch
        if t.waitForExistence(timeout: 5) { t.tap(); Thread.sleep(forTimeInterval: 1.2) }
        let tone = app.buttons["app.tone"]
        let lang = app.buttons["app.lang"]
        XCTAssertTrue(tone.waitForExistence(timeout: 6), "🚨 找不到语气钮")
        XCTAssertTrue(lang.waitForExistence(timeout: 6), "🚨 找不到语言钮")
        return (tone.frame.midX, lang.frame.midX)
    }

    func testInAppArabicAlsoMirrors() throws {
        // 🚨🚨 **默认跳过，但不是把检查删掉。**
        //    这条现在必红（缺陷还没修，2.1/0 还在定这一轮做不做阿语上架）。
        //    常红的用例会让整套失去意义 —— 大家会习惯"它一直是红的"，
        //    然后**真的坏了也没人看**。
        //    所以默认跳过 + 用一句话说清为什么，要跑时带 `TRANSLESS_RTL_INAPP=1`。
        //    🚨 修好之后**把这个开关删掉**，让它进默认套件 ——
        //    留着开关等于给自己留一个永远不会响的检查。
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["TRANSLESS_RTL_INAPP"] == "1",
            "已知未修：App 内选阿语时版面不镜像（实测 语气x=120 语言x=320，"
            + "跟中文一模一样）。等 2.1/0 定这一轮做不做。"
            + "要跑：TRANSLESS_RTL_INAPP=1")

        // ① 基准：App 内中文（系统也是 LTR）——
        //    没有它就不知道"反过来"是相对什么。
        let ltr = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        ltr.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        ltr.launchEnvironment["TRANSLESS_UILANG"] = "zh"
        ltr.launchEnvironment["TRANSLESS_UILANG_RESET"] = "1"
        ltr.launch()
        let (tone0, lang0) = paramRow(ltr)
        XCTAssertLessThan(tone0, lang0, "🚨 中文基准就不对，后面无从谈起")
        ltr.terminate()
        Thread.sleep(forTimeInterval: 1.5)

        // ② 只切 **App 内**语言成阿语 —— **故意不带系统级 RTL 启动参数**。
        //    带了的话就变成 `RtlMirrorSpec` 那条，测不到这里要测的东西。
        let rtl = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        rtl.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        rtl.launchEnvironment["TRANSLESS_UILANG"] = "ar"
        rtl.launch()
        let (tone1, lang1) = paramRow(rtl)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "RTLAPP_App内阿语"; a.lifetime = .keepAlways; add(a)

        XCTAssertGreaterThan(
            tone1, lang1,
            "🚨 App 内选阿语时版面没镜像（系统仍是 LTR）——"
            + "文字是阿语、排列还是从左到右。"
            + "根因：没有任何一处按 App 自己的语言去设 semanticContentAttribute，"
            + "UIKit 跟的是系统语言。"
            + "｜语气x=\(tone1) 语言x=\(lang1)")
    }
}
