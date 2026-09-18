import UIKit

/// 「地区」入口的第一级：选国家/地区。
///
/// 规格：0 09-18 派活——「不需要既有国家地区又有省份……进到广东省还可以
/// 再点一下，选择是什么市」。这一屏 + `RegionListViewController` 是钻取的
/// 前两级（城市那一级这次先不做，见 `ProfileCodes.swift` 类注释）。
///
/// 🚨 选完直接吐给 `onDone`，**不在这里自己 pop**——popToViewController 要
///    popToViewController 要 pop 回哪一屏，只有发起这条流程的调用方
///    （`AccountViewController`）知道，pop 的责任留给它，不然这一屏和
///    `RegionListViewController` 都要知道"我是在钻几层"这件跟自己无关的事。
final class CountryListViewController: PushedViewController,
        UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {

    /// 打开这一屏时已经存的国家/省州——只用来给当前选中项打勾，不影响列表内容。
    var initialCountry: String = ""
    var initialRegion: String = ""

    /// 走到头了（选完国家、且这个国家没有可选省州；或选完了省州）——
    /// 第二个参数是省州 code，没有可选省州时传空串。
    var onDone: ((_ country: String, _ region: String) -> Void)?

    private let table = UITableView(frame: .zero, style: .plain)
    private let searchField = UITextField()
    private var all: [(code: String, label: String)] = []
    private var filtered: [(code: String, label: String)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.profile_country
        all = ProfileCodes.allCountries
        filtered = all

        let search = UIView()
        search.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        search.layer.cornerRadius = 14
        search.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholder = L.profile_country_search
        searchField.font = .systemFont(ofSize: 15)
        searchField.textColor = Skin.text
        searchField.accessibilityIdentifier = "country.search"
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        search.addSubview(searchField)

        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        view.addSubview(search)
        view.addSubview(table)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: g.topAnchor, constant: 12),
            search.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 21),
            search.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -21),
            search.heightAnchor.constraint(equalToConstant: 46),
            searchField.leadingAnchor.constraint(equalTo: search.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: search.trailingAnchor, constant: -14),
            searchField.centerYAnchor.constraint(equalTo: search.centerYAnchor),

            table.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func searchChanged() {
        let q = (searchField.text ?? "").trimmingCharacters(in: .whitespaces)
        filtered = q.isEmpty ? all : all.filter { $0.label.localizedCaseInsensitiveContains(q) }
        table.reloadData()
    }

    func textFieldShouldReturn(_ t: UITextField) -> Bool {
        t.resignFirstResponder(); return true
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int {
        filtered.count
    }

    func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = tv.dequeueReusableCell(withIdentifier: "row", for: ip)
        let item = filtered[ip.row]
        cell.textLabel?.text = item.label
        cell.textLabel?.textColor = Skin.text
        cell.backgroundColor = .clear
        cell.accessoryType = item.code == initialCountry ? .checkmark : .none
        return cell
    }

    // MARK: - UITableViewDelegate

    /// 选了这个国家：有省州就钻进去，没有就直接收工（不弹一个空列表）。
    func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
        tv.deselectRow(at: ip, animated: true)
        let code = filtered[ip.row].code
        let opts = ProfileCodes.regions(of: code)
        if opts.isEmpty {
            onDone?(code, "")
            return
        }
        let vc = RegionListViewController()
        vc.countryCode = code
        // 🚨 只有还留在同一个国家里，"上次选过的省"这个勾才有意义——
        //    换了国家，旧省份码大概率对不上新国家，不该在这里显示成选中。
        vc.initialRegion = (code == initialCountry) ? initialRegion : ""
        vc.onDone = { [weak self] region in
            self?.onDone?(code, region)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
}
