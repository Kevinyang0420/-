import XCTest

/// **把每一屏各截一张** —— 0 要拿去跟安卓并排比。
///
/// 🚨 起因（Kevin 2026-09-06）：他只看了安卓首页就抓出两条没对齐
///    （查词没上线、随手翻译位置和 icon 不对），然后问
///    **「那其他东西还有多少没做到位啊？有人看过、review 过没有？」**
///    —— 这个问题没法靠读代码回答：两端代码里写的规格看着一样，
///    **但从来没人把两个屏并排看过。**
///
/// 🚨 **一屏一张，别拼图。** 并排比的时候要能单独放大某一屏。
/// 🚨 截图前**等一拍**：`runningForeground` 只说进程到前台了，
///    Tab 栏和凸起圆钮可能还没布局完 —— 截到半成品比没截更误导
///    （`HomeShot` 里已经踩过这条）。
final class AllScreensShot: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true          // 某一屏进不去也要把别的截完
        app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        // 🚨 模拟器音频会 abort，报出来像「App 没起来」（见 TestApp.swift）
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
    }

    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 1.2)   // 转场动画跑完再截
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        NSLog("SHOT %@", name)
    }

    /// 点底部第 `i` 个 tab。
    /// 🚨 **按位置取，不按文案** —— 界面语言一换文案就变，
    ///    而这个用例要在中英两种语言下都跑得动。
    private func tab(_ i: Int) -> Bool {
        let bar = app.tabBars.firstMatch
        guard bar.waitForExistence(timeout: 8) else { return false }
        let b = bar.buttons.element(boundBy: i)
        guard b.exists, b.isHittable else { return false }
        b.tap()
        return true
    }

    /// 按可见文字点一个按钮；点不到就**如实返回 false**，不假装点了。
    @discardableResult
    private func tapText(_ s: String) -> Bool {
        let b = app.buttons[s]
        if b.waitForExistence(timeout: 4), b.isHittable { b.tap(); return true }
        // 有些入口是自绘的 UIView，不是 UIButton
        let t = app.staticTexts[s]
        if t.exists, t.isHittable { t.tap(); return true }
        return false
    }

    func testShotEveryScreen() throws {
        // ── 底部五个 tab ────────────────────────────────
        shot("01_首页")

        let names = ["02_说话记录", "03_面对面", "04_常用词", "05_设置"]
        for (k, n) in names.enumerated() {
            // tab 顺序：首页(0) 说话记录(1) 面对面(2·凸起) 常用词(3) 设置(4)
            if tab(k + 1) { shot(n) } else { NSLog("SHOT SKIP %@（点不到）", n) }
        }

        // ── 随手翻译（首页主 CTA）+ 它右上角的「查词」──────
        // 🚨 查词**不在首页**，是随手翻译那屏导航栏右上角（`AppDelegate:3431`）。
        //    我第一版按"首页上有个查词按钮"去点，点不到 —— **入口位置得读代码，
        //    不能按"它应该在哪"去猜**。安卓完全没有这一屏，他今天第二次问了。
        _ = tab(0)
        Thread.sleep(forTimeInterval: 1.0)
        if tapText("随手翻译") {
            shot("06_随手翻译")
            let dict = app.navigationBars.buttons["查词"]
            if dict.waitForExistence(timeout: 4), dict.isHittable {
                dict.tap()
                shot("07_查词页")
                app.navigationBars.buttons.element(boundBy: 0).tap()
                Thread.sleep(forTimeInterval: 0.8)
            } else {
                NSLog("SHOT SKIP 07_查词（随手翻译那屏没有这个导航按钮）")
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            Thread.sleep(forTimeInterval: 1.0)
        } else {
            NSLog("SHOT SKIP 06_随手翻译")
        }

        // ── 单词本：**在设置里**，不在首页 ─────────────────
        // 🚨 Kevin 2026-09-04 把单词本从首页/Tab 挪进了设置（`AppDelegate:2993`）。
        //    按"它以前在哪"去找 = 找不到。
        _ = tab(4)
        Thread.sleep(forTimeInterval: 1.0)
        shot("08_设置")
        if tapText("单词本") {
            shot("09_单词本列表")
            // 🚨 **再点进一条** —— 卡片在详情页里，只截列表等于没截到他要看的那个东西
            let rows = app.otherElements.matching(identifier: "wb.row")
            let row = rows.count > 0 ? rows.element(boundBy: 0)
                                     : app.staticTexts.element(boundBy: 3)
            if row.exists, row.isHittable {
                row.tap()
                shot("10_单词本详情_卡片")
            } else {
                NSLog("SHOT SKIP 10（本子空的或行点不动）")
            }
        } else {
            NSLog("SHOT SKIP 09_单词本（设置里点不到）")
        }
    }
}
