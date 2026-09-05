import UIKit

/// **查词页**（Kevin 2026-09-05：「看到英文单词想查是什么意思，目前没有入口」）。
///
/// 版式照 2.1 出的 `D:\_tmp_ui\dict_page_v3.png`（Grok 审过 v2→v3 七处）。
/// 🚨 **版式不是我设计的，是照稿子做的** —— 有已批的图就照抄，别自己发挥。
///
/// 🚨 Grok 那七条里最容易做丢的是**第 ④ 条：组间距 > 行间距**。
///    它的原话：「英中是一对，三条是三组 —— 现在看不出组边界」。
///    所以下面把两个间距写成**命名常量**并注明来源，不散在各处 magic number 里。
final class DictViewController: UIViewController {

    // MARK: - 版式常量（全部来自 v3 稿，改之前先回去看图）

    /// 组与组之间（义项 1 / 2 / 3 之间、例句与搭配之间）。
    private static let gapGroup: CGFloat = 46
    /// 一组之内的行距（英文释义 ↔ 中文对译）。
    private static let gapLine: CGFloat = 19
    /// 主按钮上边距 —— Grok ⑥：「和搭配芯片贴得近，扫一眼会觉得芯片也是操作区」。
    private static let gapCta: CGFloat = 30

    private let scroll = UIScrollView()
    private let col = UIStackView()
    private let field = UITextField()
    private let micBtn = UIButton(type: .custom)
    private let card = UIView()
    private let cardCol = UIStackView()
    private let recentTitle = UILabel()
    private let recentRow = UIStackView()

    private var current: DictEntry?
    private var addBtn: UIButton?
    private let voice = Voice()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.dict_title
        UI.paintBg(self)
        build()
        renderRecent()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    // MARK: - 搭架子

    private func build() {
        // ── 检索条：一个框 + 一个麦克风 ─────────────────────────
        // 🚨 **麦克风只有一个键**：说单词和拼字母走同一个键。
        //    2.1 规格原话：「不要做『说词/拼写』两个模式让他选 ——
        //    他不该在按之前就知道自己要用哪种」。后端拿到音频自己判断。
        field.placeholder = L.dict_hint
        field.font = .systemFont(ofSize: 16)
        field.textColor = Theme.text
        field.backgroundColor = Theme.panel
        field.layer.cornerRadius = 14
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .search
        field.delegate = self
        field.accessibilityIdentifier = "dict.field"
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 14, height: 1))
        field.leftViewMode = .always
        field.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(field)

        micBtn.backgroundColor = Theme.accent
        micBtn.layer.cornerRadius = 21
        Theme.setMicGlyph(micBtn, side: 60)   // 🚨 走唯一出口，不自己乘系数
        micBtn.tintColor = .white
        micBtn.accessibilityIdentifier = "dict.mic"
        micBtn.addTarget(self, action: #selector(tapMic), for: .touchUpInside)
        micBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(micBtn)

        // ── 结果卡 ──────────────────────────────────────────
        card.backgroundColor = Theme.panel
        card.layer.cornerRadius = 18
        card.layer.borderWidth = 0.6
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        card.isHidden = true
        card.translatesAutoresizingMaskIntoConstraints = false

        cardCol.axis = .vertical
        cardCol.alignment = .fill
        cardCol.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardCol)

        // ── 「最近查过」：**在卡片外**（Grok ⑦：形态相近会串层级）──
        recentTitle.text = L.dict_recent
        recentTitle.font = .systemFont(ofSize: 12, weight: .semibold)
        recentTitle.textColor = Theme.dim
        recentTitle.accessibilityIdentifier = "dict.recent.title"
        recentRow.axis = .horizontal
        recentRow.spacing = 8
        recentRow.alignment = .leading

        col.axis = .vertical
        col.alignment = .fill
        col.spacing = 14
        col.translatesAutoresizingMaskIntoConstraints = false
        col.addArrangedSubview(card)
        col.addArrangedSubview(recentTitle)
        col.addArrangedSubview(recentRow)
        col.setCustomSpacing(28, after: card)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .onDrag
        scroll.addSubview(col)
        view.addSubview(scroll)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: g.topAnchor, constant: 12),
            field.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            field.heightAnchor.constraint(equalToConstant: 46),
            micBtn.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 12),
            micBtn.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            micBtn.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            micBtn.widthAnchor.constraint(equalToConstant: 42),
            micBtn.heightAnchor.constraint(equalToConstant: 42),

            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: g.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: g.bottomAnchor),

            col.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            col.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor,
                                        constant: -24),
            col.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor,
                                         constant: 16),
            col.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor,
                                          constant: -16),

            cardCol.topAnchor.constraint(equalTo: card.topAnchor, constant: 20),
            cardCol.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
            cardCol.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            cardCol.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
        ])
    }

    // MARK: - 查询

    /// 🚨 **离线样本开关**（`TRANSLESS_DICT_FAKE=1`）。
    ///
    /// 判据 2（take 只出 3 条）、6（二次查无网络）、7（中→英不是整句翻译）
    /// **都不该依赖真后端**：后端抖一下用例就红，而那个红**看不出根因**
    /// —— 今天已经因为"红得像功能坏了"浪费过好几轮。
    /// 注入的是**输入数据**，被测的截断/缓存/渲染一行都没被碰。
    private func fakeEntry(_ w: String) -> DictEntry? {
        guard ProcessInfo.processInfo.environment["TRANSLESS_DICT_FAKE"] == "1"
        else { return nil }
        let key = DictStore.key(w)
        if key == "take" {
            // 🚨 坏样本：**故意给 8 条**，验截断真的在做事。
            //    常用词给 3 条的话，"只出 3 条"在没做截断时也成立 —— 那是假检查。
            let many = (1...8).map {
                DictSense(en: "sense number " + String($0),
                          zh: "第 " + String($0) + " 个义项",
                          register: $0 == 3 ? "formal" : "")
            }
            return DictEntry(word: "take", phonetic: "teɪk", pos: "v.",
                             senses: many,
                             exampleEn: "Take your time.", exampleZh: "慢慢来。",
                             collocations: ["take issue with", "take over"])
        }
        if key == "报价" {
            return DictEntry(word: "quote", phonetic: "kwəʊt", pos: "n./v.",
                             senses: [
                                DictSense(en: "a stated price for a job or service",
                                          zh: "报价；开价", register: ""),
                                DictSense(en: "quotation - the formal written form",
                                          zh: "报价单（正式书面）", register: "formal"),
                             ],
                             exampleEn: "Could you send me a quote?",
                             exampleZh: "能发我一份报价吗？",
                             collocations: ["request a quote", "quote a price"])
        }
        return DictEntry(word: w, phonetic: "juːˈbɪkwɪtəs", pos: "adj.",
                         senses: [
                            DictSense(en: "present or found everywhere",
                                      zh: "无处不在的；普遍存在的", register: ""),
                            DictSense(en: "seeming to appear in many places at once",
                                      zh: "（某物）随处可见的", register: ""),
                            DictSense(en: "pervasive; omnipresent",
                                      zh: "遍布各处的", register: "formal"),
                         ],
                         exampleEn: "Smartphones are now ubiquitous.",
                         exampleZh: "智能手机现在随处可见。",
                         collocations: ["ubiquitous presence", "become ubiquitous"])
    }

    func search(_ raw: String) {
        let w = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return }

        if let f = fakeEntry(w) {
            // 🚨 注入也要**走同一条截断和缓存**，否则测的就不是真链路了。
            let cut = f.trimmed()
            DictStore.put(cut)
            render(cut)
            return
        }
        Backend.lookup(w) { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch r {
                case .success(let e): self.render(e)
                case .failure(let f): self.toastErr(f.userText)
                }
            }
        }
    }

    private func toastErr(_ t: String) {
        let l = UILabel()
        l.text = t
        l.font = .systemFont(ofSize: 14)
        l.textColor = Theme.text
        l.textAlignment = .center
        l.numberOfLines = 0
        l.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        l.layer.cornerRadius = 12
        l.clipsToBounds = true
        l.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            l.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,
                                      constant: -40),
            l.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
            l.heightAnchor.constraint(greaterThanOrEqualToConstant: 40),
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { l.removeFromSuperview() }
    }

    // MARK: - 渲染结果卡（Grok v3 的七条都落在这一个函数里）

    private func render(_ e: DictEntry) {
        current = e
        cardCol.arrangedSubviews.forEach { $0.removeFromSuperview() }
        card.isHidden = false

        // ① 词头 + 音标+朗读 **收成一组、紧贴词头**
        //    Grok：「音标是仅次于词头的第二锚点，现在夹在中间、字号行高都偏注释」
        let head = UILabel()
        head.text = e.word
        head.font = .systemFont(ofSize: 30, weight: .bold)
        head.textColor = Theme.text
        head.accessibilityIdentifier = "dict.word"
        cardCol.addArrangedSubview(head)

        let ph = UIButton(type: .system)
        // 🚨 喇叭用 `Theme.speakGlyph` 这张**自己画的单色图**，不是 emoji 🔊。
        //    Theme.swift:302 那段注释写着：🔊 是彩色 emoji，`tintColor` 管不到，
        //    Kevin 2026-08-22 点名「跟这个紫色调有点冲」。我刚才差点又用它。
        ph.setTitle("/" + e.phonetic + "/", for: .normal)
        ph.setImage(Theme.speakGlyph(15).withRenderingMode(.alwaysTemplate), for: .normal)
        ph.tintColor = Theme.dim
        ph.semanticContentAttribute = .forceRightToLeft   // 图标放文字右边
        ph.imageEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 0)
        ph.titleLabel?.font = .systemFont(ofSize: 13)
        ph.setTitleColor(Theme.dim, for: .normal)
        ph.contentEdgeInsets = UIEdgeInsets(top: 5, left: 10, bottom: 5, right: 10)
        ph.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        ph.layer.cornerRadius = 12
        ph.accessibilityIdentifier = "dict.phonetic"
        ph.addTarget(self, action: #selector(tapSpeak), for: .touchUpInside)
        let phRow = UIStackView(arrangedSubviews: [ph, UIView()])
        phRow.axis = .horizontal
        cardCol.addArrangedSubview(phRow)
        cardCol.setCustomSpacing(6, after: head)
        cardCol.setCustomSpacing(28, after: phRow)

        // ② 词性作**一次**小标题（不是每行前缀）
        let pos = UILabel()
        pos.text = e.pos
        pos.font = .systemFont(ofSize: 13, weight: .bold)
        pos.textColor = Theme.accent
        cardCol.addArrangedSubview(pos)
        cardCol.setCustomSpacing(14, after: pos)

        // ③④ 义项：编号 + 英文在上中文在下；**组间距 46 > 行间距 19**
        //     Grok：「英中是一对，三条是三组 —— 现在看不出组边界」
        for (i, sn) in e.senses.enumerated() {
            // ⑤ 带用法标注的那条**降一级**
            let row = senseRow(no: i + 1, sense: sn, minor: !sn.register.isEmpty)
            cardCol.addArrangedSubview(row)
            cardCol.setCustomSpacing(Self.gapGroup, after: row)
        }

        // ⑥ 例句 / 搭配 各加微型标题
        cardCol.addArrangedSubview(microTitle(L.dict_example))
        let ex = UILabel()
        ex.numberOfLines = 0
        ex.attributedText = pair(e.exampleEn, e.exampleZh, minor: false)
        cardCol.addArrangedSubview(ex)
        cardCol.setCustomSpacing(Self.gapGroup, after: ex)

        cardCol.addArrangedSubview(microTitle(L.dict_collocation))
        let chips = UIStackView(arrangedSubviews:
            e.collocations.prefix(3).map { chip($0, outlined: false) } + [UIView()])
        chips.axis = .horizontal
        chips.spacing = 8
        cardCol.addArrangedSubview(chips)

        // ⑦ 主按钮上边距 30
        cardCol.setCustomSpacing(Self.gapCta, after: chips)
        let add = UIButton(type: .custom)
        add.backgroundColor = Theme.accent
        add.layer.cornerRadius = 22
        add.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        add.setTitleColor(.white, for: .normal)
        add.accessibilityIdentifier = "dict.add.wordbook"
        add.addTarget(self, action: #selector(tapAdd), for: .touchUpInside)
        add.heightAnchor.constraint(equalToConstant: 44).isActive = true
        cardCol.addArrangedSubview(add)
        addBtn = add
        paintAdd()
        renderRecent()
    }

    private func senseRow(no: Int, sense: DictSense, minor: Bool) -> UIView {
        let n = UILabel()
        n.text = String(no)
        n.font = .systemFont(ofSize: 12, weight: .bold)
        n.textColor = minor ? Theme.dim.withAlphaComponent(0.6) : Theme.dim
        n.setContentHuggingPriority(.required, for: .horizontal)
        n.widthAnchor.constraint(equalToConstant: 16).isActive = true

        let body = UILabel()
        body.numberOfLines = 0
        let en = sense.register.isEmpty
            ? sense.en
            : "(" + sense.register + ") " + sense.en
        body.attributedText = pair(en, sense.zh, minor: minor)
        let row = UIStackView(arrangedSubviews: [n, body])
        row.axis = .horizontal
        row.alignment = .top
        row.spacing = 6
        return row
    }

    /// 英文行 + 中文行 —— **行距按 `gapLine` 算**，跟组间距拉开一档。
    private func pair(_ en: String, _ zh: String, minor: Bool) -> NSAttributedString {
        let big: CGFloat = minor ? 14 : 15
        let small: CGFloat = minor ? 13 : 14
        let strong = minor ? Theme.dim.withAlphaComponent(0.7) : Theme.text
        let weak = minor ? Theme.dim.withAlphaComponent(0.6) : Theme.dim
        let para = NSMutableParagraphStyle()
        para.lineSpacing = max(2, Self.gapLine - big)
        let out = NSMutableAttributedString(
            string: en + "\n",
            attributes: [.font: UIFont.italicSystemFont(ofSize: big),
                         .foregroundColor: strong, .paragraphStyle: para])
        out.append(NSAttributedString(
            string: zh,
            attributes: [.font: UIFont.systemFont(ofSize: small),
                         .foregroundColor: weak, .paragraphStyle: para]))
        return out
    }

    private func microTitle(_ t: String) -> UILabel {
        let l = UILabel()
        l.text = t
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        l.textColor = Theme.dim
        l.accessibilityIdentifier = "dict.micro"
        return l
    }

    /// 芯片。`outlined` = 卡外「最近查过」那种：**描边不填充、更扁**
    /// （Grok ⑦：形态相近、语义层不同，层级会串）。
    private func chip(_ t: String, outlined: Bool) -> UIView {
        let b = UIButton(type: .system)
        b.setTitle(t, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: outlined ? 13 : 14)
        b.setTitleColor(outlined ? Theme.dim : Theme.text, for: .normal)
        b.contentEdgeInsets = UIEdgeInsets(top: outlined ? 4 : 7, left: 12,
                                           bottom: outlined ? 4 : 7, right: 12)
        b.layer.cornerRadius = outlined ? 11 : 14
        if outlined {
            b.layer.borderWidth = 0.8
            b.layer.borderColor = UIColor.white.withAlphaComponent(0.22).cgColor
            b.backgroundColor = .clear
            b.accessibilityIdentifier = "dict.recent.chip"
            b.addTarget(self, action: #selector(tapRecent(_:)), for: .touchUpInside)
        } else {
            b.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        }
        return b
    }

    private func renderRecent() {
        recentRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let ws = DictStore.recent()
        recentTitle.isHidden = ws.isEmpty
        for w in ws.prefix(3) { recentRow.addArrangedSubview(chip(w, outlined: true)) }
        recentRow.addArrangedSubview(UIView())
    }

    @objc private func tapRecent(_ b: UIButton) {
        guard let w = b.title(for: .normal), let e = DictStore.cached(w) else { return }
        field.text = e.word
        render(e)
    }

    @objc private func tapSpeak() {
        guard let w = current?.word else { return }
        // 🚨 发音**复用现有 TTS 链**（Backend.speak 到 Speaker.play），别新接一个。
        Backend.speak(text: w) { r in
            DispatchQueue.main.async {
                if case .success(let mp3) = r { Speaker.play(mp3) { _ in } }
            }
        }
    }

    // MARK: - 加入单词本

    private func paintAdd() {
        guard let b = addBtn, let e = current else { return }
        let added = WordBook.list().contains { $0.id == wbId(e) }
        b.setTitle(added ? L.wb_added : L.wb_add, for: .normal)
        b.backgroundColor = added ? UIColor.white.withAlphaComponent(0.10) : Theme.accent
        b.setTitleColor(added ? Theme.dim : .white, for: .normal)
    }

    /// 🚨 身份走**唯一那个 id 算法**（随手翻译 / 说话记录 / 面对面都是它）。
    private func wbId(_ e: DictEntry) -> String {
        WordBookCore.idOf(e.word, e.senses.first?.zh ?? "")
    }

    @objc private func tapAdd() {
        guard let e = current else { return }
        let id = wbId(e)
        if WordBook.list().contains(where: { $0.id == id }) {
            WordBook.remove(id: id)
        } else {
            _ = WordBook.add(zh: e.word, en: e.senses.first?.zh ?? "",
                             span: "full", tone: "", today: Srs.todayString())
        }
        // 🚨 重画前读盘，不拿本地布尔取反（写失败时界面照样变，他会以为收进去了）
        paintAdd()
    }

    @objc private func tapMic() {
        if voice.running {
            voice.stop(keepSession: false)
            micBtn.backgroundColor = Theme.accent
            return
        }
        guard !AudioGate.off else { return }      // 模拟器上音频会 abort
        // 🚨🚨 **起录前必须先停朗读**（2.1 2026-09-05 用闸门抓到，我这处是第四个出口）。
        //    查词页是最容易撞上的一屏：🔊 和麦克风在同一张卡上，
        //    标准动线就是「点 🔊 听一遍 → 接着按麦克风查下一个词」。
        //    不停的话：① 刚播的发音会被录进去；
        //    ② 更麻烦 —— `Speaker.play` 已经把会话切成播放类别，
        //       起录会带着一个**被我们自己搞坏的会话**去开引擎，
        //       报出来的 stage/code 会长得像「扩展不能录音」，**把根因结论打偏**。
        //    这条规矩已经在三个出口上各漏过一次，形态是「规矩要按每个出口落地」。
        Speaker.stop()
        micBtn.backgroundColor = Theme.danger
        voice.start(onPartial: { _ in }, onUtterance: nil, onWav: { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.micBtn.backgroundColor = Theme.accent
                guard case .success(let wav) = r else { return }
                // 🚨 参数形状**照 Backend.swift:1177 抄** —— transcribe 只吃 wav，
                //    没有 mode/tone/lang。我第一版凭印象加了三个参数。
                Backend.transcribe(wav: wav) { t in
                    DispatchQueue.main.async {
                        guard case .success(let text) = t else { return }
                        // 🚨 说单词 / 拼字母**走同一个键**，判断在 `SpellFold`。
                        //    做成两个模式让他选是错的（2.1：他不该在按之前
                        //    就知道自己要用哪种）。
                        let w = SpellFold.fold(text)
                        self.field.text = w
                        self.search(w)
                    }
                }
            }
        })
    }
}

extension DictViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ tf: UITextField) -> Bool {
        tf.resignFirstResponder()
        search(tf.text ?? "")
        return true
    }
}
