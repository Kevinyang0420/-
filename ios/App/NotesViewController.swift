import UIKit

/// **记事本列表页** —— 记事本第一步的第 2/3/4 件
/// （规格 `_规格_记事本_20260907.md`，Kevin 09-07 批「三步同步走」）。
///
/// 他原话：「我有一个说话记录，里面有我过往说过的所有东西」
/// 「说话记录这里有一个单词本，**再加个记事本吧**」。
///
/// 这一屏做三件：
/// 1. 列出留下来的（按最后改动倒序）
/// 2. **搜索 —— 要能搜到原话**（规格判据：只搜标题 = FAIL）
/// 3. 点进去改标题 / 改正文 / 加标签 / 删掉
///
/// 🚨 视觉沿用单词本那一屏（同样的圆角、间距、危险色），**没有新设计**。
/// 🚨 明确**不做**：日历视图 / 共享 / 重复提醒 / 富文本 / 文件夹 ——
///    Kevin 已批的收窄版，判据是「这条路的尽头是不是飞书钉钉的地盘」。
final class NotesViewController: UIViewController, UITextFieldDelegate {

    private let scroll = UIScrollView()
    private let body = UIStackView()
    private let searchField = UITextField()
    private var editingId = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.note_book

        let search = UIView()
        search.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        search.layer.cornerRadius = 14
        search.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = L.note_search
        searchField.font = .systemFont(ofSize: 15)
        searchField.textColor = Skin.text
        searchField.accessibilityIdentifier = "note.search"
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(searchChanged),
                              for: .editingChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        search.addSubview(searchField)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        body.axis = .vertical
        body.spacing = 10
        body.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(search)
        view.addSubview(scroll)
        scroll.addSubview(body)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: g.topAnchor, constant: 12),
            search.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 21),
            search.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -21),
            search.heightAnchor.constraint(equalToConstant: 46),
            searchField.leadingAnchor.constraint(equalTo: search.leadingAnchor,
                                                 constant: 14),
            searchField.trailingAnchor.constraint(equalTo: search.trailingAnchor,
                                                  constant: -14),
            searchField.centerYAnchor.constraint(equalTo: search.centerYAnchor),

            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            body.topAnchor.constraint(equalTo: scroll.topAnchor),
            body.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 21),
            body.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -21),
            body.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -28),
        ])
        paint()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        paint()
    }

    @objc private func searchChanged() { paint() }

    func textFieldShouldReturn(_ t: UITextField) -> Bool {
        t.resignFirstResponder(); return true
    }

    // MARK: - 画

    private func paint() {
        body.arrangedSubviews.forEach {
            body.removeArrangedSubview($0); $0.removeFromSuperview()
        }
        // 🚨 搜索走 `Notes.search`（转 `NotesCore.search`）——
        //    **不在这一屏再写一遍过滤**。规格判据「要搜得到原话」
        //    钉在那一层，界面再写一套的话这条判据就守不住这一屏。
        let items = Notes.search(searchField.text ?? "")
        guard !items.isEmpty else {
            let l = UILabel()
            // 🚨 空态要告诉他**怎么才会有东西**，不是干写一句"暂无"。
            l.text = (searchField.text ?? "").isEmpty ? L.note_empty
                                                      : L.wb_card_failed
            l.font = .systemFont(ofSize: 15)
            l.textColor = Skin.dim
            l.numberOfLines = 0
            l.accessibilityIdentifier = "note.empty"
            body.addArrangedSubview(l)
            return
        }
        for it in items { body.addArrangedSubview(card(it)) }
    }

    private func card(_ it: NotesCore.Item) -> UIView {
        let box = UIControl()
        box.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        box.layer.cornerRadius = 14
        box.accessibilityIdentifier = "note.row"
        box.translatesAutoresizingMaskIntoConstraints = false

        let t = UILabel()
        t.text = it.title
        t.font = .systemFont(ofSize: 16, weight: .semibold)
        t.textColor = Skin.text
        t.numberOfLines = 2
        t.translatesAutoresizingMaskIntoConstraints = false

        let b = UILabel()
        // 🚨 正文只露一行 —— 列表是用来找的，不是用来读的。
        b.text = it.body
        b.font = .systemFont(ofSize: 14)
        b.textColor = Skin.dim
        b.numberOfLines = 2
        b.translatesAutoresizingMaskIntoConstraints = false

        let tag = UILabel()
        tag.text = it.tags.joined(separator: "  ·  ")
        tag.font = .systemFont(ofSize: 12)
        tag.textColor = Skin.accentHi
        tag.translatesAutoresizingMaskIntoConstraints = false

        box.addSubview(t); box.addSubview(b); box.addSubview(tag)
        NSLayoutConstraint.activate([
            t.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            t.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            t.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            b.topAnchor.constraint(equalTo: t.bottomAnchor, constant: 4),
            b.leadingAnchor.constraint(equalTo: t.leadingAnchor),
            b.trailingAnchor.constraint(equalTo: t.trailingAnchor),
            tag.topAnchor.constraint(equalTo: b.bottomAnchor, constant: 6),
            tag.leadingAnchor.constraint(equalTo: t.leadingAnchor),
            tag.trailingAnchor.constraint(equalTo: t.trailingAnchor),
            tag.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
        ])
        let tap = TapNote(target: self, action: #selector(tapRow(_:)))
        tap.id = it.id
        box.addGestureRecognizer(tap)
        return box
    }

    // MARK: - 编辑

    @objc private func tapRow(_ g: TapNote) {
        guard let it = Notes.list().first(where: { $0.id == g.id }) else { return }
        editingId = it.id
        let a = UIAlertController(title: it.title, message: it.body,
                                  preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: L.wb_note_edit, style: .default) {
            [weak self] _ in self?.editText(it)
        })
        a.addAction(UIAlertAction(title: L.wb_delete, style: .destructive) {
            [weak self] _ in
            Notes.remove(id: it.id)
            self?.paint()
        })
        a.addAction(UIAlertAction(title: L.cancel, style: .cancel))
        // iPad 上 actionSheet 要锚点，不然会崩。
        a.popoverPresentationController?.sourceView = view
        a.popoverPresentationController?.sourceRect =
            CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(a, animated: true)
    }

    /// 改标题 / 改正文 / 改标签 —— 三样在一个弹窗里，走 `Notes.update` 一个出口。
    private func editText(_ it: NotesCore.Item) {
        let a = UIAlertController(title: L.wb_note_edit, message: nil,
                                  preferredStyle: .alert)
        a.addTextField { $0.text = it.title; $0.accessibilityIdentifier = "note.edit.title" }
        a.addTextField { $0.text = it.body; $0.accessibilityIdentifier = "note.edit.body" }
        a.addTextField {
            $0.text = it.tags.joined(separator: " ")
            $0.placeholder = "tags"
            $0.accessibilityIdentifier = "note.edit.tags"
        }
        a.addAction(UIAlertAction(title: L.cancel, style: .cancel))
        a.addAction(UIAlertAction(title: L.wb_note_save, style: .default) {
            [weak self] _ in
            let f = a.textFields ?? []
            Notes.update(id: it.id,
                         title: f.count > 0 ? f[0].text : nil,
                         body: f.count > 1 ? f[1].text : nil,
                         tags: f.count > 2
                            ? (f[2].text ?? "").split(separator: " ").map(String.init)
                            : nil)
            self?.paint()
        })
        present(a, animated: true)
    }
}

private final class TapNote: UITapGestureRecognizer {
    var id: String = ""
}
