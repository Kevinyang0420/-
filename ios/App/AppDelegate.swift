import UIKit

// Transless 容器 App —— **首页 + 引导**，真正干活的是键盘扩展。
//
// 🚨🚨 2026-08-25 重写：结构对齐安卓（Kevin 拍板「备份删除，然后再完全按照
//    一样的结构对齐，没什么好犹豫的」）。
//
//    原来这里是**一整套翻译界面**（两级 Tab + 麦克风 + 语气 + 语言 + 朗读，615 行）。
//    那是 2026-08-21 的产物，当时的前提是：
//        「iOS 26.6 + 免费证书侧载，键盘扩展一启动就被代码签名校验击杀，
//          键盘那条路走不通，所以在 App 内完成同样的事」
//    **这个前提已经不成立了** —— 08-25 付费发布证书签键盘扩展走通了
//    （CI run #7 逐字为证，Keyboard.appex 签名 valid on disk）。
//    前提没了，那套 App 内翻译 UI 也就没有存在理由，而它让 iOS 和安卓
//    变成两个不同的产品：他装上 TestFlight 那个包第一句话是
//    「怎么还是黑色底的呢？还是 1.0？」
//
//    旧版备份在 `ios/_backup_before_home_align/AppDelegate.swift.20260825`
//    （字节指纹核对过）。
//
// 🚨 配色和排版**全部从 `Skin.swift` 取**，那个文件是从安卓 `Skin.java`
//    生成的（`py D:\_build\sync_skin_ios.py`）。这里一个色值都不许写死 ——
//    键盘那 11 个色值一直没漂，就是因为它有生成器；主 App 这套漂了，
//    因为它只有一句「注释说要同步」。

/// 品牌语。**两端一模一样、不随界面语言变** —— 安卓那边同样是写死在
/// SettingsActivity 里，不走 strings.xml。放进 i18n 反而制造
/// "它可以被翻译"的错觉。
enum Brand {
    static let sloganZh = "让世界听懂你"
    static let sloganEn = "No Language In Between"
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ app: UIApplication,
                     didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 🚨 首启就去后端换设备令牌：留存统计 / 按人计额度 / 推送触达都靠它。
        //    异步、失败自动回落共享口令，不阻塞启动。
        DeviceId.ensure()
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = HomeViewController()
        w.makeKeyAndVisible()
        window = w
        return true
    }
}

// MARK: - 首页（对齐安卓 SettingsActivity）

/// 安卓那边的结构：右上角齿轮 → Logo + 品牌 + 中英 slogan → 两个长条。
/// 这里逐条照搬，间距用安卓的 dp 值（iOS pt 与安卓 dp 1:1）。
final class HomeViewController: UIViewController {

    private let gradient = CAGradientLayer()

    override func viewDidLoad() {
        super.viewDidLoad()

        // ---- 背景：三段渐变（安卓 Skin.screenBg）----
        // 🚨 原来这里是 `view.backgroundColor = Theme.bg`，而 Theme.bg 是
        //    **键盘**的底色 #141033 —— 他看到的「黑色底」就是这一行。
        let g = Skin.screenBg(view.bounds)
        view.layer.insertSublayer(g, at: 0)
        gradient.frame = view.bounds

        let root = UIStackView()
        root.axis = .vertical
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            root.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
        ])

        // ---- 右上角：设置 ----
        let head = UIStackView()
        head.axis = .horizontal
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        head.addArrangedSubview(spacer)
        let gear = UIButton(type: .system)
        gear.setTitle(L.prefs_entry, for: .normal)
        gear.setTitleColor(Skin.dim, for: .normal)
        gear.titleLabel?.font = .systemFont(ofSize: 14)
        gear.addTarget(self, action: #selector(openPrefs), for: .touchUpInside)
        head.addArrangedSubview(gear)
        root.addArrangedSubview(head)

        // ---- 中间：Logo + 品牌 + 两行 slogan ----
        let mid = UIStackView()
        mid.axis = .vertical
        mid.alignment = .center

        let logo = UIImageView(image: UIImage(named: "ic_logo"))
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 92),
            logo.heightAnchor.constraint(equalToConstant: 92),
        ])
        mid.addArrangedSubview(logo)

        // 🚨 字号/字距/颜色全部来自 Skin（从安卓 Skin.java 生成）。
        //    安卓那边是 Grok 定的四维度规格，属于他已经点过头的稿，
        //    不是我能自己调的东西。
        let brand = Self.label("Transless", size: Skin.brandSize,
                               kern: Skin.brandKern, color: Skin.text,
                               weight: .medium)
        mid.setCustomSpacing(21, after: logo)
        mid.addArrangedSubview(brand)

        let zh = Self.label(Brand.sloganZh, size: Skin.sloganZhSize,
                            kern: Skin.sloganZhKern, color: Skin.sloganZh,
                            weight: .regular)
        mid.setCustomSpacing(9, after: brand)
        mid.addArrangedSubview(zh)

        let en = Self.label(Brand.sloganEn, size: Skin.sloganEnSize,
                            kern: Skin.sloganEnKern, color: Skin.dim,
                            weight: .light)
        mid.setCustomSpacing(5, after: zh)
        mid.addArrangedSubview(en)

        let wrap = UIView()
        wrap.addSubview(mid)
        mid.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mid.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            mid.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            mid.leadingAnchor.constraint(greaterThanOrEqualTo: wrap.leadingAnchor),
        ])
        root.addArrangedSubview(wrap)

        // ---- 下半：两个长条 ----
        let bars = UIStackView()
        bars.axis = .vertical
        bars.spacing = 9
        bars.addArrangedSubview(bar(L.home_login, primary: false,
                                    action: #selector(loginSoon)))
        bars.addArrangedSubview(bar(L.home_set_ime, primary: true,
                                    action: #selector(openSetup)))
        root.addArrangedSubview(bars)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 🚨 渐变层不跟着 Auto Layout 走，得手动同步 frame，
        //    否则转屏之后背景只铺一半。
        view.layer.sublayers?.first?.frame = view.bounds
    }

    private static func label(_ text: String, size: CGFloat, kern: CGFloat,
                              color: UIColor, weight: UIFont.Weight) -> UILabel {
        let l = UILabel()
        l.attributedText = NSAttributedString(
            string: text,
            attributes: [.kern: kern,
                         .font: UIFont.systemFont(ofSize: size, weight: weight),
                         .foregroundColor: color])
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }

    /// 一个长条入口。安卓那边 `bar()` 的形状：整宽、圆角、右侧一个 ›。
    private func bar(_ title: String, primary: Bool,
                     action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(primary ? .white : Skin.text, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        b.backgroundColor = primary
            ? Skin.accent
            : UIColor.white.withAlphaComponent(0.09)
        b.layer.cornerRadius = 12
        b.contentHorizontalAlignment = .leading
        b.contentEdgeInsets = UIEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        b.addTarget(self, action: action, for: .touchUpInside)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let chev = UILabel()
        chev.text = "›"
        chev.textColor = primary ? .white : Skin.dim
        chev.font = .systemFont(ofSize: 20)
        chev.translatesAutoresizingMaskIntoConstraints = false
        b.addSubview(chev)
        NSLayoutConstraint.activate([
            chev.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -18),
            chev.centerYAnchor.constraint(equalTo: b.centerYAnchor),
        ])
        return b
    }

    @objc private func loginSoon() {
        // 跟安卓一样：这一版还没做，先说清楚，别让人以为按坏了。
        let a = UIAlertController(title: nil, message: L.login_next_ver,
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }

    @objc private func openSetup() {
        present(UINavigationController(rootViewController: SetupViewController()),
                animated: true)
    }

    @objc private func openPrefs() {
        present(UINavigationController(rootViewController: PrefsViewController()),
                animated: true)
    }
}

// MARK: - 引导页（对齐安卓 SetupActivity）

/// 安卓那边是三步：① 允许录音 ② 启用输入法 ③ 设为默认。
/// iOS 的键盘扩展在系统设置里启用，步骤跟安卓不是一一对应 ——
/// 🚨 **要对齐的是观感和语言，不是流程**（这条 2026-08-22 就定了）。
final class SetupViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.layer.insertSublayer(Skin.screenBg(view.bounds), at: 0)
        title = L.home_set_ime
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close))

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
        ])

        stack.addArrangedSubview(step("1", L.step_enable))
        stack.addArrangedSubview(step("2", L.step_default))
        stack.addArrangedSubview(step("3", L.step_mic))

        let go = UIButton(type: .system)
        go.setTitle(L.act_settings, for: .normal)
        go.setTitleColor(.white, for: .normal)
        go.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        go.backgroundColor = Skin.accent
        go.layer.cornerRadius = 12
        go.heightAnchor.constraint(equalToConstant: 52).isActive = true
        go.addTarget(self, action: #selector(openSystemSettings), for: .touchUpInside)
        stack.setCustomSpacing(28, after: stack.arrangedSubviews.last!)
        stack.addArrangedSubview(go)

        let notice = UILabel()
        notice.text = L.ai_notice
        notice.textColor = Skin.dim
        notice.font = .systemFont(ofSize: 12)
        notice.numberOfLines = 0
        stack.setCustomSpacing(20, after: go)
        stack.addArrangedSubview(notice)
    }

    private func step(_ n: String, _ text: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 14
        row.alignment = .center

        let num = UILabel()
        num.text = n
        num.textColor = .white
        num.font = .systemFont(ofSize: 14, weight: .medium)
        num.textAlignment = .center
        num.backgroundColor = Skin.accent2
        num.layer.cornerRadius = 14
        num.clipsToBounds = true
        num.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            num.widthAnchor.constraint(equalToConstant: 28),
            num.heightAnchor.constraint(equalToConstant: 28),
        ])
        row.addArrangedSubview(num)

        let t = UILabel()
        t.text = text
        t.textColor = Skin.text
        t.font = .systemFont(ofSize: 15)
        t.numberOfLines = 0
        row.addArrangedSubview(t)
        return row
    }

    @objc private func openSystemSettings() {
        // iOS 只能开到本 App 的设置页，键盘那一项要用户自己往下点。
        if let u = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(u)
        }
    }

    @objc private func close() { dismiss(animated: true) }
}

// MARK: - 偏好设置（占位，对齐安卓的入口）

final class PrefsViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.layer.insertSublayer(Skin.screenBg(view.bounds), at: 0)
        title = L.prefs_entry
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close))

        // 🚨 这一页安卓那边有内容（语言、语气、清历史…），iOS 先留入口。
        //    留空白页比留一个假按钮好 —— 假按钮会让人以为坏了。
        let t = UILabel()
        t.text = L.prefs_soon
        t.textColor = Skin.dim
        t.font = .systemFont(ofSize: 15)
        t.textAlignment = .center
        t.numberOfLines = 0
        t.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(t)
        NSLayoutConstraint.activate([
            t.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            t.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            t.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            t.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    @objc private func close() { dismiss(animated: true) }
}
