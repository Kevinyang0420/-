import UIKit

/// 完善资料：**昵称（必填）+ 出生日期（选填）**。
/// 结构跟安卓 `ProfileActivity` 一一对应。
///
/// Kevin 2026-08-26：「账号尽量加个昵称，不要把那么长的邮箱一直放在左上角，
/// 放个昵称就行…比如让用户在注册时输入昵称和出生日期」
/// +「出生日期加个下拉项目嘛，就是哪一年、哪一月、哪一日，加个下拉项目嘛」。
///
/// 🚨 所以生日是**三个下拉**（年 / 月 / 日），不是日期滚轮。
///    第一版做成 `UIDatePicker`，他当场要求换掉 —— 填生日要往回翻
///    三十年，滚轮那种交互是给"选最近某天"设计的，不是给生日的。
///
/// 🚨 为什么不把这两格塞进登录表单：登录只有「邮箱 + 验证码」两格，
///    塞进去等于**每次登录**都要面对四格 —— 而昵称/生日是**一次性**的，
///    老用户回来登录不该再填一遍。所以放在验证通过之后，
///    且**只在昵称还没填过时**出现（判据见 `LoginViewController` 那处调用）。
///
/// 🚨 昵称预填成 `Auth.displayName`（邮箱 @ 前那截），
///    所以「必填」不会变成拦路虎：直接点完成就行，想改再改。
///
/// 🚨 生日**三个都选了才存**，少一个就当没填、一个字都不存。
///    不拿"年份填了就存个 xxxx-01-01"糊弄 —— 那样存的是垃圾数据，
///    以后没法区分"他生日就是元旦"和"他只选了年份"。
final class ProfileViewController: UIViewController {

    private let nickField = UITextField()
    private let yearButton = UIButton(type: .system)
    private let monthButton = UIButton(type: .system)
    private let dayButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)

    /// 0 = 还没选。跟安卓 `pick()` 同口径。
    private var year = 0
    private var month = 0
    private var day = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.profile_title
        // 🚨 不给返回键：这一步是登录之后的收尾，滑回去只会看到已经
        //    `pop` 掉的登录页。填完点「完成」是唯一出口（昵称已预填，
        //    所以这不是死路）。
        navigationItem.hidesBackButton = true

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                           constant: 21),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                            constant: -21),
            stack.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
        ])

        let sub = UILabel()
        sub.text = L.profile_sub
        sub.font = .systemFont(ofSize: 13)
        sub.textColor = Skin.dim
        sub.numberOfLines = 0
        stack.addArrangedSubview(sub)
        stack.setCustomSpacing(28, after: sub)

        stack.addArrangedSubview(label(L.profile_nick))

        nickField.placeholder = L.profile_nick_ph
        // 🚨 预填成邮箱 @ 前那截 —— 见类注释，这是让"必填"不添堵的关键。
        nickField.text = Auth.displayName
        nickField.returnKeyType = .done
        nickField.addTarget(self, action: #selector(nickChanged),
                            for: .editingChanged)
        nickField.addTarget(self, action: #selector(tapDone),
                            for: .editingDidEndOnExit)
        let nickCard = card(nickField)
        stack.addArrangedSubview(nickCard)
        stack.setCustomSpacing(24, after: nickCard)

        stack.addArrangedSubview(label(L.profile_birth))

        // ---- 三个下拉：年 / 月 / 日 ----
        let row = UIStackView(arrangedSubviews:
            [dropdown(yearButton, L.profile_year),
             dropdown(monthButton, L.profile_month),
             dropdown(dayButton, L.profile_day)])
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillProportionally
        // 年份是四位数，要宽一点 —— 跟安卓那边 1.35 : 1 : 1 同一个比例。
        yearButton.widthAnchor.constraint(
            equalTo: monthButton.widthAnchor, multiplier: 1.35).isActive = true
        dayButton.widthAnchor.constraint(
            equalTo: monthButton.widthAnchor).isActive = true
        row.heightAnchor.constraint(equalToConstant: 58).isActive = true
        stack.addArrangedSubview(row)
        stack.setCustomSpacing(36, after: row)

        rebuildMenus()

        doneButton.setTitle(L.profile_done, for: .normal)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.titleLabel?.font = .systemFont(ofSize: 16)
        doneButton.backgroundColor = Skin.accent
        doneButton.layer.cornerRadius = 14
        doneButton.addTarget(self, action: #selector(tapDone),
                             for: .touchUpInside)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.heightAnchor.constraint(equalToConstant: 52).isActive = true
        stack.addArrangedSubview(doneButton)

        syncDone()
    }

    // MARK: - 三个下拉

    private func dropdown(_ b: UIButton, _ placeholder: String) -> UIButton {
        b.setTitle(placeholder, for: .normal)
        b.setTitleColor(Skin.dim, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16)
        b.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        b.layer.cornerRadius = 14
        // 🚨 `showsMenuAsPrimaryAction` 必须打开，否则要**长按**才出菜单
        //    —— 点一下没反应，用户会以为这个格子是坏的。
        b.showsMenuAsPrimaryAction = true
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    /// 重建三个菜单。年、月一变，日的档数要跟着变（2 月只有 28/29 天）。
    private func rebuildMenus() {
        // 年份区间由 `BirthDays.years()` 定 —— 界面这层**不碰日期逻辑**。
        yearButton.menu = menu(L.profile_year, BirthDays.years(),
                               current: year) { [weak self] v in
            self?.year = v
            self?.clampDay()
            self?.rebuildMenus()
            self?.syncDone()
        }
        monthButton.menu = menu(L.profile_month, Array(1...12), current: month) {
            [weak self] v in
            self?.month = v
            self?.clampDay()
            self?.rebuildMenus()
            self?.syncDone()
        }
        dayButton.menu = menu(L.profile_day, Array(1...daysInMonth()),
                              current: day) { [weak self] v in
            self?.day = v
            self?.syncDone()
        }
        paint(yearButton, year, L.profile_year)
        paint(monthButton, month, L.profile_month)
        paint(dayButton, day, L.profile_day)
    }

    private func menu(_ title: String, _ values: [Int], current: Int,
                      _ pick: @escaping (Int) -> Void) -> UIMenu {
        UIMenu(title: title, children: values.map { v in
            UIAction(title: String(v),
                     state: v == current ? .on : .off) { _ in pick(v) }
        })
    }

    private func paint(_ b: UIButton, _ value: Int, _ placeholder: String) {
        b.setTitle(value == 0 ? placeholder : String(value), for: .normal)
        b.setTitleColor(value == 0 ? Skin.dim : Skin.text, for: .normal)
    }

    /// 这个年月有几天。真规则在 `BirthDays.daysIn`，
    /// 🚨 **这里不许再写一份** —— 留两份哪天口径变了必然漏改一处，
    ///    而漏的那处不报错，只会在 2 月默默多出一天。
    private func daysInMonth() -> Int { BirthDays.daysIn(year, month) }

    /// 原来选的是 31，改成 2 月之后就不存在了 —— 那就退回"没选"，
    /// 而不是悄悄改成 28。悄悄改会让他存下一个自己没选过的日子。
    private func clampDay() {
        if day > daysInMonth() { day = 0 }
    }

    /// 三个都选了才算填了。少一个就当没填 —— 判据在 `BirthDays.format`。
    private var birthday: String { BirthDays.format(year, month, day) }

    // MARK: - 其余

    private func label(_ s: String) -> UILabel {
        let l = UILabel()
        l.text = s
        l.font = .systemFont(ofSize: 13)
        l.textColor = Skin.dim
        return l
    }

    /// 跟登录页的 `plainCard` 同一套（玻璃底 + 14 圆角 + 18 内边距）。
    /// 🚨 不自己调配色 —— Kevin：「你不要自己设计了，我觉得你的审美很有问题」。
    private func card(_ f: UITextField) -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        box.layer.cornerRadius = 14
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
            f.trailingAnchor.constraint(equalTo: box.trailingAnchor,
                                        constant: -18),
            f.topAnchor.constraint(equalTo: box.topAnchor, constant: 20),
            f.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -20),
        ])
        return box
    }

    /// 昵称空了就把「完成」灰掉 —— 比点下去再弹一句"不能为空"好：
    /// 用户看得见为什么走不了，不用先撞一次墙。
    @objc private func nickChanged() { syncDone() }

    private func syncDone() {
        let ok = !(nickField.text ?? "")
            .trimmingCharacters(in: .whitespaces).isEmpty
        doneButton.isEnabled = ok
        doneButton.alpha = ok ? 1 : 0.4
    }

    @objc private func tapDone() {
        let nick = (nickField.text ?? "")
            .trimmingCharacters(in: .whitespaces)
        guard !nick.isEmpty else { return }   // 按钮已经灰了，这是兜底
        Auth.setNickname(nick)
        let b = birthday
        if !b.isEmpty { Auth.setBirthday(b) }
        navigationController?.popToRootViewController(animated: true)
    }
}
