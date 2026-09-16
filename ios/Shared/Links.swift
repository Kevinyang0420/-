import Foundation

/// 对外链接的**唯一出处**。
///
/// 🚨 抽出来是因为「关于」页也要用同一个隐私政策地址 ——
///    两处各写一份的话，哪天换域名必然漏一处，而漏掉的那处指向一个死链，
///    **点了才知道**。
enum Links {
    static let privacy = "https://transless.net/privacy.html"

    /// 🚨 09-16 核实：**这条不再是 nil** —— 之前留 nil 是因为站点还没有这个页面
    ///    （见下面旧注释，仍留着说明历史）。WebFetch 实测 `transless.net/terms`
    ///    现在是真实条款正文（v1.2，生效日 2026-09-13），不是空页/404。
    ///    随包副本在 `ios/Resources/terms.html`，跟 `dist/terms.html` 字节一致。
    ///
    /// （旧注释，历史存档）服务条款目前没有页面：draft 的「法律与联系」里列了
    /// 「服务条款 ›」，但当时没有那个页面 —— 不许编一个 URL 放上去，点开是
    /// 404 比没有这一行更糟。这条规矩本身没变，只是前提（有没有页面）现在变了。
    static let terms: String? = "https://transless.net/terms"
}
