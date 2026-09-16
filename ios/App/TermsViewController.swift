import UIKit
import WebKit

/// **服务条款（端内页）** —— 09-16 Kevin 亲口点出：会员页那两个链接（服务条款/隐私政策）
/// 点了跳系统浏览器，应该跟"关于 Transless"一样做成端内原生页，不跳出 App。
/// 隐私政策那边（`PrivacyViewController`）09-07 就已经这么改了，这个文件是同一套
/// 渲染方式（原生外壳 + `WKWebView` 渲染随包 HTML），只是没有隐私政策那边的
/// "上云状态"卡片——那是隐私页专属功能，服务条款没有对应的东西。
///
/// 🚨 **文档随包走，不联网**——`Resources/terms.html`，跟 `dist/terms.html`
///    保持字节一致（09-16 发现 `push_ios.py` 之前漏推 `.html`，已经修在
///    `RES_EXT` 那张白名单上，terms.html 和 privacy.html 一起补上）。
final class TermsViewController: UIViewController {

    private let web = WKWebView()
    private let docHead = UILabel()
    private let docBox = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.prefs_pro_terms
        UI.paintBg(self)

        docBox.backgroundColor = Theme.panel
        docBox.layer.cornerRadius = 18
        docBox.layer.borderWidth = 0.6
        docBox.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        docBox.clipsToBounds = true
        docBox.translatesAutoresizingMaskIntoConstraints = false

        web.translatesAutoresizingMaskIntoConstraints = false
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        // 底部留出浮动 tab 栏高度，避免条款最后几行（通常是生效日期/联系方式）被盖住。
        web.scrollView.contentInset.bottom = 96
        web.scrollView.verticalScrollIndicatorInsets.bottom = 96
        web.navigationDelegate = self

        docHead.text = L.prefs_pro_terms
        docHead.font = .systemFont(ofSize: 13, weight: .semibold)
        docHead.textColor = Theme.dim
        docHead.accessibilityIdentifier = "terms.head.doc"
        docHead.translatesAutoresizingMaskIntoConstraints = false
        docBox.addSubview(docHead)
        docBox.addSubview(web)
        NSLayoutConstraint.activate([
            docHead.topAnchor.constraint(equalTo: docBox.topAnchor, constant: 12),
            docHead.leadingAnchor.constraint(equalTo: docBox.leadingAnchor, constant: 14),
            docHead.trailingAnchor.constraint(equalTo: docBox.trailingAnchor, constant: -14),
            web.topAnchor.constraint(equalTo: docHead.bottomAnchor, constant: 6),
            web.leadingAnchor.constraint(equalTo: docBox.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: docBox.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: docBox.bottomAnchor),
        ])

        view.addSubview(docBox)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            docBox.topAnchor.constraint(equalTo: g.topAnchor, constant: 8),
            docBox.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: Theme.pad),
            docBox.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -Theme.pad),
            docBox.bottomAnchor.constraint(equalTo: g.bottomAnchor),
        ])

        loadDoc()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.viewControllers.count == 1 {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }

    private func loadDoc() {
        guard let u = Bundle.main.url(forResource: "terms", withExtension: "html"),
              let html = try? String(contentsOf: u, encoding: .utf8) else {
            KbBridge.note("🚨 服务条款：包里没有 terms.html")
            let l = UILabel()
            l.text = Links.terms ?? ""
            l.numberOfLines = 0
            l.isUserInteractionEnabled = true
            l.textColor = Theme.dim
            l.textAlignment = .center
            l.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(l)
            NSLayoutConstraint.activate([
                l.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                l.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
            return
        }
        web.loadHTMLString(Self.themed(html), baseURL: u.deletingLastPathComponent())
    }

    /// 主题化逻辑跟 `PrivacyViewController.themed(_:)` 是同一套颜色映射，
    /// 只是各自独立一份——两个文件不共用状态，改一处不牵动另一处。
    private static func themed(_ html: String) -> String {
        let css = ""
            + "<style>"
            + "html,body{background:transparent !important;color:\(hex(Theme.text)) !important}"
            + "h1,strong{color:\(hex(Theme.text)) !important}"
            + "h2{color:\(hex(Theme.accent)) !important;border-left-color:\(hex(Theme.accent)) !important}"
            + "a{color:\(hex(Theme.accent)) !important}"
            + "code{background:rgba(255,255,255,.09) !important;color:\(hex(Theme.dim)) !important}"
            + "blockquote{background:rgba(255,255,255,.06) !important;border-left-color:\(hex(Theme.accent)) !important;color:\(hex(Theme.dim)) !important}"
            + "hr{border-top-color:rgba(255,255,255,.14) !important}"
            + "th,td{border-color:rgba(255,255,255,.16) !important;color:\(hex(Theme.text)) !important}"
            + "th{background:rgba(255,255,255,.07) !important}"
            + "</style>"
        if let r = html.range(of: "</head>") {
            return html.replacingCharacters(in: r, with: css + "</head>")
        }
        KbBridge.note("服务条款：文档里没有 </head>，样式追加到末尾")
        return html + css
    }

    private static func hex(_ c: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

extension TermsViewController: WKNavigationDelegate {
    /// 正文里的外链一律不放行——放行就等于又跳出 App 了。
    func webView(_ w: WKWebView,
                 decidePolicyFor action: WKNavigationAction,
                 decisionHandler done: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated {
            KbBridge.note("服务条款：拦下一个外链，不跳出 App")
            return done(.cancel)
        }
        done(.allow)
    }
}
