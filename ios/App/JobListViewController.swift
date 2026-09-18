import UIKit

/// 职业选择——09-18 四订①：从紧凑 `UITableView` push 改成**半高 sheet + 双列
/// chip 网格**。Grok 审出「职业 27 条和地区共用全屏 push 列表」是这次抱怨的
/// 结构根因之一（原话「27 条搜是侮辱」），0 拍板三点：
///   ①半高 sheet（屏高约 55-60%）②双列 chip，每枚约 36pt ③**不要搜索框**，
///   选中即关（不需要额外的"确认"按钮）。
/// 27 项两列排布是 14 行 × 36pt ≈ 504pt，半高 sheet 装得下，不用滚动。
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
    // 🚨 09-18 四订①真机实测（UITest 截图，非公式推算）：27 项两列 = 14 行，
    //    14×36 + 13×10 间距 ≈ 634pt 内容，比 58% detent 实际可用高度
    //    （约 470-480pt）大——最后一两行会被裁到看不见，跟 Grok「几乎不用
    //    滑」的设计意图有落差。缩间距只能缓解，缩不平（算过：就算间距压到
    //    0，14×36=504pt 仍然超）。**真正的解法是给 sheet 一个可拖高的出口**
    //    （见下面 `.large()` 第二档），这里把间距收紧到 8 只是顺手再挤一点。
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

        // 🚨 半高 sheet：默认停在约 58%（Grok 要的 55-60%），但 27 项两列
        //    在 58% 里装不满（见 `spacing` 常量注释，真机截图实测过），
        //    所以**加一个 `.large()` 第二档**——默认还是半高，想看全 27 项
        //    可以拖到底，不用被迫先滚动才能找到最后几个。抓手本来就在，
        //    这是给它一个真的用处，不是额外加控件。
        if let sheet = sheetPresentationController {
            sheet.detents = [.custom { ctx in ctx.maximumDetentValue * 0.58 }, .large()]
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
