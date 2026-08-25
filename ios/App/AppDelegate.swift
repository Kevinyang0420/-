import UIKit
import AVFoundation

// Transless 容器 App —— **四个界面全部对齐安卓**：开屏 / 首页 / 引导 / 设置。
//
// 🚨🚨 Kevin 2026-08-25：「我是让你所有的 APP 的界面、功能、结构、UI
//    跟安卓的保持一模一样」。
//
// 🚨 我上一版只做了首页就把 App 里那套翻译界面删了，理由是「干活的是键盘」——
//    **那句话在安卓成立，在 iOS 不成立**：iOS 键盘扩展只有 267 行、
//    就一个麦克风，没有拼音/字母/符号/手写/九宫格（安卓那一套 4434 行）。
//    我删之前**没查 iOS 键盘里到底有什么**，直接套用了安卓的结论，
//    结果把 iOS 从"App 里还能用"变成"哪儿都不能用"。
//    他的原话：「搞了一下午就搞出一个废物出来」。
//
// 🚨 配色排版一律从 `Skin.swift` 取（由 `sync_skin_ios.py` 从安卓
//    `Skin.java` 生成）。图标和 logo 由 `sync_ios_icon.py` 从安卓的图生成。
//    这里一个色值、一张图都不许写死。

/// 品牌语。两端一模一样、不随界面语言变（安卓那边也是写死在代码里）。
enum Brand {
    static let sloganZh = "让世界听懂你"
    static let sloganEn = "No Language In Between"
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ app: UIApplication,
                     didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        DeviceId.ensure()
        let w = UIWindow(frame: UIScreen.main.bounds)
        // 🚨 跟安卓一样：先开屏，再进首页。安卓那边 LAUNCHER 指向 SplashActivity。
        w.rootViewController = SplashViewController()
        w.makeKeyAndVisible()
        window = w
        return true
    }
}

// MARK: - 共用的皮肤件（对齐安卓 Skin）

enum UI {
    /// 三段渐变背景。**每个界面都铺**，跟安卓一致。
    static func paintBg(_ vc: UIViewController) {
        let g = Skin.screenBg(vc.view.bounds)
        g.name = "skinBg"
        vc.view.layer.insertSublayer(g, at: 0)
    }

    /// 🚨 渐变层不跟 Auto Layout 走，转屏后要手动同步 frame，
    ///    否则背景只铺一半。
    static func resizeBg(_ vc: UIViewController) {
        vc.view.layer.sublayers?.first(where: { $0.name == "skinBg" })?
            .frame = vc.view.bounds
    }

    static func label(_ text: String, size: CGFloat, kern: CGFloat,
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
}

// MARK: - ① 开屏（对齐安卓 SplashActivity）

/// 安卓：Logo 常驻，中文 slogan 260ms 起浮出、英文 1180ms 起，HOLD 2600ms。
/// 🚨 淡入**自己按时间推**，不用系统动画 —— 安卓那边的教训是
///    系统「动画时长缩放」会把它乘一遍（关掉时字啪地跳出来，
///    Kevin 说「像一个青蛙一样跳出来」）。iOS 没有那个全局开关，
///    但按时间推同样稳，而且两端行为一致。
final class SplashViewController: UIViewController {

    private let logo = UIImageView(image: UIImage(named: "logo"))
    private let zh = UI.label(Brand.sloganZh, size: Skin.sloganZhSize,
                              kern: Skin.sloganZhKern, color: Skin.sloganZh,
                              weight: .regular)
    private let en = UI.label(Brand.sloganEn, size: Skin.sloganEnSize,
                              kern: Skin.sloganEnKern, color: Skin.dim,
                              weight: .light)
    private let brand = UI.label("Transless", size: Skin.brandSize,
                                 kern: Skin.brandKern, color: Skin.text,
                                 weight: .medium)
    private var went = false

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)

        let stack = UIStackView(arrangedSubviews: [logo, brand, zh, en])
        stack.axis = .vertical
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        logo.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 92),
            logo.heightAnchor.constraint(equalToConstant: 92),
        ])
        stack.setCustomSpacing(21, after: logo)
        stack.setCustomSpacing(9, after: brand)
        stack.setCustomSpacing(5, after: zh)

        zh.alpha = 0
        en.alpha = 0
        fade(zh, delay: 0.26)
        fade(en, delay: 1.18)

        // 🚨 无条件跳转，绝不能卡死在开屏（安卓同样的兜底）。
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            self?.go()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    /// 620ms 淡入 + 12pt 上浮，自己按时间推。
    private func fade(_ v: UIView, delay: Double) {
        let dur = 0.62
        let rise: CGFloat = 12
        v.transform = CGAffineTransform(translationX: 0, y: rise)
        let t0 = CACurrentMediaTime() + delay
        func step() {
            let dt = CACurrentMediaTime() - t0
            if dt < 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { step() }
                return
            }
            var k = min(1, dt / dur)
            k = k * k * (3 - 2 * k)      // smoothstep，别是生硬的线性
            v.alpha = CGFloat(k)
            v.transform = CGAffineTransform(translationX: 0,
                                            y: rise * CGFloat(1 - k))
            if k < 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { step() }
            }
        }
        step()
        // 🚨 兜底：到点还没亮就直接写死。安卓那边这条被删过一次，
        //    注释还留着而代码没了 —— 开屏可以不好看，但不能少一行字。
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + dur + 0.4) {
            if v.alpha < 1 {
                v.alpha = 1
                v.transform = .identity
            }
        }
    }

    private func go() {
        guard !went else { return }     // 只走一次
        went = true
        let home = UINavigationController(rootViewController: HomeViewController())
        home.modalTransitionStyle = .crossDissolve
        home.modalPresentationStyle = .fullScreen
        home.setNavigationBarHidden(true, animated: false)
        UIApplication.shared.windows.first?.rootViewController = home
    }
}

// MARK: - ② 首页（对齐安卓 SettingsActivity）

final class HomeViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)

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

        // 右上角：设置
        let head = UIStackView()
        head.axis = .horizontal
        let sp = UIView()
        sp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        head.addArrangedSubview(sp)
        let gear = UIButton(type: .system)
        gear.setTitle(L.prefs_entry, for: .normal)
        gear.setTitleColor(Skin.dim, for: .normal)
        gear.titleLabel?.font = .systemFont(ofSize: 14)
        gear.addTarget(self, action: #selector(openPrefs), for: .touchUpInside)
        head.addArrangedSubview(gear)
        root.addArrangedSubview(head)

        // 中间：Logo + 品牌 + 两行 slogan
        // 🚨 资源名是 **logo**，不是安卓的 `ic_logo` —— 我上一版照抄安卓写错了，
        //    而 `UIImage(named:)` 找不到时**返回 nil、静默不显示**，
        //    编译不报、静态检查也查不出，Kevin 装上才看到"没有 logo"。
        let logo = UIImageView(image: UIImage(named: "logo"))
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logo.widthAnchor.constraint(equalToConstant: 92),
            logo.heightAnchor.constraint(equalToConstant: 92),
        ])
        let brand = UI.label("Transless", size: Skin.brandSize,
                             kern: Skin.brandKern, color: Skin.text,
                             weight: .medium)
        let zh = UI.label(Brand.sloganZh, size: Skin.sloganZhSize,
                          kern: Skin.sloganZhKern, color: Skin.sloganZh,
                          weight: .regular)
        let en = UI.label(Brand.sloganEn, size: Skin.sloganEnSize,
                          kern: Skin.sloganEnKern, color: Skin.dim,
                          weight: .light)
        let mid = UIStackView(arrangedSubviews: [logo, brand, zh, en])
        mid.axis = .vertical
        mid.alignment = .center
        mid.setCustomSpacing(21, after: logo)
        mid.setCustomSpacing(9, after: brand)
        mid.setCustomSpacing(5, after: zh)

        let wrap = UIView()
        wrap.addSubview(mid)
        mid.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mid.centerXAnchor.constraint(equalTo: wrap.centerXAnchor),
            mid.centerYAnchor.constraint(equalTo: wrap.centerYAnchor),
            mid.leadingAnchor.constraint(greaterThanOrEqualTo: wrap.leadingAnchor),
        ])
        root.addArrangedSubview(wrap)

        // 下半：两个长条
        let bars = UIStackView()
        bars.axis = .vertical
        bars.spacing = 9
        bars.addArrangedSubview(Bars.make(L.home_login, primary: false,
                                          target: self,
                                          action: #selector(loginSoon)))
        bars.addArrangedSubview(Bars.make(L.home_set_ime, primary: true,
                                          target: self,
                                          action: #selector(openSetup)))
        root.addArrangedSubview(bars)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    @objc private func loginSoon() {
        let a = UIAlertController(title: nil, message: L.login_next_ver,
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default))
        present(a, animated: true)
    }

    @objc private func openSetup() {
        navigationController?.pushViewController(SetupViewController(),
                                                 animated: true)
    }

    @objc private func openPrefs() {
        navigationController?.pushViewController(PrefsViewController(),
                                                 animated: true)
    }
}

/// 首页那两个长条。抽出来给设置页复用，免得两处各画一遍。
enum Bars {
    static func make(_ title: String, primary: Bool,
                     target: Any, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(primary ? .white : Skin.text, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        b.backgroundColor = primary ? Skin.accent
                                    : UIColor.white.withAlphaComponent(0.09)
        b.layer.cornerRadius = 12
        b.contentHorizontalAlignment = .leading
        b.contentEdgeInsets = UIEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        b.addTarget(target, action: action, for: .touchUpInside)
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
}

// MARK: - ③ 引导页（对齐安卓 SetupActivity）

/// 安卓是三步带**状态检测**：每步显示「去开启」或「已完成」。
///
/// 🚨 **步骤内容按 iOS 的实际要求写，不照抄安卓的字面**
///    （这是 2026-08-22 定的口径：「要对齐的是观感和语言，不是流程」）。
///    安卓第 ③ 步是"设为默认输入法"，iOS 根本没有这个概念 ——
///    照抄会写出一句做不到的指引，比不写还糟。
///    iOS 的三步是：加键盘 → 允许完全访问 → 允许麦克风。
final class SetupViewController: UIViewController {

    private var rows: [(UIView, UILabel, UILabel)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.home_set_ime

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
        ])

        let h1 = UILabel()
        h1.text = L.home_set_ime
        h1.font = .systemFont(ofSize: 21, weight: .medium)
        h1.textColor = Skin.text
        stack.addArrangedSubview(h1)
        stack.setCustomSpacing(20, after: h1)

        for (n, t) in [("1", L.ios_step_add),
                       ("2", L.ios_step_full),
                       ("3", L.step_mic)] {
            let (row, num, state) = makeRow(n, t)
            rows.append((row, num, state))
            stack.addArrangedSubview(row)
        }

        let go = UIButton(type: .system)
        go.setTitle(L.act_settings, for: .normal)
        go.setTitleColor(.white, for: .normal)
        go.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        go.backgroundColor = Skin.accent
        go.layer.cornerRadius = 12
        go.heightAnchor.constraint(equalToConstant: 52).isActive = true
        go.addTarget(self, action: #selector(openSystemSettings),
                     for: .touchUpInside)
        stack.setCustomSpacing(26, after: rows.last!.0)
        stack.addArrangedSubview(go)

        let notice = UILabel()
        notice.text = L.ai_notice
        notice.textColor = Skin.dim
        notice.font = .systemFont(ofSize: 12)
        notice.numberOfLines = 0
        stack.setCustomSpacing(18, after: go)
        stack.addArrangedSubview(notice)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    override func viewWillAppear(_ a: Bool) {
        super.viewWillAppear(a)
        refresh()      // 从系统设置回来要重新查状态
    }

    /// 🚨 每一步的状态**真的去查**，不是写死"未完成"。
    ///    安卓那边就是查出来的（权限 / 已启用输入法 / 是否默认）。
    private func refresh() {
        let added = Self.keyboardAdded()
        let mic = AVAudioSession.sharedInstance().recordPermission == .granted
        // 🚨 「完全访问」在容器 App 里**查不到** —— 那是键盘扩展侧的状态，
        //    系统没给容器 App 这个接口。所以这一项如实显示"去设置里开"，
        //    不假装知道。宁可少报一个状态，也不报一个可能是错的。
        let states: [Bool?] = [added, nil, mic]
        for (i, s) in states.enumerated() {
            let (_, num, lab) = rows[i]
            switch s {
            case .some(true):
                lab.text = L.done_enabled
                lab.textColor = Skin.ok
                num.backgroundColor = Skin.ok
            case .some(false):
                lab.text = L.act_enable
                lab.textColor = Skin.dim
                num.backgroundColor = Skin.accent2
            case .none:
                lab.text = L.act_settings
                lab.textColor = Skin.dim
                num.backgroundColor = Skin.accent2
            }
        }
    }

    /// 我们的键盘有没有被添加到系统键盘列表里。
    static func keyboardAdded() -> Bool {
        let mine = (Bundle.main.bundleIdentifier ?? "") + ".keyboard"
        return UITextInputMode.activeInputModes.contains {
            ($0.value(forKey: "identifier") as? String)?.hasPrefix(mine) ?? false
        }
    }

    private func makeRow(_ n: String, _ text: String)
        -> (UIView, UILabel, UILabel) {
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

        let state = UILabel()
        state.font = .systemFont(ofSize: 13)
        state.textColor = Skin.dim
        state.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(state)
        return (row, num, state)
    }

    @objc private func openSystemSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(u)
        }
    }
}

// MARK: - ④ 设置（对齐安卓 PrefsActivity 的四组）

final class PrefsViewController: UIViewController {

    private let list = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.prefs_title

        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sv)
        list.axis = .vertical
        list.translatesAutoresizingMaskIntoConstraints = false
        sv.addSubview(list)
        NSLayoutConstraint.activate([
            sv.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            sv.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            sv.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            sv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            list.topAnchor.constraint(equalTo: sv.topAnchor),
            list.leadingAnchor.constraint(equalTo: sv.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: sv.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: sv.bottomAnchor),
            list.widthAnchor.constraint(equalTo: sv.widthAnchor),
        ])
        build()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    override func viewWillAppear(_ a: Bool) {
        super.viewWillAppear(a)
        build()      // 状态可能变了（比如刚去加了键盘）
    }

    private func build() {
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // ① 输入法
        list.addArrangedSubview(group(L.prefs_g_ime))
        let on = SetupViewController.keyboardAdded()
        list.addArrangedSubview(row(L.home_set_ime,
                                    on ? L.prefs_ime_on : L.prefs_ime_off,
                                    #selector(openSetup)))

        // ② 偏好
        list.addArrangedSubview(group(L.prefs_g_pref))
        list.addArrangedSubview(row(L.lang_title, Lang.label(Lang.current),
                                    #selector(pickLanguage)))

        // ③ 诊断
        list.addArrangedSubview(group(L.prefs_g_diag))
        list.addArrangedSubview(row(L.rec_log_title, L.prefs_diag_sub,
                                    #selector(showRecLog)))

        // ④ 关于
        list.addArrangedSubview(group(L.prefs_g_about))
        let ver = (Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                   as? String) ?? "?"
        list.addArrangedSubview(row(L.prefs_about, ver, nil))
        // 🚨 安卓的「检查更新」是连他局域网那台机下载 APK 的。
        //    **iOS 上不存在这条路** —— 苹果不允许 App 自己装包。
        //    所以这一项如实说明走 TestFlight，不做一个按了没反应的假按钮。
        list.addArrangedSubview(row(L.prefs_check_update, L.ios_update_note,
                                    nil))
    }

    private func group(_ s: String) -> UILabel {
        let t = UILabel()
        t.text = s
        t.font = .systemFont(ofSize: 12)
        // 安卓那边是 argb(0xB0, 0x8B, 0x7F, 0xB0)
        t.textColor = UIColor(red: 0x8B / 255.0, green: 0x7F / 255.0,
                              blue: 0xB0 / 255.0, alpha: 0xB0 / 255.0)
        t.translatesAutoresizingMaskIntoConstraints = false
        let box = UIView()
        box.addSubview(t)
        NSLayoutConstraint.activate([
            t.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 6),
            t.topAnchor.constraint(equalTo: box.topAnchor, constant: 16),
            t.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
        ])
        let w = UIStackView(arrangedSubviews: [box])
        w.axis = .vertical
        _ = w
        return t
    }

    private func row(_ title: String, _ sub: String?,
                     _ action: Selector?) -> UIView {
        let b = UIControl()
        b.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        b.layer.cornerRadius = 12
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true

        let t = UILabel()
        t.text = title
        t.textColor = Skin.text
        t.font = .systemFont(ofSize: 16)
        let s = UILabel()
        s.text = sub
        s.textColor = Skin.dim
        s.font = .systemFont(ofSize: 13)
        s.numberOfLines = 0
        let col = UIStackView(arrangedSubviews: sub == nil ? [t] : [t, s])
        col.axis = .vertical
        col.spacing = 3
        col.isUserInteractionEnabled = false
        col.translatesAutoresizingMaskIntoConstraints = false
        b.addSubview(col)
        NSLayoutConstraint.activate([
            col.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: 16),
            col.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -34),
            col.topAnchor.constraint(equalTo: b.topAnchor, constant: 11),
            col.bottomAnchor.constraint(equalTo: b.bottomAnchor, constant: -11),
        ])
        if let a = action {
            b.addTarget(self, action: a, for: .touchUpInside)
            let chev = UILabel()
            chev.text = "›"
            chev.textColor = Skin.dim
            chev.font = .systemFont(ofSize: 20)
            chev.translatesAutoresizingMaskIntoConstraints = false
            b.addSubview(chev)
            NSLayoutConstraint.activate([
                chev.trailingAnchor.constraint(equalTo: b.trailingAnchor,
                                               constant: -16),
                chev.centerYAnchor.constraint(equalTo: b.centerYAnchor),
            ])
        }
        let pad = UIView()
        pad.translatesAutoresizingMaskIntoConstraints = false
        pad.addSubview(b)
        NSLayoutConstraint.activate([
            b.leadingAnchor.constraint(equalTo: pad.leadingAnchor),
            b.trailingAnchor.constraint(equalTo: pad.trailingAnchor),
            b.topAnchor.constraint(equalTo: pad.topAnchor),
            b.bottomAnchor.constraint(equalTo: pad.bottomAnchor, constant: -8),
        ])
        return pad
    }

    @objc private func openSetup() {
        navigationController?.pushViewController(SetupViewController(),
                                                 animated: true)
    }

    /// 界面语言：跟安卓一样弹窗选。
    @objc private func pickLanguage() {
        let a = UIAlertController(title: L.lang_title, message: nil,
                                  preferredStyle: .actionSheet)
        for code in Lang.all {
            a.addAction(UIAlertAction(title: Lang.label(code),
                                      style: .default) { _ in
                Lang.set(code)
                self.build()
            })
        }
        a.addAction(UIAlertAction(title: L.cancel, style: .cancel))
        present(a, animated: true)
    }

    /// 录音诊断：跟安卓一样，能看能复制。
    @objc private func showRecLog() {
        let text = RecLog.dump()
        let a = UIAlertController(title: L.rec_log_title,
                                  message: text.isEmpty ? L.rec_log_empty : text,
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: L.prefs_copy, style: .default) { _ in
            UIPasteboard.general.string = text
        })
        a.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(a, animated: true)
    }
}
