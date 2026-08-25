import Foundation

/// 界面语言。**键名和取值跟安卓 `Lang.java` 一模一样**
/// （`sys` / `zh` / `en` / `hant`），两端存的是同一回事。
///
/// 🚨🚨 **存 Keychain，不存 UserDefaults。**
///    `DeviceId.swift` 里已经写清楚了：「UserDefaults 在键盘扩展和主 App 之间
///    **不共享**」。我第一版写的是 `UserDefaults(suiteName: "group.…")` ——
///    而这个工程**根本没配 App Group**，`suiteName` 拿不到就**静默回落**到
///    `.standard`，于是主 App 里改了语言、键盘扩展读不到，
///    而且不报任何错。
///    照 DeviceId 已经验证过的路子走，不自己另开一套。
enum Lang {
    static let sys = "sys"
    static let zh = "zh"
    static let en = "en"
    static let hant = "hant"

    /// 顺序跟安卓弹窗一致：跟随系统 → 简体 → 繁體 → English
    static let all = [sys, zh, hant, en]

    private static let service = "com.kevin.transless.prefs"
    private static let account = "lang.ui"

    private static func read() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data, let s = String(data: d, encoding: .utf8),
              !s.isEmpty else { return nil }
        return s
    }

    private static func write(_ v: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(v.utf8)
        add[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static var current: String {
        let v = read() ?? sys
        return [zh, en, hant].contains(v) ? v : sys
    }

    static func set(_ v: String) { write(v) }

    static func label(_ v: String) -> String {
        switch v {
        case zh: return "简体中文"
        case hant: return "繁體中文"
        case en: return "English"
        default: return L.lang_follow_system
        }
    }

    /// 实际生效的语言码（把 `sys` 解析成具体一档）。
    ///
    /// 🚨 判断"要不要重建界面"必须比**这个**，不能比 `current`：
    ///    偏好是「跟随系统」时用户改手机语言，`current` 前后都是 `sys`、
    ///    看不出变化。安卓那边为这条栽过，注释里写着。
    static var effective: String {
        let c = current
        if c != sys { return c }
        let pref = Locale.preferredLanguages.first ?? "en"
        if pref.hasPrefix("zh") {
            return (pref.contains("Hant") || pref.contains("TW")
                    || pref.contains("HK")) ? hant : zh
        }
        return en
    }
}
