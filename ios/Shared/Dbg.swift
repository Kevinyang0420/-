import Foundation

/// 调试面包屑。**只为了拿直接证据，不是产品功能。**
///
/// 🚨 查"谁弹了麦克风权限框"时加的：我连猜了三次
///    （Voice 单例？深链走错分支？残留弹窗？）都不对 ——
///    猜三次的时间够打十个面包屑了。
enum Dbg {
    private static let key = "transless.dbg.crumbs"

    @discardableResult
    static func crumb(_ s: String) -> Bool {
        var a = UserDefaults.standard.stringArray(forKey: key) ?? []
        a.append(s)
        UserDefaults.standard.set(Array(a.suffix(20)), forKey: key)
        return true
    }

    static var trail: String {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).joined(separator: " → ")
    }
}
