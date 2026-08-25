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
        // 🚨 导航栏样式要在**任何页面建出来之前**设，而且只设这一次。
        //    上一版我加在首页那条分支里，深链（TRANSLESS_PAGE）走的是另一条 —— 
        //    截图上「设为当前输入法」还是黑字。**一处配置要盖住所有入口**。
        NavStyle.apply()
        // 调试口子：模拟"他已经体验过了"。**走的是真实的 `Onboard.markTried()`**，
        // 不是伪造一个状态 —— 验的是"标记真写进 Keychain 了 + 首页真会据此显示"。
        // 🚨 没验到的那一半：点麦克风时会不会调 markTried（模拟器点不了，
        //    脚本没有 tap API）。那是 `tapMic` 第一行的一句话，我改的时候盯着写的。
        if ProcessInfo.processInfo.environment["TRANSLESS_MARK_TRIED"] == "1" {
            Onboard.markTried()
        }
        // 调试口子：预设说话页的档位，好并排截"选中翻译"和"选中转写"两张图。
        // 🚨 写的是 `setMode` 读的那个 key，走的是**同一条真实路径**，
        //    不是另建一套状态。
        if let m = ProcessInfo.processInfo.environment["TRANSLESS_MODE"],
           !m.isEmpty {
            UserDefaults.standard.set(m, forKey: "vime.mode")
            // 🚨 设了档位就等于"他点过 Tab" —— 这两件事在真实操作里
            //    本来就是同一下点击带来的（`pickEn`/`pickTranscribe`
            //    先 `touchTabs()` 再 `setMode`）。截图要复刻的正是那个状态。
            UserDefaults.standard.set(true, forKey: "vime.tabTouched")
        }
        DeviceId.ensure()
        let w = UIWindow(frame: UIScreen.main.bounds)
        // 🚨 **调试用的直达入口**：`xcrun simctl launch … --page speak` 之类，
        //    直接跳到某一页，免得在模拟器里手点（脚本点不了，
        //    AppleScript 点击要辅助功能授权）。
        //    这条只认启动参数，正常安装的包收不到，不影响用户。
        //    有了它，我改完 UI 能自己截图核对，不用等 Kevin 装了来告诉我。
        // 🚨 用**环境变量**不用启动参数：`simctl launch` 有自己的参数解析，
        //    `--page speak` 被它吞掉了，App 侧 arguments 里根本收不到
        //    （实测：传了 speak 却进了 setup —— 我一度以为是 switch 写错）。
        //    环境变量走 `SIMCTL_CHILD_` 前缀，simctl 会原样传进来。
        let env = ProcessInfo.processInfo.environment
        if let page = env["TRANSLESS_PAGE"], !page.isEmpty {
            let nav = UINavigationController(rootViewController: HomeViewController())
            nav.setNavigationBarHidden(true, animated: false)
            switch page {
            case "speak": nav.pushViewController(MainViewController(), animated: false)
            case "setup": nav.pushViewController(SetupViewController(), animated: false)
            case "prefs": nav.pushViewController(PrefsViewController(), animated: false)
            case "login": nav.pushViewController(LoginViewController(), animated: false)
            // 🚨 只为**我自己看键盘长什么样**：键盘扩展要在系统设置里启用、
            //    再点 🌐 切过去，这两步模拟器上脚本点不动。把同一个
            //    `TypingKeyboardView` 直接塞进 App 里截图，看到的是同一份代码。
            //    正式界面里没有任何入口，只有这个环境变量能进。
            case "kb": nav.pushViewController(KeyboardPreviewController(), animated: false)
            // 拼音引擎对拍（期望值来自独立的 Python 参照实现）
            case "pysplit": nav.pushViewController(PinyinSelfTestController(),
                                                   animated: false)
            default: break
            }
            w.rootViewController = nav
            w.makeKeyAndVisible()
            window = w
            return true
        }
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
        // 🚨🚨 **不自动跳转**。新用户看到的是**首页本身**，
        //    只不过那时候首页上只有「说一段试试」一个按钮 ——
        //    "必须让他试"是靠**没别的可点**实现的，不是靠强制跳走。
        //
        //    我上一版做成了"开 App 直接 push 说话页"，Kevin 2026-08-25 纠正：
        //    「应该是先 2（他第一次看到的），然后才是 1，试完之后变成 3。
        //      这个顺序是不是反过来了？」——是反了。
        //    直接跳走的话他连 logo 和 slogan 都没看见就被丢进功能页了。
        home.modalTransitionStyle = .crossDissolve
        home.modalPresentationStyle = .fullScreen
        // 🚨 只在**首页**隐藏导航栏，子页要显示 —— 否则设置页/引导页
        //    没有返回键、侧滑也失效，只能杀进程（交叉审查 H3）。
        //    安卓那边每个子页都有「‹ + 标题」栏。
        home.setNavigationBarHidden(true, animated: false)
        home.interactivePopGestureRecognizer?.delegate = nil
        UIApplication.shared.windows.first?.rootViewController = home
    }
}

// MARK: - ② 首页（对齐安卓 SettingsActivity）

final class HomeViewController: UIViewController {

    /// 建首页那几个长条时的状态：体验过没有、登录了没有。
    ///
    /// 🚨 存下来是为了**知道什么时候要重建** —— 从说话页/登录页返回时
    ///    状态可能刚变，不重建的话按钮不会冒出来，看着就像"试了也没用"。
    /// 🚨 **两个状态都要记**：只记 `tried` 的话，登录完回来首页不会变，
    ///    「设为当前输入法」永远出不来 —— 那种漏只在走到第三级时才现形。
    private var builtWithTried = false
    private var builtWithLogin = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        if builtWithTried != Onboard.tried || builtWithLogin != Auth.loggedIn {
            // 状态变了：整页重搭（首页很轻，重搭比逐个增删可靠）
            view.subviews.forEach { $0.removeFromSuperview() }
            viewDidLoad()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        builtWithTried = Onboard.tried
        builtWithLogin = Auth.loggedIn
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
        // 🚨 按钮间距 14。原来是 9 —— Grok 评审：「按钮间距仅约 8–10pt，
        //    形成"上松下紧"的失衡，主 CTA 没有足够的垂直呼吸空间」。
        bars.spacing = 14

        // 🚨🚨 **顺序：先让他体验，再要他付出**（Kevin 2026-08-25）：
        //    「『说一段试试』可以放在第一个 tab 里。甚至可以这样设计：
        //      新用户下载之后，必须要先完成『说一段试试』，
        //      然后再去注册登录，以及设为当前输入法。」
        //    所以「说一段试试」排第一、并且是**主按钮** ——
        //    它原来是最不起眼的第三个。
        //
        // 🚨 「必须先完成才能点后两个」那个**硬锁没做**：
        //    判断一旦出错（重装 App、换设备、本地标记丢），就会把人锁在门外，
        //    而"App 自作主张不让我用"正是他反复骂过的那类。
        //    先上顺序和主次这一半；真要硬锁再加，一行的事。
        bars.addArrangedSubview(Bars.make(L.home_try_speak, primary: true,
                                          target: self,
                                          action: #selector(openSpeak)))
        // 🚨🚨 **三级解锁**，每一级都是"不建那个按钮"而不是置灰
        //    （置灰会留一个点不动的东西在那儿，比不显示更让人困惑）：
        //      ① 没体验过       → 只有「说一段试试」
        //      ② 体验过、没登录 → 加「注册 / 登录」
        //      ③ 登录了         → 加「设为当前输入法」
        //    Kevin 2026-08-25：「必须让他试的，然后才会出现『注册登录』
        //    和『设为当前输入法』的按钮」＋「用户必须先注册和登录，
        //    然后才能设置为默认输入法」。
        if Onboard.tried {
            bars.addArrangedSubview(Bars.make(L.home_login, primary: false,
                                              target: self,
                                              action: #selector(loginSoon)))
        }
        if Onboard.tried && Auth.loggedIn {
            bars.addArrangedSubview(Bars.make(L.home_set_ime, primary: false,
                                              target: self,
                                              action: #selector(openSetup)))
        }
        root.addArrangedSubview(bars)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    @objc private func loginSoon() {
        // 🚨 以前这里只弹一句"下个版本"。后端 2026-08-25 已经全链路跑通
        //    （Supabase users 表 + 阿里云短信），Kevin：「注册登录已经 OK 了…
        //    那就把注册登录给做实吧」。
        navigationController?.pushViewController(LoginViewController(),
                                                 animated: true)
    }

    @objc private func openSetup() {
        navigationController?.pushViewController(SetupViewController(),
                                                 animated: true)
    }

    @objc private func openPrefs() {
        navigationController?.pushViewController(PrefsViewController(),
                                                 animated: true)
    }

    @objc private func openSpeak() {
        navigationController?.pushViewController(MainViewController(),
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
        // Grok ⑧：三个按钮高度圆角完全一样，只靠颜色分主次，
        //         主按钮没有尺寸权重。变体模式下主按钮高 5pt。
        b.heightAnchor.constraint(
            equalToConstant: primary ? 61 : 56).isActive = true

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
/// 导航栏统一样式。**单一配置点** —— 每个页面各设一遍必然漏一处。
///
/// 🚨 Kevin 2026-08-25：「设置里面的字又是黑色的，根本看不清楚
///    『设置』这两个字。这个 UI 我都说了很多次了」。
///    根因是从来没设过 `UINavigationBar` 的样式：深色背景 +
///    系统默认的黑标题。不是某个页面写错，是整个 App 都没设。
enum NavStyle {
    static func apply() {
        let a = UINavigationBarAppearance()
        a.configureWithTransparentBackground()      // 背景交给页面的渐变
        a.titleTextAttributes = [
            .foregroundColor: Skin.text,
            .font: UIFont.systemFont(ofSize: 17, weight: .medium),
        ]
        a.largeTitleTextAttributes = [.foregroundColor: Skin.text]
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = a
        bar.scrollEdgeAppearance = a
        bar.compactAppearance = a
        // 返回箭头也得是浅色，否则同样看不见
        bar.tintColor = Skin.text
    }
}

final class SetupViewController: UIViewController {

    // 🚨 子页要显示导航栏（首页是隐藏的）—— 不然进来就出不去。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        onAppear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.viewControllers.count == 1 {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }

    /// 子类各自的「回到前台要刷新什么」。默认什么都不做。

    private var rows: [(UIView, UILabel, UILabel)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.home_set_ime

        let stack = UIStackView()
        stack.axis = .vertical
        // 行间 15、左右 21，照安卓 SetupActivity
        //（`lp.setMargins(0,0,0,dp(15))` / `root.setPadding(dp(21),0,dp(21),0)`）
        stack.spacing = 15
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 21),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -21),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
        ])

        // 🚨 这里**不再放大标题**。导航栏上已经写着「设为当前输入法」，
        //    正文再来一个一模一样的，白占一屏高度还削弱了真正的步骤层级
        //    （Grok 评审：「用户第一眼看到两个相同标题，信息冗余」）。

        for (n, t) in [("1", L.ios_step_add),
                       ("2", L.ios_step_full),
                       ("3", L.step_mic)] {
            let (row, num, state) = makeRow(n, t)
            rows.append((row, num, state))
            stack.addArrangedSubview(row)
        }
        // 第 2 项底下补一句说明 —— 那一项永远不会变绿，得说清为什么，
        // 否则他会一直以为没设成功（他 2026-08-25 就是这么卡住的）。
        let fullNote = UILabel()
        fullNote.text = L.full_note
        fullNote.font = .systemFont(ofSize: 12)
        fullNote.textColor = Skin.dim
        fullNote.numberOfLines = 0
        stack.insertArrangedSubview(fullNote,
                                    at: stack.arrangedSubviews.count)

        // 🚨🚨 第 3 步要**可点，而且真的去请求麦克风权限**（交叉审查 H2）。
        //    iOS 只有在 App 请求过一次之后，「设置 → Transless」里才会
        //    出现麦克风开关。我上一版把 requestRecordPermission 删干净了，
        //    于是点「去设置」进去根本没有那个开关，权限永远拿不到 ——
        //    键盘按麦克风必走失败分支。
        //    `project.yml` 自己写着「键盘扩展弹不出系统权限框，
        //    必须由容器 App 先要过一次」，我删的正是那一次。
        let micTap = UITapGestureRecognizer(target: self,
                                            action: #selector(askMic))
        rows[2].0.isUserInteractionEnabled = true
        rows[2].0.addGestureRecognizer(micTap)
        // 🚨 让它**看起来能点** —— 但**不能给整行换底色**。
        //    Kevin 2026-08-25 说「允许录音那个我就是找不到啊」（这一行一直
        //    可点，他是自己撞对的）；我上一版给整行加了底色，
        //    Grok 评审当场指出「三张卡片颜色不一致，会让人误以为步骤 3
        //    是当前高亮/已完成状态」。两条都对。
        //    正解：**三张卡片底色一律相同**，"能点"由右边那个
        //    「去启用 ›」自己表达 —— 把它做成按钮的样子（见 refresh 里
        //    对 `.some(false)` 的处理）。
        rows[2].2.layer.cornerRadius = 9
        rows[2].2.clipsToBounds = true
        rows[2].2.textAlignment = .center
        // 🚨 状态标签**不许被压缩**。加了内边距之后它变宽了，
        //    横向 stack 默认按 hugging 分配，结果标题把它挤成「去启…」
        //    「请手动…」（截图上看到的）。让标题那边先缩。
        for (row, _, lab) in rows {
            lab.setContentCompressionResistancePriority(.required, for: .horizontal)
            lab.setContentHuggingPriority(.required, for: .horizontal)
            if let box = row as? UIStackView,
               let title = box.arrangedSubviews.first(where: {
                   ($0 as? UILabel) != nil && $0 !== lab
               }) as? UILabel {
                title.numberOfLines = 2          // 挤不下就换行，不截断
                title.setContentCompressionResistancePriority(.defaultLow,
                                                              for: .horizontal)
            }
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

        // 🚨 这里**没有** AI 免责声明。
        //    「译文由 AI 生成，发送前请自行核对」原来挂在这一页 ——
        //    而这一页是"怎么把键盘装上"的引导，跟译文毫无关系，
        //    用户看到会想"我现在在翻译什么？"（Grok 评审指出，属实）。
        //    那句话该出现在**真正出译文的地方**，不在这儿。
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    func onAppear() {
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
        // 🚨 第 2 项是 `nil`：**查不到**，不是"未完成"。
        //    见下面 `case .none` 的呈现 —— 不能跟未完成长一个样。
        let states: [Bool?] = [added, nil, mic]
        for (i, s) in states.enumerated() {
            let (_, num, lab) = rows[i]
            switch s {
            case .some(true):
                lab.text = L.done_enabled
                lab.textColor = Skin.ok
                // 🚨 每个分支都要**把底色清掉**，不能只在设的那个分支里管。
                //    只在一处设、别处不清，状态一变就留着上一次的底
                //    —— 那种错只在"来回切几次"时才现形。
                lab.backgroundColor = .clear
                num.backgroundColor = Skin.ok
            case .some(false):
                lab.text = "  " + L.act_enable + "  "
                lab.textColor = Skin.text
                // 🚨 「能点」由这个小标签自己表达（浅底 + 亮字），
                //    而不是给整行换底色 —— 后者会破坏三张卡片的一致性。
                lab.backgroundColor = Skin.accent.withAlphaComponent(0.35)
                lab.layer.cornerRadius = 9
                lab.clipsToBounds = true
                num.backgroundColor = Skin.accent2
            case .none:
                // 🚨 **不摆成"待办"的样子**。Kevin 2026-08-25：
                //    「第二个『允许完全访问』，我设置了之后，它还是显示
                //     要我去设置啊，没有设好啊」——
                //    他设好了，是我这一行永远显示「去设置 ›」在误导他。
                // 🚨 但也不能是个光秃秃的「—」：其他两步写着「去启用 ›」，
                //    这里突然一个破折号，"已完成 / 不可点 / 状态未知"分不出来
                //    （Grok 评审指出）。写清楚**它是什么状态**。
                lab.text = L.act_manual
                lab.textColor = Skin.dim
                lab.backgroundColor = .clear
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
        // 🚨 数字和文字之间 13，照安卓 `nlp.setMargins(0, 0, dp(13), 0)`
        row.spacing = 13
        row.alignment = .center
        // 🚨🚨 每一行是**一张卡片**，`padding(18,20,18,20)` ——
        //    照安卓 `SetupActivity`：`row.setPadding(dp(18), dp(20), dp(18), dp(20))`。
        //    iOS 原来是裸行、只有 12 的 spacing，挤成一坨
        //    （Kevin 2026-08-25：「这个界面太丑了，怎么会这么密呢？
        //     你看一下安卓怎么设计的吧，我不是让你对着安卓来做吗？」）。
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 20, left: 18,
                                         bottom: 20, right: 18)
        row.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        row.layer.cornerRadius = 14

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

    /// 点第 3 步：**真的请求麦克风权限**。
    ///
    /// 🚨 只有 `.denied`（他之前拒过）时才退回打开系统设置 ——
    ///    `.undetermined` 时必须调 request，否则系统设置里
    ///    压根不会出现那个开关。
    @objc private func askMic() {
        let st = AVAudioSession.sharedInstance().recordPermission
        switch st {
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { _ in
                DispatchQueue.main.async { self.refresh() }
            }
        case .denied:
            openSystemSettings()
        default:
            refresh()
        }
    }
}

// MARK: - ④ 设置（对齐安卓 PrefsActivity 的四组）

final class PrefsViewController: UIViewController {

    // 🚨 子页要显示导航栏（首页是隐藏的）—— 不然进来就出不去。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        onAppear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.viewControllers.count == 1 {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }

    /// 子类各自的「回到前台要刷新什么」。默认什么都不做。

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

    func onAppear() {
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
        // Grok ⑦：「20260825.467」纯日期+build 号，对普通用户毫无意义，
        //         像内部调试信息。变体模式下显示成「版本 467」。
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"]
                     as? String) ?? ver
        list.addArrangedSubview(row(L.prefs_about,
                                    "版本 " + build, nil))
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
        // 字号照安卓 PrefsActivity：标题 15.5、副标题 11.5
        t.font = .systemFont(ofSize: 15.5)
        let s = UILabel()
        s.text = sub
        // Grok ⑥：副标题在深紫底上对比度偏低。`Skin.sub` 在变体模式下更亮。
        s.textColor = Skin.sub
        s.font = .systemFont(ofSize: 11.5)
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
            // 🚨 上下 15，照安卓 `r.setPadding(dp(16), dp(15), dp(16), dp(15))`。
            //    原来写的是 11 —— 每行矮 8pt，一整页看着就"密"
            //    （Kevin 2026-08-25：「里面的排版太密了，不像安卓那样会铺开一些」）。
            col.topAnchor.constraint(equalTo: b.topAnchor, constant: 15),
            col.bottomAnchor.constraint(equalTo: b.bottomAnchor, constant: -15),
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
            // 行间距 9，照安卓 `lp.setMargins(0, 0, 0, dp(9))`
            b.bottomAnchor.constraint(equalTo: pad.bottomAnchor, constant: -9),
        ])
        return pad
    }

    @objc private func openSetup() {
        navigationController?.pushViewController(SetupViewController(),
                                                 animated: true)
    }

    /// 界面语言：跟安卓一样弹窗选。
    @objc private func pickLanguage() {
        // 🚨 用 .alert 不用 .actionSheet：这是 iPad 应用
        //    （project.yml 的 TARGETED_DEVICE_FAMILY = "1,2"），
        //    actionSheet 不设 popover 的 sourceView 会直接闪退（审查 H4）。
        let a = UIAlertController(title: L.lang_title, message: nil,
                                  preferredStyle: .alert)
        for code in Lang.all {
            a.addAction(UIAlertAction(title: Lang.label(code),
                                      style: .default) { _ in
                Lang.set(code)
                // 🚨 选完要**整棵界面重建**，不是只刷这一页（交叉审查 H6）。
                //    只 build() 的话，标题、首页、其它页全还是旧语言，
                //    他会以为这个开关是坏的。
                //    安卓那边是 recreate() 整个 Activity。
                Self.rebuildUI()
            })
        }
        a.addAction(UIAlertAction(title: L.cancel, style: .cancel))
        present(a, animated: true)
    }

    /// 选完语言把整棵界面重建 —— 对齐安卓的 `recreate()`。
    ///
    /// 🚨 回到**首页**而不是停在设置页：所有页都要用新语言重建，
    ///    停在设置页的话上一层还是旧的。
    static func rebuildUI() {
        guard let w = UIApplication.shared.windows.first else { return }
        let nav = UINavigationController(rootViewController: HomeViewController())
        nav.setNavigationBarHidden(true, animated: false)
        nav.interactivePopGestureRecognizer?.delegate = nil
        UIView.transition(with: w, duration: 0.25,
                          options: .transitionCrossDissolve,
                          animations: { w.rootViewController = nav })
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


// ============================================================
// 🚨🚨 下面这一整段是**搬回来的**（交叉审查 H1）。
//
//    我上一版把它删了，理由是「干活的是键盘」——
//    而 iOS 键盘扩展只有 267 行（就一个麦克风 + 语气循环 + 退格），
//    **没有模式选择、没有目标语言、没有朗读**。
//    删掉之后全 App 找不到任何说话入口。
//
//    最难堪的是：文件头那段注释就是我上一次犯这个错时写的教训，
//    我写完又犯了一遍。**写下教训不等于避开它。**
//
//    在 iOS 键盘扩展补齐到跟安卓一样之前，这里是唯一能用的路，
//    别再删。要删先跑 `py ios/contract_test.py` —— 它会红。
// ============================================================

// MARK: - 主界面：一个大按钮

final class MainViewController: UIViewController {

    // 🚨 子页要显示导航栏（首页是隐藏的）—— 不然进来就出不去。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        onAppear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.viewControllers.count == 1 {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }

    /// 🚨 `viewWillAppear` 里调了它，所以**必须有定义**。
    ///    这个页回到前台不用刷新什么，留空即可 —— 但不能不定义，
    ///    CI 上报的就是 "type has no member"。
    func onAppear() { }

    /// 子类各自的「回到前台要刷新什么」。默认什么都不做。

    private enum Phase { case idle, listening, thinking }

    // 🚨 三档，跟 engine.py / 安卓 Gen.TONE_CODES 一致（Kevin 2026-08-21：
    //    「邮件和正式合在一起吧，这两个没什么区别。就是随意、工作和邮件三种」）。
    //    这里是**第三份**副本，暂时只能手工对齐 —— iOS 没走构建期生成那条路。
    //    改档位时三处都要动：engine.py / build_apk.py 生成的 Gen / 这里。
    private let tones = Prompts.all
    private let toneLabels = Prompts.all.map(Prompts.label)
    private var tone = Prompts.normalize(UserDefaults.standard.string(forKey: "vime.tone"))

    /// 输出模式：译成英文（默认）/ 只转写。跟安卓一致。
    private var mode: Backend.Mode =
        Backend.Mode(rawValue: UserDefaults.standard.string(forKey: "vime.mode") ?? "en") ?? .en
    private let logoView = UIImageView()
    /// 长按说明的文案表。用 ObjectIdentifier 当键，免得给每个控件都挂 tag。
    private var tips: [ObjectIdentifier: String] = [:]
    // 第一级 Tab
    private let tabTranslate = UIButton(type: .system)
    private let tabTranscribe = UIButton(type: .system)
    // 第二级：转写下的两个子档
    private let modeZhButton = UIButton(type: .system)
    private let modeRawButton = UIButton(type: .system)
    private var subStack = UIStackView()

    /// 未选中的 Tab 收窄到多宽。要放得下完整标签，别截字。
    static let tabNarrow: CGFloat = 88
    /// 收窄约束：**只激活未选中那一个**，选中的没有宽度约束、自然吃满剩余。
    private var narrowTranslate: NSLayoutConstraint?
    private var narrowTranscribe: NSLayoutConstraint?
    /// 两个 Tab 等宽 —— **他还没点过任何一个**时用这个。
    private var equalTabs: NSLayoutConstraint?

    /// 他有没有点过这两个 Tab。
    ///
    /// 🚨 **不能拿 `mode` 判**：mode 有默认值（`.en`），拿它判的话新用户
    ///    一进来就是"翻译被选中"的样子 —— 而 Kevin 2026-08-25 要的是
    ///    「如果用户不点的话，它默认两边都是一样长」。
    ///    **默认档位** 和 **他点过没有** 是两件事。
    private var tabTouched: Bool {
        get { UserDefaults.standard.bool(forKey: "vime.tabTouched") }
        set { UserDefaults.standard.set(newValue, forKey: "vime.tabTouched") }
    }

    /// 目标语言（翻译模式用）。跟安卓共用同一套 code。
    private var lang = UserDefaults.standard.string(forKey: "vime.lang") ?? "en"
    private let langButton = UIButton(type: .system)

    /// 🔊 朗读：把刚出的译文用 Andrew 的声音念出来
    private let speakButton = UIButton(type: .system)
    private var lastOut = ""

    private let hintLabel = UILabel()
    private let heardLabel = UILabel()
    private let resultView = UITextView()
    private let aiNoticeLabel = UILabel()   // DeepSeek 条款 8.1/3.7 要求的 AI 生成披露
    private let micButton = UIButton(type: .system)
    private let toneButton = UIButton(type: .system)

    private lazy var voice = Voice()
    private var phase: Phase = .idle
    private var elapsedTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.bg
        title = "Transless"
        navigationController?.navigationBar.tintColor = Theme.accent
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L.perm_title, style: .plain, target: self, action: #selector(openSetup))

        // 🚨 两级 Tab（Kevin 2026-08-21：「按你最初的那个方案来」）：
        //    第一级只有 翻译 / 转写；子档位（结构化 / 逐字）放第二级小 chip。
        //    跟安卓 VoiceImeService 的版式一一对应 —— 两端一起改是硬规矩。
        for (b, t, sel) in [(tabTranslate, L.kb_translate, #selector(pickEn)),
                            (tabTranscribe, L.kb_transcribe, #selector(pickTranscribe))] {
            b.setTitle(t, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            b.layer.cornerRadius = 17
            b.addTarget(self, action: sel, for: .touchUpInside)
        }
        // Kevin 2026-08-21：Tab 右边那块空地放 logo（G3 图标里的整个 T+麦克风，同源）。
        // 压到次要文字色，不抢戏 —— 这一屏的强调色只留给说话长条。
        logoView.image = UIImage(named: "logo")?.withRenderingMode(.alwaysTemplate)
        logoView.tintColor = Theme.dim
        logoView.contentMode = .scaleAspectFit

        let modeStack = UIStackView(arrangedSubviews: [tabTranslate, tabTranscribe, logoView])
        modeStack.axis = .horizontal
        modeStack.spacing = Theme.gap * 0.7
        modeStack.distribution = .fill
        tabTranslate.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tabTranscribe.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // 🚨 **未选中的那个**收窄到固定宽，选中的自然吃满剩下的。
        //    Kevin 2026-08-25：「它应该是一个动态的图标，而不是静态的…
        //    我点『转写』的时候，『转写』进一步拉，也是可以拉长到那么长。」
        //    原来两个 hugging 一样低，`.fill` 把富余空间**全给第一个**
        //    （「翻译」）—— 跟谁被选中毫无关系，所以永远长短固定。
        //
        // 🚨 88 是要放得下未选中时的完整标签。太窄会截成「转…」，
        //    那比不做动画更糟。
        narrowTranslate = tabTranslate.widthAnchor.constraint(
            equalToConstant: Self.tabNarrow)
        narrowTranscribe = tabTranscribe.widthAnchor.constraint(
            equalToConstant: Self.tabNarrow)
        equalTabs = tabTranslate.widthAnchor.constraint(
            equalTo: tabTranscribe.widthAnchor)
        tabTranslate.titleLabel?.adjustsFontSizeToFitWidth = true
        tabTranslate.titleLabel?.minimumScaleFactor = 0.75
        tabTranscribe.titleLabel?.adjustsFontSizeToFitWidth = true
        tabTranscribe.titleLabel?.minimumScaleFactor = 0.75
        logoView.setContentHuggingPriority(.required, for: .horizontal)
        logoView.widthAnchor.constraint(equalToConstant: 26).isActive = true

        // 🚨 「整理 / 逐字」，不是「结构化转写 / 逐字转录」——
        //    Kevin 2026-08-21：「这几个表达让人听不懂」。安卓当天改了并加了闸门，
        //    iOS 一直留着旧名字（2026-08-22 才发现）。
        for (b, t, sel) in [(modeZhButton, L.kb_polish, #selector(pickZh)),
                            (modeRawButton, L.kb_verbatim, #selector(pickRaw))] {
            b.setTitle(t, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            b.layer.cornerRadius = 16
            b.addTarget(self, action: sel, for: .touchUpInside)
        }
        subStack = UIStackView(arrangedSubviews: [modeZhButton, modeRawButton])
        subStack.axis = .horizontal
        subStack.spacing = Theme.gap * 0.7
        subStack.distribution = .fillEqually

        // 🚨 Kevin 2026-08-21：那几行功能说明「至于要留这么大的位置吗？…
        //    用户自己点着点着自然就明白了。或者长按的时候弹一个 box 来介绍」。
        //    -> 常驻说明清空（下面 paintMode 里也不再写），改成**长按弹**（explain）。
        hintLabel.font = .systemFont(ofSize: 15)
        hintLabel.textColor = Theme.dim
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 1
        hintLabel.text = ""

        heardLabel.font = .systemFont(ofSize: 15)
        heardLabel.textColor = Theme.text
        heardLabel.textAlignment = .center
        heardLabel.numberOfLines = 4

        resultView.font = .systemFont(ofSize: 17)
        resultView.textColor = Theme.text
        resultView.backgroundColor = Theme.panel
        resultView.layer.cornerRadius = 12
        resultView.isEditable = false
        resultView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)

        // 🚨 AI 生成声明：DeepSeek 开放平台服务协议 8.1「应当向终端用户明确披露
        //    相关输出内容系由人工智能生成」+ 3.7「对生成、合成的文本进行标识」。
        aiNoticeLabel.text = L.ai_notice
        aiNoticeLabel.font = .systemFont(ofSize: 12.5)
        // 🚨 走 Theme，别硬编码 —— 硬编码的话换主题时它不跟着变，
        //    紫色改版之后会剩一块土黄。
        aiNoticeLabel.textColor = Theme.dim
        aiNoticeLabel.numberOfLines = 0
        aiNoticeLabel.textAlignment = .center

        // 🚨🚨 说话键是**圆的**，别再改回长条。
        //    Kevin 2026-08-21 先说「不要搞成圆圈…搞成一个长点的方框」，
        //    当天**又改口**：「不需要留长…还是用回原来那个圆圈的形状，
        //    这样整个输入法都显得干净一点」——以后说的为准。
        //    安卓按后一次改了（build 闸门钉着 circle=3/bar=0），
        //    iOS 停在前一次，2026-08-22 才发现。
        micButton.setTitle("", for: .normal)
        micButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        micButton.setTitleColor(.white, for: .normal)
        micButton.setImage(Theme.micGlyph(Theme.micBarHeight * 0.6), for: .normal)
        micButton.tintColor = .white
        micButton.backgroundColor = Theme.accent
        micButton.layer.cornerRadius = Theme.micBarHeight / 2
        micButton.addTarget(self, action: #selector(tapMic), for: .touchUpInside)

        toneButton.setTitle("语气：" + toneTitle(), for: .normal)
        toneButton.setTitleColor(Theme.dim, for: .normal)
        toneButton.titleLabel?.font = .systemFont(ofSize: 15)
        toneButton.backgroundColor = Theme.key
        toneButton.layer.cornerRadius = 16
        toneButton.addTarget(self, action: #selector(cycleTone), for: .touchUpInside)

        // 语言选择：跟语气并排，不藏进设置
        langButton.titleLabel?.font = .systemFont(ofSize: 15)
        langButton.setTitleColor(Theme.text, for: .normal)
        langButton.backgroundColor = Theme.key
        langButton.layer.cornerRadius = 16
        langButton.addTarget(self, action: #selector(pickLang), for: .touchUpInside)

        speakButton.setTitle(L.kb_speak, for: .normal)
        // 🚨 单色喇叭贴在文字左边（原来是彩色 emoji，跟主题冲）
        speakButton.setImage(Theme.speakGlyph(17), for: .normal)
        speakButton.tintColor = Theme.text
        speakButton.imageEdgeInsets =
            UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        speakButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        speakButton.setTitleColor(Theme.text, for: .normal)
        speakButton.backgroundColor = Theme.key
        speakButton.layer.cornerRadius = 16
        speakButton.isEnabled = false          // 没东西可念时不给点
        speakButton.addTarget(self, action: #selector(tapSpeak), for: .touchUpInside)

        [modeStack, subStack, hintLabel, heardLabel, resultView, aiNoticeLabel, micButton,
         toneButton, langButton, speakButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            modeStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.gap),
            modeStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.pad * 1.6),
            modeStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.pad * 1.6),
            modeStack.heightAnchor.constraint(equalToConstant: 34),

            subStack.topAnchor.constraint(equalTo: modeStack.bottomAnchor, constant: Theme.gap),
            subStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.pad * 1.6),
            subStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.pad * 1.6),
            subStack.heightAnchor.constraint(equalToConstant: 32),

            hintLabel.topAnchor.constraint(equalTo: subStack.bottomAnchor, constant: Theme.gap),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            // 圆形：等宽高 + 居中（跟安卓 MIC_CIRCLE_DP 那套一一对应）
            micButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micButton.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: Theme.gap + 4),
            micButton.widthAnchor.constraint(equalToConstant: Theme.micBarHeight),
            micButton.heightAnchor.constraint(equalToConstant: Theme.micBarHeight),

            toneButton.topAnchor.constraint(equalTo: micButton.bottomAnchor, constant: Theme.gap),
            toneButton.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -6),
            toneButton.widthAnchor.constraint(equalToConstant: 130),
            toneButton.heightAnchor.constraint(equalToConstant: 34),

            langButton.topAnchor.constraint(equalTo: micButton.bottomAnchor, constant: Theme.gap),
            langButton.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: 6),
            langButton.widthAnchor.constraint(equalToConstant: 110),
            langButton.heightAnchor.constraint(equalToConstant: 34),

            speakButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            speakButton.topAnchor.constraint(equalTo: toneButton.bottomAnchor, constant: 10),
            speakButton.widthAnchor.constraint(equalToConstant: 140),
            speakButton.heightAnchor.constraint(equalToConstant: 36),

            heardLabel.topAnchor.constraint(equalTo: speakButton.bottomAnchor, constant: Theme.gap),
            heardLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            heardLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            resultView.topAnchor.constraint(equalTo: heardLabel.bottomAnchor, constant: 14),
            resultView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            resultView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            resultView.bottomAnchor.constraint(equalTo: aiNoticeLabel.topAnchor, constant: -8),
            aiNoticeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            aiNoticeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            aiNoticeLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
        // 🚨 立体感统一在这儿走一遍，别在每个控件后面各写一行 —— 漏一个就少一个阴影，
        //    而"少了一个"是看不出来的（跟安卓 Theme.elevateAll 同一套做法）。
        for v in [tabTranslate, tabTranscribe, modeZhButton, modeRawButton,
                  toneButton, langButton, speakButton] {
            v.layer.cornerRadius = Theme.rKey
            Theme.elevate(v, 3)
        }
        resultView.layer.cornerRadius = Theme.rCard
        Theme.elevate(resultView, 3)
        Theme.elevate(micButton, 6)     // 主操作，投影重一档，浮在最上层

        // 长按弹说明（跟安卓 explain() 一一对应，文案保持一致）
        explain(tabTranslate, L.ex_translate)
        explain(tabTranscribe, L.ex_transcribe)
        explain(modeZhButton, L.ex_polish)
        explain(modeRawButton, L.ex_verbatim)
        explain(micButton, L.ex_mic_ios)
        explain(toneButton, L.ex_tone_cycle)
        explain(langButton, L.ex_lang_pick)
        explain(speakButton, L.ex_speak_ios)

        paintMode()
    }

    // MARK: - 模式

    /// 语言选择：用系统的 action sheet，不自己造轮子
    @objc private func pickLang() {
        let ac = UIAlertController(title: L.lbl_translate_to, message: nil, preferredStyle: .actionSheet)
        for l in Backend.langs {
            let title = (l.code == lang ? "✓ " : "") + l.label
            ac.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.lang = l.code
                UserDefaults.standard.set(l.code, forKey: "vime.lang")
                self.paintMode()
            })
        }
        ac.addAction(UIAlertAction(title: L.cancel, style: .cancel))
        ac.popoverPresentationController?.sourceView = langButton
        present(ac, animated: true)
    }

    /// 朗读最近一次的译文。再点一下 = 停。
    @objc private func tapSpeak() {
        if Speaker.isPlaying {
            Speaker.stop()
            speakButton.setTitle(L.kb_speak, for: .normal)
            return
        }
        let text = lastOut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { hintLabel.text = L.nothing_to_speak; return }
        speakButton.isEnabled = false
        speakButton.setTitle("…", for: .normal)
        Backend.speak(text: text) { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.speakButton.isEnabled = true
                switch r {
                case .failure(let e):
                    self.speakButton.setTitle(L.kb_speak, for: .normal)
                    self.hintLabel.text = "朗读失败：\(e)"
                case .success(let mp3):
                    self.speakButton.setTitle(L.kb_stop, for: .normal)
                    Speaker.play(mp3) { [weak self] err in
                        DispatchQueue.main.async {
                            self?.speakButton.setTitle(L.kb_speak, for: .normal)
                            if let err = err { self?.hintLabel.text = "朗读失败：\(err)" }
                        }
                    }
                }
            }
        }
    }

    /// 长按弹一条说明（跟安卓 VoiceImeService.explain 同一套文案）。
    /// 说明不占版面，只在长按时出现。
    private func explain(_ v: UIView, _ text: String) {
        let g = UILongPressGestureRecognizer(target: self, action: #selector(showTip(_:)))
        v.addGestureRecognizer(g)
        tips[ObjectIdentifier(v)] = text
    }

    @objc private func showTip(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let v = g.view,
              let text = tips[ObjectIdentifier(v)] else { return }
        let ac = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: L.btn_got_it, style: .cancel))
        present(ac, animated: true)
    }

    /// 🚨 只有**点这两个一级 Tab** 才算"点过"。
    ///    二级的「整理 / 逐字」不算 —— 那是转写档里面的子选择，
    ///    跟"他有没有在翻译/转写之间做过选择"是两回事。
    private func touchTabs() { tabTouched = true }

    @objc private func pickEn() { touchTabs(); setMode(.en) }
    @objc private func pickZh() { setMode(.zh) }
    @objc private func pickRaw() { setMode(.raw) }
    /// 点第一级「转写」：默认落在结构化转写；已经在转写档就保持原子档。
    @objc private func pickTranscribe() {
        touchTabs()
        setMode(mode == .raw ? .raw : .zh)
    }

    private func setMode(_ m: Backend.Mode) {
        mode = m
        UserDefaults.standard.set(m.rawValue, forKey: "vime.mode")
        paintMode()
    }

    private func paintMode() {
        // 第一级
        let isTranslate = (mode == .en)
        tabTranslate.backgroundColor = isTranslate ? Theme.accent : Theme.key
        tabTranslate.setTitleColor(isTranslate ? .white : Theme.dim, for: .normal)
        tabTranscribe.backgroundColor = isTranslate ? Theme.key : Theme.accent
        tabTranscribe.setTitleColor(isTranslate ? Theme.dim : .white, for: .normal)

        // 🚨 三态：**没点过 → 两边等长**；点了谁谁吃满、另一个收窄。
        //    只动**约束的启用状态**，不重建约束：重建的话动画没有起点，
        //    会直接跳过去而不是拉伸。
        if tabTouched {
            equalTabs?.isActive = false
            narrowTranslate?.isActive = !isTranslate
            narrowTranscribe?.isActive = isTranslate
        } else {
            narrowTranslate?.isActive = false
            narrowTranscribe?.isActive = false
            equalTabs?.isActive = true
        }
        // 首帧不做动画（还没上屏，animate 会闪一下）
        if view.window != nil {
            UIView.animate(withDuration: 0.22,
                           delay: 0,
                           usingSpringWithDamping: 0.9,
                           initialSpringVelocity: 0.2,
                           options: [.curveEaseOut]) {
                self.view.layoutIfNeeded()
            }
        }

        // 第二级：翻译下是语气+语言，转写下是 结构化/逐字。永远只出现一排。
        subStack.isHidden = isTranslate
        for (b, m) in [(modeZhButton, Backend.Mode.zh), (modeRawButton, .raw)] {
            let on = (mode == m)
            b.backgroundColor = on ? Theme.accent : Theme.key
            b.setTitleColor(on ? .white : Theme.dim, for: .normal)
        }
        toneButton.isHidden = !isTranslate
        langButton.isHidden = !isTranslate
        langButton.setTitle(Backend.langLabel(lang) + " ▾", for: .normal)
        switch mode {
        case .en:
            hintLabel.text = ""
        case .zh:
            hintLabel.text = ""
        case .raw:
            hintLabel.text = ""
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 🚨🚨 **一上来就弹系统麦克风授权框**，别 push 引导页。
        //    Kevin 2026-08-25：「Typeless 现在就是这样子，它就是让你先给权限，
        //    然后去试一下…用户下载你这个软件的时候，他就有预期这是需要录音的…
        //    iPhone 的话，肯定还是要用户确认嘛。」
        //
        //    🚨 区分两件事：弹**系统权限框**是对的（一次点允许就完事）；
        //       这里原本干的是 push **引导页**（"设为当前输入法"三步），
        //       那跟录音毫无关系 —— 刚装的人一进来就被弹去那一屏，
        //       答非所问，而且他要的体验一秒都没发生。
        let perm = AVAudioSession.sharedInstance().recordPermission
        if perm == .undetermined {
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
            return
        }
        // 被拒过：系统不会再弹了，这时候引导页才有意义（教他去设置里开）
        if perm == .denied, Onboard.tried {
            navigationController?.pushViewController(SetupViewController(), animated: true)
        }
    }

    private func toneTitle() -> String { toneLabels[tones.firstIndex(of: tone) ?? 0] }

    @objc private func openSetup() {
        navigationController?.pushViewController(SetupViewController(), animated: true)
    }

    @objc private func cycleTone() {
        let i = tones.firstIndex(of: tone) ?? 0
        tone = tones[(i + 1) % tones.count]
        UserDefaults.standard.set(tone, forKey: "vime.tone")
        toneButton.setTitle("语气：" + toneTitle(), for: .normal)
    }

    private func setPhase(_ p: Phase, hint: String) {
        phase = p
        hintLabel.text = hint
        switch p {
        case .idle:
            micButton.setTitle("", for: .normal)
            micButton.setImage(Theme.micGlyph(Theme.micBarHeight * 0.6), for: .normal)
            micButton.tintColor = .white
            micButton.backgroundColor = Theme.accent
            micButton.isEnabled = true
        case .listening:
            micButton.setTitle("", for: .normal)
            micButton.setImage(Theme.stopGlyph(Theme.micBarHeight * 0.6), for: .normal)
            micButton.backgroundColor = Theme.danger
            micButton.isEnabled = true
        case .thinking:
            micButton.setImage(nil, for: .normal)
            micButton.setTitle("…", for: .normal)
            micButton.setTitleColor(.white, for: .normal)
            micButton.backgroundColor = Theme.keyDown
            micButton.isEnabled = false
        }
    }

    @objc private func tapMic() {
        // 🚨 判据是**按过说话键**，不是"转写成功"。
        //    要求成功的话，没给麦克风权限、或者当时没网的人会被**永久锁在门外**
        //    —— 首页那两个按钮永远不出现，而他连原因都看不到。
        //    宁可判松：他确实点了、确实试了，就算数。
        Onboard.markTried()
        // 🚨 权限还没决定就**先请求**，别直接走失败分支 ——
        //    第一次体验的人就是靠这一下拿到麦克风的。
        //    只在 `.undetermined` 时请求：已经被拒过的话系统不会再弹，
        //    那种情况要给去设置的出口，不能装作在等他点（见下面的 else）。
        let perm = AVAudioSession.sharedInstance().recordPermission
        if perm == .undetermined {
            AVAudioSession.sharedInstance().requestRecordPermission { ok in
                DispatchQueue.main.async {
                    if ok { self.tapMic() }        // 给了就接着走这一次
                }
            }
            return
        }
        if perm == .denied {
            // 被拒过：系统不会再弹，只能去设置里开
            navigationController?.pushViewController(SetupViewController(),
                                                     animated: true)
            return
        }
        if phase == .listening {
            elapsedTimer?.invalidate(); elapsedTimer = nil
            setPhase(.thinking, hint: L.st_recognizing)
            voice.stop()
            return
        }
        if phase == .thinking { return }

        heardLabel.text = ""
        resultView.text = ""
        setPhase(.listening, hint: "听着呢，想到哪说到哪（最长 60 秒）\n说完再按一下红色按钮")
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, self.phase == .listening else { return }
            let s = Int(self.voice.elapsed)
            self.hintLabel.text = String(format: L.st_listening_ios, s / 60, s % 60)
        }

        // 录音 → 停止后拿到 WAV → 传后端转写 → 再润色（跟安卓同一条链）
        voice.start(onPartial: { _ in }, onWav: { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.elapsedTimer?.invalidate(); self.elapsedTimer = nil
                switch result {
                case .failure(let f):
                    self.setPhase(.idle, hint: "\(f)")
                case .success(let wav):
                    self.setPhase(.thinking, hint: L.st_recognizing)
                    Backend.transcribe(wav: wav) { [weak self] r in
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            switch r {
                            case .failure(let f): self.setPhase(.idle, hint: "\(f)")
                            case .success(let zh):
                                self.heardLabel.text = zh
                                self.polish(zh)
                            }
                        }
                    }
                }
            }
        })
    }

    private func polish(_ zh: String) {
        switch mode {
        case .en:  setPhase(.thinking, hint: L.st_translating)
        case .zh:  setPhase(.thinking, hint: L.st_polishing)
        case .raw: setPhase(.thinking, hint: L.st_inserting)   // 不过模型，一瞬间
        }
        Backend.polish(text: zh, tone: tone, mode: mode, lang: lang) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let en):
                    self.resultView.text = en
                    UIPasteboard.general.string = en   // 自动进剪贴板
                    self.lastOut = en                  // 给「🔊 朗读」用
                    self.speakButton.isEnabled = true
                    self.setPhase(.idle, hint: "已复制 ✓　去微信长按输入框 → 粘贴\n再按一下麦克风说下一条")
                case .failure(let err):
                    self.setPhase(.idle, hint: "失败：\(err)")
                }
            }
        }
    }
}



// MARK: - 键盘预览（只给 TRANSLESS_PAGE=kb 用）

/// 把打字键盘按**它在键盘扩展里的真实高度**摆出来，贴在屏幕底部。
/// 上面留一个假的输入框，好看清键盘和输入区的相对关系（跟安卓截图对齐用）。
final class KeyboardPreviewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // 🚨🚨 预览页**必须复刻键盘扩展里的环境**，否则截出来的图不代表真相。
        //    第一版我在这里刷了个灰底，截图一片灰 —— 我差点以为是键盘配色错了，
        //    去改 TypingKeyboard 的颜色。实际扩展里
        //    `KeyboardViewController` 铺的是 `Theme.keyboardBackground`，
        //    键是 `#16FFFFFF` 半透明白，**透的是什么底就是什么色**。
        view.backgroundColor = .clear
        let bg = Theme.keyboardBackground(UIScreen.main.bounds)
        bg.frame = UIScreen.main.bounds
        bg.sublayers?.forEach { $0.frame = UIScreen.main.bounds }
        view.layer.insertSublayer(bg, at: 0)

        let fakeField = UILabel()
        fakeField.text = "  预览：打字键盘"
        fakeField.textColor = UIColor(white: 0.6, alpha: 1)
        fakeField.font = .systemFont(ofSize: 15)
        fakeField.backgroundColor = UIColor(white: 0.16, alpha: 1)
        fakeField.layer.cornerRadius = 8
        fakeField.clipsToBounds = true
        fakeField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fakeField)

        let kb = TypingKeyboardView()
        // 预览页也要跟着档位改高，否则截出来的图跟真实键盘不是一回事
        let kbH = kb.heightAnchor.constraint(equalToConstant: kb.preferredHeight)
        kb.onHeightChange = { h in kbH.constant = h }
        // 🚨 预览页把 composing 显示在上面那个假输入框里 ——
        //    键盘扩展里它进的是宿主 App 的输入框，这里没有宿主。
        kb.onComposing = { [weak fakeField] s in
            fakeField?.text = s.isEmpty ? "  预览：打字键盘" : "  " + s
        }
        kb.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(kb)

        NSLayoutConstraint.activate([
            fakeField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            fakeField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            fakeField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            fakeField.heightAnchor.constraint(equalToConstant: 40),

            kb.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            kb.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            kb.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            // 键盘扩展里给的是 280（见 KeyboardViewController.showTyping）
            kbH,
        ])

        if let m = ProcessInfo.processInfo.environment["TRANSLESS_KB_MODE"],
           !m.isEmpty {
            kb.debugMode(m)
        }

        // 自动按键：让候选栏在截图里有东西，且走的是真实按键路径。
        if let seq = ProcessInfo.processInfo.environment["TRANSLESS_KB_TYPE"],
           !seq.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                for ch in seq { kb.debugTap(String(ch)) }
            }
        }
    }
}
