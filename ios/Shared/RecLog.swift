import Foundation

/// 录音诊断台账。键名取值跟安卓一致（对齐 RecLog.java）。
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
enum RecLog {

    private static let service = "com.kevin.transless.prefs"
    private static let account = "rec_log"
    /// 跟安卓一致：只留最近这些条，别让它无限长。
    private static let maxItems = 20

    struct Item: Codable {
        let t: Double          // 时间戳（秒）
        let sec: Double        // 录了几秒
        let bytes: Int         // 音频字节数
        let r: String          // 结果：成功 / 失败原因
        let d: String          // 细节
    }

    // MARK: - Keychain

    private static func readRaw() -> String {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data,
              let s = String(data: d, encoding: .utf8) else { return "[]" }
        return s
    }

    private static func writeRaw(_ s: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(s.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    // MARK: - 对外

    static func items() -> [Item] {
        guard let d = readRaw().data(using: .utf8),
              let a = try? JSONDecoder().decode([Item].self, from: d)
        else { return [] }
        return a
    }

    /// 记一条。**成功失败都记** —— 只记失败的话，
    /// 「这次到底有没有跑」这个问题永远答不上来。
    static func add(sec: Double, bytes: Int, result: String, detail: String) {
        var a = items()
        a.append(Item(t: Date().timeIntervalSince1970, sec: sec,
                      bytes: bytes, r: result, d: detail))
        if a.count > maxItems { a = Array(a.suffix(maxItems)) }
        if let d = try? JSONEncoder().encode(a),
           let s = String(data: d, encoding: .utf8) {
            writeRaw(s)
        }
    }

    /// 给设置页显示用的文本。最新的在最上面。
    static func dump() -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return items().reversed().map { it in
            let when = f.string(from: Date(timeIntervalSince1970: it.t))
            let body = it.d.isEmpty ? it.r : "\(it.r)：\(it.d)"
            return String(format: "%@  %.1fs %dKB  %@",
                          when, it.sec, it.bytes / 1024, body)
        }.joined(separator: "\n")
    }

    static func clear() { writeRaw("[]") }
}
