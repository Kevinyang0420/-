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
    private let targetField = UITextField()
    private let codeField = UITextField()
    private let hint = UILabel()

    /// 账号类型。服务端认 `phone`（探针里 `sms` 是坏样本、会被拒）。
    private let kind = "phone"

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

        // ② 账号（预填他登录用的那个，省得他自己敲）
        stack.addArrangedSubview(field(targetField, L.del_acct_target,
                                       id: "del.target",
                                       value: Auth.profile("account")))
        targetField.keyboardType = .phonePad

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

        // ⑥ 提示行 —— 🚨 **每个结果都要能跟"没反应"分开**
        hint.font = .systemFont(ofSize: 14)
        hint.textColor = Skin.dim
        hint.numberOfLines = 0
        hint.accessibilityIdentifier = "del.hint"
        stack.addArrangedSubview(hint)
    }

    // MARK: - 动作

    @objc private func tapSend() {
        let t = (targetField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { hint.text = L.del_acct_target; return }
        hint.text = ""
        AccountDelete.requestCode(kind: kind, target: t) { [weak self] r in
            DispatchQueue.main.async { self?.show(r.map { _ in [:] },
                                                 ok: L.del_acct_sent) }
        }
    }

    @objc private func tapConfirm() {
        let t = (targetField.text ?? "").trimmingCharacters(in: .whitespaces)
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
            AccountDelete.confirm(kind: self.kind, target: t, code: c) { r in
                DispatchQueue.main.async { self.show(r, ok: L.del_acct_grace) }
            }
        })
        present(a, animated: true)
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
