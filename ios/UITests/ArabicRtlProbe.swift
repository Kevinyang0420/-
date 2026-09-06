import XCTest

/// **阿拉伯语（RTL）到底炸不炸** —— 实测，不靠"应该没问题"。
///
/// 🚨 Kevin 2026-09-06 要加日/德/西/阿四门界面语言。前三门是 LTR，直接上；
///    **`ar` 是从右往左**，整套布局都是按 LTR 手写约束堆出来的
///    （leading/trailing 混着 left/right 用的地方一旦有，就会左右颠倒）。
///
/// 🚨 **「结构支持」和「可以给用户选」是两件事。**
///    代码里 `Lang.all` 已经有 `ar`，但 `Lang.selectable` 里没有 ——
///    等这个探针的图看过了再决定放不放进去。
///
/// 🚨 判据是**看图**，不是"跑过没崩"。RTL 的典型病是**不崩、但错位**：
///    返回箭头跑到右边、图标和文字左右调换、数字方向反了。
///    所以这个用例**不写断言**，只出图 —— 断言写不出来的东西别硬写一个假的。
final class ArabicRtlProbe: XCTestCase {

    func testShotArabicRtl() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        // 🚨 这两个是 UIKit 认的**强制 RTL** 开关（模拟器/真机都吃）。
        //    只设语言不设方向的话，界面还是照 LTR 排 —— 那就测了个寂寞。
        app.launchArguments += [
            "-AppleTextDirection", "YES",
            "-NSForceRightToLeftWritingDirection", "YES",
            "-AppleLanguages", "(ar)",
            "-AppleLocale", "ar_SA",
        ]
        // 🚨 **上一轮这个探针测了个半拉**：只强制了书写方向，
        //    界面文案还是中文 —— 我看的是「中文字排成 RTL」，
        //    而真正要看的是**阿拉伯文本身**：字母连写、词宽和中英差很多，
        //    长句折行才是最容易炸的地方。
        //    现在用 App 自己那套语言开关，把真阿拉伯文渲染出来。
        app.launchEnvironment["TRANSLESS_UI_LANG"] = "ar"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        func shot(_ n: String) {
            Thread.sleep(forTimeInterval: 1.0)
            let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            a.name = n
            a.lifetime = .keepAlways
            add(a)
        }

        shot("RTL_01_首页")

        // 设置页：行是「标题 + 副标题 + 右箭头」，RTL 下箭头该翻到左边
        let bar = app.tabBars.firstMatch
        if bar.waitForExistence(timeout: 8) {
            let b = bar.buttons.element(boundBy: 4)
            if b.exists, b.isHittable { b.tap(); shot("RTL_02_设置") }
        }
    }
}
