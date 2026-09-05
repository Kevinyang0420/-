import UIKit

/// 「说话记录」屏乙（iOS）—— Kevin 2026-09-03 看 `hist_list_confirm.png` 点头。
///
/// 🚨 版式**以已批图为准**：原话(灰·单行截断) + 译文(**按档位上色**·最多两行) +
///    底行(档位 chip + 时间 + `>`)，点进详情。
///    🚨 安卓 `HistoryActivity` 目前还是旧版式（meta 在上、无上色、无 chip、无 `>`）——
///    跟这张已批图不一致，已报 2.1/2.3 让安卓对齐；**iOS 照 Kevin 点头的图，不照旧安卓代码。**
///
/// 数据只有一份：`History`（`history.jsonl`）。这一屏不自己存任何东西。
/// 详情结构照 `pc_detail_confirm.png`：原话 + 译文上色 + 档位 + 时间 + 复制 + 再发一次；
/// 🚨 手机端复制走**复制按钮**（不是 Ctrl+C，2.1 明示）；「再发一次」= 拿原话重译成**新的一条**
///    （App 不在输入法会话里、没有输入框可插，跟安卓 `HistoryActivity.resend` 同口径）。
final class HistoryListViewController: UIViewController {

    // ── 顶部两个分页（Kevin 2026-09-05 拍板「用乙方案」＝并进说话记录）──
    //
    // 🚨🚨 **分段条放在内容区顶部，绝不碰导航栏。**
    //    2.1 的判据是「切分页时顶栏（返回/标题）坐标逐像素不动」——
    //    做法上让它**结构上不可能动**，比改完再去量坐标可靠得多。
    //    （量出来一致只说明这一次没动；不碰它才是每次都不动。）
    private let tabRecords = UIButton(type: .system)
    private let tabWordbook = UIButton(type: .system)
    private var showWordbook = false

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let emptyLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.hist_screen_title
        UI.paintBg(self)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)

        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        emptyLabel.text = L.hist_empty
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = Theme.dim
        emptyLabel.textAlignment = .center
        emptyLabel.numberOfLines = 0
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)

        // 分段条：样式**照抄随手翻译那对「翻译｜转写」**（圆角 17、等宽、
        // 选中 accent 填充白字、未选 key 底 dim 字）—— 同一种控件不许长得两样。
        for (btn, t, sel) in [(tabRecords, L.hist_tab_records, #selector(pickRecords)),
                              (tabWordbook, L.hist_tab_wordbook, #selector(pickWordbook))] {
            btn.setTitle(t, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            btn.layer.cornerRadius = 17
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.addTarget(self, action: sel, for: .touchUpInside)
        }
        tabRecords.accessibilityIdentifier = "hist.tab.records"
        tabWordbook.accessibilityIdentifier = "hist.tab.wordbook"
        let tabs = UIStackView(arrangedSubviews: [tabRecords, tabWordbook])
        tabs.axis = .horizontal
        tabs.spacing = Theme.gap * 0.7
        tabs.distribution = .fillEqually      // 🚨 等宽，跟方案 F 同口径
        tabs.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabs)

        paintTabs()          // 🚨 建完就画一次初始选中态，别等第一次点击

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: g.topAnchor, constant: 10),
            tabs.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: Theme.pad),
            tabs.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -Theme.pad),
            tabs.heightAnchor.constraint(equalToConstant: 34),

            scroll.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: g.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: g.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: Theme.pad),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -Theme.pad),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 60),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        // 🚨 每次进来都重读盘 —— 键盘那边可能刚加了新的一条。
        refresh()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    @objc private func pickRecords() { showWordbook = false; paintTabs(); refresh() }
    @objc private func pickWordbook() { showWordbook = true; paintTabs(); refresh() }

    private func paintTabs() {
        tabRecords.backgroundColor = showWordbook ? Theme.key : Theme.accent
        tabRecords.setTitleColor(showWordbook ? Theme.dim : .white, for: .normal)
        tabWordbook.backgroundColor = showWordbook ? Theme.accent : Theme.key
        tabWordbook.setTitleColor(showWordbook ? .white : Theme.dim, for: .normal)
    }

    private func refresh() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if showWordbook { refreshWordbook() } else { refreshRecords() }
    }

    private func refreshRecords() {
        let items = History.list()
        emptyLabel.isHidden = !items.isEmpty
        emptyLabel.text = L.hist_empty
        // 🚨 只有这一屏传 `showAdd: true` —— 随手翻译那屏共用同一个 `card`，
        //    Kevin 看过并点了头，不动它。
        for it in items { stack.addArrangedSubview(card(it, showAdd: true)) }
    }

    /// 单词本分页：**按 词 / 词组 / 句子 自动分段**。
    ///
    /// 🚨 归类**在这里算**（`WordKind.group`），不写死进存储 —— 以后改判据不用迁数据。
    /// 🚨 **空的那一段整段不出现**：`group` 只回非空的段，
    ///    所以标题跟着内容走，而不是先摆三个标题再往里填。
    ///    （2.1 的坏样本打的就是"先摆三个标题"那种写法。）
    private func refreshWordbook() {
        let items = WordBook.list()
        emptyLabel.isHidden = !items.isEmpty
        emptyLabel.text = L.wb_empty
        for (kind, group) in WordKind.group(items, en: { $0.en }) {
            stack.addArrangedSubview(sectionHeader(kindTitle(kind), count: group.count))
            for it in group { stack.addArrangedSubview(wbCard(it)) }
        }
    }

    /// 段标题的文案 —— 放界面这一层，`WordKind` 只管判据。
    private func kindTitle(_ k: WordKind.Kind) -> String {
        switch k {
        case .word: return L.wb_kind_word
        case .phrase: return L.wb_kind_phrase
        case .sentence: return L.wb_kind_sentence
        }
    }

    private func sectionHeader(_ text: String, count: Int) -> UIView {
        let l = UILabel()
        l.text = text + "  " + String(count)
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = Theme.dim
        l.accessibilityIdentifier = "wb.section"
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    /// 单词本一条 —— 版式**跟记录卡同一套**（玻璃卡、原话灰、译文上色），
    /// 免得两屏各画一种卡片。
    private func wbCard(_ it: WordBookCore.Item) -> UIView {
        let box = UIView()
        box.backgroundColor = Theme.panel
        box.layer.cornerRadius = 18
        box.layer.borderWidth = 0.6
        box.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        box.translatesAutoresizingMaskIntoConstraints = false

        let zh = UILabel()
        zh.text = it.zh
        zh.font = .systemFont(ofSize: 15)
        zh.textColor = Theme.dim
        zh.numberOfLines = 1
        zh.lineBreakMode = .byTruncatingTail
        zh.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(zh)

        let en = UILabel()
        en.text = it.en
        en.font = .systemFont(ofSize: 20, weight: .semibold)
        en.textColor = Theme.text
        en.numberOfLines = 2
        en.lineBreakMode = .byTruncatingTail
        en.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(en)

        NSLayoutConstraint.activate([
            zh.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            zh.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            zh.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            en.topAnchor.constraint(equalTo: zh.bottomAnchor, constant: 6),
            en.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            en.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            en.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -14),
        ])
        return box
    }

    // MARK: - 卡片
    // 🚨 档位→色/chip/时间的实现在共享 `HistoryUI`（详情屏也用同一份，免两处走散）。

    /// 🚨🚨 **不再是 private** —— 随手翻译那屏的「最近」也要用**同一份**行样式
    ///    （2.1 规格 2026-09-04：「复用历史列表现成的行样式，不要另画一套」）。
    ///    抄第二份必漂：这摊活已经在"同一规则两处实现"上栽过好几次。
    ///
    /// 🚨 `onTap` 传进来是因为**两处的点击去向不同**：历史页是就地跳详情，
    ///    随手翻译那屏也要跳详情但导航栈不一样。行为不同的那一点做成参数，
    ///    **样式那一大坨保持只有一份**。
    ///    传 nil = 用本类自己的跳转（历史页原来的行为，一个字没改）。
    /// - Parameter showAdd: 底行右侧显不显示「＋ 单词本」。
    ///   🚨 **默认 false**：这个 `card` 随手翻译那屏的「最近」也在用，
    ///   Kevin 已经看过那一屏并点了头。**他没要求改的地方一个像素都别动** ——
    ///   只有说话记录页传 true。
    func card(_ it: History.Item, onTap: ((History.Item) -> Void)? = nil,
              showAdd: Bool = false) -> UIView {
        let box = UIView()
        box.backgroundColor = Theme.panel                 // 玻璃卡（白 10%）
        box.layer.cornerRadius = 18
        box.layer.borderWidth = 0.6
        box.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        box.translatesAutoresizingMaskIntoConstraints = false

        // 原话（灰·单行截断）
        let zh = UILabel()
        zh.text = it.zh
        zh.font = .systemFont(ofSize: 15)
        zh.textColor = Theme.dim
        zh.lineBreakMode = .byTruncatingTail
        zh.numberOfLines = 1
        zh.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(zh)

        // 译文（按档上色·最多两行）
        let out = UILabel()
        out.text = it.out
        out.font = .systemFont(ofSize: 20, weight: .semibold)
        out.textColor = HistoryUI.modeColor(it.mode)
        out.numberOfLines = 2
        out.lineBreakMode = .byTruncatingTail
        out.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(out)

        // 底行：档位 chip + 时间 + >
        let chip = HistoryUI.chip(HistoryUI.modeChip(it.mode), color: HistoryUI.modeColor(it.mode))
        chip.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(chip)

        let time = UILabel()
        time.text = HistoryUI.timeLabel(it.ts)
        time.font = .systemFont(ofSize: 13)
        time.textColor = Theme.dim
        time.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(time)

        let chev = UILabel()
        chev.text = "›"
        chev.font = .systemFont(ofSize: 22, weight: .light)
        chev.textColor = Theme.dim
        chev.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(chev)

        // ── 「＋ 单词本」：底行最右（`›` 左边）──────────────────
        // 🚨 已加过的显示「已加入」，**再点是移除、不是重复添加**（2.1 判据 2：
        //    同一条连点三次，单词本里始终只有一条）。
        // 🚨 身份用 `WordBookCore.idOf(zh, en)` —— **随手翻译那屏 `inBook()` 用的同一个**，
        //    不另写判断。两处各写一套 id 的话，"已加入"会在两屏给出不同答案。
        var addBtn: UIButton?
        if showAdd {
            let b = UIButton(type: .system)
            b.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
            b.contentEdgeInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
            b.layer.cornerRadius = 13
            b.translatesAutoresizingMaskIntoConstraints = false
            b.accessibilityIdentifier = "hist.add.wordbook"
            paintAdd(b, added: HistoryListViewController.inBook(it))
            let t = AddWB(target: self, action: #selector(tapAdd(_:)))
            t.item = it
            t.btn = b
            b.addGestureRecognizer(t)
            box.addSubview(b)
            addBtn = b
        }

        NSLayoutConstraint.activate([
            zh.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            zh.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            zh.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),

            out.topAnchor.constraint(equalTo: zh.bottomAnchor, constant: 6),
            out.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            out.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),

            chip.topAnchor.constraint(equalTo: out.bottomAnchor, constant: 12),
            chip.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            chip.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -14),
            chip.heightAnchor.constraint(equalToConstant: 26),

            time.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            time.leadingAnchor.constraint(equalTo: chip.trailingAnchor, constant: 12),

            chev.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
            chev.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
        ])
        if let ab = addBtn {
            NSLayoutConstraint.activate([
                ab.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
                ab.trailingAnchor.constraint(equalTo: chev.leadingAnchor, constant: -10),
                // 🚨 时间跟按钮之间留够，别让长时间戳把按钮挤出屏幕
                ab.leadingAnchor.constraint(greaterThanOrEqualTo: time.trailingAnchor,
                                            constant: 8),
            ])
        }

        box.isUserInteractionEnabled = true
        let tap = TapItem(target: self, action: #selector(tapCard(_:)))
        // 🚨 **让整块卡片的手势避开「＋单词本」那颗按钮**。
        //    不设的话父视图手势会跟子按钮抢触摸 —— 表现是点按钮却跳进了详情，
        //    而且**编译不报、看代码也看不出来**，只有真点一次才知道。
        tap.delegate = self
        tap.item = it
        tap.custom = onTap
        box.addGestureRecognizer(tap)
        // 长按删这一条（「能看能删」——跟安卓一致）
        let hold = HoldItem(target: self, action: #selector(holdCard(_:)))
        hold.item = it
        hold.minimumPressDuration = 0.5
        box.addGestureRecognizer(hold)
        return box
    }


    // MARK: - 「＋ 单词本」

    /// 这一条收过没有。**用随手翻译那屏同一个 id 算法**，不另写判断。
    static func inBook(_ it: History.Item) -> Bool {
        guard WordBookCore.usable(it.out) else { return false }
        let id = WordBookCore.idOf(it.zh, it.out)
        return WordBook.list().contains { $0.id == id }
    }

    private func paintAdd(_ b: UIButton, added: Bool) {
        b.setTitle(added ? L.wb_added : L.wb_add, for: .normal)
        b.setTitleColor(added ? Theme.dim : Theme.accent, for: .normal)
        b.backgroundColor = added
            ? UIColor.white.withAlphaComponent(0.06)
            : Theme.accent.withAlphaComponent(0.16)
    }

    @objc private func tapAdd(_ g: AddWB) {
        guard let it = g.item, let b = g.btn else { return }
        guard WordBookCore.usable(it.out) else { return }
        let id = WordBookCore.idOf(it.zh, it.out)
        if WordBook.list().contains(where: { $0.id == id }) {
            // 🚨 再点是**移除**，不是重复添加（2.1 判据 2）。
            WordBook.remove(id: id)
        } else {
            // 参数形状**照抄 AppDelegate:4772 那个调用点**，不凭印象写
            //（`today:` 是必填的，我第一版就漏了它）。
            _ = WordBook.add(zh: it.zh, en: it.out, span: "full",
                             tone: it.mode, today: Srs.todayString())
        }
        // 🚨 **重画之前先读盘**：显示的状态必须来自存储，不是我刚才那个布尔量。
        //    拿本地变量取反的话，存储写失败时界面照样变，而他会以为加上了。
        paintAdd(b, added: HistoryListViewController.inBook(it))
    }

    @objc private func tapCard(_ g: TapItem) {
        guard let it = g.item else { return }
        // 🚨 外面给了去向就用外面的 —— 样式共用、行为各自，见 `card` 的说明。
        if let f = g.custom { f(it); return }
        navigationController?.pushViewController(
            HistoryDetailViewController(item: it), animated: true)
    }

    @objc private func holdCard(_ g: HoldItem) {
        guard g.state == .began, let it = g.item else { return }
        let a = UIAlertController(title: nil, message: L.hist_delete_ask,
                                  preferredStyle: .actionSheet)
        // 🚨 iPad 上 actionSheet **不给锚点就直接崩**（`TARGETED_DEVICE_FAMILY = "1,2"`，
        //    真发 iPad）。仓里另外三处 actionSheet 都设了，这个新出口漏了 ——
        //    「规矩在新出口上漏掉」是这个项目反复栽的那一类。
        a.popoverPresentationController?.sourceView = g.view
        a.popoverPresentationController?.sourceRect = g.view?.bounds ?? .zero
        a.addAction(UIAlertAction(title: L.kb_delete, style: .destructive) { _ in
            History.remove(ts: it.ts); self.refresh()
        })
        a.addAction(UIAlertAction(title: L.login_gate_later, style: .cancel))
        present(a, animated: true)
    }
}

/// 带 Item 的手势识别器（免给每张卡挂 tag）。
/// 「＋ 单词本」自己的手势 —— **带上这一条是哪条、按钮是哪个**。
///
/// 🚨 为什么按钮上还要单独挂手势：卡片整块有 `TapItem`（点进详情）。
///    UIKit 里父视图的手势会跟子按钮抢触摸，表现是**点了没反应**或**点了跳详情**。
///    给按钮自己挂一个手势，并在下面让卡片那个手势**避开 UIControl**，两边才不打架。
extension HistoryListViewController: UIGestureRecognizerDelegate {
    /// 触摸落在按钮（任何 `UIControl`）上时，**卡片那个手势不接** ——
    /// 让按钮自己处理。只对 `TapItem` 生效，长按删那条不受影响。
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard g is TapItem else { return true }
        var v: UIView? = touch.view
        while let cur = v {
            if cur is UIControl { return false }
            v = cur.superview
        }
        return true
    }
}

private final class AddWB: UITapGestureRecognizer {
    var item: History.Item?
    weak var btn: UIButton?
}

private final class TapItem: UITapGestureRecognizer {
    var item: History.Item?
    /// 非 nil = 调用方自己接管点击去向（随手翻译那屏用）。
    var custom: ((History.Item) -> Void)?
}
private final class HoldItem: UILongPressGestureRecognizer { var item: History.Item? }
