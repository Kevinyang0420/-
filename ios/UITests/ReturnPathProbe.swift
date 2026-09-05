import XCTest

/// **验「被 URL 拉起来的 App 退出时，iOS 会不会自己回到拉它的那个 App」。**
///
/// 🚨 为什么这条重要：Kevin 2026-08-31 确认 **Typeless 也会闪一下主页面**。
///    既然它也闪、却能回到原 App，那它多半**不需要认出宿主** ——
///    靠的就是这条系统行为。而「认不出宿主」正是我卡了两天的地方。
///
/// 🚨 不读偏好、只读**前后台状态** —— 探针的 `UserDefaults` 没落盘时
///    `devicectl` 会报 error 7000，那会被误读成"探针没跑"。
///    `XCUIApplication.state` 是直接问系统，没有这一层。
final class ReturnPathProbe: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    func testReturnsToOpener() throws {
        let host = XCUIApplication(bundleIdentifier: "com.kevin.tprobe")
        let ours = XCUIApplication(bundleIdentifier: "com.kevin.transless")

        // 让探针一启动就去开 transless://rec —— 它在这里扮演"微信"
        host.launchEnvironment["PROBE_OPEN_REC"] = "1"
        host.launchEnvironment["PROBE_OPEN_DELAY"] = "2"
        host.launch()
        NSLog("RET 宿主(扮微信)起来了 state=%d", host.state.rawValue)

        var sawOursFg = false
        var backToHost = false
        for t in 1...30 {
            Thread.sleep(forTimeInterval: 1)
            let h = host.state.rawValue, o = ours.state.rawValue
            NSLog("RET t=%2ds 宿主=%d 我们=%d", t, h, o)
            if o == 4 { sawOursFg = true }                 // 我们被拉到前台过
            if sawOursFg && h == 4 && o != 4 {             // 之后宿主又回前台
                backToHost = true
                NSLog("RET ✅ 第 %d 秒：我们退了，宿主回到前台", t)
                break
            }
        }
        NSLog("RET 【判据】我们被拉起过吗=%d；退出后回到拉我们的那个App吗=%d",
              sawOursFg ? 1 : 0, backToHost ? 1 : 0)
    }
}
