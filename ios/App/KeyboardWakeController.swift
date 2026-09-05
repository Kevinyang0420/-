import UIKit

/// **只做一件事：把输入框顶起来，让系统加载当前键盘。**
///
/// 🚨 为什么需要它（2026-09-04）：验 H1「键盘写的历史主 App 看得见」时，
///    要害是**键盘扩展那个进程**解析到哪个容器。而我驱动不了它：
///      · UITest 被设备的 `Enable UI Automation` 挡住
///        （实测 `Timed out while enabling automation mode`）
///      · 扩展没法 `devicectl process launch` 直接起
///    但系统在**任何输入框获得焦点**时都会加载当前键盘 —— 包括这个 App 自己的。
///    而 `History` 的落点日志写在键盘的 `viewDidLoad`，
///    **不用说话、不用按麦克风**，键盘一露面就有了。
///
/// 🚨 这个页面**没有正式入口**，只有 `TRANSLESS_PAGE=kbwake` 能进。
/// 🚨 它**不做判断**：判断在外面读日志的脚本里。
///    这里只负责制造现场 —— 所以不该有断言（跟 `HoldKeyboardUp` 同一个道理）。
final class KeyboardWakeController: UIViewController {

    private let field = UITextField()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "唤起键盘（调试）"
        UI.paintBg(self)

        field.accessibilityIdentifier = "kbwake.field"
        field.borderStyle = .roundedRect
        field.backgroundColor = Skin.glassFill
        field.textColor = Skin.text
        field.attributedPlaceholder = NSAttributedString(
            string: "这里只为把键盘顶出来",
            attributes: [.foregroundColor: Skin.dim])
        field.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(field)

        let hint = UILabel()
        hint.text = "调试页：焦点一进输入框，系统就会加载当前键盘。"
            + "如果当前键盘不是 Transless，日志里不会出现键盘那条 —— "
            + "那是「这次没叫起来」，不是「键盘写错地方」。"
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = Skin.dim
        hint.numberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: g.topAnchor, constant: 40),
            field.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 21),
            field.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -21),
            field.heightAnchor.constraint(equalToConstant: 44),
            hint.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 16),
            hint.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 21),
            hint.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -21),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 🚨 **延后一拍**：`becomeFirstResponder` 在 `viewDidAppear` 里同步调
        //    会被系统忽略（而且不报错）—— 这个坑在 `applyDebugEnv` 里已经踩过一次。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.field.becomeFirstResponder()
            KbBridge.note("唤起键盘调试页：输入框已请求焦点")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }
}
