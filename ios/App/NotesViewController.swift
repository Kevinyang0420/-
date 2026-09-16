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
///
/// 🚨 09-16 0 点名：删除入口原来挂在长按上，**入口从可见变成隐藏手势**——
///    改用 `UITableView` + `trailingSwipeActionsConfigurationForRowAt`
///    （左滑露出删除），这是 iOS 标准做法，不是自己发明的手势。
///    卡片本身的圆角/间距/字号一个值都没改，只换了容器（stack → table）。
final class NotesViewController: PushedViewController, UITextFieldDelegate,
        UITableViewDataSource, UITableViewDelegate {

    private let table = UITableView(frame: .zero, style: .plain)
    private let searchField = UITextField()
    private var items: [NotesCore.Item] = []

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

        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 100
        table.register(NoteCell.self, forCellReuseIdentifier: "note")
        view.addSubview(search)
        view.addSubview(table)
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

            table.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
        // 🚨 搜索走 `Notes.search`（转 `NotesCore.search`）——
        //    **不在这一屏再写一遍过滤**。规格判据「要搜得到原话」
        //    钉在那一层，界面再写一套的话这条判据就守不住这一屏。
        items = Notes.search(searchField.text ?? "")
        if items.isEmpty {
            let l = UILabel()
            // 🚨 空态要告诉他**怎么才会有东西**，不是干写一句"暂无"。
            l.text = (searchField.text ?? "").isEmpty ? L.note_empty
                                                      : L.wb_card_failed
            l.font = .systemFont(ofSize: 15)
            l.textColor = Skin.dim
            l.numberOfLines = 0
            l.textAlignment = .center
            l.accessibilityIdentifier = "note.empty"
            table.backgroundView = l
        } else {
            table.backgroundView = nil
        }
        table.reloadData()
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = tv.dequeueReusableCell(withIdentifier: "note", for: ip) as! NoteCell
        cell.configure(items[ip.row])
        return cell
    }

    // MARK: - UITableViewDelegate

    /// 🚨 点一下＝看/改正文（0 台账点名：存进去了但点不进去看正文）。
    ///    照抄 `WordBookViewController:392` 的调法——同一个
    ///    `NoteEditViewController`，同样只回文本、由调用方决定怎么写回。
    func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
        tv.deselectRow(at: ip, animated: true)
        let it = items[ip.row]
        let vc = NoteEditViewController(word: it.title, note: it.body)
        vc.onSave = { [weak self] text in
            Notes.update(id: it.id, body: text)
            self?.paint()
        }
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    /// 🚨 左滑＝系统标准删除手势，入口可见（不再是长按才有的隐藏菜单）。
    ///    「编辑」（改标题/加标签）同一排一起露出，走原来的 `editText`。
    func tableView(_ tv: UITableView, trailingSwipeActionsConfigurationForRowAt ip: IndexPath)
        -> UISwipeActionsConfiguration? {
        let it = items[ip.row]
        let del = UIContextualAction(style: .destructive, title: L.wb_delete) {
            [weak self] _, _, done in
            Notes.remove(id: it.id)
            self?.paint()
            done(true)
        }
        let edit = UIContextualAction(style: .normal, title: L.wb_note_edit) {
            [weak self] _, _, done in
            self?.editText(it)
            done(true)
        }
        return UISwipeActionsConfiguration(actions: [del, edit])
    }

    // MARK: - 编辑

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

/// 卡片视觉跟原来的 `card(_:)` 逐值照搬（圆角 14 / 背景 alpha 0.06 / 内边距
/// 12·14·4·6，`body.spacing`=10 的间距现在靠卡片自身的上下各 5pt 撑出来）——
/// 只是从「每次 `paint()` 重建的 `UIView`」换成「`UITableView` 复用的 cell」。
private final class NoteCell: UITableViewCell {
    private let box = UIView()
    private let t = UILabel()
    private let b = UILabel()
    private let tagLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none

        box.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        box.layer.cornerRadius = 14
        box.accessibilityIdentifier = "note.row"
        box.translatesAutoresizingMaskIntoConstraints = false

        t.font = .systemFont(ofSize: 16, weight: .semibold)
        t.textColor = Skin.text
        t.numberOfLines = 2
        t.translatesAutoresizingMaskIntoConstraints = false

        // 🚨 正文只露一行 —— 列表是用来找的，不是用来读的。
        b.font = .systemFont(ofSize: 14)
        b.textColor = Skin.dim
        b.numberOfLines = 2
        b.translatesAutoresizingMaskIntoConstraints = false

        tagLabel.font = .systemFont(ofSize: 12)
        tagLabel.textColor = Skin.accentHi
        tagLabel.translatesAutoresizingMaskIntoConstraints = false

        box.addSubview(t); box.addSubview(b); box.addSubview(tagLabel)
        contentView.addSubview(box)
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            box.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 21),
            box.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -21),
            box.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),

            t.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            t.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            t.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            b.topAnchor.constraint(equalTo: t.bottomAnchor, constant: 4),
            b.leadingAnchor.constraint(equalTo: t.leadingAnchor),
            b.trailingAnchor.constraint(equalTo: t.trailingAnchor),
            tagLabel.topAnchor.constraint(equalTo: b.bottomAnchor, constant: 6),
            tagLabel.leadingAnchor.constraint(equalTo: t.leadingAnchor),
            tagLabel.trailingAnchor.constraint(equalTo: t.trailingAnchor),
            tagLabel.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 不用") }

    func configure(_ it: NotesCore.Item) {
        t.text = it.title
        b.text = it.body
        tagLabel.text = it.tags.joined(separator: "  ·  ")
    }
}
