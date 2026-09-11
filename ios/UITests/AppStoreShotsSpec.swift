import XCTest

/// **App Store en-US 上架截图** —— Kevin 09-11 最高优先级：
/// 已上传构建 1321 卡在提审第一步，因为**截图 0 张**（App Store 连提交按钮都不给）。
///
/// 🚨 两条硬要求（0 转 Kevin 原话）：
/// 1. **真机/模拟器实拍，不是拼的示意图**（本项目铁规：示意图不算效果图）
/// 2. **不等文案** —— 用 App 里真实存在的界面出图，文案定了要改再补
///
/// 🚨 尺寸口径 [核期:2026-09-11 依据:WebFetch developer.apple.com + WebSearch 三份
///    2026 年独立第三方指南互相印证 + 本项目 09-07 已有的真机实测（见
///    `appstore_shots_audit.py` docstring）适用:2026 年 App Store Connect 提交]：
///    **Apple 现在只强制 6.9" 一档**（1320×2868），其余尺寸靠自动缩放覆盖。
///    WebFetch 那一版说"6.5" 是最低要求"——**是过期读法，已核对否掉**，
///    跟这项目 09-07 已经用真机验过的结论、以及三份独立 2026 博客一致对齐。
///    这正是「拿到规则先查时效」那条铁规要防的——两个信息来源打架时，
///    优先信**本项目自己拿真机测过的那条**，而不是一份不知道多新的官方帮助页缓存。
///
/// 🚨 **只拍 iPhone 17 Pro Max**（`mac.SIM_PRO_MAX`，1320×2868，无需缩放）——
///    这条钉死了这个项目全部截图/录屏基建都用的那台模拟器，别开新的。
///    iPad 13" 那组是同一优先级下的下一步，这个文件先不做。
///
/// 🚨 **英文界面**：这批截图给 en-US 商店页用，`TRANSLESS_UILANG=en` 钉死语言，
///    不许让模拟器的系统语言或上一轮遗留状态决定这批图长什么样。
///
/// 🚨 **不许拍到调试脚手架**：`appstore_shots_audit.py` 的判据历史里点名过
///    "拍到测试脚手架"这一类真实发生过的坏样本。此文件里凡是用
///    `TRANSLESS_PAGE` 走调试直达路由的地方，那条路由本身**不画任何调试专属 UI**
///    （复用的是 `HomeDictCardSpec` / `PrivacyPageSpec` 已经验证过的同一条机制），
///    但截图人工过一遍仍然必要——这条判据代码验不了，交给人看。
final class AppStoreShotsSpec: XCTestCase {

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testCaptureStoreScreenshots() throws {
        // ── ① 首页：主 CTA + 查词卡，正常启动路径，不走任何调试直达 ──
        let home = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        home.launchEnvironment["TRANSLESS_UILANG"] = "en"
        home.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        home.launch()
        XCTAssertTrue(home.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        snap(home, "STORE_01_home")
        home.terminate()

        // ── ② 面对面翻译 ──
        let f2f = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        f2f.launchEnvironment["TRANSLESS_UILANG"] = "en"
        f2f.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        f2f.launchEnvironment["TRANSLESS_PAGE"] = "f2f"
        f2f.launch()
        XCTAssertTrue(f2f.wait(for: .runningForeground, timeout: 25), "面对面没起来")
        Thread.sleep(forTimeInterval: 3.0)
        snap(f2f, "STORE_02_face_to_face")
        f2f.terminate()

        // ── ③ 说话记录：带种子数据，别拍一片空白 ──
        //    🚨🚨 **必须先清后种**（09-11 实拍才发现的坑）：`TRANSLESS_SEED_HIST`
        //    只在历史为空时才塞样本，这台共享模拟器上**一直留着我自己白天
        //    调试用的真实记录**（"测试语音录入是否达到要求"这种内部话），
        //    不清的话种子根本插不进去、拍出来的是一屏内部调试对话——
        //    第一轮实拍就是这么翻车的，图里满是不该给用户看的内容。
        let hist = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        hist.launchEnvironment["TRANSLESS_UILANG"] = "en"
        hist.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        hist.launchEnvironment["TRANSLESS_PAGE"] = "hist"
        hist.launchEnvironment["TRANSLESS_CLEAR_HIST"] = "1"
        hist.launchEnvironment["TRANSLESS_SEED_HIST"] = "1"
        hist.launch()
        XCTAssertTrue(hist.wait(for: .runningForeground, timeout: 25), "历史没起来")
        Thread.sleep(forTimeInterval: 3.0)
        snap(hist, "STORE_03_history")
        hist.terminate()

        // ── ④ 设置页：唯一一个跟共享状态完全无关的屏 ──
        //    🚨🚨 原来这一格先后拍过两版都翻车：
        //    ① `TRANSLESS_PAGE=kb`（键盘调试预览）——绿底横幅字面写着"预览"
        //    ② `TRANSLESS_PAGE=vocab`（常用词/单词本）——混进了一条
        //       「legacyword」，一看就是今天别的自动化测试写进 App Group
        //       共享域的假词条。单词本**没有**像历史记录那样"先清后种"的
        //       调试开关（种子要靠 `simctl spawn defaults write` 从外面塞，
        //       另一件事），这台共享模拟器上的真实状态不可控、不能直接拍。
        //    设置页是**静态**的，不读任何历史/单词本这类共享数据，
        //    不会被别的测试污染 —— 这批先用它，稳。
        let prefs = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        prefs.launchEnvironment["TRANSLESS_UILANG"] = "en"
        prefs.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        prefs.launchEnvironment["TRANSLESS_PAGE"] = "prefs"
        prefs.launch()
        XCTAssertTrue(prefs.wait(for: .runningForeground, timeout: 25), "设置页没起来")
        Thread.sleep(forTimeInterval: 3.0)
        snap(prefs, "STORE_04_settings")
        prefs.terminate()
    }
}
