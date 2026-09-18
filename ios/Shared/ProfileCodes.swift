import Foundation

/// 国家 / 一级行政区的**真实数据**，职业沿用规格 §4.3 已钉死的 27 项终稿。
///
/// 🚨🚨 2026-09-18 全量表落地：`shared/profile_codes.json`（1.1 唯一生成点
/// `tools/gen_profile_codes.py`）——249 个国家、5046 条一级行政区，本文件
/// 只负责**读它、查它**，不许再手抄第三份（之前那版 6 国 7 省的占位表已作废）。
/// `Resources/profile_codes.json` 是从仓库根 `shared/profile_codes.json`
/// **原样复制**的资源副本，换表时两处一起换、别只改一处。
///
/// 🚨🚨 09-18 二订：国家表简/繁都已 249/249 齐全（1.1 换成 CLDR/Babel 生成，
///    修掉了第一版用 `RegionInfo.DisplayName` 结果跟着生成器所在机器系统语言走
///    的 bug）——`CN` 简体"中国大陆"、繁体"中國大陸"，是真的两份译文，不是拿
///    简体凑数。但**省州只有中国 34 条有 `zh`、完全没有 `zht`**，其余 ~5000 条
///    连 `zh` 都是空的，且以后也大概率一直是空（CLDR 没有 subdivision 级别的
///    中文译名）。这个文件要接住的是"**zh/zht 是空字符串时，就算界面是中文/
///    繁体也要退英文**"这条，不能让空字符串在中文界面下被直接显示成一行空白——
///    省州那边永远会撞到这条，不因为国家表已经翻完了就可以省掉这层判断。
///
/// 🚨🚨 老数据迁移：build 1431 用的是上一版手搭的骨架占位表，`CN-44`/`CN-31`/
///    `CN-11` 是**国标**编码，新表一律 ISO 3166-2（广东是 `CN-GD` 不是 `CN-44`）。
///    这 3 个 + 骨架表里另外 4 个（`HK-HCW`/`US-CA`/`US-NY`/`JP-13`）是我自己
///    上一版写的**已知穷举清单**，不是猜的通用国标↔ISO映射表——那种映射表
///    0 明确说了不许凭记忆手写。`legacyRegionMigration` 只覆盖这 7 个，
///    已经点过旧版本这几个占位省份的人，资料页不会因为查不到码而显示空白。
enum ProfileCodes {

    // ------------------------------------------------------------ 装载

    private struct Entry { let code: String; let zh: String; let zht: String; let en: String }

    private static let lock = NSLock()
    private static var loaded = false
    private static var countryList: [Entry] = []
    private static var regionList: [Entry] = []
    private static var countryByCode: [String: Entry] = [:]
    private static var regionByCode: [String: Entry] = [:]

    /// 🚨 键盘扩展和主 App 是两个 bundle，各自找自己的资源——跟
    /// `PinyinSplit.bundle` 同一个理由，用类型锚点找到"我在哪个 bundle 里"。
    private static var bundle: Bundle { Bundle(for: ProfileCodesBundleAnchor.self) }

    private static func ensureLoaded() {
        lock.lock(); defer { lock.unlock() }
        if loaded { return }
        loaded = true
        guard let url = bundle.url(forResource: "profile_codes", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // 🚨 装不上就是空表，不崩——跟 `PinyinSplit.readLines` 同一个约定。
            return
        }
        func parse(_ key: String) -> [Entry] {
            guard let arr = obj[key] as? [[String: Any]] else { return [] }
            return arr.compactMap { row in
                guard let code = row["code"] as? String else { return nil }
                return Entry(code: code, zh: (row["zh"] as? String) ?? "",
                             zht: (row["zht"] as? String) ?? "",
                             en: (row["en"] as? String) ?? "")
            }
        }
        countryList = parse("countries")
        regionList = parse("regions")
        for e in countryList { countryByCode[e.code] = e }
        for e in regionList { regionByCode[e.code] = e }
    }

    // ------------------------------------------------------------ 职业（不变）

    /// "其他" 走的固定 code——主字段只存它，用户自己写的文本存进独立的
    /// `other_text` 字段——绝不能让自由文本混进主枚举字段（spec §三）。
    static let occOther = "occ_other"

    /// (code, 中文名, 英文名)。code 是我们自建的永久语义化字符串，不是 ISCO 原始编号。
    /// 🚨 规格§4.3 27 项已钉死，code 改不得（标签可改，code 不可改）——不受
    ///    国家/省州这次换真表影响，职业这部分终稿状态没变。
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

    // ------------------------------------------------------------ 国家 / 省州

    /// 全部国家，按显示名排序——给列表页直接用。
    /// 🚨 `searchText` 带了 zh/zht/en 三份（空格拼接），**只用来做包含匹配**——
    ///    列表页只显示当前界面语言那一份，但搜索框要三个都能匹配（0 原话
    ///    「打 de 出德国」，界面显示的是中文"德国"，光匹配显示出来的那份，
    ///    打拼音以外的任何东西都搜不到）。`en` 单独再给一份**原始未拼接**的，
    ///    是给 A-Z 分组用的——`searchText` 里的英文名可能带空格（"United
    ///    States"），按空格切出最后一个词取首字母会切错（切出"States"的S，
    ///    不是"United"的U），分组必须用这份没被拼接过的原始英文名。
    static var allCountries: [(code: String, label: String, searchText: String, en: String)] {
        ensureLoaded()
        return countryList.map {
            ($0.code, label($0), [$0.zh, $0.zht, $0.en].joined(separator: " "), $0.en)
        }.sorted { $0.1.localizedCompare($1.1) == .orderedAscending }
    }

    /// 6 个「常用」国家/地区，固定顺序（0 原话「他 99% 的时候点的就是第一组」）——
    /// 置顶展示，跟下面按字母排的全量表分开一节。
    static let commonCountryCodes = ["CN", "HK", "TW", "US", "JP", "GB"]

    /// 某个国家下面有哪些一级行政区，按显示名排序——直接按代码前缀过滤，
    /// 不额外建"省属于哪个国家"的映射表（0 点过这条：ISO 3166-2 代码自己
    /// 带父级前缀，级联关系代码自己携带）。
    static func regions(of countryCode: String) -> [(code: String, label: String)] {
        ensureLoaded()
        let prefix = countryCode + "-"
        return regionList.filter { $0.code.hasPrefix(prefix) }
            .map { ($0.code, label($0)) }
            .sorted { $0.1.localizedCompare($1.1) == .orderedAscending }
    }

    static func countryLabel(_ code: String) -> String {
        ensureLoaded()
        guard !code.isEmpty else { return "" }
        guard let e = countryByCode[code] else { return code }
        return label(e)
    }

    static func regionLabel(_ code: String) -> String {
        ensureLoaded()
        guard !code.isEmpty else { return "" }
        // 🚨 先过一遍老码迁移，再查表——老码本来就查不到，直接查表会
        //    原样吐回一个没人认得的旧 code（比如 "CN-44"），显示成天书。
        let migrated = legacyRegionMigration[code] ?? code
        guard !migrated.isEmpty, let e = regionByCode[migrated] else { return "" }
        return label(e)
    }

    static func occupationLabel(_ code: String) -> String {
        guard !code.isEmpty else { return "" }
        guard let row = occupations.first(where: { $0.code == code }) else { return code }
        // 🚨 职业表没有 `zht`（终稿只给了中/英，见 `occupations` 数组），
        //    繁体界面目前也退英文——跟国家/省州同一条规则，不是漏做。
        return Lang.effective == Lang.zh && !row.zh.isEmpty ? row.zh : row.en
    }

    /// 简体界面显示 `zh`、繁体界面显示 `zht`，别的界面退英文；**该用的那份
    /// 是空字符串时不管界面语言，一律退英文**——空字符串不是"这个国家没有
    /// 对应语言的名字"的正确表现形式，显示出来就是一行空白，用户会以为是
    /// 加载失败（省州目前完全没有 `zht`，天天撞这条，不能删）。
    private static func label(_ e: Entry) -> String {
        switch Lang.effective {
        case Lang.hant: return e.zht.isEmpty ? e.en : e.zht
        case Lang.zh: return e.zh.isEmpty ? e.en : e.zh
        default: return e.en
        }
    }

    /// build 1431 骨架版存过的 7 个占位省州 code → 新表里对应的真 code。
    /// 🚨 只有这 7 个是已知穷举——真查过新表哪个 code 对应哪个实体
    ///    （北京/上海/广东/加州/纽约州/东京，见 commit 里的核对记录），
    ///    不是凭记忆编的通用国标↔ISO映射。`HK-HCW` 新表里没有对应的香港
    ///    省级数据（新表里香港本身是 `CN` 下面的一个区 `CN-HK`，不再单独
    ///    分省），映射到空串——查不到就按"这个字段目前没有值"处理，不强凑。
    private static let legacyRegionMigration: [String: String] = [
        "CN-44": "CN-GD",
        "CN-31": "CN-SH",
        "CN-11": "CN-BJ",
        "HK-HCW": "",
        "US-CA": "US-CA",
        "US-NY": "US-NY",
        "JP-13": "JP-13",
    ]

    // ------------------------------------------------------------ 自测

    /// 由 `gate_all_selftests.py` 自动发现并运行。
    static func selfTest() -> String? {
        var bad: [String] = []
        ensureLoaded()

        // ① 表真的装进来了（不是空表——空表所有断言都会"顺利"通过，那是假绿）
        if countryList.isEmpty { bad.append("国家表是空的——bundle 里没找到 profile_codes.json？") }
        if regionList.isEmpty { bad.append("省州表是空的") }

        // ② CN 级联：广东在，不该混进日本的地址
        let cn = regions(of: "CN").map { $0.code }
        if !cn.contains("CN-GD") { bad.append("CN 级联里没有 CN-GD（广东）") }
        if cn.contains(where: { !$0.hasPrefix("CN-") }) {
            bad.append("CN 级联混进了不是 CN- 开头的 code")
        }

        // ③ 查不到的 code 原样吐回去（国家），省份查不到吐空（跟①区分对象不同）
        if countryLabel("ZZ") != "ZZ" { bad.append("查不到的国家 code 没有原样返回") }
        if !regionLabel("ZZ-ZZ").isEmpty { bad.append("查不到的省州 code 该回空") }

        // ④ 老码迁移：CN-44 要能查到广东的标签，不能因为查不到码就显示空白
        let migratedLabel = regionLabel("CN-44")
        if migratedLabel.isEmpty { bad.append("老码 CN-44 迁移失败，资料页会显示空白") }
        // 反向对照：一个真不存在、也不在迁移表里的老码，就该显示空（不强凑）
        if !regionLabel("CN-99").isEmpty {
            bad.append("凭空编的 code 不该有标签，可能迁移表匹配过宽")
        }

        // ⑤ HK-HCW 迁移到空——新表没有对应数据，不能瞎凑一个
        if !regionLabel("HK-HCW").isEmpty {
            bad.append("HK-HCW 新表里没有对应数据，不该凑出一个标签")
        }

        // ⑥ occOther 常量跟 occupations 表一致
        if !occupations.contains(where: { $0.code == occOther }) {
            bad.append("occOther 常量跟 occupations 表对不上")
        }

        return bad.isEmpty ? nil : bad.joined(separator: "; ")
    }
}

/// 只用来定位这个类型所在的 bundle（键盘扩展 vs 主 App）。
private final class ProfileCodesBundleAnchor {}
