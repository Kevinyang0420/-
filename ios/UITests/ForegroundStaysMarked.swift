import XCTest

/// **主 App 在前台待久了，`hostForeground` 还得是真。**
///
/// ## 这条为什么存在
/// Kevin 09-07 实测仍然掉回默认输入法：「那个重新加载引擎的东西还是不行，
/// 它还是要我重新加载引擎」。守望者同时抓到签名：
/// ```
/// 前台=false,主App 8 秒前还在前台
/// ```
/// 根因：`markForeground()` **只在 `didBecomeActive` 调一次**，
/// 而 `hostForeground` 按**心跳**读、`staleAfter = 6` 秒 ——
/// 没人刷新，**进前台 6 秒后标记就过期**。
/// 而"打开 App → 点进输入框 → 切到我们的键盘 → 点麦克风"这一串
/// **必然超过 6 秒**，所以他每次都撞。
///
/// ## 🚨 我原来那条自检为什么抓不到
/// 打的是 `前台标记：进前台后读回=true` —— **写完立刻读**，
/// 结构上永远是真。量的是"写没写进去"，而问题在"能存活多久"。
/// **判据挂错了时刻**，跟今晚另外两条同族。
///
/// ## 判据（能失败，而且改之前必然失败）
/// 进前台**等满 12 秒**（远超 `staleAfter` 的 6 秒）再让主 App 自报一次。
/// - 改之前：`hostForeground=false` → 红
/// - 改之后：`hostForeground=true`  → 绿
///
/// 🚨 这条测试只负责**发探针**；结论去痕迹里读
/// （`py D:/_build/run_fg_probe.py` 会读并判）。
final class ForegroundStaysMarked: XCTestCase {

    func testForegroundMarkSurvivesStaleWindow() throws {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")

        // 🚨 **等满 12 秒**：`staleAfter` 是 6 秒，等不够就等于没测 ——
        //    等 3 秒的话改不改都绿。等待时长本身就是这条判据的一半。
        Thread.sleep(forTimeInterval: 12.0)
        XCTAssertEqual(app.state, .runningForeground,
                       "🚨 等待期间 App 掉出前台了，这一轮不算数")

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.kevin.transless.debug.fgprobe" as CFString),
            nil, nil, true)
        Thread.sleep(forTimeInterval: 3.0)
    }
}
