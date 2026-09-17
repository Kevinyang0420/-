import Foundation

/// 会员状态三态判定——**从 `ProStatus` 拆出来的纯函数部分**。
///
/// 🚨 `ProStatus` 本身牵着 `Backend`/`KbBridge`/`URLSession`，编不进 UI 测试包
///    （UI 测试是独立进程，`@testable import Transless` 链接不到主 App 的符号）。
///    但"没登录 vs 没订阅 vs 查不到"这道判断——`_spec_not_logged_in_vs_not_subscribed.md`
///    那次真机 bug 的根子——不该因为编不进去就没有判据挡着，所以单独拆成这个
///    不碰网络、不碰存储的小文件，跟 `Remind`/`ThinkHint` 那一批同一个做法。
enum ProCheckResult: Equatable {
    case pro(until: TimeInterval)
    /// 后端明确说没登录（`reason` 字段存在）。**点进去该去登录页，不是付款页**——
    /// 这个人可能已经付过钱了，引去付款页 = 让他重复付费的路径。
    case notLoggedIn
    /// 登录了，但确实没订阅。点进去才是付款页。
    case notSubscribed
    /// 网络失败 / HTTP 非 200（含 503）。**不代表任何真实状态**，
    /// 界面要显示"暂时查不到"，且**绝不能清掉本地缓存**。
    case unreachable
}

enum ProCheck {
    /// 从解析好的响应字段判定三态。
    /// 🚨 **`reason` 键在不在**是区分"没登录"和"登录了没订阅"的唯一依据
    ///    ——不是看它的值是什么，是看这个键存在不存在。
    static func classify(isPro: Bool, until: TimeInterval, hasReason: Bool) -> ProCheckResult {
        if isPro { return .pro(until: until) }
        return hasReason ? .notLoggedIn : .notSubscribed
    }

    /// 🚨🚨 09-17 `_规格_价格呈现口径_20260917.md`：要不要显示"7 天免费试用"
    ///    文案的判据——`AccountViewController`（入口行）和 `SubscribeViewController`
    ///    （付费页价格行）两处共用这一条，不许各自写一遍（同一条规矩两处实现＝必漂）。
    ///    只认 `trial_days_left` 这个服务端字段本身，`nil`/`0` 都不显示，
    ///    不在客户端另算"第几天"（后端已经算好了）。
    static func showsTrial(_ trialDaysLeft: Int?) -> Bool {
        guard let d = trialDaysLeft else { return false }
        return d > 0
    }
}
