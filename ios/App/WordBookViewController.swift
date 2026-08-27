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
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            body.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 20),
            body.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                          constant: 21),
            body.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                           constant: -21),
            body.bottomAnchor.constraint(equalTo: scroll.bottomAnchor,
                                         constant: -20),
        ])
        showList()
    }

    private func clearBody() {
        body.arrangedSubviews.forEach {
            body.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    // MARK: - 列表

    private func showList() {
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
            let warn = label(L.wb_nogroup, 13, Skin.danger)
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
        for it in all { body.addArrangedSubview(card(it)) }
    }

    /// 列表里的一条：进度点 + 中文原话 + 英文。
    private func card(_ it: WordBookCore.Item) -> UIView {
        let box = UIView()
        box.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        box.layer.cornerRadius = 14
        let col = UIStackView(arrangedSubviews: [
            label(progress(it), 11, Skin.accentHi),
            label(it.zh, 15, Skin.text),
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
        let faceUp = zhFront ? it.zh : it.en
        let faceDown = zhFront ? it.en : it.zh

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
        addLine(L.wb_zh, it.zh, 18, Skin.text)
        addLine(L.wb_en, it.en, 17, Skin.accentHi)
        if !it.tone.isEmpty { addLine(L.wb_tone, it.tone, 15, Skin.dim) }
        addLine(L.wb_on, String(format: L.wb_added_on, it.on), 15, Skin.dim)
        addLine(L.wb_progress_label,
                String(format: L.wb_progress, it.rev.n, it.rev.dayList.count),
                15, Skin.dim)

        let del = bigButton(L.wb_delete, #selector(tapDelete))
        del.backgroundColor = Skin.danger
        body.addArrangedSubview(del)
        body.addArrangedSubview(bigButton(L.wb_back, #selector(showListAction)))
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
