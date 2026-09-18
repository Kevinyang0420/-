import UIKit

/// 「地区」钻取的第二级：选省州（按 `CountryListViewController` 选中的
/// 国家过滤）。城市这一级这次先不做，见 `ProfileCodes.swift` 类注释。
final class RegionListViewController: PushedViewController,
        UITableViewDataSource, UITableViewDelegate {

    /// 上一级选中的国家 code——**调用方必须先设好这个再 push**。
    var countryCode: String = ""
    /// 打开这一屏时已经存的省州——只用来给当前选中项打勾。
    var initialRegion: String = ""
    /// 选完了，把省州 code 吐给上一级（`CountryListViewController`）。
    var onDone: ((_ region: String) -> Void)?

    private let table = UITableView(frame: .zero, style: .plain)
    private var items: [(code: String, label: String)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.profile_region
        items = ProfileCodes.regions(of: countryCode)

        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "row")
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
        let cell = tv.dequeueReusableCell(withIdentifier: "row", for: ip)
        let item = items[ip.row]
        cell.textLabel?.text = item.label
        cell.textLabel?.textColor = Skin.text
        cell.backgroundColor = .clear
        cell.accessoryType = item.code == initialRegion ? .checkmark : .none
        return cell
    }

    func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
        tv.deselectRow(at: ip, animated: true)
        onDone?(items[ip.row].code)
    }
}
