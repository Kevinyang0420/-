import UIKit

/// 「地区」钻取的第二级：选省州（按 `CountryListViewController` 选中的
/// 国家过滤）。
///
/// 🚨 09-18 三订：行高压紧跟 `CountryListViewController` 同一个值、同一个
///    理由——中国 34 个省州一样会撞到"翻起来费劲"这条，不只是国家那一页的事。
/// 🚨 09-18 四订③：判据从 12+ 行改成 ≥17 行。
/// 🚨🚨 0 09-18 点名：行高原来在这里和 `CountryListViewController` 各写一份
///    字面量 48——同一条规矩两个出口，改一处不改另一处就悄悄不一致且不报错。
///    现在两边都读 `ProfileCodes.listRowHeight`，只有一处。
/// 🚨🚨 09-18 五订：城市这一级接上了（锁——GeoNames 署名条款——已解）。
///    `onDone` 签名从 `(region)` 改成 `(region, city)`——跟
///    `CountryListViewController.onDone` 09-18 二订那次加省份是同一条道理：
///    钻得更深，往上传的元组也要跟着变长，不是另开一条回调。
final class RegionListViewController: PushedViewController,
        UITableViewDataSource, UITableViewDelegate {

    /// 上一级选中的国家 code——**调用方必须先设好这个再 push**。
    var countryCode: String = ""
    /// 打开这一屏时已经存的省州——只用来给当前选中项打勾。
    var initialRegion: String = ""
    /// 打开这一屏时已经存的城市——只有还留在同一个省州时才有意义，
    /// 传法跟 `CountryListViewController.initialRegion` 同一条道理。
    var initialCity: String = ""
    /// 走到头了（选完省州、且这个省州没有可选城市；或选完了城市）——
    /// 第二个参数是城市 code，没有可选城市时传空串。
    var onDone: ((_ region: String, _ city: String) -> Void)?

    private let table = UITableView(frame: .zero, style: .plain)
    private var items: [(code: String, label: String)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.profile_region
        items = ProfileCodes.regions(of: countryCode)

        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .clear
        table.separatorColor = UIColor.white.withAlphaComponent(0.08)
        table.rowHeight = ProfileCodes.listRowHeight
        table.dataSource = self
        table.delegate = self
        // 🚨 09-18 四订⑥：不用 class-based register——那样拿不到 `.value1`
        //    的右侧 detailTextLabel，见 `CountryListViewController` 同一条注释。
        view.addSubview(table)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: g.topAnchor, constant: 12),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = tv.dequeueReusableCell(withIdentifier: "row")
            ?? UITableViewCell(style: .value1, reuseIdentifier: "row")
        let item = items[ip.row]
        // 🚨 省州没有国旗（`flagEmoji` 只认两位国家码，`CN-GD` 这种会原样
        //    返回空串），这里只要行尾码，不要旗子——跟 Grok 给的样例一致。
        cell.textLabel?.text = item.label
        cell.textLabel?.font = .systemFont(ofSize: 16)
        cell.textLabel?.textColor = Skin.text
        cell.detailTextLabel?.text = item.code
        cell.detailTextLabel?.font = .systemFont(ofSize: 11)
        cell.detailTextLabel?.textColor = Skin.dim
        cell.backgroundColor = .clear
        cell.accessoryType = item.code == initialRegion ? .checkmark : .none
        return cell
    }

    /// 选了这个省州：有城市就钻进去，没有就直接收工（不弹一个空列表）——
    /// 跟 `CountryListViewController.didSelectRowAt` 的国家→省州那一跳
    /// 同一套逻辑，钻取到第几级都不变。
    func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
        tv.deselectRow(at: ip, animated: true)
        let code = items[ip.row].code
        let opts = ProfileCodes.cities(of: code)
        if opts.isEmpty {
            onDone?(code, "")
            return
        }
        let vc = CityListViewController()
        vc.regionCode = code
        vc.initialCity = (code == initialRegion) ? initialCity : ""
        vc.onDone = { [weak self] city in
            self?.onDone?(code, city)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
}
