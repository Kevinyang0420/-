import UIKit
import StoreKit

/// **订阅页** —— Kevin 09-11「这个功能得先把上」。
///
/// 苹果审核指南 3.1.2(a) 对订阅购买页的硬性要求，逐条对应到下面的控件：
///   · 服务名称                → `titleLabel`
///   · 订阅时长                → `priceLabel` 里写清"每月"
///   · 价格（本地化）           → 直接用 `product.displayPrice`，不许自己拼字符串/硬编货币符号
///   · 服务条款 + 隐私政策的可点链接 → `linksRow`
///
/// 🚨 **不许出现"还能免费用 N 次"**（核心翻译不限次，那句是假的）；
/// 🚨 **不许写"解锁高级功能"**（要说清解锁的是哪个具体功能）——
///    两条都是 Kevin 给 `loginGate` 那份文案定的规矩，这一屏是同一类文案，照搬。
final class SubscribeViewController: UIViewController {

    private let titleLabel = UILabel()
    private let priceLabel = UILabel()
    private let trialLabel = UILabel()
    private let subscribeBtn = UIButton(type: .system)
    private let restoreBtn = UIButton(type: .system)
    private let linksRow = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()
    private var product: Product?

    /// 这一屏自己的一次性提示——**不复用** `AppDelegate` 那个 `setOneOff`，
    /// 那个是"随便说点啥"那一屏的专属状态机（挂在 `phase`/`oneOff` 上），
    /// 跟这里的控件树没关系，硬接会是"看着能编译、语义对不上"的那种坑。
    private func flash(_ msg: String) {
        statusLabel.text = msg
        statusLabel.isHidden = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.prefs_pro_title
        UI.paintBg(self)

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, priceLabel, trialLabel, spinner,
            subscribeBtn, restoreBtn, statusLabel, linksRow,
        ])
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

        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = Theme.accent
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.isHidden = true

        titleLabel.text = L.prefs_pro_headline
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = Theme.text
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0

        priceLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        priceLabel.textColor = Theme.text
        priceLabel.textAlignment = .center
        priceLabel.numberOfLines = 0
        priceLabel.text = L.prefs_pro_loading

        trialLabel.font = .systemFont(ofSize: 13)
        trialLabel.textColor = Theme.dim
        trialLabel.textAlignment = .center
        trialLabel.numberOfLines = 0
        // 🚨 这里说的是【我们自己的】7 天试用（服务端按设备算），
        //    不是苹果 introductory offer——那个已经删了。措辞不能暗示"苹果给的折扣"。
        trialLabel.text = L.prefs_pro_trial_note

        subscribeBtn.setTitle(L.prefs_pro_subscribe, for: .normal)
        subscribeBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        subscribeBtn.setTitleColor(.white, for: .normal)
        subscribeBtn.backgroundColor = Theme.accent
        subscribeBtn.layer.cornerRadius = 12
        subscribeBtn.contentEdgeInsets = UIEdgeInsets(top: 14, left: 32, bottom: 14, right: 32)
        subscribeBtn.isEnabled = false
        subscribeBtn.addTarget(self, action: #selector(tapSubscribe), for: .touchUpInside)

        restoreBtn.setTitle(L.prefs_pro_restore, for: .normal)
        restoreBtn.titleLabel?.font = .systemFont(ofSize: 14)
        restoreBtn.setTitleColor(Theme.dim, for: .normal)
        restoreBtn.addTarget(self, action: #selector(tapRestore), for: .touchUpInside)

        linksRow.axis = .horizontal
        linksRow.spacing = 24
        linksRow.addArrangedSubview(linkButton(L.prefs_pro_terms, action: #selector(openTerms)))
        linksRow.addArrangedSubview(linkButton(L.prefs_pro_privacy, action: #selector(openPrivacyLink)))

        loadProduct()
    }

    private func linkButton(_ t: String, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(t, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 12)
        b.setTitleColor(Theme.dim, for: .normal)
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    private func loadProduct() {
        spinner.startAnimating()
        IAP.fetchProduct { [weak self] result in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            switch result {
            case .success(let p):
                self.product = p
                // 🚨 直接用 StoreKit 给的本地化价格串，不自己拼货币符号/汇率——
                //    那样每个地区都得自己维护一份，还容易跟真实售价对不上。
                self.priceLabel.text = p.displayPrice + L.prefs_pro_per_month_suffix
                self.subscribeBtn.isEnabled = true
            case .failure:
                self.priceLabel.text = L.prefs_pro_load_failed
                self.subscribeBtn.isEnabled = false
            }
        }
    }

    @objc private func tapSubscribe() {
        guard let p = product else { return }
        subscribeBtn.isEnabled = false
        spinner.startAnimating()
        IAP.purchase(p) { [weak self] result in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            self.subscribeBtn.isEnabled = true
            switch result {
            case .success:
                // 🚨 这里**不直接说"已经是会员了"**——真正生效要等服务端确认。
                self.flash(L.prefs_pro_purchased_wait)
                ProStatus.refreshSoonAfterPurchase()
            case .failure(.userCancelled):
                break   // 他自己点的取消，不用提示
            case .failure(.pending):
                self.flash(L.prefs_pro_pending)
            default:
                self.flash(L.prefs_pro_failed)
            }
        }
    }

    @objc private func tapRestore() {
        restoreBtn.isEnabled = false
        spinner.startAnimating()
        IAP.restore { [weak self] ok in
            guard let self = self else { return }
            self.spinner.stopAnimating()
            self.restoreBtn.isEnabled = true
            self.flash(ok ? L.prefs_pro_purchased_wait : L.prefs_pro_restore_failed)
            if ok { ProStatus.refreshSoonAfterPurchase() }
        }
    }

    // 🚨 时间紧：这两个链接先直接跳系统浏览器，**不是**在 App 内嵌渲染。
    //    苹果审核指南 3.1.2(a) 只要求"functional links"，不强制内嵌；
    //    Kevin 之前要求隐私政策不跳出 App 是**那一屏专属的产品决定**
    //    （`_规格_同步入口oneoff_20260907.md`），不是这里的硬性红线。
    //    真要内嵌，照抄 `PrivacyViewController` 那套 bundled-html 方案即可。
    @objc private func openTerms() {
        if let u = URL(string: "https://transless.net/terms") {
            UIApplication.shared.open(u)
        }
    }
    @objc private func openPrivacyLink() {
        if let u = URL(string: "https://transless.net/privacy") {
            UIApplication.shared.open(u)
        }
    }
}
