import Foundation
import Security

/// 新手流程的状态。**单一配置点** —— 谁都别再另存一份"是不是新用户"。
///
/// Kevin 2026-08-25：「用户下载下来后，必须要先去体验一下（就是要说一段试试），
/// 这个是系统自动推给他，必须让他试的。然后才会出现『注册登录』和
/// 『设为当前输入法』的按钮。」
///
/// 🚨🚨 **判据是"按过一次说话键"，不是"转写成功"。**
///    要求成功的话，没给麦克风权限、或者当时没网的人**会被永久锁在门外**
///    —— 首页两个按钮永远不出现，而他连出错原因都看不到。
///
/// 🚨🚨 **存两处，读时任一为真即可。**
///    Keychain 扛得过卸载重装，但**不保证写得进**（模拟器上
///    `SecItemAdd` 常返回 `errSecMissingEntitlement -34018`，
///    2026-08-25 实测就是这样：`markTried()` 调了、再读还是 false，
///    首页那两个按钮出不来）。
///    所以 UserDefaults 兜底 —— 代价是卸载重装重走一次新手流程，
///    这可以接受；"已经体验过却永远出不来"不可接受。
enum Onboard {
    private static let service = "com.kevin.transless"
    private static let account = "onboard_tried"
    private static let udKey = "transless.onboard.tried"

    /// 上一次写 Keychain 的返回码。**留着是为了能查** ——
    /// 原来 `SecItemAdd(add, nil)` 的结果直接丢掉，
    /// 写失败了没有任何人知道，只能看到"功能就是不生效"。
    private(set) static var lastKeychainStatus: OSStatus = errSecSuccess

    /// 他试过说话了没有。**两处任一为真就算数。**
    static var tried: Bool {
        if UserDefaults.standard.bool(forKey: udKey) { return true }
        return kcRead() == "1"
    }

    /// 按了说话键就算试过 —— 见上面为什么不要求转写成功。
    static func markTried() {
        // 先写 UserDefaults：它一定成功，保证功能可用
        UserDefaults.standard.set(true, forKey: udKey)
        // 再试 Keychain：成功的话卸载重装也不用重走
        kcWrite("1")
    }

    /// 诊断：**直接证据**，别猜。
    static func diag() -> String {
        """
        tried=\(tried) ud=\(UserDefaults.standard.bool(forKey: udKey))         kc=\(kcRead() ?? "nil") kcStatus=\(lastKeychainStatus)
        """
    }

    // MARK: - Keychain（跟 DeviceId 同一套写法）

    private static func kcRead() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data, let s = String(data: d, encoding: .utf8)
        else { return nil }
        return s
    }

    private static func kcWrite(_ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        // 🚨 **看返回值**。原来传 nil 直接丢掉，于是写失败了没人知道。
        lastKeychainStatus = SecItemAdd(add as CFDictionary, nil)
    }
}
