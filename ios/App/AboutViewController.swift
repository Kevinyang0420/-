import UIKit

/// **「关于 Transless」** —— Kevin 2026-09-06 正在骂的那一屏。
///
/// > 我不是让市场已经写了一段话、draft 出来给了吗？为什么现在还没有更新到最新的产品里面呢？
/// > **为什么关于 Transless 这里还是一堆这什么东西啊？什么也没写啊**
///
/// draft：`voice_ime/_artifact_关于Transless页面文案.html`，它第一句就写着
/// 「**没有任何一个真正的"关于"页面/弹窗被实现过**……这次是要三端各建一个承载它的屏幕」。
/// 所以这不是加几行文案键的事，是**建屏**。
///
/// 🚨 draft 点名的三条硬要求，逐条落在下面：
/// 1. **文案走 `i18n_map` 统一生成**（`L.about_*`），不三端各写一份 ——
///    draft 原话：别重蹈"结构化转写漏了 iOS 一整天"那次
/// 2. 🚨 **31 和 7 不许写死**：分别数 `GenLangs.langs` 和 `Lang.selectable`，
///    加一门语言这一页跟着变。写死的话哪天加了语言，这里就开始骗人。
/// 3. **隐私政策/服务条款复用现有链接**，不另起一套
///
/// 🚨 视觉不用我设计（draft：「按各平台原生设置页风格走，不需要额外设计」），
///    所以这一屏的字号/间距/颜色全部沿用设置页那套。
final class AboutViewController: UIViewController {

    private let scroll = UIScrollView()
    private let col = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        // 🚨 跟兄弟屏一样走 `UI.paintBg`，别自己刷底色。
        //    我第一版写的是 `Skin.bg` —— **`Skin` 里没有这个成员**，
        //    凭印象写的。`WordBookViewController` 顶上的注释记着同一条：
        //    「我凭印象写了 `Skin.danger`，CI 编译当场挂」。
        UI.paintBg(self)
        title = L.about_title
        buildChrome()
        buildContent()
    }

    // MARK: - 骨架

    private func buildChrome() {
        scroll.translatesAutoresizingMaskIntoConstraints = false
        col.axis = .vertical
        col.spacing = 12
        col.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(col)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            col.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 20),
            col.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 20),
            col.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -20),
            col.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -40),
            col.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -40),
        ])
    }

    // MARK: - 内容（顺序照 draft 的「页面视觉草样」）

    private func buildContent() {
        // ① 标题 + 版本号
        //    🚨 **版本号读来的，不写死**（draft 点名）。改了 build number 这里跟着变。
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
            ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? ""
        add(text(L.about_title, 24, .bold, Skin.text), id: "about.title")
        add(text(L.fill(L.about_version, build), 14, .regular, Skin.dim),
            id: "about.version")

        // ② 一句话定位 + 两段介绍
        gap(10)
        add(text(L.about_tagline, 19, .semibold, Skin.accentHi), id: "about.tagline")
        add(text(L.about_body1, 15, .regular, Skin.text), id: "about.body1")
        add(text(L.about_body2, 15, .regular, Skin.text), id: "about.body2")

        // ③ 支持语言 —— 🚨 **数字全部算出来**
        gap(14)
        add(text(L.about_langs_title, 17, .semibold, Skin.text))
        let nTranslate = GenLangs.langs.count
        // 界面语言：`selectable` 里的 `sys`（跟随系统）不是一门语言，不算。
        let nUI = Lang.selectable.filter { $0 != Lang.sys }.count
        add(text(L.fill(L.about_langs_translate, String(nTranslate)),
                 15, .regular, Skin.dim), id: "about.langs.translate")
        // 列前 9 个的自称，再加「…还有 N 种」
        // 🚨🚨 **这里传的是「剩余数」，不是总数**（2.1 09-07 在 PC 的关于页
        //    截图上发现的，iOS 同款）。原来传 `nTranslate`，于是这一屏写着：
        //        「可翻译成 31 种语言，包括：」＋ 列 9 个 ＋「…等 31 种」
        //    德语更明显：`und 31 weitere`＝「还有 31 种」——
        //    **读者会以为一共 40 种（9+31）**。
        //    数字本身没算错，是**它回答的问题跟这句话问的不是同一个**。
        let listed = 9
        let sample = GenLangs.langs.prefix(listed).map { $0.label }
            .joined(separator: "  ·  ")
        add(text(sample, 15, .regular, Skin.text), id: "about.langs.sample")
        // 🚨 剩余数为 0 时整行不画 —— 语言少于 9 门时「还有 0 种」很蠢。
        let rest = max(0, nTranslate - listed)
        if rest > 0 {
            add(text(L.fill(L.about_langs_more, String(rest)),
                     14, .regular, Skin.dim), id: "about.langs.more")
        }
        add(text(L.fill(L.about_langs_ui, String(nUI)), 15, .regular, Skin.dim),
            id: "about.langs.ui")
        gap(4)
        add(text(L.about_privacy_note, 14, .regular, Skin.dim),
            id: "about.privacy")

        // ④ 法律与联系 —— 🚨 复用现有链接，不另起一套
        gap(14)
        add(text(L.about_legal_title, 17, .semibold, Skin.text))
        add(link(L.prefs_privacy, #selector(tapPrivacy)), id: "about.privacy.link")
        // 🚨 **服务条款那一行只在真有页面时才出现**（`Links.terms` 现在是 nil）。
        //    draft 列了它，但全树只有 privacy 一个地址 —— **不许编一个 URL**，
        //    点开 404 比没有这一行更糟。站点上线后加一行常量，这里自动出现。
        if Links.terms != nil {
            add(link(L.prefs_privacy, #selector(tapTerms)), id: "about.terms.link")
        }
        add(text(L.about_contact + L.sep_colon + Self.supportMail,
                 15, .regular, Skin.dim),
            id: "about.contact")

        // ⑤ 发行主体
        gap(14)
        add(text(L.about_publisher_title, 17, .semibold, Skin.text))
        add(text(Self.publisher, 14, .regular, Skin.dim), id: "about.publisher")
    }

    /// 🚨 这两条是**法律主体信息**，不进 i18n（公司名和邮箱不翻译）。
    private static let publisher = "Luminate Pacific Consulting Service Limited"
    private static let supportMail = "support@transless.net"

    // MARK: - 小工具

    private func text(_ s: String, _ size: CGFloat,
                      _ w: UIFont.Weight, _ c: UIColor) -> UILabel {
        let l = UILabel()
        l.text = s
        l.font = .systemFont(ofSize: size, weight: w)
        l.textColor = c
        // 🚨 `numberOfLines = 0`：介绍是整段话，写死行数在别的语言下必然截断
        //    （德语最长）—— 今晚键盘历史那条就是行数没设好撑出来的。
        l.numberOfLines = 0
        return l
    }

    private func link(_ s: String, _ sel: Selector) -> UIView {
        let b = UIButton(type: .system)
        b.setTitle(s + "  ›", for: .normal)
        b.setTitleColor(Skin.accentHi, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15)
        b.contentHorizontalAlignment = .left
        b.addTarget(self, action: sel, for: .touchUpInside)
        return b
    }

    private func add(_ v: UIView, id: String? = nil) {
        if let id = id { v.accessibilityIdentifier = id }
        col.addArrangedSubview(v)
    }

    private func gap(_ h: CGFloat) {
        let s = UIView()
        s.heightAnchor.constraint(equalToConstant: h).isActive = true
        col.addArrangedSubview(s)
    }

    // MARK: - 链接

    @objc private func tapPrivacy() { open(Links.privacy) }
    @objc private func tapTerms() { if let t = Links.terms { open(t) } }

    private func open(_ s: String) {
        guard let u = URL(string: s) else { return }
        UIApplication.shared.open(u)
    }
}
