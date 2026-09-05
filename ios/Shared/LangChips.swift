import UIKit

/// **「最近用过」的横滑 chips** —— 方案丙（Kevin 2026-09-05 13:0x 拍板）。
///
/// 🚨🚨 **这不是"把列表换个样子"，是让两段一眼看上去不是同一种东西。**
///
///    他早上报的是「这里为什么有两个中文」。根因**不是重复本身**，
///    是**两段长得一模一样**：「最近用过」本该是**快捷区**，
///    却被做成了跟「全部语言」同构的列表行 —— 视觉上没有区别，
///    所以重复就被读成 bug。
///
///    做成不同类之后，重复不再读作错 —— 就像浏览器的「常用站点」和「书签列表」，
///    同一个站出现两次，没人觉得是错。
///
/// 🚨 **判据是「两段一眼看上去不是同一种东西」，不是「我把它改成了 chips」。**
///    改完退一步看那一屏：如果还是像两截同样的列表，就没达到目的。
///
/// 🚨 样式**照抄查词页那份 `chip(outlined:)`**（更扁、描边、不填充），
///    不另画一套 —— 三屏各画一份的话，"不同类"这件事会在某一屏走散，
///    而那正是今天这个 bug 的成因。
enum LangChips {

    /// 一枚 chip 的样子：**描边不填充、比列表行扁**。
    static func chip(_ title: String, selected: Bool) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13)
        b.setTitleColor(selected ? Theme.accent : Theme.dim, for: .normal)
        b.contentEdgeInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        b.layer.cornerRadius = 11
        b.layer.borderWidth = 0.8
        b.layer.borderColor = (selected ? Theme.accent : UIColor.white
                                .withAlphaComponent(0.22)).cgColor
        b.backgroundColor = .clear          // 🚨 不填充 —— 跟列表行的关键区别
        b.accessibilityIdentifier = "lang.chip"
        return b
    }

    /// 造一条**横向可滑**的 chips 行。
    ///
    /// - Parameter onPick: 点了哪个语言码
    /// - Returns: 直接可以塞进竖向 stack 的一整行；`recent` 为空时返回 nil
    ///   （🚨 **空的时候整行不出现**，不要留一条空白 —— 空标题/空行是他点过名的）
    static func row(codes: [String], current: String,
                    onPick: @escaping (String) -> Void) -> UIView? {
        guard !codes.isEmpty else { return nil }

        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        for code in codes {
            let b = chip(Backend.langLabel(code), selected: code == current)
            let t = ChipTap(target: ChipTap.box, action: #selector(ChipTap.noop))
            t.code = code
            t.onPick = onPick
            b.addGestureRecognizer(t)
            row.addArrangedSubview(b)
        }

        let sc = UIScrollView()
        sc.showsHorizontalScrollIndicator = false
        sc.translatesAutoresizingMaskIntoConstraints = false
        sc.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: sc.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: sc.contentLayoutGuide.bottomAnchor),
            row.leadingAnchor.constraint(equalTo: sc.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: sc.contentLayoutGuide.trailingAnchor),
            // 🚨 **高度链**：横滑的 `UIScrollView` 自身没有固有高度
            //    （`contentLayoutGuide` 只定内容尺寸）。不接这条，
            //    这一行会塌成 0 —— 面对面那个语言面板今天上午就是这么变成
            //    「一条扁的、看不到语言」的。**同一个坑，第二次。**
            sc.heightAnchor.constraint(equalTo: row.heightAnchor),
        ])
        return sc
    }
}

/// chip 的点击手势 —— 带上是哪个语言码。
///
/// 🚨 用手势而不是 `addTarget`：这些 chip 会被放进别人的滚动视图里，
///    统一用手势的话，三屏的接法一样，不会一屏用 target、一屏用手势。
final class ChipTap: UITapGestureRecognizer {
    /// 手势必须有个 target 才能建；真正的动作走 `onPick`。
    static let box = ChipTap(target: nil, action: nil)
    @objc func noop() {}

    var code: String = ""
    var onPick: ((String) -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        addTarget(self, action: #selector(fire))
    }

    @objc private func fire() {
        guard state == .ended else { return }
        onPick?(code)
    }
}
