import XCTest

/// **在 TransProbe（我们自己的、没有 URL scheme 的 App）里驱动 Typeless 键盘录音，看它怎么回来。**
/// eMPF 的无障碍树查不了（kAXErrorIllegalArgument），换这个宿主：同样没 scheme，且 AX 可用。
final class TypelessInProbe: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    /// 对照组：同一流程换成 Transless 键盘（主 App 由 Mac 侧杀掉），看宿主/主App 的状态是不是同一种形态。
    func testTranslessMicInProbe() throws {
        let host = XCUIApplication()
        let me = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        host.launch()
        XCTAssertTrue(host.wait(for: .runningForeground, timeout: 25))
        Thread.sleep(forTimeInterval: 2.5)
        let f = host.textFields["probe.field"]; if f.exists { f.tap() }
        Thread.sleep(forTimeInterval: 2.0)
        // 已经是我们的键盘就别再切（再选一次会切走）；不是就长按地球选，最多试 3 轮
        var mic = host.buttons["transless.mic"]
        var tries = 0
        while !mic.waitForExistence(timeout: 4) && tries < 3 {
            tries += 1
            let globe = host.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.945))
            globe.press(forDuration: 1.3); Thread.sleep(forTimeInterval: 1.8)
            let row = host.cells.matching(NSPredicate(format: "label BEGINSWITH[c] 'Transless'")).firstMatch
            if row.waitForExistence(timeout: 3) { row.tap(); NSLog("TLCT 第%d轮选了 Transless", tries) }
            else { NSLog("TLCT 🚨 菜单里没有 Transless"); host.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
            Thread.sleep(forTimeInterval: 3.5)
            mic = host.buttons["transless.mic"]
        }
        if !mic.exists {
            var labels: [String] = []
            for i in 0..<min(host.buttons.count, 60) {
                let b = host.buttons.element(boundBy: i)
                let t = b.label + "/" + b.identifier
                if t != "/" { labels.append(t) }
            }
            NSLog("TLCT 键位清单（%d）：%@", labels.count, labels.prefix(30).joined(separator: " ｜ "))
            let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = "CT_nomic"; a.lifetime = .keepAlways; add(a)
            NSLog("TLCT 🚨 三轮都没看到我们的麦克风键"); return
        }
        NSLog("TLCT 按之前：宿主=%d 我们主App=%d", host.state.rawValue, me.state.rawValue)
        mic.tap()
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for t in 1...25 {
            Thread.sleep(forTimeInterval: 1)
            NSLog("TLCT t=%ds 宿主=%d 我们主App=%d 桌面=%d", t, host.state.rawValue, me.state.rawValue, sb.state.rawValue)
            if [1, 3, 6, 10, 15, 25].contains(t) {
                let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); a.name = "CT_t\(t)"; a.lifetime = .keepAlways; add(a)
            }
        }
    }

    func testTypelessMicInProbe() throws {
        let host = XCUIApplication()                      // TransProbe（被测 App）
        let tl = XCUIApplication(bundleIdentifier: "com.typeless.mobile")
        host.launch()
        XCTAssertTrue(host.wait(for: .runningForeground, timeout: 25), "TransProbe 没起来")
        Thread.sleep(forTimeInterval: 2.5)
        NSLog("TLPR 开始：Typeless主App=%d（4=前台 2=后台 1=没跑）", tl.state.rawValue)
        let f = host.textFields["probe.field"]
        if f.exists { f.tap() } else { host.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24)).tap() }
        Thread.sleep(forTimeInterval: 2.0)

        // 🚨 iOS 26 短按地球只在拼音↔英文之间来回（实测 12 轮），第三方永远轮不到。
        //    照 KeyboardUITests 的写法：长按地球 → 菜单 → 选名字含 Typeless 的那项。
        var found = false
        let globe = host.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.945))
        for attempt in 0..<3 {
            globe.press(forDuration: 1.3)
            Thread.sleep(forTimeInterval: 1.8)
            // 🚨 iOS 26 长按菜单里键盘名那几行不是 button（上一轮只扫 buttons，菜单里只剩"布局"）
            let all = host.descendants(matching: .any)
            var menu: [String] = []
            let n = min(all.count, 120)
            for i in 0..<n {
                let e = all.element(boundBy: i)
                if e.exists, !e.label.isEmpty, e.label.count < 30 { menu.append(e.label + "(" + String(e.elementType.rawValue) + ")") }
            }
            NSLog("TLPR 长按地球第%d次，菜单元素：%@", attempt, menu.prefix(30).joined(separator: " ｜ "))
            // 🚨 键盘行是 cell（类型 75）。按下标点会因为查询重算点到别的元素（上一轮点了个空的）
            //    → 直接按 label 定位那一格。
            var picked = false
            let row = host.cells.matching(NSPredicate(format: "label BEGINSWITH[c] 'Typeless'")).firstMatch
            if row.waitForExistence(timeout: 3) {
                NSLog("TLPR 找到行「%@」hittable=%d", row.label, row.isHittable ? 1 : 0)
                row.tap(); picked = true
            } else {
                let st = host.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] 'Typeless'")).firstMatch
                if st.waitForExistence(timeout: 2) { st.tap(); picked = true; NSLog("TLPR 点了文字「%@」", st.label) }
            }
            if !picked { host.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap(); Thread.sleep(forTimeInterval: 1.0); continue }
            Thread.sleep(forTimeInterval: 3.5)
            var labels: [String] = []
            for i in 0..<min(host.buttons.count, 60) {
                let b = host.buttons.element(boundBy: i)
                let t = b.label + "/" + b.identifier
                if t != "/" { labels.append(t) }
            }
            // 🚨 「听写」是 iOS 26 给第三方键盘配的系统底栏（🌐/🎤），不能当"系统键盘"的证据。
            //    系统键盘的证据是字母键 / shift / 表情符号。
            let sysKb = labels.contains { $0.hasPrefix("Q/") || $0.hasPrefix("W/") || $0.contains("shift/") || $0.contains("表情符号") || $0.contains("Emoji") }
            let ours = labels.contains { $0.contains("transless.mic") }
            NSLog("TLPR 选完：系统键盘=%d ours=%d 键数=%d｜%@", sysKb ? 1 : 0, ours ? 1 : 0, labels.count, labels.prefix(8).joined(separator: " ｜ "))
            if !sysKb && !ours { found = true; break }
        }
        NSLog("TLPR 切到 Typeless 键盘了吗=%d", found ? 1 : 0)
        guard found else { NSLog("TLPR 🚨 没切到，本轮作废"); return }

        NSLog("TLPR 按之前：宿主=%d Typeless主App=%d", host.state.rawValue, tl.state.rawValue)
        // 先把 Typeless 键盘区域里所有元素的位置打出来（下次就知道麦克风在哪，不用猜）
        let scr = host.frame
        let all2 = host.descendants(matching: .any)
        for i in 0..<min(all2.count, 80) {
            let e = all2.element(boundBy: i)
            guard e.exists else { continue }
            let f = e.frame
            let ny = (f.midY - scr.minY) / scr.height
            if ny > 0.55 && f.width > 20 && f.height > 20 && f.height < 400 {
                NSLog("TLPR   元素 类型=%d \"%@\" 中心(%.2f,%.2f) %.0fx%.0f", e.elementType.rawValue, e.label,
                      (f.midX - scr.minX) / scr.width, ny, f.width, f.height)
            }
        }
        // 🚨 Typeless 的按钮没有 AX 标签，找不到麦克风 → 扫描：主 App 死着时按麦克风它必跳，
        //    哪一下让 Typeless 主 App 从「没跑」变成「起来」，哪一下就是麦克风。
        // 🚨 不看初始状态（主 App 可能活着）：按完后「Typeless 主 App 到前台」或「宿主离开前台」= 命中
        var hitY: Double = -1
        outer: for y in stride(from: 0.66, through: 0.96, by: 0.04) {
            host.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y)).tap()
            for _ in 0..<6 {
                Thread.sleep(forTimeInterval: 0.5)
                if tl.state == .runningForeground || host.state != .runningForeground { hitY = y; break outer }
            }
            NSLog("TLPR 扫 y=%.2f：宿主=%d 主App=%d", y, host.state.rawValue, tl.state.rawValue)
        }
        NSLog("TLPR 🎯 麦克风命中 y=%.2f（-1=整列都没让主App起来）", hitY)
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for t in 1...25 {
            Thread.sleep(forTimeInterval: 1)
            NSLog("TLPR t=%ds 宿主=%d Typeless主App=%d 桌面=%d", t, host.state.rawValue, tl.state.rawValue, sb.state.rawValue)
            if [1,2,3,4,5,6,8,10,13,16,20,25].contains(t) {
                let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                a.name = "TLP_t\(t)"; a.lifetime = .keepAlways; add(a)
            }
            if [1, 3, 6, 10, 15, 25].contains(t) {
                let shot = XCUIScreen.main.screenshot()
                let a = XCTAttachment(screenshot: shot); a.name = "TL_t\(t)"; a.lifetime = .keepAlways
                add(a)
            }
        }
    }
}
