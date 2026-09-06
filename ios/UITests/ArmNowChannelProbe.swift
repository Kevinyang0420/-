import XCTest

/// **「主 App 在前台就地架引擎」那条通道，真机上通不通** ——
/// 不用等 Kevin 点键盘。
///
/// ## 它验的是 09-06 真机 FAIL 的那一步
/// 他原话：
/// > 在主 APP 上调用我们的输入法，**现在还是自动转回默认输入法**，
/// > 还要我再手工切回 Transless，**它还是要重新启动这个引擎**
///
/// 根因：键盘走 `openContainerApp("arm")` 去**拉起主 App** ——
/// **跳转这个动作本身**就让键盘失焦、系统切回默认输入法。
/// 改成：主 App 在前台时发一条 Darwin 通知让它**就地**架，一次跳转都不发生。
///
/// ## 🚨 为什么这条测试有意义（它真的会失败）
/// 那条通知以前**必然没人接**：`KbVoiceHost.observe()` 只在
/// `setStandby(true)` 里注册，而这条路要用的场景恰恰是**待机关着、引擎没架**。
/// 观察者现在改在 `didFinishLaunching` 里无条件注册，用的是
/// **AppDelegate 自己的 token**（借 `KbVoiceHost` 那个的话，
/// `setStandby(false)` 的 `stopObserving` 会把整个 token 下的观察者一起撤掉）。
///
/// ## 🚨 为什么用 UITest 而不是单元测试
/// Darwin 通知是**跨进程**的。测试进程和被测 App 是两个进程 ——
/// 这正好模拟了键盘扩展的位置。同进程里 post 给自己，验不到"跨进程收得到"。
///
/// ## 判据在哪读
/// 测试本身只负责**发**。收没收到、架没架起来看设备痕迹：
///     ① `收到就地架引擎`      ← 观察者接住了
///     ② `arm：架好了 ✅`      ← 引擎真架起来了
/// 从 Windows 这边读：`py D:/_build/kb_fg_watch.py` 或 `mac.dev_trail`。
/// 🚨 **测试绿 ≠ 通道通** —— 它绿只说明"通知发出去了"。
///    结论必须去痕迹里读那两行，这条测试不替它下结论。
final class ArmNowChannelProbe: XCTestCase {

    func testPokeArmNowFromAnotherProcess() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        // 🚨 **不设 `TRANSLESS_NO_ARM`** —— 那个会拦掉架引擎，
        //    正好把要测的东西关掉，测出来的绿是假的。
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        // 等 `didFinishLaunching` 把观察者注册上。
        Thread.sleep(forTimeInterval: 4.0)

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.kevin.transless.cmd.armnow" as CFString),
            nil, nil, true)

        // 给主 App 时间去架（`handleArmURL` 自己最多轮询 4 秒 + 4 秒等前台）。
        Thread.sleep(forTimeInterval: 12.0)

        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "ARMNOW_发完通知12秒后"; a.lifetime = .keepAlways; add(a)

        // 🚨 **就地架不该弹「向后滑动以继续」** —— 那层引导是给"跳过来"的场景的。
        //    他人就在 Transless 里，那句话是在叫他离开自己的 App。
        //    这一条是这个测试里唯一能自己判的东西，其余去痕迹里读。
        let hint = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@ OR label CONTAINS %@",
            "向后滑动", "Swipe back")).firstMatch
        XCTAssertFalse(hint.exists,
                       "🚨 就地架完弹了「向后滑动以继续」—— 他本来就在这个 App 里，"
                       + "这是在叫他离开")

        // App 还活着（架引擎不该把它弄崩）。
        XCTAssertEqual(app.state, .runningForeground, "🚨 发完通知 App 不在前台了")
    }
}
