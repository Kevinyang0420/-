import XCTest

/// **App Store 13" iPad 截图** —— 0 09-11 核实：`TARGETED_DEVICE_FAMILY: "1,2"`
/// 声明支持 iPad，就必须给 13 寸 iPad 那一档截图，躲不掉（跟 iPhone 6.9" 同一条规则：
/// 每个设备族只强制最大档，苹果自动缩放到小设备）。
///
/// 🚨 **只用已知干净、不读共享状态的静态路线**（home / f2f / speak），
///    不重蹈 iPhone 那三轮：history 依赖"先清后种"、vocab 会被别的测试污染、
///    kb 调试路由自带"预览"横幅、**prefs 混了 Diagnostics/TestFlight 这类内部文案**——
///    这四条已知道会翻车，iPad 这批全部避开，换成 `MainViewController`（说话/翻译主界面，
///    跟已经在用的 `en/03_随便说点啥` 是同一块真实存在的静态屏）。
final class AppStoreShotsIPadSpec: XCTestCase {

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testCaptureIPadStoreScreenshots() throws {
        let home = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        home.launchEnvironment["TRANSLESS_UILANG"] = "en"
        home.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        home.launch()
        XCTAssertTrue(home.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.0)
        snap(home, "IPAD_01_home")
        home.terminate()

        let f2f = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        f2f.launchEnvironment["TRANSLESS_UILANG"] = "en"
        f2f.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        f2f.launchEnvironment["TRANSLESS_PAGE"] = "f2f"
        f2f.launch()
        XCTAssertTrue(f2f.wait(for: .runningForeground, timeout: 25), "面对面没起来")
        Thread.sleep(forTimeInterval: 3.0)
        snap(f2f, "IPAD_02_face_to_face")
        f2f.terminate()

        // 🚨🚨 这一屏会触发系统麦克风权限弹窗（`NSMicrophoneUsageDescription` 那句）。
        //    `simctl privacy grant microphone` **授权不可靠**——2026-09-11 实测：
        //    授权后重跑一次，弹窗照样出现（大概率是每次 `xcodebuild test` 都会
        //    重装一次 App，TCC 记录跟着新的安装容器一起失效了）。
        //    改成在这里**直接把系统弹窗点掉**，不依赖 TCC 授权是否生效——
        //    这是系统级 alert（springboard 弹的，不是 App 自己的 view），
        //    要用 `addUIInterruptionMonitor` 才拦得住，而且必须有一次真实的
        //    交互（下面那个 `tap()`）才会触发监控器去检查弹窗在不在。
        let micAlert = addUIInterruptionMonitor(withDescription: "麦克风权限") { alert in
            let allow = alert.buttons["允许"]
            if allow.exists { allow.tap(); return true }
            let allowEN = alert.buttons["Allow"]
            if allowEN.exists { allowEN.tap(); return true }
            return false
        }
        let speak = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        speak.launchEnvironment["TRANSLESS_UILANG"] = "en"
        speak.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        speak.launchEnvironment["TRANSLESS_PAGE"] = "speak"
        speak.launch()
        XCTAssertTrue(speak.wait(for: .runningForeground, timeout: 25), "说话页没起来")
        Thread.sleep(forTimeInterval: 2.0)
        // 🚨 点导航栏标题唤醒中断监控器——**不点屏幕中央**，那边正对着
        //    翻译/转写切换和麦克风按钮，点空了不出事，点中了会把这一屏点乱。
        speak.navigationBars.firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.5)
        removeUIInterruptionMonitor(micAlert)
        snap(speak, "IPAD_03_speak")
        speak.terminate()
    }
}
