import UIKit

/// 「地区」入口的第一级：选国家/地区。
///
/// 规格：0 09-18 派活——「不需要既有国家地区又有省份……进到广东省还可以
/// 再点一下，选择是什么市」。这一屏 + `RegionListViewController` 是钻取的
/// 前两级（城市那一级这次先不做，见 `ProfileCodes.swift` 类注释）。
///
/// 🚨🚨 09-18 三订：Kevin 真机反馈「这一个下拉菜单弄太长了……国家地区也是，
///    搞这么大、这么长」——249 项要能快速找到，三件事一起做：
///    ①**行高压紧**（`rowHeight`），目标一屏 12 行以上，不是默认 44pt 的 7 行；
///    ②**常用置顶**（`ProfileCodes.commonCountryCodes`）+ 分隔线，下面才是
///    按字母排的全量表；③**右侧 A-Z 索引条**（`sectionIndexTitles`，iOS 原生
///    机制，不是自己发明的手势）——索引按**英文名首字母**分组，不是拼音首字母：
///    拼音索引需要一张"汉字→拼音声母"映射表，那类映射表 0 明确说了不许凭记忆
///    手写；英文首字母是数据里现成的字段，排序/分组不用编任何东西。
///
/// 🚨 选完直接吐给 `onDone`，**不在这里自己 pop**——pop 到哪一屏，只有发起
///    这条流程的调用方（`AccountViewController`）知道，pop 的责任留给它。
final class CountryListViewController: PushedViewController,
        UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {

    /// 打开这一屏时已经存的国家/省州——只用来给当前选中项打勾，不影响列表内容。
    var initialCountry: String = ""
    var initialRegion: String = ""

    /// 走到头了（选完国家、且这个国家没有可选省州；或选完了省州）——
    /// 第二个参数是省州 code，没有可选省州时传空串。
    var onDone: ((_ country: String, _ region: String) -> Void)?

    /// 每行高度——48pt 比默认 44pt 略大方便点击，但比原来那种自动撑开的
    /// 高度小得多；实测（见截图/UITest）一屏能看到 12 行以上。
    private static let rowHeight: CGFloat = 48
    private static let commonSectionIndex = "★"

    private let table = UITableView(frame: .zero, style: .plain)
    private let searchField = UITextField()

    /// (code, label, 供搜索用的 zh/zht/en 拼接串, 原始英文名——分组用)
    private typealias Item = (code: String, label: String, searchText: String, en: String)
    private var common: [Item] = []
    private var lettered: [(letter: String, items: [Item])] = []
    private var all: [Item] = []
    private var searching = false
    private var filtered: [Item] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.profile_country
        all = ProfileCodes.allCountries
        let commonSet = Set(ProfileCodes.commonCountryCodes)
        common = ProfileCodes.commonCountryCodes.compactMap { code in
            all.first { $0.code == code }
        }
        let rest = all.filter { !commonSet.contains($0.code) }
        var byLetter: [String: [Item]] = [:]
        for item in rest {
            // 🚨 分组键用**原始英文名**首字母（`item.en`），不是 `label`——
            //    非中文界面下 `label` 本来就是英文名没问题，但中文界面下
            //    `label` 是中文，拿中文字首字取分组毫无意义（"中"、"日"这种字
            //    排不出 A-Z）。用 `item.en` 就不受界面语言影响，分组结果恒定。
            let letter = String(item.en.first ?? Character("#")).uppercased()
            byLetter[letter, default: []].append(item)
        }
        lettered = byLetter.keys.sorted().map { ($0, byLetter[$0] ?? []) }

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
        table.separatorColor = UIColor.white.withAlphaComponent(0.08)
        table.rowHeight = Self.rowHeight
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

            table.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 8),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    @objc private func searchChanged() {
        let q = (searchField.text ?? "").trimmingCharacters(in: .whitespaces)
        searching = !q.isEmpty
        if searching {
            filtered = all.filter { $0.searchText.localizedCaseInsensitiveContains(q) }
        }
        table.reloadData()
    }

    func textFieldShouldReturn(_ t: UITextField) -> Bool {
        t.resignFirstResponder(); return true
    }

    // MARK: - 分节

    /// 搜索中：一个平铺列表，没有分节没有索引（索引条对着一份被过滤过的表没有意义）。
    /// 不搜索：0 = 常用（置顶），1...N = 按英文首字母分的组。
    private func items(in section: Int) -> [Item] {
        if searching { return filtered }
        return section == 0 ? common : lettered[section - 1].items
    }

    func numberOfSections(in tv: UITableView) -> Int {
        searching ? 1 : 1 + lettered.count
    }

    func tableView(_ tv: UITableView, titleForHeaderInSection section: Int) -> String? {
        if searching { return nil }
        return section == 0 ? nil : lettered[section - 1].letter
    }

    /// 🚨 右侧 A-Z 索引条——iOS 原生 `sectionIndexTitles` 机制，点一下跳一节，
    ///    不是自己拿手势重新发明一遍。搜索状态下不显示（列表已经被过滤，
    ///    索引条对着一份临时列表没有意义，点了也不知道要跳到哪）。
    func sectionIndexTitles(for tv: UITableView) -> [String]? {
        guard !searching else { return nil }
        return [Self.commonSectionIndex] + lettered.map { $0.letter }
    }

    func tableView(_ tv: UITableView, sectionForSectionIndexTitle title: String,
                  at index: Int) -> Int {
        index
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int {
        items(in: section).count
    }

    func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = tv.dequeueReusableCell(withIdentifier: "row", for: ip)
        let item = items(in: ip.section)[ip.row]
        cell.textLabel?.text = item.label
        cell.textLabel?.font = .systemFont(ofSize: 16)
        cell.textLabel?.textColor = Skin.text
        cell.backgroundColor = .clear
        cell.accessoryType = item.code == initialCountry ? .checkmark : .none
        return cell
    }

    // MARK: - UITableViewDelegate

    /// 选了这个国家：有省州就钻进去，没有就直接收工（不弹一个空列表）。
    func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
        tv.deselectRow(at: ip, animated: true)
        let code = items(in: ip.section)[ip.row].code
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
