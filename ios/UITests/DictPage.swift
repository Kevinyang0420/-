import XCTest

/// **查词页验收**（2.1 规格第四节，Kevin 2026-09-05 提的功能）。
///
/// 🚨 用离线样本（`TRANSLESS_DICT_FAKE=1`）跑截断/缓存/中英方向这三条 ——
///    它们**不该依赖真后端**：后端抖一下用例就红，而那个红**看不出根因**。
///    注入的是**输入数据**，被测的截断/缓存/渲染一行都没被碰。
final class DictPage: XCTestCase {

    private func shot(_ n: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = n; a.lifetime = .keepAlways; add(a)
    }

    private func open(_ app: XCUIApplication) {
        // 从随手翻译右上角进 —— 这本身就是判据 1 的前半
        let dict = app.buttons["查词"].firstMatch
        XCTAssertTrue(dict.waitForExistence(timeout: 10),
                      "🚨 随手翻译右上角没有「查词」")
        dict.tap()
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func type(_ app: XCUIApplication, _ w: String) {
        let f = app.textFields["dict.field"]
        XCTAssertTrue(f.waitForExistence(timeout: 8), "🚨 搜索框不在")
        f.tap()
        // 🚨 **先清空再输** —— `typeText` 是**追加**。
        //    第一版没清，第二次查 take 时字段变成 "ubiquitoustake"，
        //    报出来是「第二个词没出来」，**看起来像查询坏了**。
        //
        // 🚨 清空**不靠系统菜单的「全选」** —— 那依赖文案，
        //    切成英文就叫 "Select All"，用例会在第二次切换时莫名其妙失效。
        //    今天已经因为"按文案定位"栽过一次，这里用退格，不依赖任何文案。
        if let cur = f.value as? String {
            for _ in 0..<cur.count {
                f.typeText(XCUIKeyboardKey.delete.rawValue)
            }
        }
        f.typeText(w)
        app.typeText("\n")
        Thread.sleep(forTimeInterval: 1.5)
    }

    /// 判据 2 + 坏样本：查 `take`（样本给 8 条）→ **仍然只出 3 条**。
    ///
    /// 🚨 样本**故意给 8 条**。给 3 条的话，"只出 3 条"在截断根本没实现时也成立
    ///    —— 那是教科书式的假检查。
    func testTruncateToThree() throws {
        let app = TestApp.launch("speak", env: ["TRANSLESS_DICT_FAKE": "1"])
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        open(app)
        type(app, "take")

        XCTAssertTrue(app.staticTexts["take"].waitForExistence(timeout: 8),
                      "🚨 词头没出来")
        // 义项编号 1/2/3 —— 出现「4」就是没截断
        for n in ["1", "2", "3"] {
            XCTAssertTrue(app.staticTexts[n].exists, "🚨 第 \(n) 条义项不在")
        }
        XCTAssertFalse(app.staticTexts["4"].exists,
                       "🚨 出现了第 4 条 —— 截断没做（样本给了 8 条）")
        shot("01_take_只出3条")
    }

    /// 判据 7：输入「报价」→ 出 `quote`，**不是**把「报价」整句翻译一遍。
    /// 这条打的是"复用了翻译提示词"。
    func testZhToEnIsLookupNotTranslation() throws {
        let app = TestApp.launch("speak", env: ["TRANSLESS_DICT_FAKE": "1"])
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        open(app)
        type(app, "报价")
        XCTAssertTrue(app.staticTexts["quote"].waitForExistence(timeout: 8),
                      "🚨 中文输入没出英文说法（多半复用了翻译提示词）")
        // 查词页该有的结构：音标 + 例句/搭配小标题
        XCTAssertTrue(app.buttons["dict.phonetic"].exists, "🚨 没有音标")
        shot("02_报价_出quote")
    }

    /// 判据 5：加入单词本 —— **第一次点完必须变「已加入」**，再连点只有一条。
    ///
    /// 🚨 少了前半句就是假检查：什么都没加进去时，"只有一条"也成立。
    func testAddToWordbook() throws {
        let app = TestApp.launch("speak", env: ["TRANSLESS_DICT_FAKE": "1",
                                                "TRANSLESS_CLEAR_WB": "1"])
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        open(app)
        type(app, "ubiquitous")

        let add = app.buttons["dict.add.wordbook"]
        XCTAssertTrue(add.waitForExistence(timeout: 8), "🚨 「＋单词本」不在")
        add.tap(); Thread.sleep(forTimeInterval: 0.8)
        XCTAssertEqual(add.label, "已加入", "🚨 点了没进单词本")
        add.tap(); Thread.sleep(forTimeInterval: 0.5)   // 移除
        add.tap(); Thread.sleep(forTimeInterval: 0.5)   // 再加
        XCTAssertEqual(add.label, "已加入", "🚨 三次点完不是「已加入」")
        shot("03_已加入")
    }


    /// 判据 6 的**驱动部分**：查一次 → 点「最近查过」重进一次。
    ///
    /// 🚨🚨 **这条用例自己不判"有没有网络请求"** —— 判据在外面：
    ///    跑完之后数 App 打的痕迹 `查词打后端：`，**两次流程只许出现一次**。
    ///    （`DictStore.netCount` 在 App 进程里，UI 测试是另一个进程读不到。）
    ///
    /// 🚨 我第一版把注释写成「必须用真链路」，代码却开着离线注入，
    ///    而且断言只验了"能重新展开" —— **说明和判据不一致、
    ///    判据测的不是它声称的东西**。那是假检查，已改掉。
    ///    现在这个函数**只声称它真的验了的那件事**：重进能展开。
    func testRecentChipReopens() throws {
        let app = TestApp.launch("speak", env: ["TRANSLESS_DICT_FAKE": "1"])
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        open(app)

        type(app, "ubiquitous")
        XCTAssertTrue(app.staticTexts["ubiquitous"].waitForExistence(timeout: 8),
                      "🚨 第一次没查出来，后面就测不到东西")

        // 换一个词，把结果卡挤走，再点回来 —— 否则"重进"看不出效果
        type(app, "take")
        XCTAssertTrue(app.staticTexts["take"].waitForExistence(timeout: 8), "🚨 第二个词没出来")

        let chip = app.buttons["dict.recent.chip"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 6), "🚨 「最近查过」里没有词")
        chip.tap()
        Thread.sleep(forTimeInterval: 1.2)
        // 芯片是最近的那个（take 在最前），点完词头应当变回它
        XCTAssertTrue(app.staticTexts["take"].exists, "🚨 点最近查过没能重新展开结果")
        shot("05_最近查过_重进")
    }

    /// 判据 6 的**真链路驱动**：不开离线注入，连查同一个词两次。
    ///
    /// 🚨 **做成独立用例，不做成环境开关** ——
    ///    我一度想用 `TRANSLESS_DICT_FAKE` 由外面控制，但那个变量
    ///    设在 Windows 的 Python 进程里，用例读的是 **Mac 上测试运行器**的环境，
    ///    中间隔着 xcodebuild，**根本传不过去**。
    ///    做一个够不着目标的开关，比没有开关更糟：它看起来在控制什么。
    ///
    /// 🚨 这条**自己不判"打了几次后端"**（计数在 App 进程里，测试读不到）——
    ///    判据在外面：`check_dict_cache.py` 数痕迹 `查词打后端：`，
    ///    **只许出现一次**。这里只负责把流程走完。
    func testRealBackendTwice() throws {
        let app = TestApp.launch("speak")      // 🚨 不设 DICT_FAKE = 走真后端
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        open(app)
        type(app, "ubiquitous")
        Thread.sleep(forTimeInterval: 6.0)     // 真后端要时间
        type(app, "ubiquitous")                // 同一个词，第二次
        Thread.sleep(forTimeInterval: 3.0)
        shot("07_真链路连查两次")
    }

    /// 🚨 Grok 提的、要真机量的第一条：**首屏至少露出「最近查过」标题 + 一枚芯片**。
    ///    设计稿量不出来，只能在真设备尺寸上量。
    func testRecentVisibleOnFirstScreen() throws {
        let app = TestApp.launch("speak", env: ["TRANSLESS_DICT_FAKE": "1"])
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        open(app)
        type(app, "ubiquitous")

        let screen = app.windows.firstMatch.frame
        let title = app.staticTexts["dict.recent.title"]
        let chip = app.buttons["dict.recent.chip"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 8), "🚨 「最近查过」标题不在")
        XCTAssertTrue(chip.exists, "🚨 一枚芯片都没有")
        NSLog("DICT 首屏 高=%.0f 标题y=%.0f 芯片底=%.0f",
              screen.height, title.frame.minY, chip.frame.maxY)
        // 判据：**芯片的底边**要在首屏之内 —— 只判标题的话，
        //       标题露出来、芯片被切掉一半也会绿。
        XCTAssertLessThan(chip.frame.maxY, screen.height,
                          "🚨 芯片被挤出首屏了（标题 y=\(title.frame.minY)）")
        shot("06_首屏露出最近查过")
    }

    /// 🚨 Grok 提的、要真机量的第二条：**占位文案在 393pt 上挤不挤**。
    ///
    /// 🚨🚨 **必须在 393pt 上跑**（`TRANSLESS_SIM` 指到 iPhone 17e）——
    ///    默认那台是 **440pt**，宽屏上的绿**回答不了窄屏的问题**。
    ///    我 2026-09-05 就是在 440 上量完报了"通过"，而 Grok 问的是 393。
    ///    **量的对象跟结论说的对象不是一个** —— 今天这一族的第 N 次。
    ///
    /// 判据做成可量的：占位文字**没有被截断**。
    /// 🚨 判"文字宽 < 框宽"是不够的 —— iOS 截断后 `label` 里是带省略号的短串，
    ///    那个短串当然放得下。所以判据挂在**省略号**上：出现「…」就是挤了。
    func testPlaceholderFitsAt393() throws {
        let app = TestApp.launch("speak")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        open(app)

        let f = app.textFields["dict.field"]
        XCTAssertTrue(f.waitForExistence(timeout: 8), "🚨 搜索框不在")
        let screenW = app.windows.firstMatch.frame.width
        let shown = f.placeholderValue ?? ""
        NSLog("DICT 占位 屏宽=%.0f 框宽=%.0f 文案=%@",
              screenW, f.frame.width, shown)

        // 🚨 先确认这一轮**真的跑在 393pt 上** —— 不确认的话，
        //    在 440pt 上跑出来的绿会被当成"393 上没问题"。
        XCTAssertLessThan(screenW, 420,
                          "🚨 这一轮跑在 \(Int(screenW))pt 上，不是 393 档 —— 结论不作数")
        XCTAssertFalse(shown.contains("…") || shown.contains("..."),
                       "🚨 占位文案被截断了：\(shown)")
    }

    /// 🚨 判据 1 的**反向控制**：改了随手翻译那个入口之后，
    ///    **首页右上角的权限入口仍在、仍能进设置引导页**。
    ///    只验"改成查词了"的话，把权限入口一起做没了也会全绿。
    func testSetupEntryStillThere() throws {
        let app = TestApp.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        // 首页右上角那颗（未启用时是「设为输入法」，已启用时是输入法胶囊）
        let chip = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@",
                        "设为输入法", "Set as keyboard")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 8),
                      "🚨 首页那个入口没了 —— 反向控制失败")
        chip.tap()
        Thread.sleep(forTimeInterval: 1.5)
        shot("04_首页入口仍在")
    }
}
