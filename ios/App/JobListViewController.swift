import UIKit

/// 职业选择——09-18 四订①：从紧凑 `UITableView` push 改成**半高 sheet + 双列
/// chip 网格**。Grok 审出「职业 27 条和地区共用全屏 push 列表」是这次抱怨的
/// 结构根因之一（原话「27 条搜是侮辱」），0 拍板三点：
///   ①半高 sheet ②双列 chip，每枚约 36pt ③**不要搜索框**，选中即关（不需要
///   额外的"确认"按钮）。
///
/// 🚨🚨 09-18 四订①第二轮（0 打回重做）：第一版把 detent 定死在 58%（Grok
///    建议的 55-60%），但 27 项两列＝14 行，14×36+13×8 间距+插图 ≈ 636pt，
///    58% detent 实际可用高度只有约 476pt——**装不满，要划一下才能看到
///    "其他"**。我当时加了 `.large()` 第二档当出口，0 打回：
///    「他嫌弃的原话正是『往下要往下拉，那么费劲干嘛呢』——多一个手势才够得到，
///    对他就是『还是要拉』」，配套点了 `feedback_ui_below_fold_is_missing`
///    这条老账（滚不到的地方＝不存在）。**判据换成：打开就不做任何手势，
///    27 项全在屏幕上。** 现在 detent 直接开到 75%（0 给的三选一里的①，
///    最不动 chip 尺寸/列数，风险最小），真机截图数过 27 项全可见才算过。
///
/// 🚨 这一屏现在是**弹出**（`present`），不是 push——不再继承
/// `PushedViewController`（那是给 push 场景管导航栏显隐的，跟 sheet 无关），
/// 调用方也不该再对它做 `popToViewController`，选中即在这里自己 `dismiss`，
/// `onDone` 在 dismiss 完成之后才触发（见 `didSelectItemAt`）。
final class JobListViewController: UIViewController,
        UICollectionViewDataSource, UICollectionViewDelegate,
        UICollectionViewDelegateFlowLayout {

    /// 打开这一屏时已经存的职业 code——只用来给当前选中项打个高亮边框。
    var initialJob: String = ""
    /// 选完了，把职业 code 吐给调用方（sheet 已经自己关掉之后才调）——
    /// `occOther` 也原样吐出去，要不要接文本输入是调用方的事。
    var onDone: ((_ code: String) -> Void)?

    private static let chipHeight: CGFloat = 36
    private static let columns = 2
    private static let spacing: CGFloat = 8

    private let collection: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = spacing
        layout.minimumInteritemSpacing = spacing
        return UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)

        // 🚨🚨 0 打回重做后的判据：**打开不做任何手势，27 项全部可见**。
        //    58% 装不满；第一次改到 75% 真机 UITest 一量，**26/27，差最后
        //    一个**——公式估的固定开销比实际小，75% 不够留余量。改到 82%，
        //    真机数过 27/27 才定下来（见下面的判据，别再信公式）。
        //    `.large()` 保留成**第二档**，不是默认档——这是给放大字号/小屏
        //    机型的真实逃生口（0 明确说这档留着没问题），不是拿它顶替默认
        //    必须装满这条判据。
        if let sheet = sheetPresentationController {
            sheet.detents = [.custom { ctx in ctx.maximumDetentValue * 0.82 }, .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }

        collection.translatesAutoresizingMaskIntoConstraints = false
        collection.backgroundColor = .clear
        collection.dataSource = self
        collection.delegate = self
        collection.register(JobChipCell.self, forCellWithReuseIdentifier: "chip")
        view.addSubview(collection)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            collection.topAnchor.constraint(equalTo: g.topAnchor, constant: 16),
            collection.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 16),
            collection.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -16),
            collection.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -12),
        ])
    }

    func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        ProfileCodes.occupations.count
    }

    func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
        let cell = cv.dequeueReusableCell(withReuseIdentifier: "chip", for: ip)
        guard let chip = cell as? JobChipCell else { return cell }
        let o = ProfileCodes.occupations[ip.item]
        chip.configure(text: ProfileCodes.occupationLabel(o.code), selected: o.code == initialJob)
        return chip
    }

    func collectionView(_ cv: UICollectionView, layout: UICollectionViewLayout,
                        sizeForItemAt ip: IndexPath) -> CGSize {
        let totalSpacing = Self.spacing * CGFloat(Self.columns - 1)
        let w = (cv.bounds.width - totalSpacing) / CGFloat(Self.columns)
        return CGSize(width: w, height: Self.chipHeight)
    }

    /// 选中即关——不要额外的"确认"按钮（0 拍板）。先 dismiss 再吐 `onDone`，
    /// 不然调用方在 sheet 还没关完的时候弹"其他"的文本输入框会跟 sheet
    /// 收起动画打架。
    func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) {
        let code = ProfileCodes.occupations[ip.item].code
        dismiss(animated: true) { [weak self] in
            self?.onDone?(code)
        }
    }
}

/// 单个职业 chip——圆角胶囊，选中态高亮边框+背景。
private final class JobChipCell: UICollectionViewCell {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 18
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        contentView.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        label.font = .systemFont(ofSize: 14)
        label.textColor = Skin.text
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(text: String, selected: Bool) {
        label.text = text
        contentView.layer.borderColor = (selected ? Skin.text : UIColor.white.withAlphaComponent(0.12)).cgColor
        contentView.backgroundColor = selected
            ? UIColor.white.withAlphaComponent(0.14) : UIColor.white.withAlphaComponent(0.06)
    }
}
