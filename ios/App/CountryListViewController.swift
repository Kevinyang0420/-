import UIKit

/// 「地区」入口的第一级：选国家/地区。
///
/// 规格：0 09-18 派活——「不需要既有国家地区又有省份……进到广东省还可以
/// 再点一下，选择是什么市」。这一屏 + `RegionListViewController` +
/// `CityListViewController` 是钻取的三级（09-18 五订：城市那一级原来卡在
/// GeoNames 署名条款没定，锁解了之后接上）。
///
/// 🚨🚨 09-18 三订：Kevin 真机反馈「这一个下拉菜单弄太长了……国家地区也是，
///    搞这么大、这么长」——249 项要能快速找到，三件事一起做：
///    ①**行高压紧**（`rowHeight`），目标一屏 ≥17 行（09-18 四订③改的判据，
///    不再是这里最初写的 12 行），不是默认 44pt 的 7 行；
///    ②**常用置顶**（`ProfileCodes.commonCountryCodes`）+ 分隔线，下面才是
///    按字母排的全量表；③**右侧 A-Z 索引条**（`sectionIndexTitles`，iOS 原生
///    机制，不是自己发明的手势）。
///
/// 🚨🚨 09-18 四订：③的分组键改了。三订那版按**英文名首字母**分组——Grok
///    审出这是真 bug：中文界面显示的是中文名，拿英文字母分组，"中国"按
///    英文字母会掉进 Z（Zhongguo）或 C（China），自相打架。**分组键现在
///    直接读 `ProfileCodes.allCountries` 里的 `idx`**——1.1 在数据表里发了
///    拼音索引字段（多音字已消歧），中文/繁体界面自动切到拼音分桶，英文界面
///    仍是英文首字母。这里不再自己从 `.en` 现场取首字母，也**不许用
///    `CFStringTransform` 现场转拼音**——同一条规矩不许三端各转一份。
///
/// 🚨 选完直接吐给 `onDone`，**不在这里自己 pop**——pop 到哪一屏，只有发起
///    这条流程的调用方（`AccountViewController`）知道，pop 的责任留给它。
final class CountryListViewController: PushedViewController,
        UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {

    /// 打开这一屏时已经存的国家/省州/城市——只用来给当前选中项打勾，
    /// 不影响列表内容。
    var initialCountry: String = ""
    var initialRegion: String = ""
    var initialCity: String = ""

    /// 走到头了（选完国家且没有省州；或选完省州且没有城市；或选完了城市）——
    /// 09-18 五订：加了城市，三个参数，没走到的那几级传空串。
    var onDone: ((_ country: String, _ region: String, _ city: String) -> Void)?

    /// 每行高度——**读 `ProfileCodes.listRowHeight`，别在这里再写一份字面量**
    /// （0 09-18 点名：country/region 两屏各写了一份 48，是「同一规矩多处
    /// 各一份必漂」的形态，改一处不改另一处两屏就悄悄不一致）。
    /// 09-18 四订③：判据从「12+ 行算过」改成「一屏 ≥17 行」，最终数字
    /// 靠真机/UITest 数可见格数核实，不拿算式当结论。
    private static let commonSectionIndex = "★"

    private let table = UITableView(frame: .zero, style: .plain)
    private let searchField = UITextField()

    /// (code, label, 供搜索用的 zh/zht/en/alt 拼接串, 分组键——中文拼音/英文首字母)
    private typealias Item = (code: String, label: String, searchText: String, idx: String)
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
        // 🚨 09-18 四订⑤：不再是写死的常量，`commonCountryCodes()` 现在是
        //    系统区域推断(槽1)+最近选过(槽2)两槽算出来的——每次开这一屏都
        //    重新算一遍，不缓存。
        let commonCodes = ProfileCodes.commonCountryCodes()
        let commonSet = Set(commonCodes)
        common = commonCodes.compactMap { code in
            all.first { $0.code == code }
        }
        let rest = all.filter { !commonSet.contains($0.code) }
        var byLetter: [String: [Item]] = [:]
        for item in rest {
            // 🚨 分组键直接读 `ProfileCodes` 算好的 `idx`（中文拼音索引/英文
            //    首字母，随界面语言自动切换），这里不再自己推导。
            byLetter[item.idx, default: []].append(item)
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
        table.rowHeight = ProfileCodes.listRowHeight
        table.dataSource = self
        table.delegate = self
        // 🚨 09-18 四订⑥：要「主名 + 行尾次要码」（`.value1` 自带的布局），
        //    `register(UITableViewCell.self, ...)` 走 class-based 复用只能
        //    生成 `.default` 样式的 cell——拿不到右侧 detailTextLabel，
        //    这里改回手动 dequeue/构造，才能选 `.value1`。
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
        let cell = tv.dequeueReusableCell(withIdentifier: "row")
            ?? UITableViewCell(style: .value1, reuseIdentifier: "row")
        let item = items(in: ip.section)[ip.row]
        // 🚨 国旗只对**国家**有意义（`flagEmoji` 传两位 ISO 码），省州没有旗帜，
        //    这一屏全是国家级条目，直接用 `item.code`。
        let flag = ProfileCodes.flagEmoji(item.code)
        cell.textLabel?.text = flag.isEmpty ? item.label : "\(flag)  \(item.label)"
        cell.textLabel?.font = .systemFont(ofSize: 16)
        cell.textLabel?.textColor = Skin.text
        // 🚨🚨 09-18 四订⑥真机 UITest 实测踩到：`textLabel.text` 前面拼了旗子，
        //    accessibility label 默认跟着 `text` 走，于是 `app.staticTexts["中国
        //    大陆"]` 这种精确匹配全部失效——不是测试写错，是显示文本本身变了。
        //    VoiceOver 读"国旗+国名"对用户没有额外信息量，单独钉一个不带旗子的
        //    accessibilityLabel 两头都对：读起来干净，自动化定位也还认识那个名字。
        cell.textLabel?.accessibilityLabel = item.label
        cell.detailTextLabel?.text = item.code
        cell.detailTextLabel?.font = .systemFont(ofSize: 11)
        cell.detailTextLabel?.textColor = Skin.dim
        cell.backgroundColor = .clear
        cell.accessoryType = item.code == initialCountry ? .checkmark : .none
        return cell
    }

    // MARK: - UITableViewDelegate

    /// 选了这个国家：有省州就钻进去，没有就直接收工（不弹一个空列表）。
    func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
        tv.deselectRow(at: ip, animated: true)
        let code = items(in: ip.section)[ip.row].code
        // 🚨 09-18 四订⑤：选中就记进槽2（最近选过），不等真存到服务端才记——
        //    这一屏关掉再打开就该看见它排到常用区最前面。
        ProfileCodes.noteCountrySelected(code)
        let opts = ProfileCodes.regions(of: code)
        if opts.isEmpty {
            onDone?(code, "", "")
            return
        }
        let vc = RegionListViewController()
        vc.countryCode = code
        // 🚨 只有还留在同一个国家里，"上次选过的省/市"这个勾才有意义——
        //    换了国家，旧省份/城市码大概率对不上新国家，不该在这里显示成选中。
        let sameCountry = (code == initialCountry)
        vc.initialRegion = sameCountry ? initialRegion : ""
        vc.initialCity = sameCountry ? initialCity : ""
        vc.onDone = { [weak self] region, city in
            self?.onDone?(code, region, city)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
}
