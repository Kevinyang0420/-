import Foundation

/// 界面语言。键名取值跟安卓一致（对齐 Lang.java）。
///
/// 🚨🚨 **它现在只在本进程内有效，不跨进程。**
///
///    我第一版写的是「照 DeviceId 已经验证过的路子走（Keychain 跨进程共享）」——
///    **那是个假前提**：Keychain 项的默认访问组是
///    `$(AppIdentifierPrefix)<bundle id>`，主 App 是 `…transless`、
///    键盘扩展是 `…transless.keyboard`，**不是同一个组**。
///    要真共享，两个 target 都得声明 `keychain-access-groups`
///    并且读写带 `kSecAttrAccessGroup` —— 而这个工程**一条 entitlement 都没有**。
///    `DeviceId.swift` 也没被验证过，它只是同样在两个进程里各存各的。
///
///    **我把「别处也这么写」当成了「这么写是对的」。**（交叉审查 H5）
///
///    要修得动签名和描述文件（配 App Group + entitlements），那是单独一件事。
///    在那之前**别在注释里写"共享"** —— 写了下一个人就会当真。
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
        // 🚨🚨 **必须跟 `L` 用同一个来源**（2026-08-28 改）。
        //    原来这里读 `Locale.preferredLanguages`（用户的**原始偏好**），
        //    而 `Strings.swift` 的 `L` 读 `Bundle.main.preferredLocalizations`
        //    （系统**解析后**的结果 = 用户偏好 ∩ 我们声明支持的语言）。
        //    **同一件事两个来源，它们会不一致**：
        //    用户偏好是我们没声明的语言（如 `yue-Hant-HK`）时，
        //    系统可能解析成 `zh-Hant`（于是 L 出繁体），
        //    而这里按原始偏好判成 `en` —— **界面一半中文一半英文**。
        //    这跟安卓 2026-08-28 那条「中文系统显示全英文」是同族：
        //    **同一个语言判断有两个真值。**
        //    改成读同一个来源之后，两边结构上不可能再分叉。
        //    🚨 **不留 `?? Locale.preferredLanguages` 这个兜底** ——
        //       那等于把第二个来源又请回来了（`gate_lang_single_source.py`
        //       当场抓住了我自己写的这一行）。
        //       `preferredLocalizations` 至少会返回开发语言，不会是空。
        let pref = Bundle.main.preferredLocalizations.first ?? "en"
        if pref.hasPrefix("zh") {
            return (pref.contains("Hant") || pref.contains("TW")
                    || pref.contains("HK")) ? hant : zh
        }
        return en
    }
}
