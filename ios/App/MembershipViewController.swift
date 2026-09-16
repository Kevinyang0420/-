import UIKit

/// **会员状态页** —— 09-16 症状 C 修复：`.pro` 用户不该被带到付费墙 `SubscribeViewController`。
///
/// 病灶：`AccountViewController.tapMemberRow()` 原来把 `.pro`（已是会员）和
/// `.notSubscribed`（没订阅）合并成同一个 case，一起推去付费墙——审核员用的正是
/// 已订阅的白名单账号，点「订阅」会真的走进一次购买流程（Kevin 真机实测坐实，
/// Guideline 2.1 App Completeness，必拒）。见闸门 `voice_ime/verify_pro_no_paywall.py`。
///
/// 🚨 到期日展示（`pro_until`）**待 2.1 拍板**，见
/// `_规格_会员到期日展示契约_待2.1定案_20260916.md`（选项 A/B/C 都还没定）。
/// 这一版先用最保守的 A1：只显示状态词，不显示具体到期日——不预判 2.1 的选择，
/// 以后真要加，只需要在这一屏加一行，不用再动路由。
final class MembershipViewController: UIViewController {

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let manageBtn = UIButton(type: .system)
    private let linksRow = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.prefs_pro_title
        UI.paintBg(self)

        let stack = UIStackView(arrangedSubviews: [titleLabel, statusLabel, manageBtn, linksRow])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: Theme.pad),
            stack.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -Theme.pad),
            stack.topAnchor.constraint(equalTo: g.topAnchor, constant: 40),
        ])

        titleLabel.text = L.prefs_pro_headline
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = Theme.text
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        statusLabel.text = L.prefs_pro_active
        statusLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        statusLabel.textColor = Theme.text
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        manageBtn.setTitle(L.prefs_pro_manage, for: .normal)
        manageBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        manageBtn.setTitleColor(Theme.accent, for: .normal)
        manageBtn.addTarget(self, action: #selector(tapManage), for: .touchUpInside)

        linksRow.axis = .horizontal
        linksRow.spacing = 24
        linksRow.addArrangedSubview(linkButton(L.prefs_pro_terms, action: #selector(openTerms)))
        linksRow.addArrangedSubview(linkButton(L.prefs_pro_privacy, action: #selector(openPrivacyLink)))
    }

    private func linkButton(_ t: String, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(t, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 12)
        b.setTitleColor(Theme.dim, for: .normal)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    /// 苹果标准的订阅管理入口（系统「订阅」设置页）——这个必须跳系统，
    /// 不是我们自己的页面，Apple 也没给第三方 App 内嵌这个界面的办法。
    /// 这正是 Guideline 3.1.2 要求的"要有管理入口"。
    @objc private func tapManage() {
        if let u = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(u)
        }
    }
    // 🚨 09-16 改：这两个改成端内原生页，不跳系统浏览器——照
    // `SubscribeViewController` 同一天的改法（Kevin 亲口点名）。
    @objc private func openTerms() {
        navigationController?.pushViewController(TermsViewController(), animated: true)
    }
    @objc private func openPrivacyLink() {
        navigationController?.pushViewController(PrivacyViewController(), animated: true)
    }
}
