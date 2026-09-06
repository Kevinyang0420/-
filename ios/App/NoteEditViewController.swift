import UIKit

/// 写「我的笔记」的那一屏 —— 2.1 方案里的 `note` 字段的**入口**。
///
/// 存储层昨晚就做好了（`WordCard.withNote` / `noteOf`，重取时笔记原样搬回），
/// **但他没有任何地方能写** —— 字段能存能读能保住，而他手机上什么都没多。
/// 这一屏补的就是那个入口。
///
/// 🚨 为什么单开一屏而不是在详情页内联一个输入框：
///    详情页是 `UIScrollView + UIStackView`，内联要自己处理键盘遮挡、
///    滚动偏移、失焦保存 —— 三样都容易出「他打了字、退出去没了」。
///    单开一屏只有两个出口（保存 / 取消），**保存路径只有一条**。
final class NoteEditViewController: UIViewController {

    /// 保存时回调。**只回文本**，怎么写进卡片由调用方决定 ——
    /// 这一屏不认识 `WordBook`，也就不可能在这里把别的字段写坏。
    var onSave: ((String) -> Void)?

    private let word: String
    private let original: String
    private let editor = UITextView()

    init(word: String, note: String) {
        self.word = word
        self.original = note
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 不用") }

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.wb_note_title
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: L.wb_note_cancel, style: .plain,
            target: self, action: #selector(tapCancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L.wb_note_save, style: .done,
            target: self, action: #selector(tapSave))

        let head = UILabel()
        head.text = word
        head.font = .systemFont(ofSize: 17, weight: .semibold)
        head.textColor = Skin.accentHi
        head.numberOfLines = 0
        head.translatesAutoresizingMaskIntoConstraints = false

        editor.text = original
        editor.font = .systemFont(ofSize: 16)
        editor.textColor = Skin.text
        editor.backgroundColor = .clear
        editor.accessibilityIdentifier = "wb.note.editor"
        editor.translatesAutoresizingMaskIntoConstraints = false
        // 🚨 系统深色/浅色都要能看清边框，别只在一种模式下试。
        editor.layer.borderWidth = 1
        editor.layer.borderColor = Skin.dim.withAlphaComponent(0.4).cgColor
        editor.layer.cornerRadius = 8

        let hint = UILabel()
        hint.text = L.wb_note_hint
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = Skin.dim
        hint.numberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(head)
        view.addSubview(editor)
        view.addSubview(hint)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            head.topAnchor.constraint(equalTo: g.topAnchor, constant: 16),
            head.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 20),
            head.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -20),
            editor.topAnchor.constraint(equalTo: head.bottomAnchor, constant: 12),
            editor.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 20),
            editor.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -20),
            // 🚨 高度写固定值，不铺满到底 —— 铺满时键盘一弹，
            //    输入框下半截被压在键盘后面，他看不见自己打的字。
            editor.heightAnchor.constraint(equalToConstant: 160),
            hint.topAnchor.constraint(equalTo: editor.bottomAnchor, constant: 10),
            hint.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -20),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 进来就能打字，不用他再点一下输入框。
        editor.becomeFirstResponder()
    }

    @objc private func tapCancel() {
        // 🚨 **改过了才拦一下**。没改过直接关掉 ——
        //    每次退出都弹一个「要不要放弃」是骚扰。
        let now = editor.text ?? ""
        guard now != original else { dismiss(animated: true); return }
        let a = UIAlertController(title: nil, message: L.wb_note_discard_ask,
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: L.wb_note_keep_editing, style: .cancel))
        a.addAction(UIAlertAction(title: L.wb_note_discard, style: .destructive) {
            [weak self] _ in self?.dismiss(animated: true)
        })
        present(a, animated: true)
    }

    @objc private func tapSave() {
        // 🚨 去首尾空白，但**中间的换行留着** —— 他可能分行记几条。
        let t = (editor.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        onSave?(t)
        dismiss(animated: true)
    }
}
