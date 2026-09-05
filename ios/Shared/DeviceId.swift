import Foundation

/// 设备身份：首次启动向后端换一个专属令牌，之后一直用它。
///
/// 🚨 为什么要它（原来全体共用 `Secrets.pass` 一把口令，三件事都做不到）：
///   1. **统计留存** —— 后端靠 device_id 才能算次日/7日留存
///   2. **按人计免费额度** —— 共享口令下额度是全局计数器；且存本地能被卸载重装绕过
///   3. **推送触达** —— 要先有设备身份才能绑推送令牌
///
/// 🚨 存 Keychain 不存 UserDefaults：
///   - UserDefaults 在键盘扩展和主 App 之间**不共享**
///   - Keychain 用 `kSecAttrAccessGroup` 可跨 target 共享（需 App Group 权限）
///   - 且 Keychain 在 App 卸载重装后**可能保留**，正好符合"别让人白嫖额度"
///
/// 🚨 拿不到令牌时**回落 `Secrets.pass`** —— 注册失败不能让人用不了。
enum DeviceId {

    private static let service = "com.kevin.transless.device"
    private static let account = "token"
    private static let didAccount = "device_id"
    private static var cached: String?

    // MARK: - Keychain

    private static func kcRead(_ acct: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data, let s = String(data: d, encoding: .utf8),
              !s.isEmpty else { return nil }
        return s
    }

    private static func kcWrite(_ acct: String, _ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        // 解锁后可用即可；不要 ThisDeviceOnly，换机恢复时能带过去
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    // MARK: - 对外

    /// 当前该用的口令：有设备令牌就用它，没有就回落共享口令。
    static var pass: String {
        if let c = cached { return c }
        if let t = kcRead(account) {
            cached = t
            return t
        }
        return Secrets.pass          // 🚨 回落：注册失败也不能让人用不了
    }

    static var deviceId: String { kcRead(didAccount) ?? "" }
    static var registered: Bool { kcRead(account) != nil }

    /// 首启注册。已注册则直接返回，不重复注册。
    static func ensure(_ done: ((Bool) -> Void)? = nil) {
        if registered { done?(true); return }
        guard let url = URL(string: Backend.base + "/api/device") else {
            done?(false); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        req.httpBody = try? JSONSerialization.data(
            withJSONObject: ["platform": "ios"])

        URLSession.shared.dataTask(with: req) { data, resp, _ in
            guard let data = data,
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tok = j["token"] as? String, !tok.isEmpty else {
                done?(false); return          // 静默失败，下次再试
            }
            kcWrite(account, tok)
            if let did = j["device_id"] as? String { kcWrite(didAccount, did) }
            cached = tok
            done?(true)
        }.resume()
    }
}
