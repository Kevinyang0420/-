import UIKit

/// 「数据来源 / 开源许可」——09-18 五订，跟城市数据（GeoNames）同一批加的。
///
/// 🚨🚨 0 核完 CC BY 4.0 §3(a)(1)(B)：我们筛过、加了 py/idx 字段，
///    §3(a)(1)(B) 要求"indicate if You modified the Licensed Material"，
///    光写"数据来自 GeoNames"不够，必须写明改过——这一屏显示的文本
///    （`ProfileCodes.dataLicenseText`）已经含"Modified: ..."那句，
///    **别在这里自己再拼一遍署名，唯一出处是 JSON 的 `_license` 字段**，
///    数据换版时这份文本会跟着换，写死在这儿就会漂。
/// 🚨 英文原文，**不翻译成 9 语言**——CC BY 4.0 不要求，0 原话
///    「翻译只会造 9 个漂移面换零法律收益」。
final class DataAttributionViewController: PushedViewController {

    private let docBox = UIView()
    private let docHead = UILabel()
    private let body = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L.data_sources_title
        UI.paintBg(self)

        docBox.backgroundColor = Theme.panel
        docBox.layer.cornerRadius = 18
        docBox.layer.borderWidth = 0.6
        docBox.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        docBox.translatesAutoresizingMaskIntoConstraints = false

        docHead.text = L.data_sources_title
        docHead.font = .systemFont(ofSize: 13, weight: .semibold)
        docHead.textColor = Theme.dim
        docHead.translatesAutoresizingMaskIntoConstraints = false

        // 🚨 读不到时不装作没这回事——空文本上屏会看起来像"这屏是空的/坏的"，
        //    而真实原因是资源没装上。跟 `ProfileCodes` 其余"装不上就是空表，
        //    不崩"的约定一致：不崩，但**说清楚**。
        let text = ProfileCodes.dataLicenseText
        body.text = text.isEmpty ? L.data_sources_unavailable : text
        body.font = .systemFont(ofSize: 14)
        body.textColor = Theme.text
        body.numberOfLines = 0
        body.accessibilityIdentifier = "data.attribution.body"
        body.translatesAutoresizingMaskIntoConstraints = false

        docBox.addSubview(docHead)
        docBox.addSubview(body)
        view.addSubview(docBox)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            docBox.topAnchor.constraint(equalTo: g.topAnchor, constant: 8),
            docBox.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: Theme.pad),
            docBox.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -Theme.pad),

            docHead.topAnchor.constraint(equalTo: docBox.topAnchor, constant: 14),
            docHead.leadingAnchor.constraint(equalTo: docBox.leadingAnchor, constant: 16),
            docHead.trailingAnchor.constraint(equalTo: docBox.trailingAnchor, constant: -16),
            body.topAnchor.constraint(equalTo: docHead.bottomAnchor, constant: 8),
            body.leadingAnchor.constraint(equalTo: docBox.leadingAnchor, constant: 16),
            body.trailingAnchor.constraint(equalTo: docBox.trailingAnchor, constant: -16),
            body.bottomAnchor.constraint(equalTo: docBox.bottomAnchor, constant: -16),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }
}
