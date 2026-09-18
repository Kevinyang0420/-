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
        // 🚨🚨 09-17 Kevin 沙盒实测：买完成功了，停在这一页还是「未订阅」，
        //    退出去再回来才刷新。根因是 `refreshSoonAfterPurchase()` 的轮询
        //    查到会员后只写了本地缓存，没通知正停在这一页的人。
        //    判据是「不离开这一页，几秒内自己变」，不是「重进能看到」——
        //    那条本来就有。订阅 `ProStatus.didChange`，收到就照当前状态重画。
        NotificationCenter.default.addObserver(
            self, selector: #selector(proStatusDidChange),
            name: ProStatus.didChange, object: nil)

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

    deinit {
        NotificationCenter.default.removeObserver(self, name: ProStatus.didChange, object: nil)
    }

    /// 🚨 只用通知带来的 `result` 重画，**绝不在这里再调 `ProStatus.refresh()`**——
    ///    那样会跟 refresh() 自己发的 `didChange` 通知连成死循环。
    @objc private func proStatusDidChange(_ n: Notification) {
        guard let result = n.userInfo?["result"] as? ProCheckResult else { return }
        proState = result
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
        // 🚨🚨 09-17 契约 B3/B4：资料这几行照服务端那份显示——
        //    查不到就**原样保留本地缓存**，不把「查不到」画成「是空的」，
        //    也不弹完善引导（那条判断只在登录那一刻做一次，见
        //    `LoginViewController`，这里只是把最新值同步过来重画）。
        Auth.fetchProfile { [weak self] _ in
            // 结果不管 ok 还是 unreachable 都不用另外处理：
            // ok 时 `applyServerProfile` 已经把本地写好了，重画一次就是；
            // unreachable 时本地没被动过，重画出来的还是原来那份，正是 B4 要的。
            self?.refresh()
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

        // 🚨🚨 09-18 `_规格_用户资料结构化下拉_20260918.md` §七：邮箱不再跟
        //    昵称/生日/国家这些**可编辑**字段摆在同一串列表里——那样摆哪怕视觉
        //    再淡，用户扫一眼还是会以为这里都是能改的东西。矛盾的根不在颜色，
        //    在分组站错了地方。邮箱本质是账户身份的一部分（"一个会员绑定一个
        //    邮箱"），跟到期日一样属于"关于你账户状态的信息"，挪进 `memberRow()`
        //    那张卡片里显示，"点这里填写"占位符**直接不再存在**（这条不用再问）。
        // 🚨 09-18 §三：`other_text` 是 job 选"其他"时的配套字段，不该自己
        //    单独出现在这串列表里（现在 job 还是自由文本，还没到"其他"这个
        //    概念落地的时候）——`account` 排除的理由同源，见上面那条注释。
        for kv in Auth.profileKeys where kv.id != "account" && kv.id != "other_text" {
            stack.addArrangedSubview(row(label(for: kv.id),
                                         Auth.profile(kv.id), kv.id))
        }

        // 🚨🚨 **删除账号入口**（0 台账 #72，**卡 iOS 提交**）。
        //    App Store 明确要求 App 内可达 —— 网页那条（已上线）不算。
        //    点这个按钮进下面的 `openDelete()` → `DeleteAccountViewController`，
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
        // 🚨 09-18 Kevin 真机反馈：删除账号和退出登录中间隔太宽（原是
        //    `setCustomSpacing(40, ...)`，从这页 08-26 诞生起就没有任何
        //    注释解释这个 40——查了创建这页的那个 commit，只解释了顺序
        //    （删除在上/退出在下）和"要确认"，没提过这个数字。别再拉开：
        //    删除账号已经走多步确认流程防误触，间距不用再担一次这个责任。
        //    落回页面统一的 `stack.spacing = 10`，不新造一个数字。
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
        case .notSubscribed:
            // 🚨🚨 09-17 `_规格_价格呈现口径_20260917.md`：升级入口要**立刻**
            //    带上价格，不能等用户点进付费页才发起 StoreKit 请求——
            //    读 `IAP.cachedDisplayPrice`（`AppDelegate` 启动时已预热），
            //    不在这里发网络请求。没缓存（比如全新安装、还没拉到过一次）
            //    就退化成原来那句纯状态词，不显示空价格。
            //
            // 🚨 同一份规格：还有免费试用没用的账号/设备要显示试用文案而不是
            //    纯价格——判据是 `ProStatus.trialDaysLeftCached`（服务端
            //    `trial_days_left`），走 `ProCheck.showsTrial` 统一判断，
            //    跟 `SubscribeViewController` 那边共用同一条判据，不各自算一遍。
            if let price = IAP.cachedDisplayPrice {
                if ProCheck.showsTrial(ProStatus.trialDaysLeftCached) {
                    s.text = String(format: L.prefs_pro_trial_price, price)
                } else {
                    s.text = String(format: L.prefs_pro_upgrade_price, price)
                }
            } else {
                s.text = L.prefs_pro_inactive
            }
        case .unreachable: s.text = L.prefs_pro_unknown
        }
        s.textColor = Skin.sub
        s.font = .systemFont(ofSize: 11.5)
        var rows: [UIView] = [t, s]
        // 🚨 09-18 §七：邮箱只在有值时加这一行——只读展示，不可编辑、没有
        //    占位符。整张卡片本来就是一个跳去会员页的点击目标，邮箱混在
        //    里面被带着点过去无所谓（它压根不是能操作的东西）。
        let email = Auth.profile("account")
        if !email.isEmpty {
            let e = UILabel()
            e.text = email
            e.textColor = Skin.dim
            e.font = .systemFont(ofSize: 11.5)
            rows.append(e)
        }
        let col = UIStackView(arrangedSubviews: rows)
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
        // 🚨 09-18 §七：邮箱已经从这个函数的调用方里过滤掉了（挪进
        //    `memberRow()`），这里从此只画**可编辑**字段，不用再按 id
        //    分只读/可编辑两套视觉——那套分支是 09-17 邮箱还混在这个列表里
        //    时留下的，邮箱搬走之后它已经没有调用者能传 "account" 进来了。
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
        v.textColor = empty ? Skin.dim : Skin.text
        v.font = .systemFont(ofSize: 16)

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
        // 🚨 生日跳到注册那一页的三个下拉，**不在这里再写一套日期选择**。
        if id == "birthday" {
            let vc = ProfileViewController()
            // 🚨🚨 09-17 0派活②：从这里（账户页）进去必须能退出来——
            //    `ProfileViewController`默认不给返回键是给**注册流程**用的，
            //    这条路不是注册流程，Kevin真机撞到"进去出不来"。
            vc.allowBack = true
            navigationController?.pushViewController(vc, animated: true)
            return
        }
        let a = UIAlertController(title: label(for: id), message: nil,
                                  preferredStyle: .alert)
        a.addTextField { $0.text = Auth.profile(id) }
        // 🚨🚨 09-17 契约 B2：真发到服务端，**用响应回写本地**——原来这里
        //    直接 `Auth.setProfile` 写本地就算数，下次登录/换设备一问
        //    服务端全丢，这正是资料"跟不着账号走"的另一个出口。
        a.addAction(UIAlertAction(title: L.save, style: .default) { [weak self] _ in
            let v = a.textFields?.first?.text ?? ""
            // 🚨 `_规格_昵称显示口径_20260917.md`§2.1 判据②：从账户页主动
            //    保存过一次昵称，**无条件**标 true——不跟旧值比较，专门跑
            //    来这一页改资料这个动作本身已经说明了动机。只在改的是
            //    "nick"这个字段时传这个标记，别的字段（生日/国家/职业）不相关。
            let flag: Bool? = (id == "nick") ? true : nil
            Auth.saveProfile([id: v], nicknameIsCustom: flag) { ok in
                guard let self = self else { return }
                self.refresh()
                if !ok {
                    let f = UIAlertController(title: nil, message: L.profile_save_failed,
                                              preferredStyle: .alert)
                    f.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(f, animated: true)
                }
            }
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
