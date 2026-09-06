import XCTest

/// **切到日语，看面对面的语言下拉里是不是各语言的自称** —— Kevin 09-06 亲口：
/// > 界面语言调成日语后，面对面翻译里的下拉菜单和语言名称仍用中文标注…
/// > **所有语言都没换成对应语言的表达**。iOS 和安卓端都要检查。
///
/// 🚨 数据层 2.1 已经验过（`engine.LANGS['ja'] = ('日本語', …)`、iOS 31 门 label 全对）。
///    **缺的就是"他屏幕上到底显示什么"** —— 这一屏补的正是那个。
/// 判据：下拉里应当是 `日本語 / Deutsch / 한국어 / 粵語`，**不是** `日语 / 德语 / 韩语 / 粤语`。
///
/// 🚨 Kevin 2026-09-06：「德文、西班牙文那些出来了，**但我点进去之后，
///    发现它的界面语言还是英文**。」
///    根因是每条文案只有 zh/en/hant 三个键，`m["de"]` 取不到就按设计落 `en` ——
///    **回落逻辑在正确工作，缺的是数据。**
///
/// 🚨 **不能靠"我合并跑过了"交差**：合并这种活的典型失败是**部分合上**，
///    抽样对了只证明那一条对。条数由闸门查，**这一屏查的是"他真的能看到"**。
final class JapaneseLangDropShot: XCTestCase {

    func testShotJapanese() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        // 🚨 直接把界面语言偏好设成 de —— 走 App 自己那套 `Lang`，
        //    不是改系统语言：我们这套本来就不读系统 locale（09-05 修过）。
        app.launchEnvironment["TRANSLESS_UI_LANG"] = "ja"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)

        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "JADROP_01_首页"
        a.lifetime = .keepAlways
        add(a)

        // 设置页：行多、字多，最容易看出有没有漏译
        let bar = app.tabBars.firstMatch
        // 🚨 面对面那屏（Kevin 2026-09-06 报语言下拉还是中文）——
        // tab 顺序：首页(0) 说话记录(1) 面对面(2·凸起) 常用词(3) 设置(4)
        if bar.waitForExistence(timeout: 8) {
            // 🚨 **凸起那颗不在  里**（它是单独的自绘按钮，
            //    id ）。按位置取会落到「说话记录」上 ——
            //    我第一版就是这么取错的，拍回来一张说话记录当成面对面。
            //    **按标识取，别按位置猜。**
            let f = app.buttons["tab.center.f2f"]
            if f.exists, f.isHittable {
                f.tap()
                Thread.sleep(forTimeInterval: 1.5)
                let d = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                d.name = "JADROP_03_面对面"
                d.lifetime = .keepAlways
                add(d)

                // 🚨 **要拍的是下拉里面**（Kevin 报的就是那儿）。
                //    只拍那两颗按钮证明不了什么 —— 它们恰好是「中文/English」，
                //    这两门的自称本来就长这样。**看不出改没改。**
                //    真正的证据是下拉里的「日本語 / Français / 한국어」。
                let lang = app.buttons["f2f.lang.right"]
                if lang.waitForExistence(timeout: 4), lang.isHittable {
                    lang.tap()
                    Thread.sleep(forTimeInterval: 1.5)
                    let e = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                    e.name = "JADROP_04_语言下拉"
                    e.lifetime = .keepAlways
                    add(e)
                }
            }
        }

        if bar.waitForExistence(timeout: 8) {
            let b = bar.buttons.element(boundBy: 4)
            if b.exists, b.isHittable {
                b.tap()
                Thread.sleep(forTimeInterval: 1.2)
                let c = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                c.name = "DEL_02_设置"
                c.lifetime = .keepAlways
                add(c)
            }
        }
    }
}
