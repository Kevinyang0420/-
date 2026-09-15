import XCTest

/// `ProCheck.classify` 的判据测试——**不开模拟器就能跑**（纯逻辑）。
///
/// 🚨 这条存在的理由是 09-14 晚 Kevin 真机撞到的 bug：他的账号后端明明是
///    十年 Pro，界面却显示「未订阅」——根因是客户端把"没登录"和
///    "登录了没订阅"画成了同一句话，还把"没登录"的人指去了付款页
///    （他本来就付过钱，等于让他重复付费）。`_spec_not_logged_in_vs_not_subscribed.md`
///    的判据①明确要求：四种响应下四条文案两两不许相同。
final class ProCheckTests: XCTestCase {

    func testFourShapesClassifyToFourDistinctResults() {
        let pro = ProCheck.classify(isPro: true, until: 9_999_999_999, hasReason: false)
        let notLoggedIn = ProCheck.classify(isPro: false, until: 0, hasReason: true)
        let notSubscribed = ProCheck.classify(isPro: false, until: 0, hasReason: false)
        let unreachable = ProCheckResult.unreachable

        XCTAssertEqual(pro, .pro(until: 9_999_999_999), "pro:true 没判成 .pro")
        XCTAssertEqual(notLoggedIn, .notLoggedIn, "有 reason 键没判成 .notLoggedIn")
        XCTAssertEqual(notSubscribed, .notSubscribed, "没有 reason 键没判成 .notSubscribed")

        let all = [pro, notLoggedIn, notSubscribed, unreachable]
        for i in 0..<all.count {
            for k in (i + 1)..<all.count {
                XCTAssertNotEqual(all[i], all[k],
                    "🚨 第 \(i) 和第 \(k) 种状态判成了同一个结果 —— 这正是真机撞过的那个 bug")
            }
        }
    }

    /// 🚨 `reason` 键**存在**才算没登录，哪怕它的值是空字符串——
    ///    这条专门堵"看值而不是看键在不在"的实现方式（判据要挂在正确的字段上）。
    func testReasonKeyPresenceNotItsValueDecides() {
        XCTAssertEqual(ProCheck.classify(isPro: false, until: 0, hasReason: true), .notLoggedIn,
                       "reason 键存在（哪怕值为空），仍然应判成 .notLoggedIn")
    }

    /// 🚨 反向对照：`isPro` 优先于 `hasReason`——万一某天后端在 pro:true 时
    ///    也顺手带了别的 reason 字段（比如调试信息），不能把会员判成没登录。
    func testProTrueWinsEvenIfReasonKeyAlsoPresent() {
        XCTAssertEqual(ProCheck.classify(isPro: true, until: 123, hasReason: true),
                       .pro(until: 123),
                       "pro:true 时哪怕 reason 键也在，仍然要判成 .pro")
    }
}
