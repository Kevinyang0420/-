import Foundation

/// 探针 App 的留痕（写自己的 UserDefaults）。
/// 🚨 TransProbe **没有 App Group 权限**，写不了共享区；
///    而写自己那份时 `devicectl copy from` 报 error 7000。
///    所以真正的判据不靠它 —— 靠 XCUITest 直接读两个 App 的前后台状态。
///    这里留着只作辅助。
enum Probe {
    static func note(_ line: String) {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm:ss"
        var a = UserDefaults.standard.array(forKey: "probe.trail") as? [String] ?? []
        a.append(f.string(from: Date()) + "  " + line)
        if a.count > 40 { a.removeFirst(a.count - 40) }
        UserDefaults.standard.set(a, forKey: "probe.trail")
        UserDefaults.standard.synchronize()
    }
}
