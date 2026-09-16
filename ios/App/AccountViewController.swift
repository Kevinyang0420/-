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
final class AccountViewController: PushedViewController {

    private let stack = UIStackView()

    /// 🚨🚨 09-14 晚 Kevin 真机撞到的 bug 就出在这一行的旧写法上：
    ///    `memberRow()` 原来只读 `ProStatus.isProCached`（纯本地缓存，
    ///    这台设备可能从没成功同步过），从不问服务端，
    ///    也没法区分"没登录"和"登录了没订阅"——他的账号后端明明是十年 Pro，
    ///    界面却显示「未订阅」。现在页面一出现就问一次服务端，
    ///    拿到权威的三态结果存在这里，`memberRow()` 照它画。
    ///    初始值给个基于本地缓存的乐观猜测，活的结果回来后立刻纠正。
    private var proState: ProCheckResult = ProCheck.classify(
        isPro: ProStatus.isProCached, until: ProStatus.cachedUntilValue, hasReason: false)

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
        // 🚨🚨 每次进这一页都问一次服务端，不是只信本机缓存——本地缓存可能
        //    从没同步成功过（Kevin 那次就是），只有活的响应能分清
        //    "没登录"和"登录了没订阅"。资料字段的编辑走的是弹窗（`UIAlertController`），
        //    不是页面里的输入框，整页重建不会打断正在填的东西。
        ProStatus.refresh { [weak self] result in
            guard let self = self else { return }
            self.proState = result
            self.refresh()
        }
    }

    /// 照 `Auth.profileKeys` 画。加字段只改那张表。
    private func refresh() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        // 🚨🚨 09-13：会员行从设置页搬过来了（Kevin 原话：「你把那个会员那里，
        //    不要放到设置那个地方…你把它丢到账户里面嘛，单独搞个会员很奇怪呀」）。
        //    只搬位置，不重新设计版式——沿用 `PrefsViewController.row()` 那套
        //    标题+副标题+箭头的视觉语言，这里 `AccountViewController` 自己没有
        //    这个变体，所以就地起一份，别跨类复用私有方法。
        //    能进这一页就说明已登录（`openAccount()` 分流过了），
        //    `loginGate` 那道门不需要了。
        let proRow = memberRow()
        proRow.accessibilityIdentifier = "account.row.pro"
        stack.addArrangedSubview(proRow)

        for kv in Auth.profileKeys {
            stack.addArrangedSubview(row(label(for: kv.id),
                                         Auth.profile(kv.id), kv.id))
        }

        // 🚨🚨 **删除账号入口**（0 台账 #72，**卡 iOS 提交**）。
        //    App Store 明确要求 App 内可达 —— 网页那条（已上线）不算。
        //    点这个按钮进 `:144` 的 `openDelete()` → `DeleteAccountViewController`，
        //    三端均已接。文案对应 `hs_ask_3`（同步确认弹窗上的删号承诺）。
        //
        //    🚨 放在退出登录**上面**：删除比退出更重，但退出是更常用的那个，
        //    所以退出留在最底下（拇指最容易够到），删除在它上面。
        let del = UIButton(type: .system)
        del.setTitle(L.del_acct_entry, for: .normal)
        del.setTitleColor(Theme.danger, for: .normal)
        del.titleLabel?.font = .systemFont(ofSize: 16)
        del.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        del.layer.cornerRadius = 14
        del.accessibilityIdentifier = "account.delete"
        del.addTarget(self, action: #selector(openDelete), for: .touchUpInside)
        del.translatesAutoresizingMaskIntoConstraints = false
        del.heightAnchor.constraint(equalToConstant: 52).isActive = true
        stack.addArrangedSubview(del)

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

    @objc private func openDelete() {
        navigationController?.pushViewController(
            DeleteAccountViewController(), animated: true)
    }

    /// 会员行——照抄 `PrefsViewController.row()` 那套标题+副标题+箭头视觉，
    /// 那个方法是私有的、在另一个类里，拿不到，所以这里单起一份，
    /// 不引入新的共享抽象（就一处用，抽公共方法是过度设计）。
    ///
    /// 🚨🚨 副标题和点击目标现在跟着 `proState` 走（三态而不是两态），
    ///    不再是"读一次本地缓存、永远指去付款页"——
    ///    `_spec_not_logged_in_vs_not_subscribed.md` 那次真机 bug 的根子就在这里。
    private func memberRow() -> UIView {
        let b = UIControl()
        b.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        b.layer.cornerRadius = 14
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true

        let t = UILabel()
        t.text = L.prefs_pro_title
        t.textColor = Skin.text
        t.font = .systemFont(ofSize: 15.5)
        let s = UILabel()
        switch proState {
        case .pro: s.text = L.prefs_pro_active
        case .notLoggedIn: s.text = L.prefs_pro_logged_out
        case .notSubscribed: s.text = L.prefs_pro_inactive
        case .unreachable: s.text = L.prefs_pro_unknown
        }
        s.textColor = Skin.sub
        s.font = .systemFont(ofSize: 11.5)
        let col = UIStackView(arrangedSubviews: [t, s])
        col.axis = .vertical
        col.spacing = 3
        col.isUserInteractionEnabled = false
        col.translatesAutoresizingMaskIntoConstraints = false
        b.addSubview(col)
        NSLayoutConstraint.activate([
            col.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: 16),
            col.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -34),
            col.topAnchor.constraint(equalTo: b.topAnchor, constant: 15),
            col.bottomAnchor.constraint(equalTo: b.bottomAnchor, constant: -15),
        ])
        b.addTarget(self, action: #selector(tapMemberRow), for: .touchUpInside)
        let chev = UILabel()
        chev.text = UIView.userInterfaceLayoutDirection(for: .unspecified)
            == .rightToLeft ? "‹" : "›"
        chev.textColor = Skin.dim
        chev.font = .systemFont(ofSize: 20)
        chev.translatesAutoresizingMaskIntoConstraints = false
        b.addSubview(chev)
        NSLayoutConstraint.activate([
            chev.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -16),
            chev.centerYAnchor.constraint(equalTo: b.centerYAnchor),
        ])
        return b
    }

    /// 🚨🚨 09-14 晚发现：上面那条"能看到这一页就说明已登录，不需要再判断"
    ///    的假设**不成立**——`openAccount()` 的分流只看本地的 `Auth.loggedIn`
    ///    标志，这台设备**本地标志可能是真的、后端会话却早失效了**
    ///    （Kevin 真机就是这个状态：本地一直觉得自己登录着，后端 `/api/pro`
    ///    回的其实是 `reason:"未登录"`）。所以这一行**不能无条件去付款页**——
    ///    他很可能已经付过钱了，指去付款页 = 让他重复付费。
    @objc private func tapMemberRow() {
        switch proState {
        case .notLoggedIn:
            navigationController?.pushViewController(LoginViewController(), animated: true)
        case .unreachable:
            // 🚨 查不到不代表任何真实状态，点一下就是再问一次，不许乱跳页面。
            ProStatus.refresh { [weak self] result in
                guard let self = self else { return }
                self.proState = result
                self.refresh()
            }
        case .pro:
            // 🚨🚨 09-16 症状C修复：已是会员不许再被带去付费墙（见闸门
            //    verify_pro_no_paywall.py 和 MembershipViewController 头注释）。
            navigationController?.pushViewController(MembershipViewController(),
                                                     animated: true)
        case .notSubscribed:
            navigationController?.pushViewController(SubscribeViewController(),
                                                     animated: true)
        }
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
        fieldOf[box] = id
        box.addTarget(self, action: #selector(tapRow(_:)), for: .touchUpInside)
        return box
    }

    /// 哪个格子对应哪个字段。
    /// 🚨 用 map 而不是 `tag`：`tag` 是 Int，得再维护一张 id ↔ 数字的对照表，
    ///    那就是第二个配置点。
    /// 🚨🚨 **不能叫 `editing`** —— `UIViewController` 自己就有一个
    ///    `isEditing`/`editing` 属性（Bool），重名会被当成"覆盖父类属性"，
    ///    编译报 `property 'editing' with type '[UIControl : String]'
    ///    cannot override a property with type 'Bool'`。
    ///    跟 `acct` 撞 POSIX 函数名是同一族：**起名前先想想这个作用域里
    ///    有没有同名的东西**，尤其是继承来的。
    private var fieldOf: [UIControl: String] = [:]

    @objc private func tapRow(_ sender: UIControl) {
        guard let id = fieldOf[sender] else { return }
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
