import UIKit

/// 常用词屏。**照抄安卓 `VocabActivity.java`，不是重新设计。**
///
/// 🚨 出处：`android/java/com/kevin/shuoyingwen/VocabActivity.java`（541 行）。
///    版式、色值、交互矩阵、文案全部一一对应 —— 有标准答案就照抄。
///    Kevin 09-03 让安卓改成现在这个「芯片带」的（原话：「常用词太大了，
///    要一眼看到很多个词……看一看 Typeless」），所以**别照那份旧规格文档
///    里的 52dp 行列表**，那一版已经被他否掉了。
///
/// ## 为什么是芯片不是列表行
/// 一眼能看到几十个词。列表行一屏只放得下 8 条，而常用词的用法是"扫一眼确认
/// 这些词在不在"，不是"逐条读"。
///
/// ## 交互矩阵（跟安卓一字不差）
/// | 芯片 | 点一下 | 长按 |
/// |---|---|---|
/// | 候选 | 收录（→ `on`）+ 提示「已收录：X」 | 否掉（→ `no`），**不提示、不确认** |
/// | 已收录 | 无动作 | 弹确认框删除 |
///
/// 🚨 **只有点选，零滑动手势**：PC 端做不了滑动，三端会走散
///    （所以没有 iOS 常见的左滑删除 —— 这是决定，不是漏做）。
final class VocabViewController: UIViewController {

    /// 「我不要的」折叠条默认收起。**不持久化**，退出即复位（跟安卓一致）。
    private var showRejected = false

    private let scroll = UIScrollView()
    private let body = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.home_vocab
        UI.paintBg(self)
        // 🚨 进这一屏再收一次（跟安卓 `VocabActivity.onCreate` 一致）。
        //    主力是 `WordBook.add` 那一刻就流过来了，这里是**兜底**：
        //    万一有哪条路径绕过了 `add`（比如以后加导入/同步），这一屏也能补上。
        WordBook.pushToVocab()

        body.axis = .vertical
        body.alignment = .fill
        body.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(body)
        view.addSubview(scroll)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: g.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: g.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: g.trailingAnchor),
            // 页边距 21，跟安卓 `root.setPadding(dp(21), dp(24), dp(21), dp(16))` 一致
            body.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 24),
            body.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -16),
            body.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 21),
            body.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -21),
            body.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -42),
        ])
        showList()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    // MARK: - 整屏重搭
    //
    // 🚨 每次变更都整屏重搭（跟安卓 `showList()` 一样）。这一屏很轻，
    //    重搭比逐个增删可靠 —— 增删改三条路各写一遍才是会漏的那种。

    private func showList() {
        body.arrangedSubviews.forEach {
            body.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let all = KbBridge.loadVocab()
        var cand: [VocabCore.Term] = []
        var on: [VocabCore.Term] = []
        var no: [VocabCore.Term] = []
        for t in all {
            switch VocabCore.statusOf(t.status) {
            case VocabCore.ST_CAND: cand.append(t)
            case VocabCore.ST_NO:   no.append(t)
            default:                on.append(t)
            }
        }

        // 🚨 **不排序**（跟安卓一致）：候选组要保后端给的顺序 ——
        //    那个顺序就是推荐顺序，重排等于把后端的判断丢了。

        // 🚨 **页内不再画大标题** —— 这一屏 2026-09-04 从"设置里点进来的子页"
        //    升成了**独立 Tab**，导航栏已经有「常用词」三个字，
        //    页内再来一个就是同一句话写两遍（端到端截图一眼看出来）。
        //    单一出口：标题只由 `title = L.home_vocab`（第 33 行）给。
        //
        // 🚨 这类"改了结构、没回头看老结构留下的东西"最容易漏：
        //    升 Tab 那次我只管接上，没打开看过它长什么样。

        // ---- 候选芯片带：**0 个整块消失**，不留空态行、不写「暂无新词」----
        if !cand.isEmpty {
            body.addArrangedSubview(
                card(head: L.fill(L.cand_head, "\(cand.count)"),
                     items: cand, kept: false,
                     topGap: 12, botGap: 12))
        }

        // ---- 「＋ 添加」大按钮 ----
        body.addArrangedSubview(addButton())

        // ---- 我的常用词 ----
        if on.isEmpty {
            let empty = UILabel()
            empty.text = L.vocab_empty
            empty.font = .systemFont(ofSize: 14)
            empty.textColor = Skin.dim
            empty.numberOfLines = 0
            body.addArrangedSubview(gap(24))
            body.addArrangedSubview(empty)
        } else {
            body.addArrangedSubview(
                card(head: L.fill(L.vocab_kept_head, "\(on.count)"),
                     items: on, kept: true,
                     topGap: 4, botGap: 12))
        }

        // ---- 「我不要的」折叠区 ----
        if !no.isEmpty { body.addArrangedSubview(rejectedSection(no)) }
    }

    private func gap(_ h: CGFloat) -> UIView {
        let v = UIView()
        v.heightAnchor.constraint(equalToConstant: h).isActive = true
        return v
    }

    // MARK: - 卡片 + 芯片带

    /// 一张玻璃卡：卡头一行小字 + 芯片带。候选卡和已收录卡是**同一个函数**
    /// （安卓那边是两个几乎一样的函数，那是两处实现 —— 这里收成一个）。
    private func card(head: String, items: [VocabCore.Term], kept: Bool,
                      topGap: CGFloat, botGap: CGFloat) -> UIView {
        let wrap = UIView()
        let box = UIView()
        box.backgroundColor = Skin.glassFill
        box.layer.cornerRadius = 18
        box.layer.borderWidth = 0.6
        box.layer.borderColor = Skin.glassStroke.cgColor
        box.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(box)
        NSLayoutConstraint.activate([
            box.topAnchor.constraint(equalTo: wrap.topAnchor, constant: topGap),
            box.bottomAnchor.constraint(equalTo: wrap.bottomAnchor,
                                        constant: -botGap),
            box.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            box.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
        ])

        let h = UILabel()
        h.text = head
        h.font = .systemFont(ofSize: 13)
        h.textColor = Skin.dim
        h.numberOfLines = 0
        h.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(h)

        let flow = chipFlow(items, kept: kept)
        flow.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(flow)
        NSLayoutConstraint.activate([
            h.topAnchor.constraint(equalTo: box.topAnchor, constant: 10),
            h.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            h.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            flow.topAnchor.constraint(equalTo: h.bottomAnchor, constant: 10),
            flow.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            flow.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor,
                                           constant: -16),
            flow.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
        ])
        return wrap
    }

    /// 贪心折行的芯片带。
    ///
    /// 🚨 自己算折行**是照抄安卓**（那边没有 flexbox，手写了同一套贪心）。
    ///    iOS 这边本来可以用 UICollectionView 的 flow layout ——
    ///    但两端各用各的排版算法，同一批词会折出不同的行数，
    ///    截图对不上时没人分得清是"版式漂了"还是"算法不同"。
    /// 🚨 可用宽度 = 屏宽 − 页边距 21×2 − 卡内边 16×2，跟安卓那行一样。
    private func chipFlow(_ items: [VocabCore.Term], kept: Bool) -> UIView {
        let col = UIStackView()
        col.axis = .vertical
        col.alignment = .leading
        col.spacing = 8

        let avail = UIScreen.main.bounds.width - 21 * 2 - 16 * 2
        let font = UIFont.systemFont(ofSize: 13)
        let chipPad: CGFloat = 12 * 2
        let gap: CGFloat = 8

        var row: UIStackView?
        var used: CGFloat = 0
        for t in items {
            let w = (t.text as NSString)
                .size(withAttributes: [.font: font]).width + chipPad
            if row == nil || used + w > avail {
                let r = UIStackView()
                r.axis = .horizontal
                r.spacing = gap
                r.alignment = .center
                col.addArrangedSubview(r)
                row = r
                used = 0
            }
            row?.addArrangedSubview(chip(t, kept: kept))
            used += w + gap
        }
        return col
    }

    /// 一枚芯片：36 高、18 圆角、13pt、1pt 紫描边。
    /// 已收录填充实一点（紫 20%）、候选淡一点（紫 8%）。
    private func chip(_ t: VocabCore.Term, kept: Bool) -> UIView {
        let b = UIButton(type: .custom)
        b.setTitle(t.text, for: .normal)
        b.setTitleColor(Skin.text, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13)
        b.contentEdgeInsets = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        b.backgroundColor = kept ? Skin.chipKeptFill : Skin.chipCandFill
        b.layer.cornerRadius = 18
        b.layer.borderWidth = 1
        b.layer.borderColor = Skin.accent.cgColor
        b.heightAnchor.constraint(equalToConstant: 36).isActive = true

        // 🚨 用 `objc` 选择器拿不到 Term，所以把它挂在闭包上；
        //    `UIAction` 要 iOS 14+，项目最低版本够（其它屏已经在用）。
        if kept {
            let lp = UILongPressGestureRecognizer(
                target: self, action: #selector(onLongPressKept(_:)))
            b.addGestureRecognizer(lp)
            b.accessibilityHint = L.vocab_delete
            keptById[t.id] = t
            b.accessibilityIdentifier = "chip.kept." + t.id
            longPressTermId[ObjectIdentifier(lp)] = t.id
        } else {
            candById[t.id] = t
            b.accessibilityIdentifier = "chip.cand." + t.id
            b.addAction(UIAction { [weak self] _ in
                self?.setStatus(t, VocabCore.ST_ON)
                self?.toast(L.fill(L.cand_added, t.text))
            }, for: .touchUpInside)
            let lp = UILongPressGestureRecognizer(
                target: self, action: #selector(onLongPressCand(_:)))
            b.addGestureRecognizer(lp)
            longPressTermId[ObjectIdentifier(lp)] = t.id
        }
        return b
    }

    // 长按手势拿不到闭包捕获的 Term，用 id 反查。
    private var keptById: [String: VocabCore.Term] = [:]
    private var candById: [String: VocabCore.Term] = [:]
    private var longPressTermId: [ObjectIdentifier: String] = [:]

    @objc private func onLongPressKept(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began,
              let id = longPressTermId[ObjectIdentifier(g)],
              let t = keptById[id] else { return }
        confirmDelete(t)
    }

    @objc private func onLongPressCand(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began,
              let id = longPressTermId[ObjectIdentifier(g)],
              let t = candById[id] else { return }
        // 🚨 否掉**不提示、不确认**（跟安卓一致）：他长按就是明确表态，
        //    再弹一个框是把一个决定问两遍。误操作有「我不要的」里的「收回候选」兜底。
        setStatus(t, VocabCore.ST_NO)
    }

    // MARK: - 「我不要的」折叠区

    private func rejectedSection(_ no: [VocabCore.Term]) -> UIView {
        let col = UIStackView()
        col.axis = .vertical
        col.alignment = .fill
        col.spacing = 6

        let bar = UIButton(type: .system)
        bar.setTitle(L.fill(showRejected ? L.cand_rej_open : L.cand_rej_closed,
                            "\(no.count)"), for: .normal)
        bar.setTitleColor(Skin.dim, for: .normal)
        bar.titleLabel?.font = .systemFont(ofSize: 14)
        bar.contentHorizontalAlignment = .left
        bar.contentEdgeInsets = UIEdgeInsets(top: 12, left: 4, bottom: 12, right: 4)
        bar.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            self.showRejected.toggle()
            self.showList()
        }, for: .touchUpInside)
        col.addArrangedSubview(bar)

        guard showRejected else { return col }
        for t in no {
            let r = UIView()
            r.backgroundColor = Skin.glassFill
            r.layer.cornerRadius = 18
            r.layer.borderWidth = 0.6
            r.layer.borderColor = Skin.glassStroke.cgColor

            let tv = UILabel()
            tv.text = t.text
            tv.font = .systemFont(ofSize: 15)
            tv.textColor = Skin.dim            // 否掉的降一级
            tv.numberOfLines = 0
            tv.translatesAutoresizingMaskIntoConstraints = false

            let back = UIButton(type: .system)
            back.setTitle(L.cand_recall, for: .normal)
            back.setTitleColor(Skin.accent, for: .normal)
            back.titleLabel?.font = .systemFont(ofSize: 13)
            back.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10,
                                                  bottom: 6, right: 10)
            back.translatesAutoresizingMaskIntoConstraints = false
            // 🚨🚨 收回写的是 **`ST_CAND` 不是 `ST_ON`** —— 还要再点一次才收录。
            //    直接进已收录的话，"我按错了想撤销"会变成"我按错了结果它生效了"。
            back.addAction(UIAction { [weak self] _ in
                self?.setStatus(t, VocabCore.ST_CAND)
            }, for: .touchUpInside)

            r.addSubview(tv)
            r.addSubview(back)
            NSLayoutConstraint.activate([
                tv.leadingAnchor.constraint(equalTo: r.leadingAnchor, constant: 14),
                tv.topAnchor.constraint(equalTo: r.topAnchor, constant: 10),
                tv.bottomAnchor.constraint(equalTo: r.bottomAnchor, constant: -10),
                tv.trailingAnchor.constraint(lessThanOrEqualTo: back.leadingAnchor,
                                             constant: -8),
                back.trailingAnchor.constraint(equalTo: r.trailingAnchor,
                                               constant: -14),
                back.centerYAnchor.constraint(equalTo: r.centerYAnchor),
            ])
            col.addArrangedSubview(r)
        }
        return col
    }

    // MARK: - 添加

    private func addButton() -> UIView {
        let b = UIButton(type: .custom)
        b.setTitle(L.vocab_add, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16)
        // 🚨 照安卓：这个按钮用的是**键盘那套 `Theme.accent`**（#7C5CE6 / 圆角 12），
        //    不是芯片的 `Skin.accent`（#8B5CF6 / 圆角 18）。两套紫共存是现状，
        //    我不在这里自作主张统一 —— 配色归 Kevin 和 2.1 定（他说过别自己设计）。
        //    渐变紫走 `Theme.purpleGrad`（他 09-04 要的「紫色不够渐变」那条）。
        b.setBackgroundImage(Theme.purpleGrad, for: .normal)
        b.layer.cornerRadius = 12
        b.clipsToBounds = true
        b.heightAnchor.constraint(equalToConstant: 52).isActive = true
        b.addAction(UIAction { [weak self] _ in self?.askAdd() }, for: .touchUpInside)

        let wrap = UIView()
        b.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(b)
        NSLayoutConstraint.activate([
            b.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 14),
            b.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -4),
            b.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            b.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
        ])
        return wrap
    }

    /// 添加弹窗：输入框 + 三档 kind。
    ///
    /// 🚨 安卓那边踩过一个坑值得记：`setView` 和 `setSingleChoiceItems` 一起用时，
    ///    系统把输入框渲染到档位列表**下面**，顺序是反的，而编译全绿。
    ///    iOS 的 `UIAlertController` 只支持 `addTextField`，放不下三个单选 ——
    ///    所以档位改成**一行分段控件**塞进输入框下面做不到，
    ///    这里的做法是：先弹输入框，确定后再弹一个档位选择（两步）。
    ///    🚨 **不是**默默用 `both` 就完事 —— 那样「只帮我听对 / 只帮我说得像」
    ///    这两档在 iOS 上就永远选不到，等于砍了功能还不说。
    private func askAdd() {
        let a = UIAlertController(title: L.vocab_add, message: nil,
                                  preferredStyle: .alert)
        a.addTextField { tf in
            tf.placeholder = L.vocab_add_hint
            tf.autocorrectionType = .no
        }
        a.addAction(UIAlertAction(title: L.ok, style: .default) { [weak self] _ in
            let word = a.textFields?.first?.text ?? ""
            self?.askKind(word)
        })
        a.addAction(UIAlertAction(title: L.cancel, style: .cancel))
        present(a, animated: true)
    }

    /// 第二步：这个词喂给谁。默认第一档 `both`。
    private func askKind(_ word: String) {
        // 🚨 空词直接静默返回（跟安卓 `add()` 回 "empty" 时不提示一致）——
        //    他什么都没输就按了确定，弹个错误框是在骂他。
        guard VocabCore.usable(word) else { return }
        let a = UIAlertController(title: L.vocab_add, message: word,
                                  preferredStyle: .actionSheet)
        let kinds = [(VocabCore.KIND_BOTH, L.vocab_kind_both),
                     (VocabCore.KIND_ASR, L.vocab_kind_asr),
                     (VocabCore.KIND_STYLE, L.vocab_kind_style)]
        for (k, label) in kinds {
            a.addAction(UIAlertAction(title: label, style: .default) {
                [weak self] _ in self?.doAdd(word, kind: k)
            })
        }
        a.addAction(UIAlertAction(title: L.cancel, style: .cancel))
        // 🚨 iPad 上 actionSheet 不给 anchor 会**直接崩**（09-04 说话记录屏刚踩过）。
        a.popoverPresentationController?.sourceView = view
        a.popoverPresentationController?.sourceRect =
            CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        present(a, animated: true)
    }

    /// 真正落盘。**校验规则全在 `VocabCore`，这里不自己判。**
    private func doAdd(_ word: String, kind: String) {
        if VocabCore.tooLong(word) { return toast(L.vocab_too_long) }
        var cur = KbBridge.loadVocab()
        let id = VocabCore.idOf(word)
        // 命中已有词时要看它是什么态：
        //  · 已收录 → 真「已经有了」，静默不动
        //  · 候选/否掉 → 他现在**手动**加它 = 明确要收录，直接提成 on
        //    🚨 不这么做的话，「我误否掉了想加回来」只会得到"已经有了"，
        //       而那个词其实一直不生效 —— 看起来像功能坏了。
        if let i = cur.firstIndex(where: { $0.id == id }) {
            if VocabCore.statusOf(cur[i].status) == VocabCore.ST_ON { return }
            cur[i] = cur[i].withStatus(VocabCore.ST_ON)
            KbBridge.saveVocab(cur)
            VocabSync.pushStatusAsync(cur[i], VocabCore.ST_ON)
            return showList()
        }
        // 🚨 额度**只数已收录的**，候选/否掉不占 500。
        let onCount = cur.filter {
            VocabCore.statusOf($0.status) == VocabCore.ST_ON
        }.count
        if onCount >= VocabCore.LIMIT_COUNT { return toast(L.vocab_full) }
        let fresh = VocabCore.Term(id: id, text: VocabCore.norm(word),
                                   kind: VocabCore.kindOf(kind),
                                   src: VocabCore.SRC_MANUAL,
                                   at: Int64(Date().timeIntervalSince1970 * 1000))
        cur.append(fresh)
        KbBridge.saveVocab(cur)
        VocabSync.pushChangeAsync(added: fresh, removed: nil)
        showList()
    }

    // MARK: - 改态 / 删除

    private func setStatus(_ t: VocabCore.Term, _ status: String) {
        let out = KbBridge.loadVocab().map {
            $0.id == t.id ? $0.withStatus(status) : $0
        }
        KbBridge.saveVocab(out)
        // 🚨 同步走 SYNC-1 三步（拉云端 → 在【云端那份】上改 → replace）。
        //    **不等它**：界面立刻刷新，同步在后台走；拉不到就这次不同步，
        //    本地已经改好了，下次启动还会再同步一次。
        VocabSync.pushStatusAsync(t, status)
        showList()
    }

    private func confirmDelete(_ t: VocabCore.Term) {
        let a = UIAlertController(
            title: nil, message: L.fill(L.vocab_del_confirm, t.text),
            preferredStyle: .alert)
        a.addAction(UIAlertAction(title: L.vocab_delete, style: .destructive) {
            [weak self] _ in
            // 🚨 删除是**删掉 + 记墓碑**（安卓 `removeAndForget`）：
            //    只删不记的话，单词本下次又会把同一个词流回来，
            //    表现成"我删了它自己又回来了"。
            let left = KbBridge.loadVocab().filter { $0.id != t.id }
            KbBridge.saveVocab(left)
            KbBridge.addVocabTombstone(t.id)
            // 🚨 删除必须走 replace 传播出去 —— 只发 merge 的话
            //    **删除永远传不到别的设备**（SYNC-1a）。
            VocabSync.pushChangeAsync(added: nil, removed: t.id)
            self?.showList()
        })
        a.addAction(UIAlertAction(title: L.login_gate_later, style: .cancel))
        present(a, animated: true)
    }

    private func toast(_ s: String) {
        // 🚨 一律中性口吻、不许红色、不许「失败」字样（SYNC-7）。
        let a = UIAlertController(title: nil, message: s, preferredStyle: .alert)
        present(a, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            a.dismiss(animated: true)
        }
    }
}
