import XCTest

/// **验最后一条活路**：App 在后台时，由灵动岛按钮触发的 `AudioRecordingIntent`
/// 能不能真的起录。
///
/// 🚨 为什么只剩这条：苹果 DTS 明确答复「键盘识别宿主 App」和
///    「容器 App 知道谁拉起它」**都没有公开办法**，iOS 26.4 后私有路子也全死
///    （我实测拿得到宿主 pid，但 `proc_pidpath`/`proc_name` 被沙盒挡，`errno=1`）。
///    → 「跳过去再切回来」这条路是死的，只剩「压根不跳」。
///
/// 判据**必须是录到了音**（痕迹里 `收工 N 字节`），不是「Intent 跑了」。
/// 「跑了」和「录到了」是两回事 —— 今天已经在这上面栽过好几次。
final class IslandIntentProbe: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    func testIslandButtonStartsRecording() throws {
        // 先把别的 App 推到前台，确保 Transless 在后台
        let sf = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        sf.activate()
        Thread.sleep(forTimeInterval: 4)
        NSLog("ISLAND Safari state=%d（4 = 前台，说明我们的 App 在后台）", sf.state.rawValue)

        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        // 灵动岛在屏幕顶部正中。先点一下把它展开。
        let pill = sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.018))
        pill.tap()
        NSLog("ISLAND 点了灵动岛（展开）")
        Thread.sleep(forTimeInterval: 2.5)

        // 展开后找「开始录音」按钮
        var tapped = false
        for i in 0..<min(sb.buttons.count, 40) {
            let b = sb.buttons.element(boundBy: i)
            if b.exists, b.label.contains("录音"), b.isHittable {
                b.tap(); tapped = true
                NSLog("ISLAND ✅ 点到了按钮：%@", b.label)
                break
            }
        }
        // 🚨 上一版没认到按钮就瞎点坐标 —— **先把元素树打出来**，
        //    否则"点了没反应"分不清是没点到还是点到了不起作用。
        let dump = sb.debugDescription
        for (i, chunk) in stride(from: 0, to: min(dump.count, 3000), by: 300).enumerated() {
            let a = dump.index(dump.startIndex, offsetBy: chunk)
            let b = dump.index(a, offsetBy: min(300, dump.count - chunk))
            NSLog("ISLAND 树[%d] %@", i, String(dump[a..<b]))
        }
        if !tapped {
            // 认不到就按坐标点展开视图的下半部分
            NSLog("ISLAND 没认到按钮，SpringBoard 按钮数=%d", sb.buttons.count)
            for i in 0..<min(sb.buttons.count, 20) {
                NSLog("ISLAND   按钮[%d]=%@", i, sb.buttons.element(boundBy: i).label)
            }
            sb.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.11)).tap()
            NSLog("ISLAND 改按坐标点了展开视图下半部")
        }
        Thread.sleep(forTimeInterval: 10)
        NSLog("ISLAND 结束，Safari 还在前台吗 state=%d", sf.state.rawValue)
    }
}
