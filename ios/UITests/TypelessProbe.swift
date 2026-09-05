import XCTest

/// **拍 Typeless 按下麦克风那一刻，它的主 App 会不会跳到前台。**
///
/// 🚨 换宿主：不再驱动微信。微信的界面自动化太不稳
///    （会落进网页、会切到「按住说话」、会进不去会话），
///    **每一次失败都不是产品的问题，全是导航的问题**，而它们会把结论搅浑。
///    改用我们自己的 `TransProbe` —— 它一启动就自动聚焦文本框、键盘立刻弹出，
///    没有导航这一层。**换宿主不影响要测的东西**：键盘扩展的行为跟宿主是谁无关。
///
/// 判据：按下 Typeless 的麦克风之后，每秒记一次
/// `TransProbe` 和 `Typeless 主App` 的前后台状态。
/// · Typeless 主App 进前台（4）→ **它也跳**，那它必有一条我没找到的回程
/// · 一直不进前台 → **它在键盘里录**，那 `2003329396` 是我的 bug
final class TypelessProbe: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    private func keys(_ app: XCUIApplication) -> [String] {
        var out: [String] = []
        for i in 0..<min(app.buttons.count, 40) {
            let b = app.buttons.element(boundBy: i)
            let s = b.label + "/" + b.identifier
            if s != "/" { out.append(s) }
        }
        return out
    }

    func testWatchTypelessMic() throws {
        let host = XCUIApplication(bundleIdentifier: "com.kevin.tprobe")
        let tl = XCUIApplication(bundleIdentifier: "com.typeless.mobile")
        host.launch()
        Thread.sleep(forTimeInterval: 4)
        NSLog("TLPROBE 宿主 state=%d", host.state.rawValue)

        // 循环切键盘，直到不是系统键盘、也不是我们自己的
        var which = "?"
        for round in 0..<8 {
            let k = keys(host)
            NSLog("TLPROBE 第%d个键盘（%d 键）：%@", round, host.buttons.count,
                  k.prefix(14).joined(separator: " ｜ "))
            if k.contains(where: { $0.contains("transless.mic") }) {
                which = "ours"
            } else if k.contains(where: { $0.hasPrefix("听写/") }) {
                which = "system"
            } else if k.count >= 1 {
                which = "other"
                NSLog("TLPROBE ✅ 非系统、非我们的键盘 → 很可能是 Typeless")
                break
            }
            let nb = host.buttons["下一个键盘"]
            if nb.exists && nb.isHittable { nb.tap() } else {
                NSLog("TLPROBE 没有「下一个键盘」按钮，停"); break
            }
            Thread.sleep(forTimeInterval: 2.0)
        }
        NSLog("TLPROBE 当前键盘判定=%@", which)

        var pressed = false
        for i in 0..<min(host.buttons.count, 40) {
            let b = host.buttons.element(boundBy: i)
            let s = (b.label + b.identifier).lowercased()
            if s.contains("mic") || b.label.contains("录") || s.contains("record")
                || b.label.contains("话筒") {
                NSLog("TLPROBE 按下：%@", b.label + "/" + b.identifier)
                b.tap(); pressed = true; break
            }
        }
        if !pressed {
            NSLog("TLPROBE 没认出麦克风键；全部按钮：%@",
                  keys(host).joined(separator: " ｜ "))
        }
        for t in 1...10 {
            Thread.sleep(forTimeInterval: 1.0)
            NSLog("TLPROBE t=%ds 宿主=%d Typeless=%d", t,
                  host.state.rawValue, tl.state.rawValue)
        }
    }
}
