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
final class SubscribeViewController: PushedViewController {

    private let titleLabel = UILabel()
    private let priceLabel = UILabel()
    private let trialLabel = UILabel()
    private let subscribeBtn = UIButton(type: .system)
    private let restoreBtn = UIButton(type: .system)
    private let linksRow = UIStackView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let statusLabel = UILabel()
    private var product: Product?
    /// 🚨🚨 09-16 App Completeness(2.1)修复：`_iOS送审前必过清单_20260916.md`⑧——
    ///    审核员账号已是会员，点「订阅」却真走进了一次购买流程（Kevin 真机实测坐实）。
    ///    根因是这一屏进页面前一次都没读过会员状态。`isKnownPro` 在 `checkProStatus()`
    ///    确认为 `.pro` 后置 true，购买按钮隐藏 + `tapSubscribe()` 兜底拒绝，
    ///    两道闸都挂，防的是 `loadProduct()`/`checkProStatus()` 两个异步回调谁先回来的竞态。
    ///
    /// 🚨🚨 09-17 0 补的口子（付费状态枚举 S9×E1）：名字叫"已知是会员"，
    ///    但两道闸真正锁的是「买按钮准不准开」，不是"这个人是不是会员"——
    ///    `.unreachable`（服务端此刻查不到）**同样该锁住按钮**，跟"确认是会员"
    ///    共用这一个闸：都不该让人发起购买，只是理由不同（一个是已经买过，
    ///    一个是不知道买没买过）。别为这条另开一个变量，两条路径本来就要
    ///    同一套竞态防护（`loadProduct()`/`checkProStatus()` 谁先回来）。
    private var isKnownPro = false

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
        // 🚨🚨 09-17 `_规格_价格呈现口径_20260917.md`：先用缓存价格顶上，
        //    不让用户先看到"加载中"再跳成价格——`loadProduct()` 稍后还是会
        //    发起真实请求，拿到权威值后原样覆盖这一行，缓存只管**这一帧**
        //    显示什么，不代替那次真实请求。
        priceLabel.text = IAP.cachedDisplayPrice.map { $0 + L.prefs_pro_per_month_suffix }
            ?? L.prefs_pro_loading

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
        checkProStatus()
    }

    private func checkProStatus() {
        ProStatus.refresh { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .pro:
                self.showAlreadyMember()
            case .unreachable:
                // 🚨 09-17 S9×E1：查不到不代表任何真实状态，不许放行购买——
                //    `.notLoggedIn`/`.notSubscribed` 两条不动（反向控制：
                //    没订阅的人这一屏该照常能点，别改成谁都买不了）。
                self.showProStatusUnknown()
            case .notLoggedIn, .notSubscribed:
                break
            }
        }
    }

    /// 已确认是会员：收起购买入口，不给一个已经付过钱的人第二次购买的机会。
    private func showAlreadyMember() {
        isKnownPro = true
        spinner.stopAnimating()
        priceLabel.text = L.prefs_pro_active
        trialLabel.isHidden = true
        subscribeBtn.isHidden = true
        restoreBtn.isHidden = true
    }

    /// 服务端此刻查不到会员状态：**锁住购买按钮，但不下结论**——
    /// 不是「他不是会员」（那样没订阅的人会被误锁），也不是「他是会员」
    /// （那样是会员的人这一屏会消失订阅入口）。跟 `showAlreadyMember()`
    /// 共用 `isKnownPro` 这一个闸，理由见类头那条 09-17 注释。
    /// 🚨 文案复用 `L.prefs_pro_unknown`（账户页会员行同一句"暂时查不到，
    /// 点一下重试"），不新写一份——另写一份就是下一次漂移的起点。
    private func showProStatusUnknown() {
        isKnownPro = true
        spinner.stopAnimating()
        priceLabel.text = L.prefs_pro_unknown
        subscribeBtn.isEnabled = false
        trialLabel.isHidden = true
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
            guard !self.isKnownPro else { return }   // checkProStatus 已抢先确认是会员，别再把购买按钮打开
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
        guard !isKnownPro else { return }   // 兜底：万一按钮在确认结果前被点了，也不许真的发起购买
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

    // 🚨 09-16 改：端内原生页，不跳系统浏览器——Kevin 亲口点名这两个链接
    //    不该弹网页。照抄 `PrivacyViewController` 那套 bundled-html 方案，
    //    `TermsViewController` 是同一天新建的对应件（服务条款那边原来
    //    没有随包页面，`Links.terms` 一直是 nil，这次一起补上，见
    //    `Links.swift` 和 `push_ios.py` 的 `RES_EXT`）。
    @objc private func openTerms() {
        navigationController?.pushViewController(TermsViewController(), animated: true)
    }
    @objc private func openPrivacyLink() {
        navigationController?.pushViewController(PrivacyViewController(), animated: true)
    }
}
