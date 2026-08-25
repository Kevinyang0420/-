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

    private let phoneField = UITextField()
    private let codeField = UITextField()
    private let sendButton = UIButton(type: .system)
    private let loginButton = UIButton(type: .system)
    private let hint = UILabel()
    private var codeRow: UIView?
    private var countdown: Timer?
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

        // ---- 手机号 ----
        phoneField.keyboardType = .numberPad
        phoneField.textContentType = .telephoneNumber
        phoneField.placeholder = L.login_phone_ph
        stack.addArrangedSubview(card(phoneField))

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
        note.text = L.login_note
        note.font = .systemFont(ofSize: 12)
        note.textColor = Skin.dim
        note.numberOfLines = 0
        stack.setCustomSpacing(24, after: hint)
        stack.addArrangedSubview(note)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    // MARK: - 动作

    @objc private func tapSend() {
        let t = (phoneField.text ?? "").trimmingCharacters(in: .whitespaces)
        // 🚨 只做**最起码**的本地校验（非空、看着像号码）。
        //    真正判合不合法是服务端的事 —— 客户端写一套正则去卡，
        //    换个国家的号码格式就把人挡在外面了。
        guard t.count >= 6 else {
            say(L.login_need_phone, bad: true); return
        }
        sendButton.isEnabled = false
        say(L.login_sending, bad: false)
        Auth.sendCode(.phone, t) { [weak self] r in
            DispatchQueue.main.async {
                guard let s = self else { return }
                switch r {
                case .success:
                    s.codeRow?.isHidden = false
                    s.loginButton.isHidden = false
                    s.codeField.becomeFirstResponder()
                    s.say(L.login_sent, bad: false)
                    s.startCountdown()
                case .failure(let e):
                    s.sendButton.isEnabled = true
                    s.say(s.text(for: e), bad: true)
                }
            }
        }
    }

    @objc private func tapLogin() {
        let t = (phoneField.text ?? "").trimmingCharacters(in: .whitespaces)
        let c = (codeField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { say(L.login_need_code, bad: true); return }
        loginButton.isEnabled = false
        say(L.login_checking, bad: false)
        Auth.verify(.phone, t, code: c) { [weak self] r in
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
