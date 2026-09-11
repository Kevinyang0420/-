import UIKit

/// 单词本：**列表 / 复习 / 详情**三个视图，一个 VC 三态。
/// 跟安卓 `WordBookActivity` 一一对应。
///
/// Kevin 2026-08-26 逐条拍板：
///   · **存本机**（不上后端）
///   · **两面都能当正面** —— 加个切换，他知道"多一个设置项、多一点工作量"仍然选了它
///   · 输入法历史记录里留入口，把说过的翻译同步进来
///
/// 🚨 默认正面 = **中文**（产品经理 2026-08-28 定：主场景是"说中文出英文"，
///    复习方向应当和使用方向一致；反向是巩固用的，作为可切换项）。
///
/// 🚨🚨 **换正面之后，已有的卡也要跟着变**，不是只对新加的生效
///    （产品经理点名的 W2-c，"最容易做漏的一半"）。
///    这里做得到是因为正面只是**渲染时读一个开关**，没有把方向写进记录。
///    如果哪天有人把方向存进 `Item`，这条就会悄悄坏掉。
///
/// 🚨 危险色用 `Theme.danger`（跟安卓 `Theme.DANGER` 同源），
///    **`Skin` 里没有 danger** —— 我凭印象写了 `Skin.danger`，
///    CI 编译当场挂。安卓那边同一天也犯过一模一样的（`Skin.DANGER`）。
///    **用常量前先 grep 一下它真的存在。**
///
/// 🚨 一行纯逻辑都不写在这里：去重、插入、封顶、该不该复习在 `WordBookCore`，
///    间隔重复在 `Srs`，两者都进了 `gate_pure_logic.py`。
final class WordBookViewController: UIViewController {

    /// 复习卡正面朝哪一面。存本机，切了记住。跟安卓同一个键名。
    private static let kFront = "wordbook_front"
    private static let frontZh = "zh"
    private static let frontEn = "en"

    private let scroll = UIScrollView()
    private let body = UIStackView()

    /// 当前在哪个视图。**返回靠它判断**，别靠"body 有没有子 view"
    /// （安卓那边第一版就是这么写的，条件恒真，列表页退不出去）。
    private enum Mode { case list, review, detail }
    private var mode: Mode = .list

    private var queue: [WordBookCore.Item] = []
    private var qi = 0
    private var flipped = false

    private var front: String {
        UserDefaults.standard.string(forKey: Self.kFront) ?? Self.frontZh
    }

    private func setFront(_ f: String) {
        UserDefaults.standard.set(f, forKey: Self.kFront)
    }

    private var today: String { Srs.todayString() }

    /// 进来就直接打开这一条的卡片（从「说话记录 · 单词本」那屏点进来时用）。
    ///
    /// 🚨 **不加这个的话卡片从他最常看的那一屏根本到不了** ——
    ///    那屏的条目**一个手势都没挂**，点了什么都不会发生。
    ///    「功能做出来了」和「他点得到」是两件事。
    private var openId: String?

    convenience init(open id: String) {
        self.init()
        self.openId = id
    }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.wb_title

        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        body.axis = .vertical
        body.spacing = 9
        body.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(body)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // 🚨 钉**安全区**，不是 `view.bottomAnchor`。
            //    钉 view 底的话滚动内容会钻到底栏下面 —— 滚到底时
            //    最后一根按钮被底栏压住，看着就是"贴死"。
            //    实测：加了 16pt 垫片 + 20pt 内边距（共 36），
            //    可见间距仍只有 14.7pt —— **21pt 被底栏吃掉了**。
            //    这不是间距调小了，是**内容区的边界画错了**。
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            body.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 20),
            body.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                          constant: 21),
            body.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                           constant: -21),
            body.bottomAnchor.constraint(equalTo: scroll.bottomAnchor,
                                         constant: -20),
        ])
        // 🚨 带着 id 进来就直接翻到那张卡片，别让他到了列表再找一遍。
        if let want = openId,
           let it = WordBook.list().first(where: { $0.id == want }) {
            showDetail(it)
        } else {
            showList()
        }
    }

    private func clearBody() {
        body.arrangedSubviews.forEach {
            body.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    // MARK: - 列表

    private func showList() {
        clearDetailMenu()
        mode = .list
        clearBody()
        let all = WordBook.list()
        let due = WordBookCore.due(all, today).count

        body.addArrangedSubview(label(L.wb_title, 24, Skin.text))
        body.addArrangedSubview(
            label(String(format: L.wb_count, all.count, due), 13, Skin.dim))

        // 🚨 App Group 没配好时**说出来**，不装作"本子是空的"。
        //    键盘收的词落在扩展本地、主 App 读自己那份 —— 两边各存各的，
        //    界面上只表现为"空" —— 那是最贵的一类错。
        if !WordBook.groupReady {
            let warn = label(L.wb_nogroup, 13, Theme.danger)
            warn.numberOfLines = 0
            body.addArrangedSubview(warn)
        }

        if all.isEmpty {
            let e = label(L.wb_empty, 14, Skin.dim)
            e.numberOfLines = 0
            body.addArrangedSubview(e)
            return
        }
        if due > 0 {
            body.addArrangedSubview(
                bigButton(String(format: L.wb_review_n, due),
                          #selector(tapReview)))
        }
        // 🚨🚨 Kevin 2026-09-05 08:39：「这个单词本还要做一个定期整理 organize
        //    一下：按照翻译的东西（**词、词组、句子**等）去 organize 一下，
        //    方便人去回看」。**这一屏一直是平铺的**，他 09-06 又问了一次。
        //
        // 🚨 判据本体是现成的 `WordKind.group` —— 它已经在「说话记录」那屏用了，
        //    **偏偏这一屏没用**。又是「规矩只落在一个出口」。
        //    别在这里重写一套分类，会跟那屏走散。
        // 🚨 **空的那一段整段不出现**：`group` 只回非空的段，所以标题跟着内容走，
        //    不是先摆三个标题再往里填。
        for (kind, grp) in WordKind.group(all, en: { $0.en }) {
            body.addArrangedSubview(sectionHeader(kindTitle(kind), grp.count))
            for it in grp { body.addArrangedSubview(card(it)) }
        }
    }

    /// 段标题文案 —— 放界面这一层，`WordKind` 只管判据。
    /// 🚨 跟 `HistoryListViewController.kindTitle` 用**同一批串**，别另写文案。
    private func kindTitle(_ k: WordKind.Kind) -> String {
        switch k {
        case .word: return L.wb_kind_word
        case .phrase: return L.wb_kind_phrase
        case .sentence: return L.wb_kind_sentence
        }
    }

    private func sectionHeader(_ text: String, _ count: Int) -> UIView {
        let l = UILabel()
        l.text = text + "  " + String(count)
        l.font = .systemFont(ofSize: 13, weight: .semibold)
        l.textColor = Skin.dim
        l.accessibilityIdentifier = "wb.section"
        return l
    }

    /// 列表里的一条：进度点 + 中文原话 + 英文。
    private func card(_ it: WordBookCore.Item) -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        box.layer.cornerRadius = 14
        let col = UIStackView(arrangedSubviews: [
            label(progress(it), 11, Skin.accentHi),
            label(zhFace(it), 15, Skin.text),
            label(it.en, 14, Skin.dim),
        ])
        col.axis = .vertical
        col.spacing = 3
        col.translatesAutoresizingMaskIntoConstraints = false
        col.isUserInteractionEnabled = false
        box.addSubview(col)
        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            col.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -14),
            col.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            col.trailingAnchor.constraint(equalTo: box.trailingAnchor,
                                          constant: -16),
        ])
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapCard(_:)))
        box.addGestureRecognizer(tap)
        // 🚨 **给行一个 id** —— 它一直有手势、能点，但没有标识，
        //    自动化就抓不到它。表现是"卡片截不到图"，看起来像功能没做，
        //    其实是**测试够不着**。「能点」和「能被找到」是两件事。
        box.accessibilityIdentifier = "wb.row" 
        box.tag = abs(it.id.hashValue % 1_000_000)
        idByTag[box.tag] = it.id
        return box
    }

    private var idByTag: [Int: String] = [:]

    /// `●●○` 或「熟了」。跟安卓、跟 Alex 同一个表示法。
    private func progress(_ it: WordBookCore.Item) -> String {
        if it.rev.done { return L.wb_graduated }
        let n = min(it.rev.n, 3)
        return String(repeating: "●", count: n)
            + String(repeating: "○", count: 3 - n)
    }

    // MARK: - 复习

    @objc private func tapReview() {
        queue = WordBookCore.due(WordBook.list(), today)
        qi = 0
        flipped = false
        showCard()
    }

    private func showCard() {
        mode = .review
        clearBody()
        guard qi < queue.count else {
            body.addArrangedSubview(label(L.wb_review_done, 18, Skin.text))
            body.addArrangedSubview(bigButton(L.wb_back, #selector(showListAction)))
            return
        }
        let it = queue[qi]

        // 顶栏：进度 + 换正面
        let pos = label("\(qi + 1) / \(queue.count)", 13, Skin.dim)
        let swap = UIButton(type: .system)
        // 🚨 显示**当前是哪一面**（"正面显示：中文"），点一下切换。
        //    格式串放资源里，**不在代码里拼标点** —— 安卓那边拼了个全角冒号，
        //    英文界面长出 "Card front：Chinese"。
        swap.setTitle(String(format: L.wb_front_fmt,
                             front == Self.frontZh ? L.wb_front_zh
                                                   : L.wb_front_en),
                      for: .normal)
        swap.setTitleColor(Skin.accentHi, for: .normal)
        swap.titleLabel?.font = .systemFont(ofSize: 13)
        swap.addTarget(self, action: #selector(tapSwapFront), for: .touchUpInside)
        let top = UIStackView(arrangedSubviews: [pos, swap])
        top.axis = .horizontal
        body.addArrangedSubview(top)

        let zhFront = front == Self.frontZh
        // 🚨 查词条目的 `zh` 是**空的**（身份只由词决定，释义只进 card）——
        //    中文面要从 card 里取首义，不然复习卡会是一片空白。
        let zhText = zhFace(it)
        let faceUp = zhFront ? zhText : it.en
        let faceDown = zhFront ? it.en : zhText

        let up = label(faceUp, 22, Skin.text)
        up.numberOfLines = 0
        body.addArrangedSubview(up)
        body.setCustomSpacing(30, after: up)

        if !flipped {
            body.addArrangedSubview(bigButton(L.wb_show, #selector(tapFlip)))
            return
        }
        let down = label(faceDown, 19, Skin.accentHi)
        down.numberOfLines = 0
        body.addArrangedSubview(down)
        body.setCustomSpacing(28, after: down)

        let no = smallButton(L.wb_missed, primary: false, #selector(tapMissed))
        let yes = smallButton(L.wb_got, primary: true, #selector(tapGot))
        let row = UIStackView(arrangedSubviews: [no, yes])
        row.axis = .horizontal
        row.spacing = 10
        row.distribution = .fillEqually
        row.heightAnchor.constraint(equalToConstant: 52).isActive = true
        body.addArrangedSubview(row)
    }

    @objc private func tapSwapFront() {
        setFront(front == Self.frontZh ? Self.frontEn : Self.frontZh)
        // 换了正面，这张卡重新盖上 —— 否则等于直接把答案亮给他。
        flipped = false
        showCard()
    }

    @objc private func tapFlip() {
        flipped = true
        showCard()
    }

    @objc private func tapGot() { answer(true) }
    @objc private func tapMissed() { answer(false) }

    private func answer(_ ok: Bool) {
        guard qi < queue.count else { return }
        WordBook.answer(id: queue[qi].id, ok: ok, today: today)
        qi += 1
        flipped = false
        showCard()
    }

    // MARK: - 详情

    @objc private func tapCard(_ g: UITapGestureRecognizer) {
        guard let tag = g.view?.tag, let id = idByTag[tag],
              let it = WordBook.list().first(where: { $0.id == id })
        else { return }
        showDetail(it)
    }

    private var detailId: String = ""

    private func showDetail(_ it: WordBookCore.Item) {
        mode = .detail
        detailId = it.id
        clearBody()
        // 🚨 **「你当时想说 · 语气」放最上面**（2.1 方案，Kevin 09-06 点名要求
        //    单词本这屏也照方案做）。这是**词典没有、我们独有**的一块：
        //    词典不知道用户为什么查一个词，我们知道 —— 他收藏它是因为
        //    当时想说这句话、用的是这个语气。
        //    🚨 `zh` 和 `tone` **本来就在 `Item` 里**，不用新存字段。
        //    原来这两样是分开两块、中间还隔着英文和收藏日期，看不出关联。
        let saidLine = originLine(it)
        if !saidLine.isEmpty {
            addLine(L.wb_zh, saidLine, 17, Skin.text)
        }
        addLine(L.wb_en, it.en, 18, Skin.accentHi)
        addLine(L.wb_on, String(format: L.wb_added_on, it.on), 15, Skin.dim)
        addLine(L.wb_progress_label,
                String(format: L.wb_progress, it.rev.n, it.rev.dayList.count),
                15, Skin.dim)

        renderCard(it)

        renderNote(it)

        // 🚨🚨 **方案 A：这里原来还有两根通栏条，已经拆掉**（Kevin 09-07 点头）。
        //    他的话是「这三个长条太丑了」。Grok 的判断（我同意）：
        //    丑的不是圆角也不是配色，是**三根同形同尺寸同权重的东西贴着底栏叠成一堵墙** ——
        //    几何完全一样，只靠红/紫区分，看着像三个广告位，不像三个不同级别的操作。
        //    · 「删掉这条」低频且破坏性 → 降权进导航栏右上 `⋯`（见 `installDetailMenu`）
        //    · 「返回」系统已经给了（左上角 chevron）→ **纯重复，删掉**
        //    · 只留「写笔记」，它才是这一屏唯一想让他点的东西
        //    剩的那根由 `renderNote` 画，规格见 `primaryButton`。
        installDetailMenu(it)
    }

    /// **我的笔记** —— 卡片上唯一由他自己写的东西。
    ///
    /// 🚨 **有没有笔记，这一段都要出现**。别的段落空了就不画（那是词典没给），
    ///    笔记不一样：不画的话他**根本不知道可以写** ——
    ///    昨晚存储层全做好了，他手机上却什么都没多，就是因为没有入口。
    ///    没写过时显示一句灰的引导语 + 「写笔记」；写过了显示正文 + 「编辑」。
    private func renderNote(_ it: WordBookCore.Item) {
        let note = WordCard.noteOf(it.card)
        let t = label(L.wb_note_title, 13, Skin.dim)
        t.accessibilityIdentifier = "wb.card.section"
        body.addArrangedSubview(t)
        let v = label(note.isEmpty ? L.wb_note_empty : note, 15,
                      note.isEmpty ? Skin.dim : Skin.text)
        v.accessibilityIdentifier = "wb.note.body"
        body.addArrangedSubview(v)
        let b = primaryButton(note.isEmpty ? L.wb_note_write : L.wb_note_edit,
                              #selector(tapEditNote))
        b.accessibilityIdentifier = "wb.note.edit"
        body.addArrangedSubview(b)
        // 与上面笔记文案 12pt（`body` 的 spacing 是 12，这里不用再加）；
        // 🚨 **与底栏至少 16pt** —— 原来 `body` 底部只留 20pt 到 scroll 底，
        //    而 scroll 铺到 view 底、底栏压在上面，看起来就是贴死的。
        //    这一条只在详情页加，列表页不受影响。
        let pad = UIView()
        pad.heightAnchor.constraint(equalToConstant: 16).isActive = true
        body.addArrangedSubview(pad)
    }

    @objc private func tapEditNote() {
        guard let it = WordBook.list().first(where: { $0.id == detailId })
        else { return }
        let vc = NoteEditViewController(
            word: it.en, note: WordCard.noteOf(it.card))
        vc.onSave = { [weak self] text in
            guard let self = self else { return }
            // 🚨 走 `WordCard.withNote` 改**这一个字段**，其余原样。
            //    别在这里重新拼一张卡 —— 那会把后端给的字段
            //    （音标/义项/例句）在他写一次笔记时全抹掉。
            WordBook.setCard(id: it.id,
                             card: WordCard.withNote(it.card, note: text))
            // 重画详情：拿改完的那一条，不是手上这个旧 `it`。
            if let fresh = WordBook.list().first(where: { $0.id == it.id }) {
                self.showDetail(fresh)
            }
        }
        let nav = UINavigationController(rootViewController: vc)
        present(nav, animated: true)
    }

    /// 这一条的中文面。
    ///
    /// 🚨 **查词条目的 `zh` 是空的**（2.1 09-06 规格：身份只由词决定，
    ///    释义/例句/搭配只进 `card`）。直接显示 `it.zh` 的话，
    ///    复习卡和列表会是一片空白 —— **看起来像数据丢了**。
    /// 🚨 **一个出口**：列表 / 详情 / 复习卡三处都走这里。
    ///    三处各写一次的话，改口径时必漏一个（今天已经栽过几次）。
    /// 「你当时想说」那一行 —— 原话 + 语气，拼成一句。
    ///
    /// 🚨 两样都可能为空：查词来的条目 `zh` 是空串（他没说话，是直接查的词），
    ///    语气也可能没选。**都空就整行不画**，不许留一个空标签在那儿。
    private func originLine(_ it: WordBookCore.Item) -> String {
        let said = zhFace(it)
        let tone = it.tone.trimmingCharacters(in: .whitespaces)
        if said.isEmpty { return tone.isEmpty ? "" : L.wb_tone + L.sep_colon + tone }
        if tone.isEmpty { return said }
        return said + L.sep_dot + L.wb_tone + L.sep_colon + tone
    }

    private func zhFace(_ it: WordBookCore.Item) -> String {
        if !it.zh.isEmpty { return it.zh }
        let c = WordCard.parse(it.card)
        return c.senses.first?.1 ?? ""
    }

    /// 画那张卡片。**空的就如实说"还没有"，不许画个空壳。**
    ///
    /// 🚨 Kevin 2026-09-06 连问三次「单词卡片在哪儿呢」。规格/契约/prompt/
    ///    三端同步链全做了，**就是没人去画这一屏**。
    /// 🚨 两种形态字段完全不同（查词 = 音标/释义/例句/搭配；
    ///    句子 = 结构拆解/替代表达/关键搭配），`WordCard.Parsed` 里
    ///    **用不上的那几组就是空的**，跳过即可。
    private func renderCard(_ it: WordBookCore.Item) {
        let c = WordCard.parse(it.card)
        // 🚨 **老卡片也要重取一次** —— 他手机上那张 commute 是今天早些时候存的，
        //    里面根本没有义项级词性。只判 `isEmpty` 的话，代码改对了、
        //    他打开老卡还是没有词性，然后会说"又没修好"。
        //    （这条是 0 点名"最容易漏"的那一条。）
        if c.isEmpty || needsRefetchForPos(c) {
            // 🚨 **点进去这一刻才取**（列表滚动绝不取 —— 那会为他根本没看的
            //    条目烧一堆请求）。取到存回，下次不重取。
            fetchCard(it)
            return
        }
        if !c.phonetic.isEmpty || !c.pos.isEmpty {
            // 🚨 卡片里存的是**收藏那一刻**的数据 —— 旧卡片带着斜杠，
            //    不剥就显示成 `//…//`（Kevin 2026-09-06 报的）。
            let ph = c.phonetic.trimmingCharacters(
                in: CharacterSet(charactersIn: "/ "))
            let head = [ph.isEmpty ? "" : "/" + ph + "/", c.pos]
                .filter { !$0.isEmpty }.joined(separator: "   ")
            body.addArrangedSubview(label(head, 14, Skin.dim))
        }
        // A · 查词 —— **按词性分节**，跟查词卡共用 `PosGrouping`。
        // 🚨 Kevin 2026-09-06：「单词本那个地方就只有一个动词」
        //    「连动词也没了，完全没标是动词还是名词」。
        //    两句是同一条链的前后两半：词性被当成整卡级的，而它是义项级的。
        // 🚨 **不写第二份分组代码** —— 今天「同一规矩两处实现」已经栽了四次。
        let poses = c.senses.map { $0.2 }
        var lines: [String] = []
        for (i, s) in c.senses.enumerated() {
            if let title = PosGrouping.sectionTitle(at: i, poses: poses) {
                lines.append(title)
            }
            lines.append(s.0.isEmpty ? s.1
                                     : (s.0 + (s.1.isEmpty ? "" : "\n" + s.1)))
        }
        section(L.wb_card_senses, lines)
        section(L.wb_card_examples, c.examples.map { e in
            e.0 + (e.1.isEmpty ? "" : "\n" + e.1)
        })
        section(L.wb_card_collocations, c.collocations)
        // B · 句子 / 词组
        section(L.wb_card_breakdown, c.breakdown.map { p in
            let head = p.part + (p.role.isEmpty ? "" : "  · " + p.role)
            return head + (p.note.isEmpty ? "" : "\n" + p.note)
        })
        section(L.wb_card_alternatives, c.alternatives.map { a in
            a.en + (a.when.isEmpty ? "" : "\n" + a.when)
        })
        section(L.wb_card_keys, c.keys.map { k in
            k.0 + (k.1.isEmpty ? "" : "  " + k.1)
        })
    }

    /// 这张**已存的**卡片需不需要重新取一次。
    ///
    /// 🚨 他手机上那张 commute 是今天早些时候存的，里面**根本没有义项级词性**。
    ///    代码改对了、他打开老卡还是没有词性 —— 然后会说"又没修好"。
    ///    所以：**卡片在、但一个义项词性都没有 → 重取**。
    ///    只对查词卡（`kind == "word"` 且有义项）成立，句子卡本来就没有词性。
    private func needsRefetchForPos(_ c: WordCard.Parsed) -> Bool {
        guard !c.senses.isEmpty else { return false }
        return !PosGrouping.hasAnyPos(c.senses.map { $0.2 })
    }

    /// 现取这一条的卡片。**只在详情页、只在没有卡片时（或缺词性时）调。**
    ///
    /// 🚨 **不许一直转圈**：转圈是没有终点的状态，他分不出「还在取」
    ///    和「已经死了」，只能干等或者退出去。失败要**落终态 + 给重试**。
    private func fetchCard(_ it: WordBookCore.Item) {
        let loading = label(L.wb_card_loading, 13, Skin.dim)
        loading.numberOfLines = 0
        body.addArrangedSubview(loading)

        // 🚨🚨 **单词走 `lookup`，句子才走 `card`。**
        //    Kevin 09-06：「这个单词没有例句，什么都没了呀！」——
        //    我当时把例句写进了**测试数据**，产品这条路一直没修。
        //    09-07 把种子换成真查，例句当场消失，才现形。
        //
        //    实测线上：`card` 问 commute 回的是
        //    `{"kind":"sentence","alternatives":[…],"keys":[]}` ——
        //    **没有音标、没有义项、没有例句**；
        //    而 `lookup` 回音标 + 义项 + 3 条例句。
        //    两屏"内容不一样"从来不是渲染问题，是**取数取错了接口**。
        //
        //    🚨 判据用现成的 `WordKind`，不新写一套 ——
        //    这摊活在"同一规则两处实现"上已经栽过好几次。
        if WordKind.of(it.en) == .word {
            Backend.lookup(it.en) { [weak self] r in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    guard self.mode == .detail, self.detailId == it.id else { return }
                    switch r {
                    case .success(let e):
                        // 🚨 笔记照旧要接住 —— 它是卡片上唯一不该被重取覆盖的字段。
                        WordBook.setCard(
                            id: it.id,
                            card: WordCard.merged(fromServer: WordCard.fromDict(e),
                                                  keepingNoteOf: it.card))
                        if let fresh = WordBook.list().first(where: { $0.id == it.id }) {
                            self.showDetail(fresh)
                        }
                    case .failure(let f):
                        KbBridge.note("取词条失败：\(f)")
                        loading.text = L.wb_card_failed
                        let again = self.bigButton(L.wb_card_retry,
                                                   #selector(self.tapRetryCard))
                        self.body.addArrangedSubview(again)
                    }
                }
            }
            return
        }
        Backend.card(en: it.en, zh: it.zh, tone: it.tone) { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // 🚨 **他可能已经翻走了**。回来时还停在这一条才重画 ——
                //    否则会把这条的卡片画到另一条的详情页上。
                //    （判据挂在 `detailId` 上，不是"这个页面还活着"。）
                guard self.mode == .detail, self.detailId == it.id else { return }
                switch r {
                case .success(let json):
                    // 🚨🚨 **重取会拿新数据整份替换这张卡，笔记必须先接住。**
                    //    `note` 是卡片上**唯一不是后端给的**字段 ——
                    //    不搬回去的话，他写的笔记会在某次重取时悄悄消失，
                    //    **不报错**，等他下次打开才发现，那时已经不知道何时丢的。
                    //    （2.1 方案原话：「这是卡片上唯一不会被重取覆盖的字段」）
                    WordBook.setCard(
                        id: it.id,
                        card: WordCard.merged(fromServer: json,
                                              keepingNoteOf: it.card))
                    // 重画整页 —— 取到之后这一条已经变了，
                    // 拿旧的 `it` 继续画会漏掉刚存进去的卡片。
                    if let fresh = WordBook.list().first(where: { $0.id == it.id }) {
                        self.showDetail(fresh)
                    }
                case .failure(let f):
                    KbBridge.note("取卡片失败：\(f)")
                    loading.text = L.wb_card_failed
                    let again = self.bigButton(L.wb_card_retry,
                                               #selector(self.tapRetryCard))
                    self.body.addArrangedSubview(again)
                }
            }
        }
    }

    /// 重试：**把这一条重新走一遍详情**，不另写一条取数路径。
    @objc private func tapRetryCard() {
        guard let it = WordBook.list().first(where: { $0.id == detailId })
        else { return }
        showDetail(it)
    }

    /// 卡片里的一段。🚨 **空的整段不出现** —— 先摆标题再填内容的话，
    /// 没数据时会留下一排孤零零的标题（2.1 的坏样本打的就是这个写法）。
    private func section(_ title: String, _ rows: [String]) {
        guard !rows.isEmpty else { return }
        let t = label(title, 13, Skin.dim)
        t.accessibilityIdentifier = "wb.card.section"
        body.addArrangedSubview(t)
        for r in rows {
            let l = label(r, 15, Skin.text)
            l.numberOfLines = 0
            l.accessibilityIdentifier = "wb.card.row"
            body.addArrangedSubview(l)
        }
    }

    @objc private func tapDelete() {
        // 🚨 删除要**能反悔**：他攒的东西，误触删掉找不回来。
        //    取消那一支**什么都不做**（`.cancel` 且不带 handler）——
        //    这正是 N4 那个 bug 的本质：只验"确认后删掉了"跟原来的 bug 兼容。
        let a = UIAlertController(title: nil, message: L.wb_delete_ask,
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: L.cancel, style: .cancel))
        a.addAction(UIAlertAction(title: L.wb_delete, style: .destructive) { _ in
            WordBook.remove(id: self.detailId)
            self.showList()
        })
        present(a, animated: true)
    }

    @objc private func showListAction() { showList() }

    /// 详情页的导航栏：右上 `⋯`，标题换成这个词本身。
    ///
    /// 🚨 **标题换成词**（Kevin 也点了头）：这一屏从头到尾没有出现过这个单词，
    ///    导航标题却写着「单词本」—— 用户会以为自己还在列表页。
    ///    音标上面空着的那一行本来就是词该在的位置。
    /// 🚨 删除**只放这一处**，不再在正文里留一根红条：
    ///    破坏性操作不该跟主操作同体积同实心（Grok 的四条规则之一）。
    private func installDetailMenu(_ it: WordBookCore.Item) {
        title = it.en.isEmpty ? L.wb_title : it.en
        let del = UIAction(title: L.wb_delete,
                           image: UIImage(systemName: "trash"),
                           attributes: .destructive) { [weak self] _ in
            // 🚨 复用现有的 `tapDelete` —— 那里已经有确认框，
            //    再写一个"确认"就是同一规矩两处实现，改的时候必漏一个。
            self?.tapDelete()
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: [del]))
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "wb.more"
    }

    /// 回列表时**必须把详情的导航栏收掉**。
    ///
    /// 🚨 不收的话：列表页顶上挂着上一条词的标题和一个 `⋯`，
    ///    而那个 `⋯` 里的「删掉这条」删的是 `detailId` —— **删的是他已经离开的那一条**。
    ///    这类残留在截图上完全看不出来（标题像是"当前分组"），
    ///    只有真去点才会出事。
    private func clearDetailMenu() {
        title = L.wb_title
        navigationItem.rightBarButtonItem = nil
    }

    // MARK: - 小工具

    private func label(_ s: String, _ size: CGFloat, _ c: UIColor) -> UILabel {
        let l = UILabel()
        l.text = s
        l.font = .systemFont(ofSize: size)
        l.textColor = c
        return l
    }

    private func addLine(_ lab: String, _ value: String,
                         _ size: CGFloat, _ c: UIColor) {
        let l = label(lab, 12, Skin.dim)
        body.addArrangedSubview(l)
        body.setCustomSpacing(4, after: l)
        let v = label(value, size, c)
        v.numberOfLines = 0
        body.addArrangedSubview(v)
        body.setCustomSpacing(18, after: v)
    }

    /// **唯一的主按钮**（方案 A）。数字是 Grok 定的，三端共用，别随手改：
    ///
    /// | 项 | 值 | 为什么 |
    /// |---|---|---|
    /// | 高度 | 48pt | 原来 52，三根并排时更显厚重 |
    /// | 圆角 | 12pt | 🚨 **不是全高胶囊** —— 全胶囊只适合单颗 FAB 或小 chip，
    ///                 三根并排就成了「糖豆广告」 |
    /// | 与上文 | 12pt | 跟笔记正文成一组 |
    /// | 与底栏 | ≥16pt | 🚨 原来贴死，底栏已经占一层，再贴一根就是"下面好挤" |
    ///
    /// 🚨 **同一屏最多一颗实心主色按钮**（Grok 四条规则之首）——
    ///    加第二颗之前先想清楚它是不是真的同级。
    private func primaryButton(_ t: String, _ sel: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(t, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        b.backgroundColor = Skin.accent
        b.layer.cornerRadius = 12
        b.addTarget(self, action: sel, for: .touchUpInside)
        b.heightAnchor.constraint(equalToConstant: 48).isActive = true
        return b
    }

    private func bigButton(_ t: String, _ sel: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(t, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16)
        b.backgroundColor = Skin.accent
        b.layer.cornerRadius = 14
        b.addTarget(self, action: sel, for: .touchUpInside)
        b.heightAnchor.constraint(equalToConstant: 52).isActive = true
        return b
    }

    private func smallButton(_ t: String, primary: Bool,
                             _ sel: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(t, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15)
        b.backgroundColor = primary ? Skin.accent
            : UIColor.white.withAlphaComponent(0.06)
        b.layer.cornerRadius = 14
        b.addTarget(self, action: sel, for: .touchUpInside)
        return b
    }
}
