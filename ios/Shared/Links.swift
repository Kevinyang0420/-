import Foundation

/// 对外链接的**唯一出处**。
///
/// 🚨 抽出来是因为「关于」页也要用同一个隐私政策地址 ——
///    两处各写一份的话，哪天换域名必然漏一处，而漏掉的那处指向一个死链，
///    **点了才知道**。
enum Links {
    static let privacy = "https://transless.net/privacy.html"

    // 🚨 **服务条款目前没有页面**（全树只有 privacy 一个地址）。
    //    draft 的「法律与联系」里列了「服务条款 ›」，但我们没有那个页面 ——
    //    **不许编一个 URL 放上去**，点开是 404 比没有这一行更糟。
    //    等站点上线之后在这里加一行，「关于」页会自动多出那个入口。
    static let terms: String? = nil
}
