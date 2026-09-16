import UIKit
import WebKit

/// **隐私政策（端内页）** —— Kevin 09-07 #97①：
/// > 现在点进去会在浏览器打开新窗口，不要这么搞。像「关于 Transless」一样，
/// > 做成 App 端内的原生界面，**不要跳出 App**。
///
/// ## 为什么正文用 WKWebView 而不是一堆 UILabel（说清楚，别当成偷懒）
/// 线上那份 `privacy.html` 有 **表格**（数据类型／用途／保留期那几张）、
/// 引用块、代码样式。拆成原生 label 会**丢掉表格**，而表格恰好是
/// 合规文本里信息密度最高的一段 —— 丢了不是"简化"，是**内容不全**。
/// 所以：**外壳原生**（我们的导航栏／返回／背景／同步那一行都是原生控件），
/// **正文用同一份文档原样渲染**。他看到的不会是浏览器，没有地址栏、没有 Safari。
///
/// 🚨 **文档随包走，不联网** —— `Resources/privacy.html`。
///    联网取的话飞行模式下这一页是空白，而隐私政策是**必须随时看得到**的东西。
///
/// 🚨🚨 09-16 改：随包这份**不再跟 `dist/privacy.html` 逐字节一致**——
///    Kevin 亲口点名「这是在 App 端内，为什么还要搞返回官网」：官网那份的
///    导航（回官网/公司信息/下载页）在包里全是死链（`href="/"` 在 bundle 里
///    指不到任何地方），已经删掉／改成相对路径。**正文内容仍然跟 `dist/` 走**，
///    只有导航链接这一层是随包定制的，别为了"求字节一致"把它们改回去。
///    判据：`voice_ime/verify_bundled_html_links.py`，扫的是随包这份，
///    `dist/` 官网那份故意不在扫描范围内。
///
/// 🚨 **进得来必须出得去**：首页那条路藏了导航栏，子页要自己显回来。
///    （09-07 刚在查词页栽过同一个：「点进去没有返回按钮，怎么返回呢？」）
final class PrivacyViewController: UIViewController {

    private let web = WKWebView()
    /// 第 1 格（同步的开关）内容。**没开过同步时整格不画** —— 连标题一起。
    private let syncBox = UIStackView()
    /// 第 1 格的卡片外壳——见下面 `docBox` 的说明，两格必须是**同一种卡片**。
    private let syncCard = UIView()
    /// 第 2 格（具体的隐私政策）的小标题。
    ///
    /// 🚨🚨 09-14 二次翻车，写清楚别再犯：09-07 那版已经把 `syncBox`/`docHead`
    ///    拆成了两个变量、各自有标题，**但只有 `syncBox` 内部那个状态行
    ///    （`row.backgroundColor = Theme.key`）有卡片背景，`docHead`+`web`
    ///    从来没被套进一个真正的卡片容器**——只是一个灰色小标题浮在裸的
    ///    WebView 上面，没有背景、没有边框。所以视觉上是"一个圆角胶囊
    ///    + 底下一大片没有边界的正文"，跟 Kevin 09-14 说的一模一样：
    ///    「头顶上一个『同步说话记录』，下面全是这些隐私条款」。
    ///    "分成两个变量" 不等于 "分成两个看得见的格子"——安卓
    ///    `PrivacyScreen.java` 的 `syncBox`/`docBox` **都**套了
    ///    `Skin.glass(host)` 背景，这才是"并列"的真正意思。
    ///    现在 `docHead`+`web` 一起装进 `docBox`（下面那个 UIView），
    ///    `syncBox` 也整体套进 `syncCard`，两个卡片用同一套样式
    ///    （`Theme.panel` + 18pt 圆角 + 0.6pt 描边，跟 `HistoryListViewController`
    ///    的卡片同源，不自己再配一套）。
    private let docHead = UILabel()
    /// 第 2 格的卡片外壳，装 `docHead` + `web`。
    private let docBox = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.prefs_privacy
        UI.paintBg(self)

        // ── 卡片通用样式：跟 `HistoryListViewController.wbCard` 同一套，
        //    别自己再配一套（他定过「你不要自己设计了」）。
        for card in [syncCard, docBox] {
            card.backgroundColor = Theme.panel
            card.layer.cornerRadius = 18
            card.layer.borderWidth = 0.6
            card.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
            card.clipsToBounds = true
            card.translatesAutoresizingMaskIntoConstraints = false
        }

        // ── 格子 1：上云状态 + 停止（#97②a：入口挪到隐私这一类里统一操作）──
        syncBox.axis = .vertical
        syncBox.spacing = 6
        syncBox.translatesAutoresizingMaskIntoConstraints = false
        syncCard.addSubview(syncBox)
        NSLayoutConstraint.activate([
            syncBox.topAnchor.constraint(equalTo: syncCard.topAnchor),
            syncBox.leadingAnchor.constraint(equalTo: syncCard.leadingAnchor),
            syncBox.trailingAnchor.constraint(equalTo: syncCard.trailingAnchor),
            syncBox.bottomAnchor.constraint(equalTo: syncCard.bottomAnchor),
        ])
        // 🚨 没开过同步时**整张卡片隐藏**，不是"卡片在、内容空"——
        //    卡片有背景和描边，空着也会画出一个没内容的圆角框，
        //    等于把"难找"的取消入口变成"显眼但空"的怪东西。
        //    `UIStackView` 会自动跳过 `isHidden` 的 arranged subview，
        //    根 stack 不用再靠"空 stack + required hugging"这种
        //    间接手法猜它会不会占位——直接让它不占位。

        web.translatesAutoresizingMaskIntoConstraints = false
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        // 🚨 **底部留出浮动 tab 栏的高度** —— 那条栏是浮在内容上的，
        //    正文底边虽然钉在安全区底，最后几行仍会被它盖住，
        //    而隐私政策**最后几行往往是联系方式和生效条款**，盖住不行。
        //    图上看得很清楚：那张表格的最后一行正压在 tab 栏底下。
        web.scrollView.contentInset.bottom = 96
        web.scrollView.verticalScrollIndicatorInsets.bottom = 96
        // 🚨 **不许在这一页里跳走** —— 正文里若有外链，点了会离开 App，
        //    那正是他要消掉的行为。策略见 `webView(_:decidePolicyFor:)`。
        web.navigationDelegate = self

        // ── 格子 2：隐私政策正文，标题 + 正文一起装进 docBox 这张卡 ──
        docHead.text = L.prefs_privacy
        docHead.font = .systemFont(ofSize: 13, weight: .semibold)
        docHead.textColor = Theme.dim
        docHead.accessibilityIdentifier = "privacy.head.doc"
        docHead.translatesAutoresizingMaskIntoConstraints = false
        docBox.addSubview(docHead)
        docBox.addSubview(web)
        NSLayoutConstraint.activate([
            docHead.topAnchor.constraint(equalTo: docBox.topAnchor, constant: 12),
            docHead.leadingAnchor.constraint(equalTo: docBox.leadingAnchor, constant: 14),
            docHead.trailingAnchor.constraint(equalTo: docBox.trailingAnchor, constant: -14),
            web.topAnchor.constraint(equalTo: docHead.bottomAnchor, constant: 6),
            web.leadingAnchor.constraint(equalTo: docBox.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: docBox.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: docBox.bottomAnchor),
        ])

        // 🚨🚨 **一个根竖直 stack，多余空间确定性地给 docBox（正文那张卡）。**
        //    上一版三个视图各挂各的约束时留过一个自由度、被 Auto Layout
        //    解出"正文压成 0 高"的坏解（09-07 栽过一次）。现在两个卡片
        //    平级放进 `.fill` 的根 stack，只给 `docBox` 低 hugging，
        //    `syncCard` 保持 required —— 跟原来那版的处理方式一致，
        //    只是把"三个视图"换成了"两张卡片"，道理没变。
        let root = UIStackView(arrangedSubviews: [syncCard, docBox])
        root.axis = .vertical
        root.distribution = .fill
        root.alignment = .fill
        root.spacing = 14
        root.isLayoutMarginsRelativeArrangement = true
        root.layoutMargins = UIEdgeInsets(top: 0, left: Theme.pad,
                                          bottom: 0, right: Theme.pad)
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        syncCard.setContentHuggingPriority(.required, for: .vertical)
        docBox.setContentHuggingPriority(.defaultLow, for: .vertical)
        docBox.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: g.topAnchor, constant: 8),
            root.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: g.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: g.bottomAnchor),
        ])

        paintSyncRow()
        loadDoc()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    /// 🚨 首页把导航栏藏了，子页要自己显回来 —— 不然进来就出不去。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        paintSyncRow()          // 从别处关掉同步再回来，这一行要跟着变
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.viewControllers.count == 1 {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }

    // ────────────────────────────── 正文

    private func loadDoc() {
        guard let u = Bundle.main.url(forResource: "privacy",
                                      withExtension: "html"),
              let html = try? String(contentsOf: u, encoding: .utf8) else {
            // 🚨 **不静默留白页**：文档没打进包是构建问题，得说出来，
            //    否则表现是"隐私政策一片空白"，而那是最不该沉默的一屏。
            KbBridge.note("🚨 隐私政策：包里没有 privacy.html")
            let l = UILabel()
            // 🚨 **不借用别处的错误文案**：`err_ourbug` 是「这条没发出去」，
            //    说的是发消息，摆在隐私政策页上驴唇不对马嘴。
            //    这里只摆**网址本身** —— 不需要新文案，也不编一句没人审过的话。
            l.text = Links.privacy
            l.numberOfLines = 0
            l.isUserInteractionEnabled = true
            l.textColor = Theme.dim
            l.textAlignment = .center
            l.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(l)
            NSLayoutConstraint.activate([
                l.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                l.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
            return
        }
        web.loadHTMLString(Self.themed(html),
                           baseURL: u.deletingLastPathComponent())
    }

    /// 把 App 的主题色**盖到那份 HTML 上**。
    ///
    /// 🚨 Kevin 09-07：「那个隐私政策为什么还是这黑底呀？…**不能跟 APP 的
    ///    主题色保持一致吗**？」—— 那几个近黑是**文档自己写死的**，不是 WebView 没透明。
    ///
    /// 🚨 **不改文件、只在渲染时盖**：随包这份的**正文**仍然跟着 `dist/privacy.html`
    ///    走（09-16 起两份不再逐字节一致，见文件头注释——差异只在导航链接那一层，
    ///    正文/表格/条款文字这些不该因为"要主题化"就分叉出第二份）；
    ///    而且线上那一页本来就该保持它自己的样子。
    ///
    /// 🚨 **一个色都不自己配** —— 全部取 `Theme` 里现成的常量
    ///    （他定过「你不要自己设计了」）。
    ///
    /// 🚨 **底色用 transparent，不填色**：填一个色会盖住 App 自己那层渐变，
    ///    等于在渐变上贴一块纯色补丁 —— 那正是他说的「突兀」。
    ///    需要块面的（表头/引用块/代码）用半透明白，跟 `Theme.panel` 同源。
    ///
    /// 🚨 表格**只换颜色**，不动 `border-collapse` / `table-layout` /
    ///    `word-break` —— 动了会打乱窄屏上的换行规则，表格当场塌掉。
    private static func themed(_ html: String) -> String {
        let css = ""
            + "<style>"
            + "html,body{background:transparent !important;color:\(hex(Theme.text)) !important}"
            + "h1,strong{color:\(hex(Theme.text)) !important}"
            + "h2{color:\(hex(Theme.accent)) !important;border-left-color:\(hex(Theme.accent)) !important}"
            + "a{color:\(hex(Theme.accent)) !important}"
            + "code{background:rgba(255,255,255,.09) !important;color:\(hex(Theme.dim)) !important}"
            + "blockquote{background:rgba(255,255,255,.06) !important;border-left-color:\(hex(Theme.accent)) !important;color:\(hex(Theme.dim)) !important}"
            + "hr{border-top-color:rgba(255,255,255,.14) !important}"
            + "th,td{border-color:rgba(255,255,255,.16) !important;color:\(hex(Theme.text)) !important}"
            + "th{background:rgba(255,255,255,.07) !important}"
            + "</style>"
        // 🚨 插在 </head> **前面**：插在文档最前面会被文档自己的
        //    <style> 覆盖回去（同权重时后面的规则赢）。
        //    找不到 </head> 就追加到末尾并**记一行**，不静默什么都不做。
        if let r = html.range(of: "</head>") {
            return html.replacingCharacters(in: r, with: css + "</head>")
        }
        KbBridge.note("隐私政策：文档里没有 </head>，样式追加到末尾")
        return html + css
    }

    /// `UIColor` → `#rrggbb`，只给上面那段 CSS 用。
    private static func hex(_ c: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X",
                      Int(r * 255), Int(g * 255), Int(b * 255))
    }

    // ────────────────────────────── 上云状态那一行

    /// **状态和动作分开画**（#97②b，Kevin 亲口）：
    /// > 刚才我明明打开了上传，这边却显示「已关闭上传」，状态显示有问题。
    /// > 如果已上传好，就显示已上传（或者上云状态打个绿色的勾）；
    /// > 再点一下则是停止上传（比如显示停止符号）。
    ///
    /// 🚨 老代码的毛病：那一行的标题用的是 `hs_off_1`「已停止同步。」——
    ///    **那是"点下去之后的结果"，却被当成"当前状态"显示**。
    ///    于是同步开着的时候，它反而告诉他"已停止同步"。
    ///    → 现在：左边是**状态**（已同步 ✓ 绿勾），右边是**动作**（停止符号）。
    ///
    /// 🚨 **没开过同步的人看不到这一行** —— 原逻辑如此，别改掉
    ///    （他 09-07 下午定过：取消入口要"难找"，不是要显眼）。
    private func paintSyncRow() {
        syncBox.arrangedSubviews.forEach {
            syncBox.removeArrangedSubview($0); $0.removeFromSuperview()
        }
        // 🚨 没开过同步的人：**整张卡片隐藏**，不只是清空内容
        //    ——卡片现在有背景和描边，空着也会画出一个没内容的圆角框。
        //    别为了"版式对称"把取消入口露给没开过的人（他定过要"难找"）。
        guard HistSync.isOn else { syncCard.isHidden = true; return }
        syncCard.isHidden = false

        let head = UILabel()
        head.text = L.hs_title
        head.font = .systemFont(ofSize: 13, weight: .semibold)
        head.textColor = Theme.dim
        head.accessibilityIdentifier = "privacy.head.sync"
        syncBox.addArrangedSubview(head)
        syncBox.setCustomSpacing(6, after: head)

        let row = UIControl()
        row.backgroundColor = Theme.key
        row.layer.cornerRadius = 14
        row.accessibilityIdentifier = "privacy.row.syncstate"
        row.addTarget(self, action: #selector(tapStop), for: .touchUpInside)
        row.translatesAutoresizingMaskIntoConstraints = false

        // 左：绿点 + 「已同步」——**状态**
        // 🚨🚨 09-16 0 插队指出：原来那个打勾图标（symbol 名字里带
        //    "checkmark" 那个）本身就是「完成/已验证」的宣告，而服务端连
        //    接收端点都没有，那个勾从没验证过任何东西。规格
        //    `_规格_同步状态清单_20260916.md` §8.3：改成纯圆点（不带勾，
        //    symbol 名字就是下面这行的字面量），颜色仍保留绿色
        //    （读作"开着/激活中"），但不再暗示"已经验证完成"。
        let tick = UIImageView(image: UIImage(
            systemName: "circle.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17)))
        tick.tintColor = .systemGreen
        tick.accessibilityIdentifier = "privacy.sync.tick"
        let state = UILabel()
        // 🚨🚨 09-16 §8.1：同一条替换，跟 HistoryListViewController 那处
        //    同一个理由——"已同步"是没发生的动作完成陈述，"已开启"是状态陈述。
        state.text = L.hs_on_state
        state.font = .systemFont(ofSize: 15)
        state.textColor = Theme.text
        state.accessibilityIdentifier = "privacy.sync.state"

        // 右：停止符号 —— **动作**
        let stop = UIImageView(image: UIImage(
            systemName: "stop.circle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)))
        stop.tintColor = Theme.dim
        stop.accessibilityIdentifier = "privacy.sync.stop"

        for v in [tick, state, stop] as [UIView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.isUserInteractionEnabled = false      // 整行响应，别抢触摸
            row.addSubview(v)
        }
        syncBox.addArrangedSubview(row)
        syncBox.isLayoutMarginsRelativeArrangement = true
        syncBox.layoutMargins = UIEdgeInsets(top: 12, left: Theme.pad,
                                             bottom: 12, right: Theme.pad)
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 52),
            tick.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            tick.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            state.leadingAnchor.constraint(equalTo: tick.trailingAnchor, constant: 8),
            state.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            stop.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            stop.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
    }

    /// 停止上传。**动作跟状态分开之后，这里只做"停"这一件事。**
    ///
    /// 🚨 走 `HistSync.turnOff()`（**同时复位 one-off**），不是 `set(false)` ——
    ///    只关开关的话，说话记录那屏的开启入口**永远不会再出现**，
    ///    等于把功能永久藏死。这条是从设置页那版原样搬过来的，别丢。
    @objc private func tapStop() {
        let a = UIAlertController(title: L.hs_off_1, message: L.hs_off_2,
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: L.cancel, style: .cancel))
        a.addAction(UIAlertAction(title: L.ok, style: .destructive) { [weak self] _ in
            HistSync.turnOff()
            self?.paintSyncRow()
        })
        present(a, animated: true)
    }
}

extension PrivacyViewController: WKNavigationDelegate {
    /// 🚨 **正文里的外链一律不放行** —— 放行就等于又跳出 App 了，
    ///    而"不要跳出 App"正是这一整条需求。
    ///    首屏那次加载（`loadHTMLString`）不是 `.linkActivated`，不受影响。
    func webView(_ w: WKWebView,
                 decidePolicyFor action: WKNavigationAction,
                 decisionHandler done: @escaping (WKNavigationActionPolicy) -> Void) {
        if action.navigationType == .linkActivated {
            KbBridge.note("隐私政策：拦下一个外链，不跳出 App")
            return done(.cancel)
        }
        done(.allow)
    }
}
