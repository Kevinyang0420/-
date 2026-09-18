import UIKit

/// 职业选择列表——27 项终稿（规格§4.3），选"其他"由调用方接后续的文本输入。
///
/// 🚨 09-18 三订：原来是 `UIAlertController` actionSheet，Kevin 反馈「职业
/// 只有 27 条都嫌长……往下要往下拉，那么费劲干嘛呢」——**27 条都嫌长，说明
/// 是行高的问题，不是条数的问题**（0 原话）。换成跟 `CountryListViewController`/
/// `RegionListViewController` 同一套紧凑 `UITableView`，同一个行高常量，
/// 别让"国家地区"和"职业"两处各按各的高矮来，那是同一条规矩的两个出口。
final class JobListViewController: PushedViewController,
        UITableViewDataSource, UITableViewDelegate {

    /// 打开这一屏时已经存的职业 code——只用来给当前选中项打勾。
    var initialJob: String = ""
    /// 选完了，把职业 code 吐给调用方——`occOther` 也原样吐出去，
    /// 要不要接文本输入是调用方的事，这一屏只管"选了哪一项"。
    var onDone: ((_ code: String) -> Void)?

    private let table = UITableView(frame: .zero, style: .plain)

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.profile_job

        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .clear
        table.separatorColor = UIColor.white.withAlphaComponent(0.08)
        // 🚨 跟国家/省州两页同一个行高常量（48pt）——三处是同一条"翻起来费劲"
        //    规矩的三个出口，改一处不改另外两处等于没改。
        table.rowHeight = 48
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
        ProfileCodes.occupations.count
    }

    func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = tv.dequeueReusableCell(withIdentifier: "row", for: ip)
        let o = ProfileCodes.occupations[ip.row]
        cell.textLabel?.text = ProfileCodes.occupationLabel(o.code)
        cell.textLabel?.font = .systemFont(ofSize: 16)
        cell.textLabel?.textColor = Skin.text
        cell.backgroundColor = .clear
        cell.accessoryType = o.code == initialJob ? .checkmark : .none
        return cell
    }

    func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
        tv.deselectRow(at: ip, animated: true)
        onDone?(ProfileCodes.occupations[ip.row].code)
    }
}
