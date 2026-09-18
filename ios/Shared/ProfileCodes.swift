import Foundation

/// 国家/一级行政区/职业下拉的**骨架数据**——不是最终数据源。
///
/// 🚨🚨 2026-09-18·`_规格_用户资料结构化下拉_20260918.md`：0 拍板"字段结构和下拉骨架先做，
///    值先留空"——数据源（ISO 3166 显示名怎么翻、职业用 ISCO 哪一档）还没定，城市（GeoNames）
///    许可证判读没过、整个先不接。这个类只放够跑通交互的极少量占位条目，用来证明三件事：
///    ①国家→省州能级联（省州按国家码前缀过滤，不用额外映射表，跟 ISO 3166-2 代码自身
///    携带父级前缀那条设计一致）②存进服务端的是 code 不是显示名
///    ③职业"其他"走独立的 code（`occOther`）+ 自由文本字段，不混进主枚举。
///
///    🚨 **这份逐字照抄安卓 `ProfileCodes.java`**——同一份产品决定三端各写一份必然漂，
///    数据/注释/口径都跟那份对齐，改一处两边都要改。
///
///    🚨 **真表落地时这个类整个作废**——改成读 1.1 按 `LANG_LABELS_BY_UI` 同款架构生成的
///    `COUNTRY_*`/`OCC_*` 表（见 spec §三），届时把这里的占位数组删掉，
///    `label(for:in:)`/`regions(of:)` 这两个函数签名不变、内部实现换成查生成表。
///
///    🚨 显示名这里只给中/英——9 门界面语言的翻译是真表落地时才做的活，不在骨架阶段
///    伪造凑数（伪造出来的"翻译"比没有更糟，会被当成真译文抄走）。非中文界面一律退英文，
///    **包括繁体**（骨架阶段没有单独的繁体译文，别拿简体凑数、也别拿英文冒充繁体）。
enum ProfileCodes {

    /// (code, 中文名, 英文名)。code 是 ISO 3166-1 alpha-2。
    static let countries: [(code: String, zh: String, en: String)] = [
        ("CN", "中国大陆", "Mainland China"),
        ("HK", "中国香港", "Hong Kong"),
        ("TW", "中国台湾", "Taiwan"),
        ("US", "美国", "United States"),
        ("JP", "日本", "Japan"),
        ("GB", "英国", "United Kingdom"),
    ]

    /// (code, 中文名, 英文名)。code 是 ISO 3166-2，前缀即所属国家（"CN-44" 属于 "CN"）。
    static let regions: [(code: String, zh: String, en: String)] = [
        ("CN-44", "广东省", "Guangdong"),
        ("CN-31", "上海市", "Shanghai"),
        ("CN-11", "北京市", "Beijing"),
        ("HK-HCW", "香港岛", "Hong Kong Island"),
        ("US-CA", "加利福尼亚州", "California"),
        ("US-NY", "纽约州", "New York"),
        ("JP-13", "东京都", "Tokyo"),
    ]

    /// "其他" 走的固定 code——主字段只存它，用户自己写的文本存进另一个字段，不进这张表。
    static let occOther = "occ_other"

    /// (code, 中文名, 英文名)。code 是我们自建的永久语义化字符串，不是 ISCO 原始编号。
    /// 🚨 2026-09-18 规格§4.3 27项已钉死——这不是占位数据了，code 改不得（标签可改，code
    ///    不可改，拆类时新增 code、旧 code 保留）。中/英标签抄规格表原文。
    static let occupations: [(code: String, zh: String, en: String)] = [
        ("occ_student", "学生", "Student"),
        ("occ_education_training", "教育培训", "Education & Training"),
        ("occ_healthcare", "医疗健康", "Healthcare"),
        ("occ_finance_audit", "金融财务审计", "Finance / Audit"),
        ("occ_legal", "法律", "Legal"),
        ("occ_engineering", "工程技术研发", "Engineering / R&D"),
        ("occ_software_it", "软件IT", "Software / IT"),
        ("occ_design_creative", "设计创意", "Design / Creative"),
        ("occ_marketing", "市场营销", "Marketing"),
        ("occ_sales_biz", "销售商务", "Sales / Business"),
        ("occ_customer_service_ops", "客服运营", "Customer Service / Ops"),
        ("occ_hr_admin", "人力资源行政", "HR / Admin"),
        ("occ_supply_chain_logistics", "采购供应链物流", "Procurement / Supply Chain"),
        ("occ_manufacturing", "制造生产", "Manufacturing"),
        ("occ_construction_realestate", "建筑房地产", "Construction / Real Estate"),
        ("occ_retail_fnb_service", "零售餐饮服务业", "Retail / F&B / Service"),
        ("occ_agriculture_fishery", "农业渔业", "Agriculture / Fishery"),
        ("occ_government_public", "政府公共服务", "Government / Public Service"),
        ("occ_nonprofit", "非营利公益", "Nonprofit / NGO"),
        ("occ_media_publishing", "媒体新闻出版", "Media / Publishing"),
        ("occ_arts_culture_sports", "艺术文化体育娱乐", "Arts / Culture / Sports"),
        ("occ_transportation", "交通运输", "Transportation"),
        ("occ_freelance", "自由职业", "Freelance"),
        ("occ_homemaker", "家庭主妇主夫", "Homemaker"),
        ("occ_retired", "退休", "Retired"),
        ("occ_job_seeking", "待业求职中", "Job Seeking"),
        (occOther, "其他", "Other"),
    ]

    /// 中文界面显示中文名，别的界面（包括繁体）先退英文——骨架阶段不伪造翻译。
    private static var zhUi: Bool { Lang.effective == Lang.zh }

    /// 从三元组表里按 code 找显示名；找不到就把 code 原样吐回去。
    private static func labelIn(_ table: [(code: String, zh: String, en: String)],
                                _ code: String) -> String {
        guard let row = table.first(where: { $0.code == code }) else { return code }
        return zhUi ? row.zh : row.en
    }

    static func countryLabel(_ code: String) -> String {
        code.isEmpty ? "" : labelIn(countries, code)
    }

    static func regionLabel(_ code: String) -> String {
        code.isEmpty ? "" : labelIn(regions, code)
    }

    static func occupationLabel(_ code: String) -> String {
        code.isEmpty ? "" : labelIn(occupations, code)
    }

    /// 某个国家下面有哪些一级行政区——**直接按代码前缀过滤**，不额外建"省属于哪个国家"的
    /// 映射表（0 点过这条：ISO 3166-2 代码自己带父级前缀，级联关系代码自己携带）。
    static func regions(of countryCode: String) -> [(code: String, zh: String, en: String)] {
        let prefix = countryCode + "-"
        return regions.filter { $0.code.hasPrefix(prefix) }
    }

    // ------------------------------------------------------------ 自测

    /// 由 `gate_all_selftests.py` 自动发现并运行。
    ///
    /// 🚨 这段级联过滤逻辑本该在 `ProfileDropdownSpec.swift`（UITest）里连着 UI 一起
    ///    验，但那条路会跟 `AccountViewController.viewDidLoad()` 里真实的
    ///    `Auth.fetchProfile()` 网络请求赛跑——服务端返回空的国家/省份，会把本地
    ///    为了测试种的 "CN" 原样覆盖回空（B1/B3 契约本身是对的：服务端说没有就该
    ///    显示没有），级联逻辑还没等到被点开就已经被冲掉了。**这不是产品 bug，是
    ///    测试手法跟真实网络时序打架**——所以纯逻辑这半放这里单独测，不跟网络赛跑；
    ///    UI 那半只验"picker 弹得出来、职业其他能输文本"这种不依赖服务端返回值的部分。
    static func selfTest() -> String? {
        var bad: [String] = []

        // ① CN 前缀过滤：只出广东/上海/北京，不出日本的东京都
        let cnRegions = regions(of: "CN").map { $0.code }
        if !cnRegions.contains("CN-44") || !cnRegions.contains("CN-31")
            || !cnRegions.contains("CN-11") {
            bad.append("CN 级联漏了应有的省份 -> \(cnRegions)")
        }
        if cnRegions.contains("JP-13") {
            bad.append("CN 级联混进了日本的省份 -> \(cnRegions)")
        }

        // ② JP 前缀过滤：只出东京都，不该混进任何 CN- 开头的
        let jpRegions = regions(of: "JP").map { $0.code }
        if jpRegions != ["JP-13"] {
            bad.append("JP 级联不对 -> \(jpRegions)")
        }

        // ③ 没有任何省份的国家（表里的 US 有，但假设一个没有的）：回空，不许崩
        if !regions(of: "GB").isEmpty {
            bad.append("GB 在骨架表里没有省份，级联应该回空 -> \(regions(of: "GB"))")
        }

        // ④ 查不到的 code 原样吐回去，不是空字符串也不是崩溃
        if countryLabel("ZZ") != "ZZ" { bad.append("查不到的国家 code 没有原样返回") }
        if occupationLabel("occ_not_real") != "occ_not_real" {
            bad.append("查不到的职业 code 没有原样返回")
        }

        // ⑤ 空 code 回空字符串，不是原样返回空
        if !countryLabel("").isEmpty { bad.append("空 code 该回空字符串") }

        // ⑥ occOther 常量本身就在 occupations 表里，两处不能不一致
        if !occupations.contains(where: { $0.code == occOther }) {
            bad.append("occOther 常量跟 occupations 表对不上")
        }

        return bad.isEmpty ? nil : bad.joined(separator: "; ")
    }
}
