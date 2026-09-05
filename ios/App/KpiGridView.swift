import UIKit

/// 首页四格 KPI 的**可复用组件**（2×2 + 脚注）。翻译口径，2.1 2026-09-04 定的最终四格。
///
/// 🚨 **已落位到首页**（2026-09-04）：Kevin 当天直接下令「iOS 首页换成安卓那一套」，
///    所以不用再等渲染图了。挂载点在 `HomeViewController.viewDidLoad` 的 ③④ 那一段。
///    （上一版这里写着「只建组件、先不落位、等 2.1 出图」—— 那句已经过期，
///     留着会让下一个人以为它还是个孤儿组件。）
///
/// 版式照安卓乙的 2×2：数字 32/600、单位 13/DIM 紧贴数字右侧、标签 12/DIM 在数字下一行。
/// 空态（`enough == false`）：不画格子，整块显示一句引导（HOME-B：没数据一个数字都不上屏）。
/// 某格拿不到数（② 没时长）：那格写「还没有数据」，绝不显示 0（KPI-13）。
final class KpiGridView: UIView {

    /// 算四格。🚨 **四个数全部来自累加器**（2026-09-04「甲」：lifetime、清历史不动 KPI），
    /// 不再读 History —— 所以这里也不需要传记录进来了。
    static func stats() -> HomeStatsCore.Stats {
        HomeStatsCore.compute(words: KpiWords.total,
                              spokenMs: KpiWords.spokenMs,
                              chars: KpiWords.chars,
                              transMs: KpiWords.transMs)
    }

    init(stats s: HomeStatsCore.Stats) {
        super.init(frame: .zero)
        build(s)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build(_ s: HomeStatsCore.Stats) {
        translatesAutoresizingMaskIntoConstraints = false

        // 空态：**一张跟 2×2 一样高的玻璃卡**，里面一句引导，不画格子。
        //
        // 🚨 高度写死 **202 = 96 + 10 + 96**（照安卓 `kpiGrid()` 的空态分支）：
        //    跟有数据时的两行格子**一样高**，所以第一次翻译完 KPI 出来时
        //    下面的「随手翻译」不会跳位置。
        // 🚨 2026-09-04 修：原来是一行**居中的裸文字、没有卡片背景**，
        //    结果首页中间空出一大块（截图上一眼就看出来）。安卓那份是
        //    `Skin.glass` + `padding(18,16,18,16)` + 13sp + **左上对齐**。
        //    我之前只搬了文案没搬容器 —— 版式照抄要连容器一起抄。
        guard s.enough else {
            let card = UIView()
            card.backgroundColor = Skin.glassFill
            card.layer.cornerRadius = 18
            card.layer.borderWidth = 0.6
            card.layer.borderColor = Skin.glassStroke.cgColor
            card.translatesAutoresizingMaskIntoConstraints = false
            addSubview(card)

            let e = UILabel()
            e.text = L.home_stats_empty
            e.font = .systemFont(ofSize: 13)
            e.textColor = Skin.dim
            e.textAlignment = .left
            e.numberOfLines = 0
            e.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(e)

            NSLayoutConstraint.activate([
                card.topAnchor.constraint(equalTo: topAnchor),
                card.bottomAnchor.constraint(equalTo: bottomAnchor),
                card.leadingAnchor.constraint(equalTo: leadingAnchor),
                card.trailingAnchor.constraint(equalTo: trailingAnchor),
                // 🚨 **跟有数据时一样高** = 110 + 10 + 110。
                //    格子 09-04 从 96 长到 110（多容一行算法说明），
                //    这里必须跟着改 —— 不改的话第一次出数据那一刻，
                //    下面的「随手翻译」会往下跳 28pt。
                //    **同一个高度两处写死就是会漂**，所以下面用算式而不是抄个数。
                card.heightAnchor.constraint(equalToConstant: 110 * 2 + 10),
                e.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
                e.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
                e.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            ])
            return
        }

        // ③ 说话时长。🚨 M2：**「不知道」和「0」不能显示成同一个「0 分钟」**
        //    （KPI-13 就是要挡这个）。而且整数除法会把"说了 45 秒"也变成 0。
        let spoken: (String, String)
        if s.spokenMs <= 0 {
            spoken = (L.kpi_nodata, "")                       // 一条带时长的都没有
        } else if s.spokenMs < 60_000 {
            spoken = (L.kpi_under_min, "")                    // 不足 1 分钟，别显示 0
        } else if s.spokenMs < 3_600_000 {
            spoken = (String(s.spokenMs / 60_000), L.kpi_u_min)
        } else {
            spoken = (String(format: "%.1f", Double(s.spokenMs) / 3_600_000.0),
                      L.kpi_u_hours)
        }

        // 🚨 ①「翻译的词」**读累加器**（后端 `words` 累加），不端上数词、不遍历 History。
        //    `nil` = 老服务端没给过 words / 还没翻译过 → 写「还没有数据」，**绝不显示 0**
        //    （规格 §3：字段缺失和真的是 0 必须分得开）。
        let wordsCell: (String, String, String) = KpiWords.total.map {
            ("\($0)", L.kpi_u_words, L.kpi_words)
        } ?? (L.kpi_nodata, "", L.kpi_words)

        let cells: [(String, String, String)] = [
            // (数字, 单位, 标签)
            wordsCell,                                                          // ①
            // 🚨🚨 ②「省下时间」：**有活动就出数，≤0 显示「0 分」，永不显示裸「—」**
            //    （Kevin 2026-09-05 当场推翻 09-04 那条「≤0 一律显示破折号」）。
            //    他的原话：「省下时间这个指标所有的终端显示的都是一个杠，没有数字」。
            //
            //    🚨 老口径不是"显示方式选错了"，是**它掩盖了一个真 bug**：
            //       分子只数翻译档、减数却含全部说话 ⇒ 结构性偏负 ⇒ 破折号恒亮。
            //       减数已经换成只算翻译档的 `transMs`（见 HomeStatsCore）；
            //       这里只负责"算出来是负的也照样出数"。
            //    「—」只留给**真的什么都没记过**（`enough == false`）。
            s.savedValid ? savedCell(max(0, s.savedMinutes))
                         : ("—", "", L.kpi_saved),                              // ②
            (spoken.0, spoken.1, L.kpi_spoken),                                 // ③
            ("\(s.chars)", L.kpi_u_chars, L.kpi_chars),                         // ④
        ]

        // 2×2：两行，每行两格等宽。
        let rows = UIStackView()
        rows.axis = .vertical
        rows.spacing = 10
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        // 🚨🚨 **脚注 2026-09-04 从「四格外面吊一行」挪进了「省下时间」那一格**
        //    （Kevin：「突然露一行『平均打字 40 词/分钟』，啥意义呢」
        //     「做在方框里吧，不要放在下面」）。
        //    吊在外面时它跟四个格子都没有明显归属；贴在那一格自己的标签下面，
        //    才看得出它是**这一格的算法说明**。
        // 🚨 **只有索引 1（省下时间）那一格有** —— 另外三格是直接计数，
        //    没有基准问题，加了就是噪音。
        // 🚨 那个数从 `HomeStatsCore.typingWPM` 取，**不写死在文案里**。
        //    占位符走 `L.fill`（`String(format:)` 遇到 `%1$s` 会 strlen 崩溃）。
        let note = L.fill(L.home_stats_footnote, "\(HomeStatsCore.typingWPM)")
        for r in 0..<2 {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 10
            for c in 0..<2 {
                let i = r * 2 + c
                row.addArrangedSubview(cell(cells[i], note: i == 1 ? note : nil))
            }
            rows.addArrangedSubview(row)
        }

        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// ② 省下时间：**内部是分钟**（KPI② = 词数÷40 − 说话分钟）。
    /// 不足 60 分钟显示分钟，超过折成小时 —— 跟 ③ 同一套折算口径，别两处不一样。
    /// 🚨 可能是**负数**（说得比打字慢）：那就如实显示负号，不许藏。
    private func savedCell(_ minutes: Double) -> (String, String, String) {
        // 🚨 M3：省下不足 1 分钟时显示「不到 1 分钟」，别四舍五入成「0 分钟」——
        //    "省了 0" 看着像功能没用。（`savedValid` 已保证走到这里时是正数。）
        if minutes < 1 { return (L.kpi_under_min, "", L.kpi_saved) }
        if minutes < 60 {
            return (String(format: "%.0f", minutes), L.kpi_u_min, L.kpi_saved)
        }
        return (String(format: "%.1f", minutes / 60), L.kpi_u_hours, L.kpi_saved)
    }

    /// 一格：玻璃卡，数字 32/600 + 单位 13/DIM 紧贴右侧同一行，标签 12/DIM 下一行。
    /// - Parameter note: 贴在标签**下面**的算法说明（只有「省下时间」那一格有）。
    ///   传 nil = 这一格不加，卡片高度也不变。
    private func cell(_ v: (num: String, unit: String, label: String),
                      note: String? = nil) -> UIView {
        // 🚨 玻璃走 `Skin.glassFill/glassStroke`（**单一配置点**），不用键盘那套
        //    `Theme.panel` —— 两者差一档透明度（白 8% vs 白 10%），
        //    同屏放在一起时 KPI 格子会比旁边的卡暗一点点，说不上哪里不对但就是不齐。
        let box = UIView()
        box.backgroundColor = Skin.glassFill
        box.layer.cornerRadius = 18
        box.layer.borderWidth = 0.6
        box.layer.borderColor = Skin.glassStroke.cgColor
        // 🚨 **四格必须一样高**，所以高度由「最高的那一格」定 ——
        //    带说明那格要多容一行，其余三格跟着长，否则两行卡会参差。
        //    96 是原高；加一行 11pt 小字 + 3pt 行距 → 110。
        box.heightAnchor.constraint(equalToConstant: 110).isActive = true

        let num = UILabel()
        // 「还没有数据」时字号收小，别撑爆格子。
        let isNoData = v.unit.isEmpty
        num.text = v.num
        num.font = .systemFont(ofSize: isNoData ? 15 : 32,
                               weight: isNoData ? .regular : .semibold)
        num.textColor = isNoData ? Skin.dim : Skin.text
        num.translatesAutoresizingMaskIntoConstraints = false

        let unit = UILabel()
        unit.text = v.unit
        unit.font = .systemFont(ofSize: 13)
        unit.textColor = Skin.dim
        unit.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = v.label
        label.font = .systemFont(ofSize: 12)
        label.textColor = Skin.dim
        label.translatesAutoresizingMaskIntoConstraints = false

        box.addSubview(num)
        box.addSubview(unit)
        box.addSubview(label)
        NSLayoutConstraint.activate([
            num.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            num.topAnchor.constraint(equalTo: box.topAnchor, constant: 18),
            unit.leadingAnchor.constraint(equalTo: num.trailingAnchor, constant: 4),
            unit.firstBaselineAnchor.constraint(equalTo: num.firstBaselineAnchor),
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            label.topAnchor.constraint(equalTo: num.bottomAnchor, constant: 2),
            label.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -12),
        ])

        // 算法说明：贴在标签下面，**比标签再淡一档、字号再小一号** ——
        // 它是脚注不是内容（2.1 09-04 的判据：「脚注比标签淡一档」）。
        if let note = note {
            let n = UILabel()
            n.text = note
            n.font = .systemFont(ofSize: 11)
            // 🚨 标签已经是 `Skin.dim`，脚注要再淡一档 → 给 dim 加透明度。
            //    **不另挑一个色值** —— 配色的单一配置点是 `Skin`，
            //    在这里凭感觉调一个新灰就是第二配置点（他说过别自己设计配色）。
            n.textColor = Skin.dim.withAlphaComponent(0.7)
            // 🚨 允许缩到 0.8 倍：英文那句比中文长，窄屏上不缩会被截断成
            //    「At 40 wpm typ…」—— 截断的脚注比没有更糟。
            n.adjustsFontSizeToFitWidth = true
            n.minimumScaleFactor = 0.8
            n.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(n)
            NSLayoutConstraint.activate([
                n.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
                n.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 3),
                n.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor,
                                            constant: -12),
            ])
        }
        return box
    }
}

/// 🚨 **只给我截图核对 KPI 组件用**的调试宿主（`TRANSLESS_PAGE=kpi`）。
/// 正式首页怎么放这个组件，等 2.1 出 iOS 首页图给 Kevin 点头后再定。
final class KpiDebugController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "KPI 组件（调试）"
        UI.paintBg(self)
        let grid = KpiGridView(stats: KpiGridView.stats())
        view.addSubview(grid)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 21),
            grid.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -21),
            grid.topAnchor.constraint(equalTo: g.topAnchor, constant: 40),
        ])
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }
}
