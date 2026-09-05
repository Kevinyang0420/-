import UIKit

// 🚨🚨 2026-09-03 配色跟宿主外观分叉之后，本文件**必须用 `Theme.kb*`**，
//    不能再用 `Theme.key` / `Theme.text` / `Theme.dim`（那三个是**深色专用**的）。
//    Kevin 当天的原话：「你改完颜色，你要知道这是牵一发动全身的，每个地方都要看一下。
//    你现在键盘的颜色淡成什么样子了？别人能用吗？」
//    —— 我当时只换了 `KeyboardViewController.swift`，本文件漏了，于是
//    半透明白键 + 近白文字压在浅紫面板上，基本看不见。
//    这是「同一规矩散在多个文件，改一处等于没改」那一族。

/// 候选栏。**逐行照搬安卓 `TypingKeyboard.java` 的 `paintPage` / `pageButton`。**
///
/// 结构（Kevin 2026-08-23 定的那一版，别改回去）：
/// - 没打字：左边 `中` / `EN` 两个 chip
/// - 一打字：**chips 整体让位，整行都给候选**
/// - 拼音串**不在这里显示** —— 它走输入框的 marked text（安卓那边是
///   `setComposingText`）。他原话：「拼音那一栏显示字母，文本框里也显示字母，
///   就重复了」。
/// - 候选**分页，不滚动**。滚动内容会画到边界外盖住左边（他连提两次），
///   靠裁剪修不牢 —— 结构上不存在"滚出去的内容"才是根治。
final class CandidateBar: UIView {

    /// 候选尺寸的**唯一配置点**，值照抄安卓同名常量。
    enum K {
        static let w1: CGFloat = 34       // 单字候选宽
        static let wn: CGFloat = 18       // 每多一个字加多少
        static let wmax: CGFloat = 110    // 封顶（码表最长 4 字）
        static let margin: CGFloat = 3    // 候选左右各留
        static let moreW: CGFloat = 26    // 翻页键宽
        static let h: CGFloat = 34        // 候选/翻页键高
        static let chipW: CGFloat = 46
        static let candFont: CGFloat = 17
        static let pageFont: CGFloat = 16
    }

    /// 点了某个候选
    var onPick: ((String) -> Void)?
    /// 点了 中 / EN 芯片
    var onMode: ((Bool) -> Void)?      // true = 中文

    private var cands: [String] = []
    /// 当前这一页从第几个候选开始。**不是页号** —— 每页个数按宽度算，不固定。
    private var from = 0
    /// 本页实际画了几个。翻页要靠它算下一页起点。
    private var shown = 0
    /// 每一页的起始下标。◂ 靠它回退 —— **每页个数不固定，反推不出来**
    /// （`from - 上页个数` 是错的：上页放几个取决于那些候选各自多宽）。
    private var pageStack: [Int] = [0]
    private var chinese = true

    /// 右端固定键（九宫格态的 `←` / `⌫`）。空数组 = 不显示。
    ///
    /// 🚨 尺寸跟中/EN 芯片**共用 `K.chipW` / `K.h`**，别再来一套量法 ——
    ///    Kevin 点名过「语音波纹键和中/EN 切换键的方格大小不一致」。
    var topKeys: [(String, () -> Void)] = [] {
        didSet { rebuildTopKeys() }
    }
    private var topKeyViews: [UIButton] = []

    /// 点了左上角的波形键 = 去语音面板。
    /// 🚨 安卓待命态候选栏左起就是这个键（真机截图 `_kb_idle.png`），
    ///    它是**打字 → 语音**的唯一入口。
    var onVoice: (() -> Void)?

    private let voiceBtn = UIButton(type: .system)
    private let chipZh = UIButton(type: .system)
    private let chipEn = UIButton(type: .system)
    private var candViews: [UIView] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        for (b, t) in [(chipZh, L.kb_chip_zh), (chipEn, "EN")] {
            b.setTitle(t, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 15)
            b.layer.cornerRadius = Theme.rKey
            addSubview(b)
        }
        // 波形键。安卓那个是画出来的声波图标，这里用同一套画法
        // （`Theme.waveIcon`），别用 emoji —— 系统 emoji 在深色底上发灰。
        voiceBtn.setImage(Theme.waveIcon(color: Theme.kbKeyText), for: .normal)
        voiceBtn.tintColor = Theme.kbKeyText
        voiceBtn.backgroundColor = Theme.kbKey
        voiceBtn.layer.cornerRadius = Theme.rKey
        voiceBtn.addAction(UIAction { [weak self] _ in self?.onVoice?() },
                           for: .touchUpInside)
        addSubview(voiceBtn)

        // 🚨 给端到端测试**按类型的锚点**：按文字「中」「英」找会随文案/界面语言变，
        //    而这两个键正是验「英文档下左下角那个输入法键该消失」的入口。
        chipZh.accessibilityIdentifier = "kb.chip.zh"
        chipEn.accessibilityIdentifier = "kb.chip.en"
        chipZh.addTarget(self, action: #selector(tapZh), for: .touchUpInside)
        chipEn.addTarget(self, action: #selector(tapEn), for: .touchUpInside)
        refreshChips()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 对外

    /// 换一批候选：**重置到第一页再画**。
    func setCandidates(_ list: [String]) {
        cands = list
        from = 0
        shown = 0
        pageStack = [0]
        setNeedsLayout()
    }

    /// 有没有在打字。打字时 chips 让位，整行给候选。
    var typing: Bool { !cands.isEmpty }

    func setChinese(_ v: Bool) {
        chinese = v
        refreshChips()
    }

    // MARK: - 排版

    override func layoutSubviews() {
        super.layoutSubviews()
        candViews.forEach { $0.removeFromSuperview() }
        candViews.removeAll()

        let showChips = !typing
        chipZh.isHidden = !showChips
        chipEn.isHidden = !showChips
        // 🚨 波形键跟芯片一起让位。安卓也是"一打字整行都给候选"
        //    （Kevin 2026-08-23：「返回那一行是不是可以再放字了？
        //    这样就不需要这么高了。人要灵活一点。」）
        voiceBtn.isHidden = !showChips

        let y = (bounds.height - K.h) / 2
        var x: CGFloat = K.margin

        // 右端固定键先摆，候选区的可用宽度要扣掉它们
        var rightEdge = bounds.width - K.margin
        for b in topKeyViews.reversed() {
            b.frame = CGRect(x: rightEdge - K.chipW, y: y,
                             width: K.chipW, height: K.h)
            rightEdge -= K.chipW + K.margin * 2
        }
        if showChips {
            // 🚨 尺寸跟芯片**共用 K.chipW / K.h**。他点名过
            //    「语音波纹键和中/EN 切换键的方格大小不一致」。
            voiceBtn.frame = CGRect(x: x, y: y, width: K.chipW, height: K.h)
            x += K.chipW + 6
            chipZh.frame = CGRect(x: x, y: y, width: K.chipW, height: K.h)
            x += K.chipW + 6
            chipEn.frame = CGRect(x: x, y: y, width: K.chipW, height: K.h)
            x += K.chipW + 8
            return
        }

        // 🚨 可用宽度直接取**自己的 bounds**。安卓那边要绕开
        //    「candWrap.getWidth() 是上一次布局量的」那个坑（表现是
        //    "打第一个字母只出 4 个候选，点一下右键才出一排"）；
        //    iOS 在 layoutSubviews 里 bounds 已经是当前值，天然没有这个问题。
        let total = cands.count
        if total == 0 { return }
        if from >= total {
            // 🚨 `from` 和 `pageStack` 是**同一件事的两半**，只重置一个
            //    就是两个状态各活各的：候选从 10 个变 3 个时 `from` 归零了、
            //    `pageStack` 里还留着 [0, 5]，点 ◂ 会跳回一个越界的位置。
            from = 0
            pageStack = [0]
        }

        // 🚨 有右就要有左（他：「每次想往左边选，就要一直往右点点点点，
        //    最后才能够点回头吗？」）。◂ **只在不是第一页时出现** ——
        //    第一页仍是满满一排候选。
        let canBack = from > 0
        let keys = (K.moreW + K.margin * 2)
            + (canBack ? (K.moreW + K.margin * 2) : 0)
        // 🚨 用 `rightEdge` 不是 `bounds.width`：九宫格态右端还站着 ← / ⌫，
        //    按整宽算的话候选会画到它们底下。
        let avail = rightEdge - K.margin - x - keys

        if canBack {
            let b = pageButton("◂", forward: false)
            b.frame = CGRect(x: x, y: y, width: K.moreW, height: K.h)
            addSubview(b)
            candViews.append(b)
            x += K.moreW + K.margin * 2
        }

        var used: CGFloat = 0
        var n = 0
        // 🚨 一页放几个是**量出来的**，不是写死 4 个。码表里有「阿富汗」
        //    「葡萄牙人」这类 3–4 字词，定宽只装得下两个汉字，
        //    多字词被截掉后**看起来仍像正常候选**，点下去上屏的却是完整词。
        for i in from..<total {
            let w = candWidth(cands[i])
            if n > 0 && used + w + K.margin * 2 > avail { break }
            used += w + K.margin * 2
            n += 1
            let b = candButton(cands[i])
            b.frame = CGRect(x: x, y: y, width: w, height: K.h)
            addSubview(b)
            candViews.append(b)
            x += w + K.margin * 2
        }
        shown = n

        let hasMore = (from + n) < total || from > 0
        if hasMore {
            let b = pageButton((from + n) < total ? "▸" : "↺", forward: true)
            b.frame = CGRect(x: rightEdge - K.moreW, y: y,
                             width: K.moreW, height: K.h)
            addSubview(b)
            candViews.append(b)
        }
    }

    /// 一个候选要多宽。单字 34，每多一字加 18，封顶 110。
    private func candWidth(_ s: String) -> CGFloat {
        let n = CGFloat(max(1, s.count))
        return min(K.w1 + (n - 1) * K.wn, K.wmax)
    }

    // MARK: - 造件

    private func candButton(_ s: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(s, for: .normal)
        b.setTitleColor(Theme.kbKeyText, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: K.candFont)
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.minimumScaleFactor = 0.7
        b.backgroundColor = Theme.kbKey
        b.layer.cornerRadius = Theme.rKey
        b.addAction(UIAction { [weak self] _ in self?.onPick?(s) },
                    for: .touchUpInside)
        return b
    }

    private func pageButton(_ label: String, forward: Bool) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(label, for: .normal)
        b.setTitleColor(Theme.kbHint, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: K.pageFont)
        b.backgroundColor = Theme.kbKey
        b.layer.cornerRadius = Theme.rKey
        b.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            if forward {
                // 下一页起点 = 本页起点 + 本页放了几个。
                // 🚨 `shown` 必须 >0，否则点一下不动 = 死循环给他看。
                let next = self.from + max(1, self.shown)
                if next >= self.cands.count {          // 到底了，绕回第一页
                    self.pageStack = [0]
                    self.from = 0
                } else {
                    self.pageStack.append(next)
                    self.from = next
                }
            } else {
                if self.pageStack.count > 1 { self.pageStack.removeLast() }
                self.from = self.pageStack.last ?? 0
            }
            self.setNeedsLayout()
        }, for: .touchUpInside)
        return b
    }

    private func rebuildTopKeys() {
        topKeyViews.forEach { $0.removeFromSuperview() }
        topKeyViews.removeAll()
        for (title, act) in topKeys {
            let b = UIButton(type: .system)
            b.setTitle(title, for: .normal)
            b.setTitleColor(Theme.kbKeyText, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 18)
            b.backgroundColor = Theme.kbKey
            b.layer.cornerRadius = Theme.rKey
            b.addAction(UIAction { _ in act() }, for: .touchUpInside)
            addSubview(b)
            topKeyViews.append(b)
        }
        setNeedsLayout()
    }

    private func refreshChips() {
        chipZh.backgroundColor = chinese ? Theme.accent : Theme.kbKey
        chipZh.setTitleColor(chinese ? .white : Theme.kbHint, for: .normal)
        chipEn.backgroundColor = chinese ? Theme.kbKey : Theme.accent
        chipEn.setTitleColor(chinese ? Theme.kbHint : .white, for: .normal)
    }

    @objc private func tapZh() { onMode?(true) }
    @objc private func tapEn() { onMode?(false) }
}
