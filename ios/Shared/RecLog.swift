import Foundation

/// 录音诊断台账。对齐安卓 `RecLog.java`。
///
/// 🚨 为什么要有它（安卓那边的由来）：Kevin 报过十次「说完话不出字」，
///    每次我都只能猜。有了这个台账，他再报时能直接看**最后一条的状态**，
///    不用靠推。
///
/// 🚨🚨 **记了但没有查看入口 = 等于没记**（他点过名的一条）。
///    所以设置页里那一项是能点开、能复制的，不是只写进文件。
///
/// 存 Keychain 的理由跟 `Lang` 一样：键盘扩展是另一个进程，
/// UserDefaults 不共享，而这个工程没配 App Group。
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
