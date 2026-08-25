import UIKit

/// 手机号验证码登录。
///
/// **一屏两步**：先填手机号拿码，码发出去之后验证码框才出现 ——
/// 比推两个页面顺，也少一次返回。
///
/// 🚨 版式照 `SetupViewController`：卡片 18/20 内边距、行间 15、左右 21，
///    值全部来自安卓 `SetupActivity`。这里**没有一个数是我自己挑的**。
///
/// 🚨 「验证码不对」和「这个号没注册过」后端返回的是**同一句话**，
///    否则这接口就成了查「某人有没有用过 Transless」的工具。
///    界面上也不许试图区分，别自作聪明加"该手机号未注册"这种提示。
final class LoginViewController: UIViewController {

    /// 当前用邮箱还是手机号。**邮箱是默认** ——
    /// Kevin 2026-08-25：「第一期不在内地，海外的话主要是邮箱。
    /// 你先上线邮箱的注册，手机号这个先晚一点。」
    private var kind: Auth.Kind = .email
    private let tabEmail = UIButton(type: .system)
    private let tabPhone = UIButton(type: .system)
    /// 收窄约束：只激活未选中那一个（跟说话页那两个 Tab 同一个做法）
    private var narrowEmail: NSLayoutConstraint?
    private var narrowPhone: NSLayoutConstraint?

    private let phoneField = UITextField()
    private let codeField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let loginButton = UIButton(type: .system)
    private let hint = UILabel()
    private var codeRow: UIView?
    private var countdown: Timer?
    /// 底下那句"没注册过会自动建号"。**跟着 tab 换** ——
    /// 邮箱 tab 下写"手机号"是明显的错话。
    private weak var noteLabel: UILabel?
    /// 国家区号那一格。**独立的小卡片**，跟手机号框并排。
    ///
    /// 🚨 Kevin 2026-08-25：「单独搞个小格嘛，不要和手机号放在一起嘛。
    ///    因为后面也可能会涉及，也会加各个不同国家的手机号的嘛。」
    ///    所以现在就摆成最终的样子 —— 以后接国家列表只换里面的行为，
    ///    排版和位置都不用再动。
    ///
    /// 🚨 **固定 +86，不让他自己打**：自己打的话 `+86` / `86` / `0086` /
    ///    什么都不加，四种写法都会出现，而后端只认一种 ——
    ///    那些差异会变成"验证码发不出去"，他还完全看不出是自己少打了两个字符。
    private let ccButton = UIButton(type: .system)
    /// 区号那一格整体。邮箱 tab 下**整格不出现**（不是变灰）——
    /// 邮箱前面放一个国家区号是没有意义的东西。
    private var ccBox: UIView?
    /// 调试用：进来就落在手机号 tab（截图用）。正式界面没有入口。
    var startOnPhoneTab = false
    private var left = 0

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.home_login

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 15                    // 照安卓 SetupActivity
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                           constant: 21),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                            constant: -21),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor,
                                       constant: 24),
        ])

        let why = UILabel()
        why.text = L.login_why
        why.font = .systemFont(ofSize: 13)
        why.textColor = Skin.sub
        why.numberOfLines = 0
        stack.addArrangedSubview(why)
        stack.setCustomSpacing(20, after: why)

        // ---- 两个 tab：邮箱 / 手机号 ----
        for (b, t, sel) in [(tabEmail, L.login_tab_email, #selector(pickEmail)),
                            (tabPhone, L.login_tab_phone, #selector(pickPhone))] {
            b.setTitle(t, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            b.layer.cornerRadius = 17
            b.titleLabel?.adjustsFontSizeToFitWidth = true
            b.titleLabel?.minimumScaleFactor = 0.8
            b.addTarget(self, action: sel, for: .touchUpInside)
        }
        let tabs = UIStackView(arrangedSubviews: [tabEmail, tabPhone])
        tabs.axis = .horizontal
        tabs.spacing = 8
        tabs.distribution = .fill
        tabEmail.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tabPhone.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // 🚨 跟说话页那两个 Tab **同一个做法**：未选中的收窄、选中的吃满。
        //    别再来第二套量法。
        narrowEmail = tabEmail.widthAnchor.constraint(equalToConstant: 96)
        narrowPhone = tabPhone.widthAnchor.constraint(equalToConstant: 96)
        tabs.heightAnchor.constraint(equalToConstant: 40).isActive = true
        stack.addArrangedSubview(tabs)

        // ---- 账号输入（邮箱或手机号，同一个框换口径）----
        phoneField.placeholder = L.login_email_ph
        phoneField.autocapitalizationType = .none
        phoneField.autocorrectionType = .no
        stack.addArrangedSubview(accountCard())
        paintTabs(animated: false)

        sendButton.setTitle(L.login_send_code, for: .normal)
        style(sendButton, primary: true)
        sendButton.addTarget(self, action: #selector(tapSend),
                             for: .touchUpInside)
        stack.addArrangedSubview(sendButton)

        // ---- 验证码（发出去之后才显示）----
        codeField.keyboardType = .numberPad
        codeField.textContentType = .oneTimeCode   // 让系统能自动填短信里的码
        codeField.placeholder = L.login_code_ph
        let cr = card(codeField)
        cr.isHidden = true
        codeRow = cr
        stack.addArrangedSubview(cr)

        loginButton.setTitle(L.login_do, for: .normal)
        style(loginButton, primary: true)
        loginButton.addTarget(self, action: #selector(tapLogin),
                              for: .touchUpInside)
        loginButton.isHidden = true
        stack.addArrangedSubview(loginButton)

        hint.font = .systemFont(ofSize: 12)
        hint.textColor = Skin.sub
        hint.numberOfLines = 0
        hint.textAlignment = .center
        stack.setCustomSpacing(18, after: loginButton)
        stack.addArrangedSubview(hint)

        let note = UILabel()
        noteLabel = note
        note.text = L.login_note_mail        // 默认是邮箱 tab
        note.font = .systemFont(ofSize: 12)
        note.textColor = Skin.dim
        note.numberOfLines = 0
        stack.setCustomSpacing(24, after: hint)
        stack.addArrangedSubview(note)

        // 🚨 **必须在 note 建好之后**再切 tab。
        //    原来这句在上面（accountCard 之后），那时 `noteLabel` 还是 nil，
        //    于是手机号 tab 下底部文案仍然写着「没注册过的**邮箱**」——
        //    截图上一眼看到的错话。
        //    「在哪儿调」和「调什么」一样重要。
        if startOnPhoneTab { switchTo(.phone) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    // MARK: - 动作

    // MARK: - Tab

    @objc private func pickEmail() { switchTo(.email) }
    @objc private func pickPhone() { switchTo(.phone) }

    private func switchTo(_ k: Auth.Kind) {
        guard k != kind else { return }
        kind = k
        phoneField.text = ""
        codeRow?.isHidden = true
        loginButton.isHidden = true
        hint.text = ""
        switch k {
        case .email:
            phoneField.keyboardType = .emailAddress
            phoneField.textContentType = .emailAddress
            phoneField.placeholder = L.login_email_ph
        case .phone:
            phoneField.keyboardType = .numberPad
            phoneField.textContentType = .telephoneNumber
            phoneField.placeholder = L.login_phone_ph
        }
        let isPhone = (k == .phone)
        ccBox?.isHidden = !isPhone
        // placeholder 的颜色是在 card() 里设的，换完文案要重设一次
        phoneField.attributedPlaceholder = NSAttributedString(
            string: phoneField.placeholder ?? "",
            attributes: [.foregroundColor: Skin.dim])
        noteLabel?.text = (k == .email) ? L.login_note_mail : L.login_note
        paintTabs(animated: true)
    }

    private func paintTabs(animated: Bool) {
        let onEmail = (kind == .email)
        tabEmail.backgroundColor = onEmail ? Skin.accent : Theme.key
        tabEmail.setTitleColor(onEmail ? .white : Skin.dim, for: .normal)
        tabPhone.backgroundColor = onEmail ? Theme.key : Skin.accent
        tabPhone.setTitleColor(onEmail ? Skin.dim : .white, for: .normal)
        narrowEmail?.isActive = !onEmail
        narrowPhone?.isActive = onEmail
        guard animated, view.window != nil else { return }
        UIView.animate(withDuration: 0.22, delay: 0,
                       usingSpringWithDamping: 0.9, initialSpringVelocity: 0.2,
                       options: [.curveEaseOut]) { self.view.layoutIfNeeded() }
    }

    /// 中国内地手机号：`1` 开头、11 位数字。
    ///
    /// 🚨 卡这一道是因为**后端走的是阿里云短信，它本来就只发内地**。
    ///    不卡的话用户填个海外号、点发码、等半天拿回一个看不懂的服务端错误
    ///    —— 当场说清比事后报错强。
    ///    Kevin 2026-08-25：「手机号只能输入中国内地的手机号，
    ///    如果不是的话，它就会不支持。」
    private static func isMainlandPhone(_ s: String) -> Bool {
        let d = s.filter { $0.isNumber }
        return d.count == 11 && d.hasPrefix("1")
    }

    @objc private func tapSend() {
        let t = (phoneField.text ?? "").trimmingCharacters(in: .whitespaces)
        switch kind {
        case .email:
            // 🚨 只做**最起码**的校验（有 @、有点）。真正判合不合法是服务端的事
            //    —— 客户端写一套正则去卡，遇到少见但合法的地址就把人挡在外面。
            guard t.contains("@"), t.contains("."), t.count >= 6 else {
                say(L.login_need_email, bad: true); return
            }
        case .phone:
            guard Self.isMainlandPhone(t) else {
                say(L.login_mainland_only, bad: true); return
            }
        }
        // 🚨 手机号要带 `+86` 再发出去。后端 `auth_store.py` 的自测用的就是
        //    `+8613800000001`，`PhoneNumber` 是原样传给阿里云的
        //    —— 这个格式是从它的自测里读出来的，不是我猜的。
        let target = (kind == .phone) ? ("+86" + t.filter { $0.isNumber }) : t
        sendButton.isEnabled = false
        say(L.login_sending, bad: false)
        Auth.sendCode(kind, target) { [weak self] r in
            DispatchQueue.main.async {
                guard let s = self else { return }
                switch r {
                case .success:
                    s.codeRow?.isHidden = false
                    s.loginButton.isHidden = false
                    s.codeField.becomeFirstResponder()
                    s.say(s.kind == .email ? L.login_sent_mail : L.login_sent,
                          bad: false)
                    s.startCountdown()
                case .failure(let e):
                    s.sendButton.isEnabled = true
                    s.say(s.text(for: e), bad: true)
                }
            }
        }
    }

    @objc private func tapLogin() {
        let raw = (phoneField.text ?? "").trimmingCharacters(in: .whitespaces)
        // 🚨 **验码用的 target 必须跟发码时一模一样**。
        //    发的时候加了 `+86`、验的时候不加，后端就是两个不同的键，
        //    永远报"验证码不对" —— 而那句话看起来像用户输错了。
        let t = (kind == .phone) ? ("+86" + raw.filter { $0.isNumber }) : raw
        let c = (codeField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { say(L.login_need_code, bad: true); return }
        loginButton.isEnabled = false
        say(L.login_checking, bad: false)
        Auth.verify(kind, t, code: c) { [weak self] r in
            DispatchQueue.main.async {
                guard let s = self else { return }
                s.loginButton.isEnabled = true
                switch r {
                case .success:
                    // 回首页 —— 那边会重建，「设为当前输入法」这时才冒出来
                    s.navigationController?.popViewController(animated: true)
                case .failure(let e):
                    s.say(s.text(for: e), bad: true)
                }
            }
        }
    }

    /// 🚨 每种失败都要有**自己的话**。全都写"登录失败"的话，
    ///    用户不知道是自己输错了、还是被限流了、还是服务器挂了 ——
    ///    而这三种他该做的事完全不同。
    private func text(for e: Auth.Failure) -> String {
        switch e {
        case .badCode(let m): return m
        case .rateLimited(let s): return String(format: L.login_too_often, s)
        case .failed(let m): return m
        }
    }

    private func startCountdown() {
        left = 60
        countdown?.invalidate()
        countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] t in
            guard let s = self else { t.invalidate(); return }
            s.left -= 1
            if s.left <= 0 {
                t.invalidate()
                s.sendButton.isEnabled = true
                s.sendButton.setTitle(L.login_send_again, for: .normal)
            } else {
                s.sendButton.setTitle(String(format: L.login_wait, s.left),
                                      for: .normal)
            }
        }
    }

    private func say(_ s: String, bad: Bool) {
        hint.text = s
        hint.textColor = bad ? Theme.danger : Skin.sub
    }

    // MARK: - 造件

    /// 账号输入区。手机号 tab 下是 `[+86 v] [手机号]` **两格并排**；
    /// 邮箱 tab 下只有一格。
    ///
    /// 🚨 Kevin 2026-08-25：「单独搞个小格嘛，不要和手机号放在一起嘛。
    ///    因为后面也可能会涉及，也会加各个不同国家的手机号的嘛。」
    ///    所以现在就摆成最终的样子 —— 以后接国家列表只换里面的行为，
    ///    排版和位置都不用再动。
    private func accountCard() -> UIView {
        // ---- 左边：区号小格 ----
        let ccWrap = UIView()
        ccWrap.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        ccWrap.layer.cornerRadius = 14
        ccButton.setTitle("+86 \u{25BE}", for: .normal)
        ccButton.setTitleColor(Skin.text, for: .normal)
        ccButton.titleLabel?.font = .systemFont(ofSize: 17)
        ccButton.addTarget(self, action: #selector(tapCC), for: .touchUpInside)
        ccButton.translatesAutoresizingMaskIntoConstraints = false
        ccWrap.addSubview(ccButton)
        NSLayoutConstraint.activate([
            ccButton.leadingAnchor.constraint(equalTo: ccWrap.leadingAnchor),
            ccButton.trailingAnchor.constraint(equalTo: ccWrap.trailingAnchor),
            ccButton.topAnchor.constraint(equalTo: ccWrap.topAnchor),
            ccButton.bottomAnchor.constraint(equalTo: ccWrap.bottomAnchor),
        ])
        ccWrap.widthAnchor.constraint(equalToConstant: 96).isActive = true
        ccWrap.isHidden = true                 // 默认邮箱 tab
        ccBox = ccWrap

        let fieldBox = plainCard(phoneField)
        let row = UIStackView(arrangedSubviews: [ccWrap, fieldBox])
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fill
        // 🚨 输入框吃满剩下的宽度：区号那格是固定宽 96，
        //    不给输入框低 hugging 的话两个会平分，手机号框只剩一半。
        fieldBox.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return row
    }

    /// 一张普通的输入卡片。
    private func plainCard(_ f: UITextField) -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        box.layer.cornerRadius = 14
        // 🚨 显式左对齐。不设的话 `.natural` 会把 placeholder 顶到最右边
        //    （截图上「手机号」离 +86 老远）。
        f.textAlignment = .left
        f.textColor = Skin.text
        f.font = .systemFont(ofSize: 17)
        f.tintColor = Skin.accent
        f.attributedPlaceholder = NSAttributedString(
            string: f.placeholder ?? "",
            attributes: [.foregroundColor: Skin.dim])
        f.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(f)
        NSLayoutConstraint.activate([
            f.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 18),
            f.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -18),
            f.topAnchor.constraint(equalTo: box.topAnchor, constant: 20),
            f.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -20),
        ])
        return box
    }

    /// 点了区号那一格。
    /// 🚨 现在只有 +86，所以只说清"目前只支持这个"。
    ///    以后接国家列表时换成选择器 —— 位置和交互都不用再动。
    @objc private func tapCC() {
        say(L.login_mainland_only, bad: false)
    }
    private func card(_ field: UITextField) -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        box.layer.cornerRadius = 14
        field.textColor = Skin.text
        field.font = .systemFont(ofSize: 17)
        field.tintColor = Skin.accent
        field.attributedPlaceholder = NSAttributedString(
            string: field.placeholder ?? "",
            attributes: [.foregroundColor: Skin.dim])
        field.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: box.leadingAnchor,
                                           constant: 18),
            field.trailingAnchor.constraint(equalTo: box.trailingAnchor,
                                            constant: -18),
            field.topAnchor.constraint(equalTo: box.topAnchor, constant: 20),
            field.bottomAnchor.constraint(equalTo: box.bottomAnchor,
                                          constant: -20),
        ])
        return box
    }

    private func style(_ b: UIButton, primary: Bool) {
        b.setTitleColor(.white, for: .normal)
        b.setTitleColor(Skin.dim, for: .disabled)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        b.backgroundColor = primary ? Skin.accent : Skin.accent2
        b.layer.cornerRadius = 12
        b.heightAnchor.constraint(equalToConstant: 52).isActive = true
    }
}
