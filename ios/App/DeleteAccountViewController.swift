import UIKit

/// **删除账号**这一屏 —— App Store 硬要求 App 内可达（0 台账 #72，卡 iOS 提交）。
///
/// 承诺早就印在同步弹窗上（`hs_ask_3`：「你删除账号时，云端的记录会一并删掉」），
/// 而**三端一个入口都没有**。这一屏兑现它。
///
/// 🚨 视觉沿用账户页那套（同样的圆角、间距、危险色），**没有新设计** ——
///    Kevin 定过我不许自己设计 UI。
final class DeleteAccountViewController: UIViewController {

    private let stack = UIStackView()
    private let codeField = UITextField()
    private let hint = UILabel()
    private var cancelBtn: UIButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.del_acct_title

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 21),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -21),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -28),
        ])

        // ① 说清后果 —— 不许只放一个红按钮就完事
        let body = UILabel()
        body.text = L.del_acct_body
        body.font = .systemFont(ofSize: 15)
        body.textColor = Skin.text
        body.numberOfLines = 0
        body.accessibilityIdentifier = "del.body"
        stack.addArrangedSubview(body)

        // 🚨🚨 **这里没有"填账号"这一栏，是故意的。**
        //    我第一版有 —— 而服务端源码写死：验证码的 target
        //    **只从他自己的账号行取**，「不许客户端传 —— 让客户端指定 target
        //    就等于送人一个接管账号的口子」。
        //    留个输入框在这儿，他填了也没用，**还会以为能删别人的号**。

        // ③ 发码
        stack.addArrangedSubview(button(L.del_acct_send, id: "del.send",
                                        danger: false, #selector(tapSend)))

        // ④ 验证码
        stack.addArrangedSubview(field(codeField, L.del_acct_code,
                                       id: "del.code", value: ""))
        codeField.keyboardType = .numberPad

        // ⑤ 确认删除（危险色）
        stack.addArrangedSubview(button(L.del_acct_confirm, id: "del.confirm",
                                        danger: true, #selector(tapConfirm)))

        // ⑥ 🚨 **撤销** —— 冷静期内他能反悔。
        //    `del_acct_grace` 自己写着「7 天内你随时可以再登录一次来撤销」，
        //    **承诺在文案里、按钮却没有** —— 跟 #72 本身一模一样的形状
        //    （2.3 在安卓侧发现的，我这边同款）。
        //    默认藏着，进页面查一次状态，`pending` 才露出来。
        cancelBtn = button(L.del_acct_cancel, id: "del.cancel",
                           danger: false, #selector(tapCancel))
        cancelBtn?.isHidden = true
        if let cb = cancelBtn { stack.addArrangedSubview(cb) }

        // ⑦ 提示行 —— 🚨 **每个结果都要能跟"没反应"分开**
        hint.font = .systemFont(ofSize: 14)
        hint.textColor = Skin.dim
        hint.numberOfLines = 0
        hint.accessibilityIdentifier = "del.hint"
        stack.addArrangedSubview(hint)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 🚨 进来查一次：已经在冷静期里就把「撤销」露出来，
        //    不用他"再登录一次"（那句话是给网页那条路写的）。
        AccountDelete.status { [weak self] st in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch st {
                case .pending(let d):
                    self.cancelBtn?.isHidden = false
                    // 🚨 用现成的 `del_acct_grace`，**不新加键** ——
                    //    台账正在合并 `del_acct_*` / `acct_del_*` 两套，
                    //    这时候再加一个键只会让合并更难。
                    //    天数写在那句话里了（7 天），`d` 只留痕不上屏。
                    KbBridge.note("删账号：冷静期还剩 \(d) 天")
                    self.hint.text = L.del_acct_grace
                case .notEnabled:
                    self.hint.text = L.del_acct_off
                default:
                    self.cancelBtn?.isHidden = true
                }
            }
        }
    }

    // MARK: - 动作

    @objc private func tapSend() {
        hint.text = ""
        // 🚨 发到哪由服务端决定（他账号行上的手机/邮箱），客户端不传目标。
        AccountDelete.requestCode { [weak self] r in
            DispatchQueue.main.async { self?.show(r, ok: L.del_acct_sent) }
        }
    }

    @objc private func tapConfirm() {
        let c = (codeField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { hint.text = L.del_acct_need_code; return }
        // 🚨 **确认一次**：这一步不可撤（虽然有 7 天冷静期，但那是账号级的，
        //    他未必知道）。跟账户页「退出登录」同一套做法：危险动作要确认。
        let a = UIAlertController(title: L.del_acct_title,
                                  message: L.del_acct_body,
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: L.cancel, style: .cancel))
        a.addAction(UIAlertAction(title: L.del_acct_confirm,
                                  style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            self.hint.text = ""
            AccountDelete.confirm(code: c) { r in
                DispatchQueue.main.async { self.show(r, ok: L.del_acct_grace) }
            }
        })
        present(a, animated: true)
    }

    @objc private func tapCancel() {
        hint.text = ""
        AccountDelete.cancel { [weak self] r in
            DispatchQueue.main.async {
                self?.cancelBtn?.isHidden = true
                self?.show(r, ok: L.del_acct_cancelled)
            }
        }
    }

    /// 🚨 **每一种结果都说人话**，不许静默。
    ///    尤其 `enabled:false` —— 它是 HTTP 200，只看状态码会读成"成功"，
    ///    而他会以为账号删了。
    private func show(_ r: Result<[String: Any], AccountDelete.Failure>,
                      ok: String) {
        switch r {
        case .success:
            hint.text = ok
        case .failure(let f):
            switch f {
            case .notEnabled(let why):
                hint.text = L.del_acct_off
                KbBridge.note("删账号：服务端说没开启｜" + why)
            case .http(let code, let why):
                hint.text = L.del_acct_failed
                KbBridge.note("删账号失败：HTTP \(code)｜" + why)
            case .badRequest:
                hint.text = L.del_acct_failed
                KbBridge.note("删账号：请求拼不出来")
            }
        }
    }

    // MARK: - 小工具（样式沿用账户页，没有新设计）

    private func field(_ f: UITextField, _ title: String,
                       id: String, value: String) -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        box.layer.cornerRadius = 14
        box.translatesAutoresizingMaskIntoConstraints = false
        let l = UILabel()
        l.text = title
        l.font = .systemFont(ofSize: 12)
        l.textColor = Skin.dim
        l.translatesAutoresizingMaskIntoConstraints = false
        f.text = value
        f.font = .systemFont(ofSize: 16)
        f.textColor = Skin.text
        f.accessibilityIdentifier = id
        f.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(l); box.addSubview(f)
        NSLayoutConstraint.activate([
            box.heightAnchor.constraint(equalToConstant: 64),
            l.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            l.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            f.topAnchor.constraint(equalTo: l.bottomAnchor, constant: 2),
            f.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            f.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
        ])
        return box
    }

    private func button(_ t: String, id: String, danger: Bool,
                        _ sel: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(t, for: .normal)
        b.setTitleColor(danger ? Theme.danger : .white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16)
        b.backgroundColor = danger
            ? UIColor.white.withAlphaComponent(0.06) : Skin.accent
        b.layer.cornerRadius = 14
        b.accessibilityIdentifier = id
        b.addTarget(self, action: sel, for: .touchUpInside)
        b.heightAnchor.constraint(equalToConstant: 52).isActive = true
        return b
    }
}
