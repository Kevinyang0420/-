import UIKit

/// **Pico HID 标定专用网格 —— 满屏都是我们自己定义的按钮，点哪个都没有副作用。**
///
/// 🚨🚨 0 09-16 定的改法：原计划在系统/Typeless 键盘上标定，但那块屏幕布满
///    "地雷"——globe 键点一下就把键盘换掉（后面全部读数作废，Pico 端毫无察觉），
///    删除键会吃掉已经打出来的字符（把顺序解码搞乱），而且键位是**别人定的**，
///    只能连蒙带猜。这个页面反过来：**我们自己定按钮位置，点哪都无害**，
///    标定从"跟布满地雷的屏幕搏斗"变成"点这一页、读一个字符串"。
///
/// 🚨 这个页面**没有正式入口**，只有 `TRANSLESS_PAGE=calib` 能进
///    （跟本文件同级的 `kb`/`vocab`/`kbwake` 等调试页是同一套约定——
///    这个工程里没有任何地方用 `#if DEBUG` 排除这类页面，全靠"生产环境
///    不会有人设这个环境变量"这一条挡着，这里跟着抄同一个约定，不引入
///    第二套"只有这一页额外裹一层编译开关"的不一致）。
///
/// ## Pico 那边是瞎子，怎么知道点中了哪一格
///
/// 不靠时间同步、也不靠"最后读到的字符串比尝试次数短就分不出谁中谁没中"
/// 那套——每次点击（不管点中按钮还是点在按钮缝隙/网格外）都会**往同一个
/// 累计日志里追加一行**，行数恒等于点击次数，一一对应，读一次日志（在
/// 整个标定序列跑完之后）就有完整的、无歧义的点击轨迹。
///
/// - 点中某个按钮 -> 追加该按钮的坐标标识（如 "R3C2"）
/// - 点在按钮之间的缝隙或整个网格区域之外（背景手势兜底）-> 追加 "MISS"
///
/// XCUITest 只需要读一次 `accessibilityValue`（见 `logLabel`），
/// 按分隔符拆开就是完整、按顺序排好的点击结果，不用猜。
final class CalibGridViewController: PushedViewController {

    /// 🚨 行列数刻意留大一点（覆盖满整个屏幕、格子不算太小）——
    ///    格子越多，标定用的候选落点越密，最后从这些格子里挑 3 个量级
    ///    对应的行更容易找到干净的样本。
    private static let cols = 6
    private static let rows = 10

    /// 分隔符用换行——跟 Notes 那条路径读出来的东西格式一致，
    /// 下游脚本（后续要写的换算脚本）可以复用同一套"按行拆"的逻辑。
    private static let separator = "\n"

    private var log: [String] = []
    private let logLabel = UILabel()
    private let countLabel = UILabel()
    private var buttons: [UIButton] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Pico 标定网格（调试）"
        view.backgroundColor = .black

        buildGrid()

        // 🚨 背景兜底：网格本身满铺整个屏幕，理论上不会有"点在网格外"的情况，
        //    但留着这道闸——万一将来改了网格边距，缝隙点击也不会变成"读不到"。
        let bg = UITapGestureRecognizer(target: self, action: #selector(onBackgroundTap))
        bg.cancelsTouchesInView = false
        view.addGestureRecognizer(bg)

        logLabel.accessibilityIdentifier = "calib.log"
        // 🚨 XCUITest 读多行长文本更稳的是 `.value`（`accessibilityValue`），
        //    `.label` 在很长的时候容易被系统截断——跟这个工程别处用
        //    `accessibilityValue` 当状态载体是同一个约定（见键盘 `setPhase`）。
        // 🚨 这是调试专用页，不用刻意藏起来——刻意做成近乎零尺寸/近乎透明
        //    去"藏"一个无障碍元素，本身就有被系统判成"太小/不可见"从而被
        //    无障碍树过滤掉的风险（零尺寸元素常被直接排除，跟"读到空
        //    字符串"是两种完全不同的坏法）。给它一块真实可见的小条更稳。
        logLabel.isAccessibilityElement = true
        logLabel.numberOfLines = 0
        logLabel.font = .systemFont(ofSize: 9)
        logLabel.textColor = UIColor(white: 0.4, alpha: 1)
        logLabel.backgroundColor = .black
        logLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logLabel)
        NSLayoutConstraint.activate([
            logLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 2),
            logLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            logLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            logLabel.heightAnchor.constraint(equalToConstant: 16),
        ])

        countLabel.accessibilityIdentifier = "calib.count"
        countLabel.textColor = .white
        countLabel.font = .boldSystemFont(ofSize: 14)
        countLabel.text = "0"
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(countLabel)
        NSLayoutConstraint.activate([
            countLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            countLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
        ])
    }

    private func buildGrid() {
        let cols = Self.cols, rows = Self.rows
        for r in 0..<rows {
            for c in 0..<cols {
                let b = UIButton(type: .system)
                b.accessibilityIdentifier = "calib.cell.R\(r)C\(c)"
                // 🚨 交替底色只是方便人肉眼看截图核对网格没有错位，
                //    自动化判据完全不依赖颜色。
                b.backgroundColor = (r + c) % 2 == 0
                    ? UIColor(white: 0.15, alpha: 1) : UIColor(white: 0.25, alpha: 1)
                b.setTitle("\(r),\(c)", for: .normal)
                b.setTitleColor(UIColor(white: 0.5, alpha: 1), for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 9)
                b.tag = r * cols + c
                b.addTarget(self, action: #selector(onCellTap(_:)), for: .touchUpInside)
                view.addSubview(b)
                buttons.append(b)
            }
        }
    }

    /// 🚨 网格四周留一圈真正点不到按钮的边——`verify_calib.py` 强制要求一条
    ///    反向控制（`landed_key: null`），而**铺满整个屏幕的网格没有"点不中"
    ///    这回事**（每个像素都属于某个按钮，clamp 到边缘也还是踩在最外圈
    ///    按钮上）。留一条 20pt 的边，让"归位之后不移动就点"或者"刻意往
    ///    屏幕外沿推一点"这类操作有真实的"落空"可能，MISS 分支才不是死代码。
    private static let margin: CGFloat = 20

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let cols = Self.cols, rows = Self.rows
        let usable = view.bounds.insetBy(dx: Self.margin, dy: Self.margin)
        let w = usable.width / CGFloat(cols)
        let h = usable.height / CGFloat(rows)
        for b in buttons {
            let r = b.tag / cols, c = b.tag % cols
            b.frame = CGRect(x: usable.minX + CGFloat(c) * w,
                             y: usable.minY + CGFloat(r) * h, width: w, height: h)
        }
    }

    private func append(_ entry: String) {
        log.append(entry)
        // 🚨 09-16 真机实测坑：只改 `accessibilityValue` 不动 `.text`，
        //    XCUITest 读到的 `.value` 会停在第一次的内容不再更新——
        //    `micButton.accessibilityValue`（`phase.listening` 那套）能实时
        //    刷新，是因为按钮那边每次连着别的可见状态一起变（背景色/图标），
        //    真的触发了布局重绘；这个纯文字 label 从来没变过 `.text`，
        //    没有视觉变化触发重绘，无障碍层就没跟着刷新。
        //    直接把 `.text` 也设成同一份内容——反正是调试页，全显示出来
        //    也没关系，`.text` 变了才会真正带动布局/无障碍一起刷新。
        let joined = log.joined(separator: Self.separator)
        logLabel.text = joined
        logLabel.accessibilityValue = joined
        countLabel.text = "\(log.count)"
    }

    @objc private func onCellTap(_ sender: UIButton) {
        let cols = Self.cols
        let r = sender.tag / cols, c = sender.tag % cols
        append("R\(r)C\(c)")
    }

    @objc private func onBackgroundTap(_ g: UITapGestureRecognizer) {
        // 🚨 `cancelsTouchesInView = false` 意味着按钮自己的 `touchUpInside`
        //    会先响一次——这里不能对"点中了按钮"重复记一遍"MISS"。
        //    判据：手势落点如果确实在某个按钮的 frame 内，交给按钮自己处理，
        //    这里只补"网格覆盖不到的地方"那一类。
        let p = g.location(in: view)
        if buttons.contains(where: { $0.frame.contains(p) }) { return }
        append("MISS")
    }
}
