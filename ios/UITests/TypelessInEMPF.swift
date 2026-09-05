import XCTest

/// **用 UI 自动化替 Kevin 做：eMPF 点输入框 → 切到 Typeless 键盘 → 按麦克风 → 看它怎么回来。**
///
/// 🚨 为什么要它：2026-09-02 10:1x Kevin「手机都给了你了，为什么自己不会做？」——
///    我一直只用 devicectl 拉 App，忘了手上有能"点屏幕"的 XCUITest 跑器。
/// 观察量：每秒记 eMPF / Typeless 主 App 的 state（4=前台 2=后台 1=没跑），
///    配合 Mac 上 `log collect` 抓的 SpringBoard 日志，就能看到它是怎么把人送回去的。
final class TypelessInEMPF: XCTestCase {

    override func setUp() { continueAfterFailure = true }

    func testTypelessMicInEMPF() throws {
        let empf = XCUIApplication(bundleIdentifier: "hk.org.empf")
        let tl = XCUIApplication(bundleIdentifier: "com.typeless.mobile")
        // 先把 Typeless 主 App 划掉（照 Kevin 的实验：主 App 关掉的情况下按）
        if tl.state == .runningForeground || tl.state == .runningBackground {
            tl.terminate(); Thread.sleep(forTimeInterval: 1.0)
        }
        NSLog("TLEM 开始：Typeless主App=%d", tl.state.rawValue)
        empf.activate()
        XCTAssertTrue(empf.wait(for: .runningForeground, timeout: 25), "eMPF 没起来")
        Thread.sleep(forTimeInterval: 3)

        // 找输入框：优先用真实元素，退回坐标（截图里「用户名称」框在 y≈0.21）
        var tapped = false
        if empf.textFields.count > 0 {
            let f = empf.textFields.element(boundBy: 0)
            if f.exists && f.isHittable { f.tap(); tapped = true }
        }
        if !tapped { empf.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.21)).tap() }
        Thread.sleep(forTimeInterval: 2.0)
        NSLog("TLEM 点了输入框（元素=%d）｜键盘数=%d", tapped ? 1 : 0, empf.keyboards.count)

        // 切键盘直到是"第三方且不是我们的"
        var found = false
        for n in 0..<12 {
            var labels: [String] = []
            for i in 0..<min(empf.buttons.count, 60) {
                let b = empf.buttons.element(boundBy: i)
                let s = b.label + "/" + b.identifier
                if s != "/" { labels.append(s) }
            }
            let sys = labels.contains { $0.contains("听写") || $0.contains("dictation")
                                     || $0.contains("聽寫") || $0.contains("布局") }
            let ours = labels.contains { $0.contains("transless.mic") }
            NSLog("TLEM 第%d轮：系统=%d ours=%d 键数=%d｜%@", n, sys ? 1 : 0, ours ? 1 : 0,
                  labels.count, labels.prefix(8).joined(separator: " ｜ "))
            if !sys && !ours && labels.count > 0 { found = true; break }
            let g = empf.buttons["下一个键盘"]
            guard g.exists, g.isHittable else {
                NSLog("TLEM 🚨 找不到「下一个键盘」键，停"); break
            }
            g.tap()
            Thread.sleep(forTimeInterval: 3.0)
        }
        NSLog("TLEM 切到 Typeless 键盘了吗=%d", found ? 1 : 0)
        guard found else { NSLog("TLEM 🚨 没切到，本轮作废"); return }

        NSLog("TLEM 按之前：eMPF=%d Typeless主App=%d", empf.state.rawValue, tl.state.rawValue)
        empf.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.86)).tap()
        NSLog("TLEM ✅ 按了麦克风（0.50,0.86）")
        for t in 1...20 {
            Thread.sleep(forTimeInterval: 1)
            NSLog("TLEM t=%ds eMPF=%d Typeless主App=%d", t, empf.state.rawValue, tl.state.rawValue)
        }
    }
}
