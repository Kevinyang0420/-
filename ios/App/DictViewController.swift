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

    // 🚨🚨 Kevin 2026-09-06（带截图）：「我在查词那个界面，这里查出来的东西太松了…
    //    卡片太松散了，能不能把它弄得紧凑一些？」
    //    他那张图上一整屏只装下 3 条释义 + 1 个例句。
    // 🚨 **只收间距，不动字号** —— 他说的是"松"，没说字小。
    // 🚨 **`gapCta` 一个点不动**：那 30 是 Grok ⑥ 专门定的
    //    （「和搭配芯片贴得近，扫一眼会觉得芯片也是操作区」）——
    //    他抱怨的是释义之间、释义和例句之间，不是主按钮那一段。
    //    **别顺手把别人为具体问题定过的数一起改了。**

    /// 组与组之间（义项 1 / 2 / 3 之间、例句与搭配之间）。46 → 24。
    private static let gapGroup: CGFloat = 24
    /// 一组之内的行距（英文释义 ↔ 中文对译）。
    /// 🚨 19 → 6：这两行**是同一个义项的两半**，本来就该贴着。
    ///    19 让它们看起来像两条独立的东西 —— 那正是"松散"的主要来源。
    private static let gapLine: CGFloat = 6
    /// 主按钮上边距 —— Grok ⑥：「和搭配芯片贴得近，扫一眼会觉得芯片也是操作区」。
    /// 🚨 **这个不动**（见上面那段）。
    private static let gapCta: CGFloat = 30

    private let scroll = UIScrollView()
    private let col = UIStackView()
    private let field = UITextField()
    private let searchBtn = UIButton(type: .custom)
    /// 查询失败时的**弱化提示行** —— 2.1 2026-09-06 定案。
    ///
    /// 🚨🚨 **原来是黑底 toast 浮在屏幕底部**，两个毛病：
    ///    ① 它盖在别的东西上、2.2 秒就没了，他没看清就走了；
    ///    ② 位置在最底下，看着像是「+ 单词本」弹的 ——
    ///       0 就是这么把它误判成「加入单词本失败」的（`tapAdd` 全程不弹任何提示）。
    ///    **提示放错地方，会让下一个人把故障归错因。**
    private let errLabel = UILabel()
    private let card = UIView()
    private let cardCol = UIStackView()
    private let recentTitle = UILabel()
    private let recentRow = UIStackView()

    private var current: DictEntry?
    private var addBtn: UIButton?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.dict_title
        UI.paintBg(self)
        build()
        renderRecent()
    }

    /// 🚨🚨 **进来得能出去** —— Kevin 09-07：「从首页点了查词进去，
    ///    它没有一个返回的按钮啊，怎么回事？它怎么返回呢？」
    ///
    ///    根因：**首页在自己的 `viewWillAppear` 里把导航栏藏了**
    ///    （`MainViewController` 那句 `setNavigationBarHidden(true)`），
    ///    子页要自己把它显回来 —— `SetupViewController` 那边的注释
    ///    早就写着「子页要显示导航栏（首页是隐藏的）—— **不然进来就出不去**」。
    ///
    /// 🚨 **为什么以前没暴露**：查词页原来只能从「随手翻译」右上角进，
    ///    那条栈里导航栏本来就是显示的。09-07 加了首页那张查词卡之后，
    ///    多了一条**从藏栏的屏推进来**的路，这一屏才第一次露出问题。
    ///    → **一屏的导航栏状态不该取决于是谁把它推进来的**，
    ///      所以修在这里，不是修在首页那张卡上。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    /// 退回栈底（首页）时把栏重新藏回去，否则首页顶上会多一条空栏。
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.viewControllers.count == 1 {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
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

        // 🚨🚨 **这个钮原来是麦克风、点下去起录；现在是放大镜、点下去就查。**
        //    Kevin 2026-09-06 一手原话（2.1 转）：
        //    「就用放大镜就好了…**不需要麦克风的 icon，打字的话就是我录入，
        //      我用 Transless 去说话转写就行了**」
        //
        //    他点破的是：**我们自己就是语音输入法** —— 要说话就用 Transless 键盘
        //    往这个框里说，查词页不需要再长一个麦克风。
        //    （我和 2.1 都先想成「删麦克风＝丢掉语音查词」，
        //      那是**盯着这一屏找入口，而入口在产品的另一层**。）
        //
        // 🚨 只换图形和行为：42×42、圆角 21、紫底、白 tint、位置**一个都没动**。
        searchBtn.backgroundColor = Theme.accent
        searchBtn.layer.cornerRadius = 21
        searchBtn.setImage(Theme.searchGlyph(60), for: .normal)
        searchBtn.tintColor = .white
        // 🚨 名字和 a11y id 这次**跟着行为一起改** —— 它现在真的是查询了。
        //    （上一版故意留着 `mic`，因为那时它还在起录；名字要指着它真做的事。）
        searchBtn.accessibilityIdentifier = "dict.search"
        searchBtn.addTarget(self, action: #selector(tapSearch),
                            for: .touchUpInside)
        searchBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBtn)

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
        // 🚨 错误行排在**结果卡之上**，紧贴搜索框下方 ——
        //    2.1：「不占结果卡片的位置」。它平时 isHidden，
        //    `UIStackView` 会把隐藏项的尺寸压成 0，所以不留空。
        errLabel.font = .systemFont(ofSize: 13)
        errLabel.textColor = Theme.dim          // 弱化：次要色，不是警告红
        errLabel.numberOfLines = 0
        errLabel.isHidden = true
        errLabel.accessibilityIdentifier = "dict.err"
        col.addArrangedSubview(errLabel)
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
            searchBtn.leadingAnchor.constraint(equalTo: field.trailingAnchor, constant: 12),
            searchBtn.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            searchBtn.centerYAnchor.constraint(equalTo: field.centerYAnchor),
            searchBtn.widthAnchor.constraint(equalToConstant: 42),
            searchBtn.heightAnchor.constraint(equalToConstant: 42),

            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: g.trailingAnchor),
            // 🚨🚨 **底部要给中间那个凸起让位**，否则最后一块内容点不到也看不全。
            //    Kevin 2026-09-06 那张图：「最近查过」的标题贴在悬浮 tab 栏上沿，
            //    **它下面的 chip 一条都露不出来** —— 记忆 `feedback_ui_below_fold_is_missing`：
            //    **滚不到的地方 = 不存在。**
            //
            // 🚨 用 `MainTabController.bottomClearance`（= bumpLift + 12），
            //    **不自己另写一个数** —— 那个常量就是为这件事设的单一配置点，
            //    它的注释里写着「凸起是盖在**所有** Tab 页上的…谁把控件贴到底
            //    就会被它压住（09-04 面对面的录音钮就被压了）」。
            //
            // 🚨 规矩早就有，**只有面对面一屏用了它**，其余屏全漏（含这一屏）——
            //    典型的「规矩要按每个出口落地」。
            scroll.bottomAnchor.constraint(
                equalTo: g.bottomAnchor,
                constant: -MainTabController.bottomClearance),

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
        // 🚨🚨 **`SpellFold` 挂在这里，不挂在某一条输入路径上。**
        //
        //    它原来只在麦克风回调里跑（`DictViewController` 旧的 `tapMic`）——
        //    那是它**唯一的生产调用点**。麦克风一删，拼字母折叠就没人走了，
        //    而单元测试还全绿：**测试活着不等于功能活着。**
        //    （今天刚栽过反过来的一次：换实现时没清死代码，留下骗人的名字；
        //      这次是删实现时差点把还要用的东西一起删掉。）
        //
        //    挂在 `search` 上比原来更全：不管是打字、用 Transless 键盘口述、
        //    还是点「最近查过」，**发起查询前都过一遍**。
        //    判据不变：≥3 段且每段单字母才拼，否则原样返回。
        let w = SpellFold.fold(
            raw.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !w.isEmpty else { return }
        clearErr()      // 🚨 新查询先收掉旧错误，别让它挂在新结果旁边
        // 折过之后把框里也同步成真正查的那个词，别让他看到的和查的不是一个
        if field.text != w { field.text = w }

        // 🚨 **确定性失败注入**（只在离线样本开关下生效）。
        //    2.1 的判据是「制造一次查词失败 → 截图 → 输入框里仍是那个词」，
        //    没有注入口就只能靠网络抖动 —— **那是不可复现的假验证**。
        if ProcessInfo.processInfo.environment["TRANSLESS_DICT_FAKE"] == "1",
           DictStore.key(w) == "failnow" {
            showErr(L.err_other)
            return
        }
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
                case .failure(let f):
                    // 🚨🚨 **失败必须留痕**（09-07 撞的）：他看到「出了点问题，
                    //    再试一次」，而痕迹里只有「查词打后端：…」，之后一片空白 ——
                    //    我在设备上**查不出为什么**，只能猜（我先猜了 token 上限，
                    //    改完照样红）。
                    //    Kevin 的规矩：诊断记了但没有查看入口 = 等于没记；
                    //    这里是更前一步 —— **根本没记**。
                    KbBridge.note("查词失败：" + String("\(f)".prefix(160)))
                    self.showErr(f.userText)
                }
            }
        }
    }

    /// 显示一条查询失败提示。**不写进输入框、不做浮层。**
    ///
    /// 🚨🚨 2.1 2026-09-06 的定案，原话：
    ///    「问题不是文案不好看，是**【错误变成了输入】** —— 用户下一次点查询，
    ///      会拿着"网络连接失败"这句话去查词。**输入框里的东西一定会被再查一次，
    ///      那是它的语义。**」
    ///    → `field.text` 只放用户要查的词，**任何时候都不许被写入非用户内容**。
    private func showErr(_ t: String) {
        errLabel.text = t
        errLabel.isHidden = false
        // 🚨🚨 **失败时必须把上一条的卡片收掉**，否则它会冒充这一次的结果。
        //
        //    2.1 2026-09-06 从我自己交的验收图上抓到的：那张图里输入框是
        //    `lookup`、而卡片显示的是上一次 `ubiquitous` 的释义 ——
        //    **用户点「最近查过」里的 lookup，读到的是别的词的解释，
        //    而且没有任何东西告诉他这是旧卡片。**
        //
        // 🚨 这跟「错误文案被写进输入框」是**同一个形状**：
        //    **一个东西冒充了另一个东西**。那次是错误冒充用户输入，
        //    这次是旧结果冒充新结果。修一个不修另一个等于只修了一半。
        card.isHidden = true
        current = nil          // 🚨 连带清掉，否则「＋单词本」会收上一条
    }

    /// 发起新查询时先把上一条错误收掉 —— 否则旧错误会挂在新结果旁边。
    private func clearErr() {
        errLabel.text = nil
        errLabel.isHidden = true
    }

    // MARK: - 渲染结果卡（Grok v3 的七条都落在这一个函数里）

    private func render(_ e: DictEntry) {
        current = e
        cardCol.arrangedSubviews.forEach { $0.removeFromSuperview() }
        card.isHidden = false

        // 🚨🚨 **句子走另一套渲染**（Kevin 09-07：「还需要支持查句子…
        //    帮我分析这段句子是什么意思、它的结构，以及有什么可参考的句式」）。
        //    规格 `_规格_查句子_20260907.md`：**判据只看模型返回的 `kind`**，
        //    客户端不许按空格或字数猜 —— 英文短语有空格、中文句子没有，
        //    任何本地规则都会在某一门语言上错**而且不报错**。
        //
        //    🚨 段落内容走 `CardSections`（跟单词本详情页**同一份**）——
        //    两处各写一套必漂，今晚已经栽过三次。
        //
        //    🚨 **后端还没上线 `kind` 分流**（我 09-07 实测：查整句返回的
        //    仍是词卡形状，连 `kind` 字段都没有）。所以这条分支现在**走不到** ——
        //    夹具自测在 `UITests/CardSectionsTests`（好样本过、坏样本红过），
        //    但**端到端没验过**，等 1.1 上线后再验，不拿夹具绿冒充通过。
        if let o = (try? JSONSerialization.jsonObject(with: Data(e.raw.utf8)))
            as? [String: Any], CardSections.isSentence(o) {
            renderSentence(o, query: e.word)
            return
        }
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
        ph.setTitle("/" + e.phoneticForDisplay + "/", for: .normal)
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
        // 🚨 28 → 14：音标行跟下面的词性/释义是同一张卡的内容，
        //    不是两个区块。
        cardCol.setCustomSpacing(14, after: phRow)

        // ② 词性小标题。
        // 🚨 **只在整卡真有一个统一词性时才显示**（旧结构顶层带 pos）。
        //    新结构的词性是**义项级**的，由下面的分节标题负责 ——
        //    在这里显示第一条的词性，正是 Kevin 报的
        //    「commute 只给了动词，名词没写上来」的成因。
        if !e.pos.isEmpty {
            let pos = UILabel()
            pos.text = e.pos
            pos.font = .systemFont(ofSize: 13, weight: .bold)
            pos.textColor = Theme.accent
            cardCol.addArrangedSubview(pos)
            cardCol.setCustomSpacing(14, after: pos)
        }

        // ③④ 义项：编号 + 英文在上中文在下；**组间距 46 > 行间距 19**
        //     Grok：「英中是一对，三条是三组 —— 现在看不出组边界」
        // 🚨 **按词性分节**：词性一变就起一个小标题。
        //    Kevin 2026-09-06「commute 只给了动词，名词没写上来」——
        //    三条义项是 v./n./v.，而界面只在页头标了第一条的 `v.`，
        //    名词那条就藏在动词标题底下。
        //    1.1 已在 prompt 里保证**同词性的义项相邻**，所以比一下上一条就够，
        //    不用自己聚合。逐条都标的话 `adj.` 会重复三次（Grok 点过是噪音）。
        var lastPos = ""
        for (i, sn) in e.senses.enumerated() {
            if !sn.pos.isEmpty, sn.pos != lastPos {
                let head = UILabel()
                head.text = sn.pos
                head.font = .systemFont(ofSize: 13, weight: .bold)
                head.textColor = Theme.accent
                head.accessibilityIdentifier = "dict.pos.section"
                cardCol.addArrangedSubview(head)
                cardCol.setCustomSpacing(6, after: head)
                lastPos = sn.pos
            }
            // ⑤ 带用法标注的那条**降一级**
            let row = senseRow(no: i + 1, sense: sn, minor: !sn.register.isEmpty)
            cardCol.addArrangedSubview(row)
            cardCol.setCustomSpacing(Self.gapGroup, after: row)
        }

        // ⑥ 例句 / 搭配 各加微型标题
        // 🚨 **画全部例句**（2026-09-06）。原来只画 `e.exampleEn` 一条，
        //    而后端给的是多条 —— Kevin 那张卡上就一句。
        if !e.examples.isEmpty {
            cardCol.addArrangedSubview(microTitle(L.dict_example))
            for (i, one) in e.examples.enumerated() {
                let ex = UILabel()
                ex.numberOfLines = 0
                ex.accessibilityIdentifier = "dict.example"
                ex.attributedText = pair(one.0, one.1, minor: false)
                cardCol.addArrangedSubview(ex)
                // 例句之间留行距，最后一条后面留组距
                cardCol.setCustomSpacing(
                    i == e.examples.count - 1 ? Self.gapGroup : 10, after: ex)
            }
        }

        cardCol.addArrangedSubview(microTitle(L.dict_collocation))
        let chips = UIStackView(arrangedSubviews:
            e.collocations.prefix(3).map { chip($0, outlined: false) } + [UIView()])
        chips.axis = .horizontal
        chips.spacing = 8
        cardCol.addArrangedSubview(chips)

        // ⑦ 主按钮上边距 30
        cardCol.setCustomSpacing(Self.gapCta, after: chips)
        let add = makeAddButton()
        cardCol.addArrangedSubview(add)
        paintAdd()
        renderRecent()
    }

    /// 句子卡：意思 / 结构拆解 / 换个说法 / 关键搭配。
    ///
    /// 🚨 **不重画一套行样式** —— 用这一屏已有的 `sectionTitle` / `plainRow`
    ///    （跟词卡同一套间距和字号），只是内容来自 `CardSections`。
    private func renderSentence(_ o: [String: Any], query: String) {
        let head = UILabel()
        head.text = query
        head.font = .systemFont(ofSize: 22, weight: .semibold)
        head.textColor = Theme.text
        head.numberOfLines = 0
        head.accessibilityIdentifier = "dict.sentence"
        cardCol.addArrangedSubview(head)

        let secs = CardSections.sentence(
            o, titles: (meaning: L.wb_card_meaning,
                        breakdown: L.wb_card_breakdown,
                        alternatives: L.wb_card_alternatives,
                        keys: L.wb_card_keys))
        for sec in secs {
            let t = UILabel()
            t.text = sec.title
            t.font = .systemFont(ofSize: 13)
            t.textColor = Theme.dim
            t.accessibilityIdentifier = "dict.section"
            cardCol.addArrangedSubview(t)
            for r in sec.rows {
                let l = UILabel()
                l.text = r
                l.font = .systemFont(ofSize: 15)
                l.textColor = Theme.text
                l.numberOfLines = 0
                cardCol.addArrangedSubview(l)
            }
        }
        // 🚨 「也要支持我加入到单词本」是他原话里的后半句，别只做前半。
        cardCol.addArrangedSubview(makeAddButton())
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
    /// 查词条目的身份 —— **只由那个词决定**（2.1 09-06 规格，安卓已对齐）。
    ///
    /// 🚨 原来是 `idOf(e.word, 首义中文)` —— **释义参与了身份**。
    ///    同一个词查两次、释义差一个字就变成两条，他会问「怎么多出来一条」。
    ///    **身份不能由会变的内容决定。**
    /// 🚨 `zh` 传空串是**规格定的**，不是偷懒：查词条目没有"当时说的中文"。
    ///    复习卡的中文面改从 `card` 取首义（见 `WordBookViewController`）。
    private func wbId(_ e: DictEntry) -> String {
        WordBookCore.dictId(word: e.word)
    }

    /// 「加入单词本」那颗按钮 —— **词卡和句子卡共用一个出口**。
    ///
    /// 🚨 抽出来是因为句子卡也要这颗（Kevin 原话后半句：「**同时也要支持我
    ///    加入到单词本**」）。两处各造一颗的话，改样式/改埋点必漏一处。
    private func makeAddButton() -> UIButton {
        let add = UIButton(type: .custom)
        add.backgroundColor = Theme.accent
        add.layer.cornerRadius = 22
        add.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        add.setTitleColor(.white, for: .normal)
        add.accessibilityIdentifier = "dict.add.wordbook"
        add.addTarget(self, action: #selector(tapAdd), for: .touchUpInside)
        add.heightAnchor.constraint(equalToConstant: 44).isActive = true
        addBtn = add
        paintAdd()
        return add
    }

    @objc private func tapAdd() {
        guard let e = current else { return }
        // 🚨 **句子存的字段跟词不一样**（规格第三节）：
        //    `zh` = 模型给的 meaning，`en` = 他查的那句原文，`span` = "full"。
        //    id 仍走 `WordId`，不另造一套。
        if let o = (try? JSONSerialization.jsonObject(with: Data(e.raw.utf8)))
            as? [String: Any], CardSections.isSentence(o) {
            let f = CardSections.wordbookFields(o, query: e.word)
            // 🚨 用三端已有的 ，不另造 id 口径（规格点名）。
            let sid = WordId.make(f.zh, f.en)
            if WordBook.list().contains(where: { $0.id == sid }) {
                WordBook.remove(id: sid)
            } else {
                _ = WordBook.add(zh: f.zh, en: f.en, span: f.span, tone: "",
                                 today: Srs.todayString(), card: e.raw)
            }
            paintAdd()
            return
        }
        let id = wbId(e)
        if WordBook.list().contains(where: { $0.id == id }) {
            WordBook.remove(id: id)
        } else {
            // 🚨🚨 **把查词已经拿到的那份解释一起存下来**（Kevin 09-06 连问三次
            //    「单词卡片在哪儿呢」）。以前只存了词 + 第一条中文释义，
            //    音标/词性/全部释义/例句/搭配**全丢了**，点进去就是一片空白。
            // 🚨 **在这一刻存**，不是点进去再查 —— 那时这份数据已经不在手上了，
            //    而且规格明写「重新查一次…两次结果可能不一样，
            //    用户会觉得『我收藏的那个解释变了』」。
            // 🚨 `zh` 空串、`en` = 规范化后的那个词 —— 跟 `wbId` 同一套口径。
            //    原来是反的（zh 装英文词、en 装中文释义），两个字段的含义整个颠倒，
            //    而且释义进了 id。
            _ = WordBook.add(zh: "", en: WordId.norm(e.word).lowercased(),
                             span: "full", tone: "", today: Srs.todayString(),
                             card: WordCard.fromDict(e))
        }
        // 🚨 重画前读盘，不拿本地布尔取反（写失败时界面照样变，他会以为收进去了）
        paintAdd()
    }

    /// 点放大镜 = 查框里的词。
    ///
    /// 🚨 收键盘再查 —— 不收的话结果卡被键盘挡住一半，
    ///    他会以为"点了没反应"。
    @objc private func tapSearch() {
        field.resignFirstResponder()
        search(field.text ?? "")
    }
}

extension DictViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ tf: UITextField) -> Bool {
        tf.resignFirstResponder()
        search(tf.text ?? "")
        return true
    }
}
