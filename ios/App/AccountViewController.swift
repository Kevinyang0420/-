import UIKit

/// 账户页（个人中心）。结构跟安卓 `AccountActivity` 一一对应。
///
/// Kevin 2026-08-26 真机反馈两条，这一页同时解决：
///
/// 🚨🚨 **第 4 条（真 bug，两端都有，是我写的）**：
///    「我在设置里点了一下『我的账户』，它居然直接把我退出了。
///      登出应该有专门的『退出登录』按钮，而不是点一下账户就退出，
///      重新发验证码登录非常繁琐。」
///    —— 原来设置页那一行点了直接 `signOut()`，**一点就登出、连确认都没有**。
///    现在点账户进这一页，退出登录是页面**底部一个单独的按钮**，**且要确认**。
///
/// 🚨 **第 3 条**：「用户信息页需要完善，可以多加一些选填项
///    （如邮箱、生日、国家、省份、职业等）」。
///    字段表在 `Auth.profileKeys`，**这一页照表画**，加字段只改那张表。
///
/// 🚨 每一项**点了就地编辑**（弹一个输入框），不做"编辑模式"开关 ——
///    多一个模式就多一处状态，而用户只想改一个字段。
///    生日那项跳到 `ProfileViewController` 的三个下拉，
///    **不在这里再写一套日期选择**（写第二套哪天口径变了必然漏改一处）。
final class AccountViewController: UIViewController {

    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.account_page

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                           constant: 21),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                            constant: -21),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor,
                                          constant: -28),
        ])
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 从生日那一页回来要刷新。
        refresh()
    }

    /// 照 `Auth.profileKeys` 画。加字段只改那张表。
    private func refresh() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for kv in Auth.profileKeys {
            stack.addArrangedSubview(row(label(for: kv.id),
                                         Auth.profile(kv.id), kv.id))
        }

        // 🚨 退出登录**在最底下、单独一个按钮、点了要确认**。
        //    Kevin 撞到的就是"点账户直接登出"。
        let out = UIButton(type: .system)
        out.setTitle(L.account_signout, for: .normal)
        // 🚨 危险色用 Theme.danger（紫调的红，不跳色）。
        //    Skin 是从安卓 Skin.java **生成**的，那边没有危险色，
        //    所以 Skin.swift 里也不会有 —— 写之前先去文件里确认它在。
        out.setTitleColor(Theme.danger, for: .normal)
        out.titleLabel?.font = .systemFont(ofSize: 16)
        out.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        out.layer.cornerRadius = 14
        out.addTarget(self, action: #selector(askSignOut), for: .touchUpInside)
        out.translatesAutoresizingMaskIntoConstraints = false
        out.heightAnchor.constraint(equalToConstant: 52).isActive = true
        stack.addArrangedSubview(out)
        stack.setCustomSpacing(40, after: stack.arrangedSubviews[
            max(0, stack.arrangedSubviews.count - 2)])
    }

    private func label(for id: String) -> String {
        switch id {
        case "nick": return L.profile_nick
        case "account": return L.profile_email
        case "birthday": return L.profile_birth
        case "country": return L.profile_country
        case "region": return L.profile_region
        case "job": return L.profile_job
        default: return id
        }
    }

    private func row(_ title: String, _ value: String, _ id: String) -> UIView {
        let box = UIControl()
        box.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        box.layer.cornerRadius = 14
        box.accessibilityIdentifier = "profile_" + id

        let l = UILabel()
        l.text = title
        l.font = .systemFont(ofSize: 12)
        l.textColor = Skin.dim

        let v = UILabel()
        let empty = value.isEmpty
        // 🚨 空的时候写「点这里填写」而不是留空 —— 留空看不出是"能填"还是"坏了"。
        v.text = empty ? L.account_edit : value
        v.font = .systemFont(ofSize: 16)
        v.textColor = empty ? Skin.dim : Skin.text

        let col = UIStackView(arrangedSubviews: [l, v])
        col.axis = .vertical
        col.spacing = 3
        col.isUserInteractionEnabled = false
        col.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(col)
        NSLayoutConstraint.activate([
            col.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 18),
            col.trailingAnchor.constraint(equalTo: box.trailingAnchor,
                                          constant: -18),
            col.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            col.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -14),
        ])
        editing[box] = id
        box.addTarget(self, action: #selector(tapRow(_:)), for: .touchUpInside)
        return box
    }

    /// 哪个格子对应哪个字段。
    /// 🚨 用 map 而不是 `tag`：`tag` 是 Int，得再维护一张 id ↔ 数字的对照表，
    ///    那就是第二个配置点。
    private var editing: [UIControl: String] = [:]

    @objc private func tapRow(_ sender: UIControl) {
        guard let id = editing[sender] else { return }
        // 🚨 邮箱不给改：它是**登录凭据**，不是资料。改了就跟登录态对不上了。
        if id == "account" {
            let a = UIAlertController(title: L.account_title,
                                      message: Auth.account,
                                      preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default))
            present(a, animated: true)
            return
        }
        // 🚨 生日跳到注册那一页的三个下拉，**不在这里再写一套日期选择**。
        if id == "birthday" {
            navigationController?.pushViewController(
                ProfileViewController(), animated: true)
            return
        }
        let a = UIAlertController(title: label(for: id), message: nil,
                                  preferredStyle: .alert)
        a.addTextField { $0.text = Auth.profile(id) }
        a.addAction(UIAlertAction(title: L.save, style: .default) { [weak self] _ in
            Auth.setProfile(id, a.textFields?.first?.text ?? "")
            self?.refresh()
        })
        a.addAction(UIAlertAction(title: L.cancel, style: .cancel))
        present(a, animated: true)
    }

    @objc private func askSignOut() {
        let a = UIAlertController(title: nil, message: L.account_signout_ask,
                                  preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: L.account_signout,
                                  style: .destructive) { [weak self] _ in
            Auth.signOut()
            self?.navigationController?.popToRootViewController(animated: true)
        })
        a.addAction(UIAlertAction(title: L.cancel, style: .cancel))
        a.popoverPresentationController?.sourceView = view
        present(a, animated: true)
    }
}
