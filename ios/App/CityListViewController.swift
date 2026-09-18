import UIKit

/// 「地区」钻取的第三级：选城市（按 `RegionListViewController` 选中的省州
/// 过滤）。09-18 五订——第一版（三订）城市这一级没做，卡在 GeoNames 署名
/// 条款没定；0 09-18 核完 CC BY 4.0 许可证正文，锁解了，这一屏补上。
///
/// 🚨 版式/行高跟国家/省州两屏同一套（`ProfileCodes.listRowHeight`、
///    `.value1` 样式 cell），同一条"翻起来费劲"规矩的第三个出口。
final class CityListViewController: PushedViewController,
        UITableViewDataSource, UITableViewDelegate {

    /// 上一级选中的省州 code——**调用方必须先设好这个再 push**。
    var regionCode: String = ""
    /// 打开这一屏时已经存的城市——只用来给当前选中项打勾。
    var initialCity: String = ""
    /// 选完了，把城市 code 吐给上一级（`RegionListViewController`）。
    var onDone: ((_ city: String) -> Void)?

    private let table = UITableView(frame: .zero, style: .plain)
    private var items: [(code: String, label: String)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.profile_city
        items = ProfileCodes.cities(of: regionCode)

        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .clear
        table.separatorColor = UIColor.white.withAlphaComponent(0.08)
        table.rowHeight = ProfileCodes.listRowHeight
        table.dataSource = self
        table.delegate = self
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
        cell.textLabel?.text = item.label
        cell.textLabel?.font = .systemFont(ofSize: 16)
        cell.textLabel?.textColor = Skin.text
        cell.backgroundColor = .clear
        cell.accessoryType = item.code == initialCity ? .checkmark : .none
        return cell
    }

    func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
        tv.deselectRow(at: ip, animated: true)
        onDone?(items[ip.row].code)
    }
}
