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
            // 调试：直接落在手机号 tab（好并排截两个 tab 的图）。
            // 🚨 走的是**真实的 tab 切换方法**，不是另建一套状态。
            case "login-phone":
                let lv = LoginViewController()
                lv.startOnPhoneTab = true
                nav.pushViewController(lv, animated: false)
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
    private var builtWithIme = false
    /// 建的时候首页显示的名字。改了昵称回来要刷新 —— 见 viewWillAppear。
    private var builtWithName = ""
    private var builtWithLogin = false

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        // 🚨🚨 **四个**状态都要盯：少盯一个，那一种变化回到首页就不刷新。
        //    这条被同一族的 bug 打过两次：
        //      · 「设完输入法回来那条还在」—— 当时只盯了 tried/login
        //      · 「填完昵称回来首页还是旧名字」—— 当时漏了 displayName
        //    2026-08-26 在安卓上实测抓到第二个（强制重启看得到新名字、
        //    走 viewWillAppear 看到的是旧的），iOS 这边同型，一并修。
        if builtWithTried != Onboard.tried
            || builtWithLogin != Auth.loggedIn
            || builtWithName != Auth.displayName
            || builtWithIme != SetupViewController.keyboardAdded() {
            // 状态变了：整页重搭（首页很轻，重搭比逐个增删可靠）
            view.subviews.forEach { $0.removeFromSuperview() }
            viewDidLoad()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        builtWithTried = Onboard.tried
        builtWithIme = SetupViewController.keyboardAdded()
        builtWithName = Auth.displayName
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
        // 🚨🚨 昵称**不再挂在 slogan 底下**（Kevin 2026-08-26 真机反馈：
        //    「现在登录后的用户名显示在 slogan 下面，很不明显、很奇怪。
        //      建议放到左上角，参考 Typeless 的设计：放一个小人图标/头像，
        //      点击直接进入账户设置页」）。
        //    挪到**导航栏左上角**：`person.circle` + 昵称，点了进账户页。
        //    🚨 没登录就不放这个按钮，不是变灰 —— 首页该干净。
        if Auth.loggedIn {
            let item = UIBarButtonItem(
                image: UIImage(systemName: "person.circle"),
                style: .plain, target: self, action: #selector(openAccount))
            item.title = Auth.displayName
            navigationItem.leftBarButtonItem = item
        } else {
            navigationItem.leftBarButtonItem = nil
        }
        let midItems: [UIView] = [logo, brand, zh, en]
        let mid = UIStackView(arrangedSubviews: midItems)
        mid.axis = .vertical
        mid.alignment = .center
        mid.setCustomSpacing(21, after: logo)
        mid.setCustomSpacing(9, after: brand)
        mid.setCustomSpacing(5, after: zh)
        mid.setCustomSpacing(12, after: en)

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
        // 🚨🚨 **四态**（跟安卓 `SettingsActivity` 一字不差）：
        //      ① 全新用户        → **强制体验**：只有「随手翻译」
        //      ② 体验完、没登录  → **有且仅有**「注册 / 登录」
        //         Kevin 2026-08-26：「它绝对不能跟注册登录放在同一个界面」
        //         「全新用户的时候，就不要有那个虚线出来了」
        //      ③ 登录了、没设输入法 → 「随手翻译」「单词本」「设为默认输入法」
        //      ④ 设完输入法      → 设输入法那条**消失**（一次性配置）
        //
        // 🚨 修两个 bug（他自己撞到的，安卓那边同型）：
        //    · 登录后还显示「注册/登录」—— 原来 `if Onboard.tried` 漏判 loggedIn
        //    · 设完输入法那条不消失 —— 原来没判"是不是已经设好了"
        // 🚨🚨 **方案 D**（Kevin 2026-08-26 14:0x 逐字拍板：
        //    「D·随手翻译永久免登录」，选项说明是「只有单词本/输入法要登录。
        //     最符合"登录是为了存我的东西"这个直觉。代价：随手翻译白送，
        //     拿不到注册转化。」—— 他看到那个代价之后仍然选了它）。
        //
        //    所以**随手翻译永远都在**，不被任何门槛挡；
        //    登录只挡「单词本」和「设为默认输入法」。
        //    原来那个"体验过就转登录页"的分支已经拿掉 ——
        //    他撞到的「一进去就是登录页」正是那个分支。
        let logged = Auth.loggedIn
        let imeAdded = SetupViewController.keyboardAdded()

        // 随手翻译：**永远第一个，永远都在**
        bars.addArrangedSubview(Bars.make(L.home_try_speak, primary: true,
                                          target: self,
                                          action: #selector(openSpeak)))
        if !logged {
            bars.addArrangedSubview(Bars.make(L.home_login, primary: false,
                                              target: self,
                                              action: #selector(openLogin)))
        } else {
            bars.addArrangedSubview(Bars.make(L.home_wordbook, primary: false,
                                              target: self,
                                              action: #selector(openWordbook)))
            if !imeAdded {
                // 🚨 只在**还没设**时出现。设完就消失 —— Kevin：
                //    「这其实是初始化时的一步配置，配置完就该消失」。
                bars.addArrangedSubview(Bars.make(L.home_set_ime,
                                                  primary: false,
                                                  target: self,
                                                  action: #selector(openSetup)))
            }
        }
        root.addArrangedSubview(bars)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    /// 打开注册/登录页。
    ///
    /// 🚨 方法名以前叫 `loginSoon` —— 那是"下个版本再说"时代留下的，
    ///    现在它跳的是真登录页，名字却还在说"soon"，读代码的人会误判。
    @objc private func openLogin() {
        // 🚨 以前这里只弹一句"下个版本"。后端 2026-08-25 已经全链路跑通
        //    （Supabase users 表 + 阿里云短信），Kevin：「注册登录已经 OK 了…
        //    那就把注册登录给做实吧」。
        navigationController?.pushViewController(LoginViewController(),
                                                 animated: true)
    }

    /// 单词本：还没做，但**给真反馈**，不做纯装饰按钮
    /// （`gate_no_dead_feature.py` 会拦装饰按钮）。
    /// 左上角小人 -> 账户页。
    /// 🚨 **不能复用 `PrefsViewController.tapAccount`** —— 那是另一个类的方法，
    ///    `#selector` 只在**当前类**里找。第一版直接写了 `tapAccount`，
    ///    报 `cannot find 'tapAccount' in scope`。
    @objc private func openAccount() {
        navigationController?.pushViewController(AccountViewController(),
                                                 animated: true)
    }

    @objc private func openWordbook() {
        let a = UIAlertController(title: L.home_wordbook,
                                  message: L.home_wordbook_soon,
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
        // 🚨 「账户」放**第一行** —— Kevin：「设置里应该有个账户栏目，
        //    能看到我是用哪个账户登录的」。
        //    这里显示**完整账号**（跟首页那行昵称不同）：
        //    设置页就是查看账户的地方。
        list.addArrangedSubview(row(
            L.account_title,
            Auth.account.isEmpty ? L.account_none : Auth.account,
            #selector(tapAccount)))
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
        // 🚨 隐私政策入口。**AI 生成披露从产品界面移走之后，这一条是必需的**
        //    —— 条款 8.1 要的是「向终端用户明确披露」，
        //    藏在一个够不着的文档里不叫披露。
        list.addArrangedSubview(row(L.prefs_privacy, nil,
                                    #selector(openPrivacy)))
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

    /// 隐私政策地址。**只写这一处** —— 域名变了只改这儿。
    /// 🚨 必须定义在 `PrefsViewController` 里 —— 调用点在这个类的设置列表里。
    ///    上一版我按 `openSetup` 这个名字找锚点，结果插进了
    ///    `HomeViewController`（它也有同名方法），编译报
    ///    `cannot find 'openPrivacy' in scope`。
    ///    **「在哪儿定义」跟「定义什么」一样重要**（今天第三次栽在这上面）。
    private static let privacyURL = "https://transless.net/privacy.html"

    /// 账户行：登录了就退出登录，没登录就去登录。
    @objc private func tapAccount() {
        // 🚨🚨 点这一行是**进账户页**，不是登出。
        //    Kevin 2026-08-26 真机撞到：「我在设置里点了一下『我的账户』，
        //    它居然直接把我退出了。登出应该有专门的『退出登录』按钮，
        //    而不是点一下账户就退出，重新发验证码登录非常繁琐。」
        //    —— 原来这里直接 `Auth.signOut()`，**一点就登出、连确认都没有**。
        //    退出登录现在在账户页底部，单独按钮 + 要确认。
        if Auth.loggedIn {
            navigationController?.pushViewController(AccountViewController(),
                                                     animated: true)
        } else {
            navigationController?.pushViewController(LoginViewController(),
                                                     animated: true)
        }
    }

    @objc private func openPrivacy() {
        guard let u = URL(string: Self.privacyURL) else { return }
        UIApplication.shared.open(u)
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

    // MARK: - 连续模式（Kevin 2026-08-26 的"随手翻译"同传场景）

    /// 连续模式开关。点一次一直听，说一句出一句。
    private let contButton = UIButton(type: .system)
    private var continuous = false
    /// 结果行。**按序号占位**，不是来一句 append 一句 ——
    /// 🚨 多句会并发在飞（第 2 句说完时第 1 句可能还没回来），
    ///    直接 append 的话顺序由**网络快慢**决定，
    ///    说的顺序和显示的顺序会对不上。
    private var lines: [String] = []
    /// 已经发出去几句（下一句的下标）。
    private var seq = 0
    /// 大字展示。旅游时把译文铺满屏幕，手机一转给对方看。
    private let bigButton = UIButton(type: .system)
    /// 反向翻译：**对方**说外语 → 译成我的语言（界面语言那一档）。
    /// 正向是我说话 → 译成 `lang`（给对方看）。
    private let revButton = UIButton(type: .system)
    private var reversed = false

    private let hintLabel = UILabel()
    private let heardLabel = UILabel()
    private let resultView = UITextView()
    /// 🚨 **不再放进版面**。Kevin 2026-08-26：
    ///    「不用每次在产品功能里面写这个…换在隐私政策里面写就好了。」
    ///    隐私政策第八节「AI 生成内容提示」写着这条，设置页有入口能打开
    ///    —— 满足 DeepSeek 条款 8.1「向终端用户明确披露」。
    ///    对象留着只是为了不改一堆引用，**永远不进版面**。
    private let aiNoticeLabel = UILabel()
    private let micButton = UIButton(type: .system)
    private let toneButton = UIButton(type: .system)

    private lazy var voice = Voice()
    private var phase: Phase = .idle
    private var elapsedTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        // 🚨 这是 **App 里的页面**，要用 App 的渐变底（跟首页/设置页一致），
        //    不是 `Theme.bg` —— 那是**键盘扩展**的底色。
        //    刷错的后果：说话页看起来跟 App 其他页不是一套东西。
        //    安卓构建的漂移闸门抓到的（"iOS 主 App 还在刷 Theme.bg"）。
        UI.paintBg(self)
        // 🚨 标题跟安卓的 `try_title` 一致 —— 两端一模一样是硬规矩。
        //    原来写死 "Transless"，而安卓那边是「随手翻译」。
        title = L.home_try_speak
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
        // 🚨 **不能用 `.alwaysTemplate`** —— logo 是一张带紫色圆角底的方形图标，
        //    template 模式会把所有非透明像素**整块涂成 tintColor**，
        //    渲染出来就是 tab 行右边那个莫名其妙的灰方块（2026-08-26 截图发现）。
        //    template 只适合单色描边图形，不适合有底的图标。
        logoView.image = UIImage(named: "logo")
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
        contButton.setTitle(L.try_continuous, for: .normal)
        contButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        contButton.titleLabel?.adjustsFontSizeToFitWidth = true
        contButton.titleLabel?.minimumScaleFactor = 0.7
        // 🚨 摘出 subStack 之后要**自己设底色和字色** ——
        //    原来是靠 `paintMode()` 给 stack 里那几个统一刷的。
        contButton.setTitleColor(Theme.text, for: .normal)
        contButton.backgroundColor = Theme.key
        contButton.layer.cornerRadius = 16
        contButton.addTarget(self, action: #selector(toggleContinuous),
                             for: .touchUpInside)
        // 🚨 `contButton` **不能放进 subStack** —— `paintMode()` 里
        //    `subStack.isHidden = isTranslate`，那一行是转写模式的子选项，
        //    翻译模式下整行隐藏。放进去的话「连续」在主模式下就没了。
        //    它现在跟「⇄ 对方说」一样，独立约束在麦克风旁边。
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
        paintOutputButtons()
        speakButton.addTarget(self, action: #selector(tapSpeak), for: .touchUpInside)

        bigButton.setTitle(L.try_bigtext, for: .normal)
        bigButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        bigButton.setTitleColor(Theme.text, for: .normal)
        bigButton.backgroundColor = Theme.key
        bigButton.layer.cornerRadius = 16
        paintOutputButtons()
        bigButton.addTarget(self, action: #selector(tapBig),
                            for: .touchUpInside)

        // 🚨 按钮文字**就是当前方向**（Kevin 2026-08-26：
        //    「我点一下『对方说』就能变成『我说』」）。
        //    只靠底色区分，用户回头看想不起来现在是哪个方向。
        revButton.setTitle(L.try_dir_me, for: .normal)
        revButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        revButton.titleLabel?.adjustsFontSizeToFitWidth = true
        revButton.titleLabel?.minimumScaleFactor = 0.7
        revButton.setTitleColor(Theme.text, for: .normal)
        revButton.backgroundColor = Theme.key
        revButton.layer.cornerRadius = 16
        revButton.addTarget(self, action: #selector(tapReverse),
                            for: .touchUpInside)

        [modeStack, subStack, hintLabel, heardLabel, resultView, micButton,
         toneButton, langButton, speakButton, bigButton,
         revButton, contButton].forEach {
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
            // 🚨 反向钮贴在麦克风**左边**，不进那一行选项 ——
            //    那行已经有「整理/逐字/连续」，Kevin 说过「排版太密了」。
            //    麦克风自己的居中约束不动，所以视觉重心不会被推偏。
            revButton.trailingAnchor.constraint(
                equalTo: micButton.leadingAnchor, constant: -16),
            revButton.centerYAnchor.constraint(equalTo: micButton.centerYAnchor),
            revButton.widthAnchor.constraint(equalToConstant: 76),
            revButton.heightAnchor.constraint(equalToConstant: 32),

            // 「连续」在麦克风**右边**，跟左边的「⇄ 对方说」对称。
            contButton.leadingAnchor.constraint(
                equalTo: micButton.trailingAnchor, constant: 16),
            contButton.centerYAnchor.constraint(equalTo: micButton.centerYAnchor),
            contButton.widthAnchor.constraint(equalToConstant: 76),
            contButton.heightAnchor.constraint(equalToConstant: 32),

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

            // 🚨 朗读 + 大字**并排居中**：总宽 140+8+100=248，
            //    所以朗读的中心要落在 centerX-54（= -124+70）。
            speakButton.centerXAnchor.constraint(
                equalTo: view.centerXAnchor, constant: -54),
            bigButton.leadingAnchor.constraint(
                equalTo: speakButton.trailingAnchor, constant: 8),
            bigButton.centerYAnchor.constraint(
                equalTo: speakButton.centerYAnchor),
            bigButton.widthAnchor.constraint(equalToConstant: 100),
            bigButton.heightAnchor.constraint(equalToConstant: 36),
            speakButton.topAnchor.constraint(equalTo: toneButton.bottomAnchor, constant: 10),
            speakButton.widthAnchor.constraint(equalToConstant: 140),
            speakButton.heightAnchor.constraint(equalToConstant: 36),

            heardLabel.topAnchor.constraint(equalTo: speakButton.bottomAnchor, constant: Theme.gap),
            heardLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            heardLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            resultView.topAnchor.constraint(equalTo: heardLabel.bottomAnchor, constant: 14),
            resultView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            resultView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            // 🚨 原来这里锚在 `aiNoticeLabel.topAnchor` 上。
            //    那条披露移走之后，resultView 的底要直接接 safeArea
            //    —— 只删视图不改约束的话它会失去底部约束、整块塌掉，
            //    而且**编译不报错**，只有跑起来才看得见。
            resultView.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                constant: -16),
        ])
        // 🚨 立体感统一在这儿走一遍，别在每个控件后面各写一行 —— 漏一个就少一个阴影，
        //    而"少了一个"是看不出来的（跟安卓 Theme.elevateAll 同一套做法）。
        for v in [tabTranslate, tabTranscribe, modeZhButton, modeRawButton,
                  toneButton, langButton, speakButton, bigButton] {
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
            bigButton.setTitle(L.try_bigtext, for: .normal)
            revButton.setTitle(
                reversed ? L.try_dir_them : L.try_dir_me,
                for: .normal)
            return
        }
        let text = lastOut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { hintLabel.text = L.nothing_to_speak; return }
        paintOutputButtons()
        speakButton.setTitle("…", for: .normal)
        Backend.speak(text: text) { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.paintOutputButtons()
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

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    /// 调试口子：把新功能的状态摆出来好截图。
    ///
    /// 🚨 **每一条都调真实方法**，不是另设一个布尔。
    ///    伪造状态截出来的图只能证明"我画得出来"，
    ///    证明不了那个按钮点下去真会这样。
    private func applyDebugEnv() {
        let env = ProcessInfo.processInfo.environment
        if let t = env["TRANSLESS_RESULT"], !t.isEmpty {
            // 走 setLine 那条真实回填路径的等价物：写结果区 + 按真实规则点亮
            resultView.text = t
            lastOut = t
            paintOutputButtons()
        }
        if env["TRANSLESS_CONT"] == "1" { toggleContinuous() }
        if env["TRANSLESS_REV"] == "1" { tapReverse() }
        if env["TRANSLESS_BIG"] == "1" {
            // 🚨 延后一拍：`present` 要等这一层真的上了屏，
            //    在 viewDidAppear 同步调会被系统忽略（而且不报错）。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                [weak self] in self?.tapBig()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyDebugEnv()
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

    /// 出了结果才算"体验过"。**跟安卓 `TryActivity` 同一个判据**：
    /// `if (fo.length() > 0) Onboard.markTried(...)`。
    ///
    /// 🚨 判据故意放在这一个函数里，两处调用点都走它 ——
    ///    散成两行 `if ... { Onboard.markTried() }` 就是下一次走散的起点。
    private func markTriedIfProduced(_ out: String) {
        if !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Onboard.markTried()
        }
    }

    @objc private func tapMic() {
        // 🚨🚨 **这里不再 `markTried()`**（2026-08-26 修）。
        //    原来是函数第一行就置位 —— 权限都还没请求。
        //    后果：Kevin 只是点了一下麦克风（弹窗都没点完），
        //    就被记成"体验过了"，下次进来只剩注册登录页。
        //    他的原话：**「没用过，一进去就是登录页」**。
        //
        //    而**安卓那边是拿到非空结果才置位**的
        //    （`TryActivity`：`if (fo.length() > 0) markTried(...)`）。
        //    同一个标志两端两套判据，两边注释还各自说自己那套才对
        //    —— 典型的「同一规则两处实现，悄悄走散」。
        //    现在统一成安卓那套：**真出了结果才算体验过**。
        //    见 `markTriedIfProduced(_:)`。
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
        lines.removeAll()
        seq = 0
        setPhase(.listening, hint: continuous
                 ? L.try_cont_on
                 : "听着呢，想到哪说到哪（最长 60 秒）\n说完再按一下红色按钮")
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, self.phase == .listening else { return }
            let s = Int(self.voice.elapsed)
            self.hintLabel.text = String(format: L.st_listening_ios, s / 60, s % 60)
        }

        // 录音 → 停止后拿到 WAV → 传后端转写 → 再润色（跟安卓同一条链）
        // 🚨 连续模式才传 `onUtterance`。不传 = 老的单句行为，
        //    一个字节的行为差别都没有（同一段 tap，只是不切）。
        voice.start(onPartial: { _ in },
                    onUtterance: continuous ? { [weak self] wav in
                        self?.sendUtterance(wav)
                    } : nil,
                    onWav: { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.elapsedTimer?.invalidate(); self.elapsedTimer = nil
                switch result {
                case .failure(let f):
                    self.setPhase(.idle, hint: "\(f)")
                case .success(let wav):
                    // 🚨 连续模式下空 WAV 是**正常收尾**（刚切完一句才按的停止，
                    //    `Voice.stop()` 查过 `hasVoice` 才交空的），不是错。
                    if self.continuous {
                        self.setPhase(.idle, hint: "")
                        if wav.count > 44 { self.sendUtterance(wav) }
                        return
                    }
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

    /// 切连续模式。**录音中不许切** —— 切了之后录音器还在老模式跑，
    /// 界面显示的却是新模式，两份状态会对不上。
    @objc private func toggleContinuous() {
        if phase != .idle { return }
        continuous.toggle()
        paintContinuous()
        hintLabel.text = continuous ? L.try_cont_on : ""
    }

    private func paintContinuous() {
        contButton.backgroundColor = continuous ? Theme.accent : Theme.panel
        contButton.setTitleColor(continuous ? .white : Theme.text,
                                 for: .normal)
    }

    /// 把 `lines` 拼成结果文本。还没回来的那行显示成省略号占位。
    private func paintLines() {
        resultView.text = lines
            .map { $0.isEmpty ? "\u{2026}" : $0 }
            .joined(separator: "\n")
    }

    /// 连续模式：一句走完 transcribe → polish 两步，回填到 `lines[idx]`。
    ///
    /// 🚨 idx **必须贯穿两步**。只在 polish 那步取 `lines.count` 的话，
    ///    第 2 句先回来时会写到第 1 句的位置上。
    private func sendUtterance(_ wav: Data) {
        // 🚨 在**发出去之前**把目标语言定死。等结果时用户点了反向的话，
        //    这一句会用错的语言回来。
        let fLang = langNow
        let idx = seq
        seq += 1
        lines.append("")            // 先占位，保住说话的顺序
        paintLines()
        Backend.transcribe(wav: wav) { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch r {
                case .failure(let f):
                    // 错误落在**那一行**上，别把整块已经出来的结果冲掉
                    self.setLine(idx, "\(f)")
                case .success(let zh):
                    self.heardLabel.text = zh
                    // 🚨 反向时目标语言换成**我的语言**。
                    //    用 `self.lang` 的话反向按钮点了等于没点，
                    //    而界面还亮着 —— 那种"看起来生效了"的错最难查。
                    Backend.polish(text: zh, tone: self.tone,
                                   mode: self.mode, lang: fLang) {
                        [weak self] r2 in
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            switch r2 {
                            case .success(let en):
                                self.lastOut = en
                                self.paintOutputButtons()
                                self.setLine(idx, en)
                                // 🚨 连续模式也要算 —— 少接一处的话，
                                //    只用连续模式的人永远解锁不了。
                                self.markTriedIfProduced(en)
                            case .failure(let e):
                                self.setLine(idx, "\(e)")
                            }
                        }
                    }
                }
            }
        }
    }

    /// 切正向/反向。**录音中不许切** —— 这一次录的是谁的话，
    /// 中途改了的话发出去的目标语言跟界面显示的对不上。
    @objc private func tapReverse() {
        if phase != .idle { return }
        reversed.toggle()
        revButton.setTitle(reversed ? L.try_dir_them : L.try_dir_me,
                           for: .normal)
        revButton.backgroundColor = reversed ? Theme.accent : Theme.key
        revButton.setTitleColor(reversed ? .white : Theme.text, for: .normal)
        hintLabel.text = reversed ? L.try_reverse_on : ""
        // 🚨 反向必须是**翻译**模式。停在「逐字」上的话，
        //    对方说的英文会被原样吐回来 —— 一个字都没翻，
        //    而用户以为反向没生效。
        if reversed && mode == .raw { pickEn() }
    }

    /// 这一次要译成什么语言。
    ///
    /// 🚨 反向时走 `Reverse`（两端同一份口径、有自测），
    ///    **不要在这里现写 if-else**。
    private var langNow: String {
        return reversed ? Reverse.target(for: Lang.current) : lang
    }

    /// 「朗读 / 大字」的显隐。**只由这里决定**，别在别处再写一遍。
    ///
    /// 🚨 跟安卓一致：没内容时**隐藏**（不是置灰）。
    ///    `speakBtn.setVisibility(lastText.length() > 0 ? VISIBLE : GONE)`
    ///
    /// 🚨 两个判据不同，别合并：
    ///    朗读看 `lastOut`（念最后那一句），
    ///    大字看 `resultView`（展示整段 —— 连续模式下有好几句）。
    private func paintOutputButtons() {
        // 🚨🚨 这两行**曾经被我自己的批量正则替换成了 `paintOutputButtons()`**，
        //    于是方法调用自己 → 无限递归 → EXC_BAD_ACCESS/SIGSEGV，
        //    App 一启动就崩。**编译完全通过**，只有真跑才看得见。
        //    根因是顺序错了：我先插入这个方法、再跑全局替换，
        //    方法体自然也在替换范围里。
        //    → 批量替换一律**先换、后插新代码**；插完再 grep 一遍新方法体。
        let canSpeak = !lastOut.isEmpty
        let canBig = !bigTextNow().isEmpty
        speakButton.isHidden = !canSpeak
        speakButton.isEnabled = canSpeak
        bigButton.isHidden = !canBig
        bigButton.isEnabled = canBig
    }

    /// 现在该拿去大字展示的内容：连续模式给整段，单句模式给那一句。
    private func bigTextNow() -> String {
        return (resultView.text ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines)
    }

    /// 大字展示：译文铺满屏幕，点一下关掉。
    @objc private func tapBig() {
        let text = bigTextNow()
        guard !text.isEmpty else { return }
        let vc = BigTextViewController(text: text)
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }

    private func setLine(_ idx: Int, _ text: String) {
        guard idx < lines.count else { return }
        lines[idx] = text
        paintLines()
        // 🚨 大字按钮的判据是**结果区有没有东西**，不是 `lastOut` ——
        //    连续模式下 lastOut 只是最后一句，而结果区是整段对话。
        paintOutputButtons()
    }

    private func polish(_ zh: String) {
        switch mode {
        case .en:  setPhase(.thinking, hint: L.st_translating)
        case .zh:  setPhase(.thinking, hint: L.st_polishing)
        case .raw: setPhase(.thinking, hint: L.st_inserting)   // 不过模型，一瞬间
        }
        let fLang = langNow
        Backend.polish(text: zh, tone: tone, mode: mode, lang: fLang) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let en):
                    self.resultView.text = en
                    self.paintOutputButtons()
                    UIPasteboard.general.string = en   // 自动进剪贴板
                    self.lastOut = en                  // 给「🔊 朗读」用
                    // 🚨 **真出了结果才算体验过** —— 跟安卓 `TryActivity`
                    //    的 `if (fo.length() > 0) markTried(...)` 同一个判据。
                    self.markTriedIfProduced(en)
                    self.paintOutputButtons()
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
/// 键盘预览：**把真的 `KeyboardViewController` 嵌进来跑**。
///
/// 🚨🚨 上一版是我自己摆的一个假页面（直接 new 一个 `TypingKeyboardView`），
///    于是截图永远显示"打字键盘、跟安卓一致"，
///    而用户打开键盘看到的是语音面板、比安卓少两整行 ——
///    我"验过"的每一次都是白验。**判据挂在了错的对象上。**
///    （Kevin 2026-08-26 真机截图打脸后重写。）
///
/// 🚨 仍有两处跟真扩展不同，**写清楚，别当等价**：
///    ① 没有宿主输入框，`textDocumentProxy` 是空的 → 能验版面，不能验上屏
///    ② `hasFullAccess` 在容器 App 里恒 false → 预览里会看到那行红字，
///       那是预览环境的限制，不代表真机也这样
final class KeyboardPreviewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let bg = Theme.keyboardBackground(UIScreen.main.bounds)
        bg.frame = UIScreen.main.bounds
        view.layer.insertSublayer(bg, at: 0)

        let fake = UILabel()
        fake.text = "  预览：真实键盘扩展（KeyboardViewController）"
        fake.font = .systemFont(ofSize: 13)
        fake.textColor = Theme.dim
        fake.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        fake.layer.cornerRadius = 8
        fake.layer.masksToBounds = true
        fake.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fake)

        // 🚨 **真的那个类**，不是复刻。改了键盘，这里跟着变；
        //    改漏了，这里也一眼看得出来。
        let kb = KeyboardViewController()
        addChild(kb)
        kb.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(kb.view)
        kb.didMove(toParent: self)

        NSLayoutConstraint.activate([
            fake.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            fake.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                          constant: 12),
            fake.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                           constant: -12),
            fake.heightAnchor.constraint(equalToConstant: 40),

            kb.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            kb.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            kb.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

// 下面这个是**旧的假预览**，留着只为对照，不再被任何入口引用。
private final class _OldFakeKeyboardPreview: UIViewController {
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


// MARK: - 大字展示

/// 译文铺满屏幕，点一下关掉。旅游时手机一转给对方看。
///
/// 🚨 字号走 `BigText`（跟安卓同一张表、有自测），**不在这里现算**。
/// 🚨 展示期间不让屏幕灭掉 —— 给对方看的时候没人在碰手机，
///    十几秒就黑屏了。`isIdleTimerDisabled` 在 `viewWillDisappear` 里**必须
///    还原**，否则整个 App 从此不再自动锁屏（用户会当成耗电 bug）。
final class BigTextViewController: UIViewController {

    private let text: String

    init(text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 用不到") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 🚨 用**主界面那个渐变底**（`Skin.screenBg`），不是 `Theme.bg` ——
        //    后者是**键盘扩展**的底色。这两个搞混过一次，被漂移闸门抓出来。
        //    也别自己挑颜色：Kevin 说过「你不要自己设计了」。
        // 🚨 **不设 backgroundColor** —— 主 App 的页面一律只插渐变层。
        //    我第一版写了 `Theme.bg`，那是**键盘扩展**的底色，
        //    当场被漂移闸门拦下来（`iOS 跟安卓没有漂移` 那一项）。
        //    页面别处（AppDelegate:108）就是只 insertSublayer、不设色。
        let bg = Skin.screenBg(UIScreen.main.bounds)
        bg.frame = UIScreen.main.bounds
        view.layer.insertSublayer(bg, at: 0)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: BigText.size(text), weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(label)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            label.topAnchor.constraint(greaterThanOrEqualTo: scroll.topAnchor, constant: 20),
            label.bottomAnchor.constraint(lessThanOrEqualTo: scroll.bottomAnchor, constant: -20),
            label.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -20),
            label.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -40),
            // 🚨 文字少时要**垂直居中**，不能贴在顶上。
            //    `centerY` 用低优先级，文字长到撑破一屏时让它让位给上面
            //    那两条 greaterThan/lessThan，否则约束会冲突。
            {
                let c = label.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
                c.priority = .defaultHigh
                return c
            }(),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(close))
        view.addGestureRecognizer(tap)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 🚨 一定要还原 —— 忘了的话整个 App 从此不自动锁屏。
        UIApplication.shared.isIdleTimerDisabled = false
    }

    @objc private func close() { dismiss(animated: true) }
}
