import UIKit

/// 说话记录**详情**（iOS）—— 照 `pc_detail_confirm.png` 的结构（2.1 定，Kevin 点头）：
/// 时间 + 档位 chip → 你说的(原话) → 译文(按档上色) → 复制译文 → 再发一次。
///
/// 🚨 手机端复制走**复制按钮**（不是 Ctrl+C）；「再发一次」= 拿原话重译成**新的一条**
///    （App 不在输入法会话里，没有输入框可插；跟安卓 `HistoryActivity.resend` 同口径）。
final class HistoryDetailViewController: UIViewController {

    private let item: History.Item
    private var resendBtn: UIButton?

    init(item: History.Item) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.hist_screen_title
        UI.paintBg(self)

        let color = HistoryUI.modeColor(item.mode)
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let col = UIStackView()
        col.axis = .vertical
        col.spacing = 12
        col.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(col)

        // 头：时间 + 档位 chip
        let head = UIStackView()
        head.axis = .horizontal
        head.spacing = 10
        head.alignment = .center
        let time = UILabel()
        time.text = HistoryUI.timeLabel(item.ts)
        time.font = .systemFont(ofSize: 13)
        time.textColor = Theme.dim
        head.addArrangedSubview(time)
        head.addArrangedSubview(HistoryUI.chip(HistoryUI.modeChip(item.mode), color: color))
        let headSpacer = UIView()
        headSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        head.addArrangedSubview(headSpacer)
        col.addArrangedSubview(head)

        // 你说的（原话）
        col.addArrangedSubview(sectionLabel(L.hist_d_orig))
        col.addArrangedSubview(box(item.zh, color: Theme.text, selectable: true))

        // 译文（按档上色）
        col.addArrangedSubview(sectionLabel(L.hist_d_out))
        col.addArrangedSubview(box(item.out, color: color, selectable: true))

        // 复制译文
        let copy = filledButton(L.hist_copy, bg: Theme.key, fg: Theme.text)
        copy.addTarget(self, action: #selector(tapCopy), for: .touchUpInside)
        col.addArrangedSubview(copy)

        // 再发一次（只有原话在才给 —— 没原话无从重翻）
        if !item.zh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let rs = filledButton(L.hist_resend, bg: Theme.accent, fg: .white)
            rs.addTarget(self, action: #selector(tapResend), for: .touchUpInside)
            resendBtn = rs
            col.addArrangedSubview(rs)
        }

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: g.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: g.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: g.bottomAnchor),
            col.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 16),
            col.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            col.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: Theme.pad),
            col.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -Theme.pad),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    private func sectionLabel(_ t: String) -> UILabel {
        let l = UILabel()
        l.text = t
        l.font = .systemFont(ofSize: 12)
        l.textColor = Theme.accent
        return l
    }

    private func box(_ text: String, color: UIColor, selectable: Bool) -> UIView {
        let wrap = UIView()
        wrap.backgroundColor = Theme.panel
        wrap.layer.cornerRadius = 14
        wrap.layer.borderWidth = 0.6
        wrap.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        let tv = UITextView()
        tv.text = text
        tv.font = .systemFont(ofSize: 17,
                              weight: color == Theme.text ? .regular : .semibold)
        tv.textColor = color
        tv.backgroundColor = .clear
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.isSelectable = selectable        // 长按也能选字复制
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        tv.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(tv)
        NSLayoutConstraint.activate([
            tv.topAnchor.constraint(equalTo: wrap.topAnchor),
            tv.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            tv.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            tv.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
        ])
        return wrap
    }

    private func filledButton(_ t: String, bg: UIColor, fg: UIColor) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(t, for: .normal)
        b.setTitleColor(fg, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        b.backgroundColor = bg
        b.layer.cornerRadius = Theme.rCard
        b.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return b
    }

    @objc private func tapCopy() {
        UIPasteboard.general.string = item.out
        toast(L.ok_copied)
    }

    /// 拿原话重译成新的一条（走 `Backend.polish`，不重跑 ASR、不花那笔钱）。
    @objc private func tapResend() {
        resendBtn?.isEnabled = false
        resendBtn?.setTitle(L.kb_resending, for: .normal)
        let mode = Backend.Mode(rawValue: item.mode) ?? .en
        // 🚨 兜底用**目标语言偏好**，不是界面语言（安卓深审 M3 同款教训）。
        let lang = item.lang.isEmpty
            ? (KbBridge.prefs.string(forKey: "vime.lang") ?? "en") : item.lang
        Backend.polish(text: item.zh, tone: item.tone, mode: mode, lang: lang) {
            [weak self] r in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.resendBtn?.isEnabled = true
                self.resendBtn?.setTitle(L.hist_resend, for: .normal)
                switch r {
                case .success(let out):
                    guard !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    else { self.toast(L.msg_not_heard); return }
                    // 🚨 **`durMs` 传 0**（交叉审查 M5）：重译是拿原话再跑一次模型，
                    //    **他并没有再说一遍话**。原样把 durMs 抄过来的话，KPI ③「累计说话」
                    //    会被重复计数 —— 连点 3 次「再发一次」，1 分钟变 4 分钟，② 跟着歪。
                    //    🚨 `zh` 仍要带（详情/列表要显示原话），④「说了多少字」的重复计数
                    //    由 `HomeStatsCore` 按 `re` 标记跳过，不能靠这里清空 zh。
                    History.add(mode: self.item.mode, tone: self.item.tone,
                                zh: self.item.zh, out: out,
                                durMs: 0, lang: lang, isRetranslate: true)
                    self.toast(L.hist_resent)
                    // 🚨 重译成新的一条，回列表能立刻看到（列表 viewWillAppear 会重读）。
                    self.navigationController?.popViewController(animated: true)
                case .failure(let f):
                    self.toast(f.userText)
                }
            }
        }
    }

    private func toast(_ text: String) {
        let l = UILabel()
        l.text = "  " + text + "  "
        l.font = .systemFont(ofSize: 14)
        l.textColor = .white
        l.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        l.textAlignment = .center
        l.numberOfLines = 0
        l.layer.cornerRadius = 10
        l.layer.masksToBounds = true
        l.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            l.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            l.heightAnchor.constraint(equalToConstant: 40),
            l.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            l.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
        l.alpha = 0
        UIView.animate(withDuration: 0.2, animations: { l.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.3, delay: 2.0, options: [],
                           animations: { l.alpha = 0 },
                           completion: { _ in l.removeFromSuperview() })
        }
    }
}

/// 说话记录列表/详情**共用**的档位→色/文案/时间（单一实现，免两处走散）。
enum HistoryUI {
    /// 译文按档上色：结构化英文 = **主紫**、其余（整理/逐字）= 浅紫。
    ///
    /// 🚨🚨 **2026-09-04 把英文档那个绿换成主紫**（Kevin 当面拍板）。
    ///    他的原话：「不要用这个绿色，太丑了，这跟我们的主题色不搭的」「最起码用 C 吧」。
    ///
    /// 🚨 **改的是"用法"，不是那个色值常量** —— `Theme.modeEnGreen`
    ///    在 `<<<PALETTE-*>>>` 标记之间，那一段是**从安卓自动生成的**，
    ///    手改下次生成就被冲掉（这个坑踩过一次）。安卓那边同样只改用法、
    ///    不动 `Skin.OK` 本身（它还被"成功勾"用着，动了会误伤）。
    ///
    /// 🚨 **可读性的账已经摆给他看过了**：`#8B5CF6` 对卡片底 `#4A2C6D`
    ///    对比度只有 **2.65:1**（原来那个绿是 7.36，白正文 10.05），
    ///    低于 4.5 的可读下限。**他知道这个数之后仍然选它**，所以按他的做。
    ///    真机上要是暗到影响阅读，**回报给他看实拍再定，别自己改色**。
    static func modeColor(_ mode: String) -> UIColor {
        mode == "en" ? Theme.accent : Theme.modeZhPurple
    }
    static func modeChip(_ mode: String) -> String {
        switch mode {
        case "en": return L.hist_chip_en
        case "raw": return L.kb_verbatim
        default: return L.hist_chip_zh
        }
    }
    /// 今天 HH:mm / 昨天 HH:mm / M月d日 HH:mm。
    static func timeLabel(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts / 1000)
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: d)
        let clock = String(format: "%02d:%02d", hm.hour ?? 0, hm.minute ?? 0)
        if cal.isDateInToday(d) { return L.hist_today + " " + clock }
        if cal.isDateInYesterday(d) { return L.hist_yesterday + " " + clock }
        let md = cal.dateComponents([.month, .day], from: d)
        return String(format: L.hist_monthday, md.month ?? 0, md.day ?? 0) + " " + clock
    }
    /// 药丸 chip：描边+文字都用档位色，透明底。
    static func chip(_ text: String, color: UIColor) -> UIView {
        let wrap = UIView()
        wrap.layer.cornerRadius = 13
        wrap.layer.borderWidth = 1
        wrap.layer.borderColor = color.withAlphaComponent(0.7).cgColor
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 13)
        l.textColor = color
        l.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(l)
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 10),
            l.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -10),
            l.topAnchor.constraint(equalTo: wrap.topAnchor, constant: 4),
            l.bottomAnchor.constraint(equalTo: wrap.bottomAnchor, constant: -4),
        ])
        return wrap
    }
}
