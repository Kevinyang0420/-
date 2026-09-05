import Foundation

/// 「这个 `URLSession` 错误是不是**网络够不着**」——纯函数，带坏实现自测。
///
/// 🚨🚨 **这个文件存在的原因：`err_network` 这句文案曾经【零生产者】。**
///
///    `Strings.swift` 里写着「网络连不上，检查一下网络」，
///    `FailureText` 里也留了位置 —— **但全项目没有一处会产出它**：
///    四个 `dataTask` 回调一律 `.message(err.localizedDescription)`，
///    落到 `.message` 那张关键词表 → 认不出 → 兜底 `err_other`「出了点问题」。
///    **他拔了网线，App 说的是"出了点问题"。**
///
///    这是「假检查」的近亲：**文案写对了、分类写对了，但那条路没人走**。
///
/// 🚨 **判据按 `NSURLErrorDomain` 的错误码，不按 `localizedDescription` 的文字。**
///    文字随系统语言变（他这台是中文），按文字匹配等于又建一张补不完的关键词表。
enum NetClassify {

    /// 这些码 = **够不着服务器**，跟我们的代码无关，也不是后端的错。
    /// 取自 `NSURLError*`（`Foundation` 常量，值是稳定的负数）。
    static let networkCodes: Set<Int> = [
        -1001,  // timedOut
        -1003,  // cannotFindHost
        -1004,  // cannotConnectToHost
        -1005,  // networkConnectionLost
        -1006,  // dnsLookupFailed
        -1009,  // notConnectedToInternet
        -1018,  // internationalRoamingOff
        -1019,  // callIsActive
        -1020,  // dataNotAllowed
        // 🚨 L1：TLS 这一族也是**够不着服务器**，漏了会落进兜底句「出了点问题」。
        -1200,  // secureConnectionFailed
        -1201,  // serverCertificateHasBadDate
        -1202,  // serverCertificateUntrusted
        -1203,  // serverCertificateHasUnknownRoot
        -1204,  // serverCertificateNotYetValid
        -1205,  // clientCertificateRejected
        -1015,  // cannotDecodeContentData（代理插了个错误页进来时会撞）
        -1008,  // resourceUnavailable
    ]

    static func isNetwork(domain: String, code: Int) -> Bool {
        return domain == NSURLErrorDomain && networkCodes.contains(code)
    }

    static func isNetwork(_ error: Error) -> Bool {
        let e = error as NSError
        return isNetwork(domain: e.domain, code: e.code)
    }

    // MARK: - 自测

    static func selfTest() -> [String] {
        var f: [String] = []
        // ① 断网必须认出来 —— **这条要是不成立，err_network 又变回零生产者**
        if !isNetwork(domain: NSURLErrorDomain, code: -1009) {
            f.append("断网(-1009)没被认成网络问题 —— err_network 会再次零生产者")
        }
        // ② 超时、DNS、连不上主机，都算
        for c in [-1001, -1004, -1006] where !isNetwork(domain: NSURLErrorDomain, code: c) {
            f.append("网络码 \(c) 没被认出来")
        }
        // 🚨 ③ **别的 domain 同样的码不算** —— 否则"码撞车"会把别的错误说成网络问题，
        //    而那正是 2.1 硬规矩③：**我们自己的 bug 不许推给他的网络**。
        if isNetwork(domain: "com.transless.fake", code: -1009) {
            f.append("别的 domain 的 -1009 被误判成网络问题")
        }
        // 🚨 L1 的坏样本：TLS 失败必须算网络问题（曾经整族漏掉）
        for c in [-1200, -1202, -1205, -1015, -1008]
        where !isNetwork(domain: NSURLErrorDomain, code: c) {
            f.append("TLS/传输码 \(c) 没被认出来（L1 那一族）")
        }
        // ④ 取消（-999）不是网络问题：是我们自己主动取消的
        if isNetwork(domain: NSURLErrorDomain, code: -999) {
            f.append("主动取消(-999)被误判成网络问题")
        }
        // ⑤ 后端返回的业务错误（不带 NSURLErrorDomain）不许被吃成网络问题
        if isNetwork(domain: NSCocoaErrorDomain, code: -1009) {
            f.append("Cocoa 域的错误被误判成网络问题")
        }
        return f
    }
}
