import CoreGraphics
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
///
/// 🚨🚨 09-18 四订（Grok 审出的真 bug + 0 拍板）：中文界面的 A-Z 索引/排序
///    **不许按英文首字母**——"中国"按英文字母会掉进 Z（Zhongguo）或 C
///    （China）自相打架。也**不许自己拿 `CFStringTransform` 现场转拼音**——
///    那是「同一条规矩三端各一份」，安卓/PC 各转各的迟早漂。正解：1.1 在
///    `profile_codes.json` 里直接发了 `py`（拼音排序键）/`idx`（索引字母，
///    多音字已消歧——重庆是 `chongqingshi` 不是 `zhongqing`）两个字段，
///    三端吃同一份表，排序/分桶只读这两个字段，不自己算。`en` 首字母分组
///    **只在英文界面**保留（英文界面显示的就是英文名，按英文字母分组才对
///    应得上眼睛看到的东西）。
enum ProfileCodes {

    // ------------------------------------------------------------ 装载

    private struct Entry {
        let code: String; let zh: String; let zht: String; let en: String
        let py: String; let idx: String; let alt: [String]
    }

    /// 城市——09-18 五订，锁（GeoNames 署名条款）解了之后加的第三级。
    /// 跟国家/省州的 `Entry` 形状不完全一样：身份键是 `id`（GeoNames 数字
    /// id，不是 ISO 码），没有 `zht`/`alt`（1.1 的数据源没给，繁体界面
    /// 退英文——跟省州没有 zht 时同一条规则，不是漏做），多一个 `pop`
    /// （人口，目前排序不用它，留着给以后可能的"按人口排"用）。
    private struct CityEntry {
        let id: String; let region: String; let zh: String; let en: String
        let py: String; let idx: String; let pop: Int
    }

    private static let lock = NSLock()
    private static var loaded = false
    private static var countryList: [Entry] = []
    private static var regionList: [Entry] = []
    private static var cityList: [CityEntry] = []
    private static var countryByCode: [String: Entry] = [:]
    private static var regionByCode: [String: Entry] = [:]
    private static var cityById: [String: CityEntry] = [:]
    /// GeoNames 署名文本——**唯一出处是 JSON 里的 `_license` 字段**，
    /// 不在这里再抄一遍（1.1 的生成器自己校验过四要件，抄第二份的话
    /// 数据换版时这里会漂）。城市数据没装上时是空串，调用方要处理空串。
    private static var licenseText = ""

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
                             en: (row["en"] as? String) ?? "",
                             py: (row["py"] as? String) ?? "",
                             idx: (row["idx"] as? String) ?? "",
                             alt: (row["alt"] as? [String]) ?? [])
            }
        }
        countryList = parse("countries")
        regionList = parse("regions")
        for e in countryList { countryByCode[e.code] = e }
        for e in regionList { regionByCode[e.code] = e }

        if let arr = obj["cities"] as? [[String: Any]] {
            cityList = arr.compactMap { row in
                guard let id = row["id"] as? String,
                      let region = row["region"] as? String else { return nil }
                return CityEntry(id: id, region: region,
                                 zh: (row["zh"] as? String) ?? "",
                                 en: (row["en"] as? String) ?? "",
                                 py: (row["py"] as? String) ?? "",
                                 idx: (row["idx"] as? String) ?? "",
                                 pop: (row["pop"] as? Int) ?? 0)
            }
            for e in cityList { cityById[e.id] = e }
        }
        licenseText = (obj["_license"] as? String) ?? ""
    }

    /// 国家/省州两屏共用的行高——09-18 四订③改判据成"一屏 ≥17 行"之后，
    /// 0 点出这个数原来散在 `CountryListViewController`/`RegionListViewController`
    /// 两个文件里各写一份字面量，是「同一规矩多处各一份必漂」的形态：改一处
    /// 不改另一处，两屏就悄悄不一致，且编译器不会报错。现在只有这一处。
    /// （职业页 09-18 四订①已经改成 chip 网格，不再用这个——那边是
    /// `JobListViewController.chipHeight`，形状不同，不该硬凑同一个常量。）
    static let listRowHeight: CGFloat = 38

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

    /// 中文/繁体界面用拼音分桶排序，英文界面用英文名——两套桶，别一套打天下
    /// （09-18 四订，见类注释）。
    private static var usePinyinIndex: Bool { Lang.effective == Lang.zh || Lang.effective == Lang.hant }

    /// 全部国家，已按当前界面语言排好序——给列表页直接用。
    /// 🚨 `searchText` 带了 zh/zht/en/alt 全部（空格拼接），**只用来做包含
    ///    匹配**——列表页只显示当前界面语言那一份，但搜索框要全都能匹配
    ///    （0 原话「打 de 出德国」）。`idx` 是**预先算好的分组键**：中文/繁体
    ///    界面用 1.1 发的拼音索引字母，英文界面用英文名首字母——**不在这里
    ///    自己现场转拼音**，直接读表。
    static var allCountries: [(code: String, label: String, searchText: String, idx: String)] {
        ensureLoaded()
        let pinyin = usePinyinIndex
        // 🚨🚨 09-19 撤销：这里原来按拼音/英文名重排，会把 1.1 在 JSON 里
        //    排好的顺序（CN/HK/MO/TW 置顶 + 其余人口/业务序）打散回字母序。
        //    2.1 拍板"JSON 顺序说了算"——不再排序，直接吃数组原序
        //    （`ensureLoaded()` 用 `JSONSerialization` 解出的数组本来就是
        //    文件里写的顺序，`compactMap` 不改变顺序）。
        return countryList.map {
            (code: $0.code, label: label($0),
             searchText: ([$0.zh, $0.zht, $0.en] + $0.alt).joined(separator: " "),
             idx: pinyin ? ($0.idx.isEmpty ? "#" : $0.idx)
                         : String($0.en.first ?? Character("#")).uppercased())
        }
    }

    /// 国旗 emoji——**纯算法**（ISO 3166-1 alpha-2 每个字母映射到一个
    /// Regional Indicator Symbol，Unicode 标准机制，两个凑一对系统自动
    /// 渲染成对应国旗），不是查一张手搭的"国家→emoji"表（09-18 四订⑥）。
    /// 传两位字母以外的东西（比如省州的 `CN-GD`）原样返回空串——国旗只对
    /// 国家有意义，省州没有对应旗帜，不该凑一个出来。
    static func flagEmoji(_ iso2: String) -> String {
        let up = iso2.uppercased()
        guard up.count == 2, up.allSatisfy({ $0.isASCII && $0.isLetter }) else { return "" }
        var s = ""
        for ch in up.unicodeScalars {
            guard let scalar = Unicode.Scalar(0x1F1E6 + (ch.value - 65)) else { return "" }
            s.unicodeScalars.append(scalar)
        }
        return s
    }

    /// 「常用」国家/地区——09-18 四订⑤砍掉了写死的固定 6 国（Grok 点出跟
    /// 他实际所在地脱节；0 拍板只做两槽，**不接服务端 TopN**，不用拉 1.1）：
    /// 槽1：系统区域推断他大概率在哪（`Locale.current.region`，系统本来就有
    ///      的信息，不申请定位权限）；
    /// 槽2：这台设备上最近选过的国家（≤3，最近的排最前）。
    /// 两槽去重合并，槽1在前；`noteCountrySelected` 由调用方在用户选中
    /// 国家时调用，写进槽2。
    static func commonCountryCodes() -> [String] {
        var out: [String] = []
        if let region = Locale.current.region?.identifier, !region.isEmpty,
           countryByCode[region] != nil {
            out.append(region)
        }
        for code in recentCountryCodes() where !out.contains(code) {
            out.append(code)
        }
        return out
    }

    private static let recentCountryKey = "profile_recent_countries"

    private static func recentCountryCodes() -> [String] {
        (UserDefaults.standard.array(forKey: recentCountryKey) as? [String]) ?? []
    }

    /// 记一次「他选了这个国家」——最近的排最前，最多留 3 个（槽2的上限）。
    static func noteCountrySelected(_ code: String) {
        var list = recentCountryCodes()
        list.removeAll { $0 == code }
        list.insert(code, at: 0)
        if list.count > 3 { list = Array(list.prefix(3)) }
        UserDefaults.standard.set(list, forKey: recentCountryKey)
    }

    /// 某个国家下面有哪些一级行政区，按显示名排序——直接按代码前缀过滤，
    /// 不额外建"省属于哪个国家"的映射表（0 点过这条：ISO 3166-2 代码自己
    /// 带父级前缀，级联关系代码自己携带）。
    static func regions(of countryCode: String) -> [(code: String, label: String)] {
        ensureLoaded()
        let prefix = countryCode + "-"
        let pinyin = usePinyinIndex
        return regionList.filter { $0.code.hasPrefix(prefix) }
            .sorted { pinyin ? $0.py < $1.py : $0.en.localizedCompare($1.en) == .orderedAscending }
            .map { ($0.code, label($0)) }
    }

    /// 09-18 五订：第三级——某个省州下面有哪些城市。**精确匹配 `region`
    /// 字段**（不是前缀匹配）——城市直接携带父级省州的 ISO 3166-2 码，
    /// 跟 `regions(of:)` 用前缀匹配国家码是同一条"级联关系代码自己携带"
    /// 的道理，只是城市这一层是精确等于不是前缀（一个省只有一个值，
    /// 不像"CN-"要匹配"CN-GD"/"CN-SH"一整批）。没有城市数据的省州
    /// 回空数组——调用方据此判断"选完省就收工"还是"再钻一层"。
    static func cities(of regionCode: String) -> [(code: String, label: String)] {
        ensureLoaded()
        guard !regionCode.isEmpty else { return [] }
        // 🚨🚨 09-19 撤销：这里原来按拼音/英文名重排，会把 1.1 按人口倒序排好的
        // 顺序打散——判据是真机打开广东省城市列表首屏第一个必须是深圳（人口
        // 最多），拼音序会把它排到"S"堆里，够不着首屏。不再排序，直接吃
        // `cityList`（JSON 原序）里属于这个省的那些行，`filter` 不改变相对顺序。
        return cityList.filter { $0.region == regionCode }
            .map { ($0.id, cityLabelFor($0)) }
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

    /// GeoNames 署名文本，给"数据来源"入口显示用——见类头注释，唯一出处
    /// 是 JSON 的 `_license` 字段，这里只负责读出来，不重抄一遍内容。
    static var dataLicenseText: String {
        ensureLoaded()
        return licenseText
    }

    static func cityLabel(_ code: String) -> String {
        ensureLoaded()
        guard !code.isEmpty, let e = cityById[code] else { return "" }
        return cityLabelFor(e)
    }

    /// 城市没有 `zht` 字段（数据源没给，跟省州一样）——繁体界面直接退英文，
    /// 不是漏做，是跟省州同一条已有规则（见 `label(_:)` 对省州的处理）。
    private static func cityLabelFor(_ e: CityEntry) -> String {
        switch Lang.effective {
        case Lang.hant: return e.en
        case Lang.zh: return e.zh.isEmpty ? e.en : e.zh
        default: return e.en
        }
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

        // ⑦ 拼音字段真的装进来了，且重庆没被消歧错（09-18 四订，Grok bug）
        if let cq = regionByCode["CN-CQ"], cq.py != "chongqingshi" {
            bad.append("CN-CQ 拼音键不是 chongqingshi（多音字消歧可能没生效）：\(cq.py)")
        }
        if let cn = countryByCode["CN"], cn.idx.isEmpty {
            bad.append("CN 的 idx 索引字母是空的——拼音分桶会失真")
        }

        // ⑧ 国旗是算出来的（09-18 四订⑥）：CN → 🇨🇳，按 codepoint 比对，
        //    不按显示比对（终端/日志渲染 emoji 不可靠，见历史教训）。
        let cnFlag = flagEmoji("CN").unicodeScalars.map { $0.value }
        if cnFlag != [0x1F1E8, 0x1F1F3] {
            bad.append("CN 国旗 emoji 算错了：\(cnFlag)")
        }
        // 反向对照：省州码（三段式，非两位字母）不该凑出一面旗
        if !flagEmoji("CN-GD").isEmpty {
            bad.append("省州码不该凑出国旗（省州没有对应旗帜）")
        }

        // ⑨ 常用国家槽2（09-18 四订⑤）：去重 + 封顶3 + 最近的排最前。
        //    动了 UserDefaults 真实的键，测完必须复原，不能污染他手机上
        //    真实积累的"最近选过"记录。
        let savedRecent = recentCountryCodes()
        UserDefaults.standard.removeObject(forKey: recentCountryKey)
        noteCountrySelected("JP")
        noteCountrySelected("FR")
        noteCountrySelected("JP")   // 重复选同一个——不该出现两次，且要跳到最前
        noteCountrySelected("DE")
        noteCountrySelected("IT")   // 第 4 个——槽2该封顶在 3 个，最早的 FR 被挤掉
        let recent = recentCountryCodes()
        if recent.count != 3 { bad.append("槽2没封顶在3个：\(recent)") }
        if recent.first != "IT" { bad.append("槽2最近选的没排在最前：\(recent)") }
        if Set(recent).count != recent.count { bad.append("槽2里同一个国家出现了不止一次") }
        UserDefaults.standard.set(savedRecent, forKey: recentCountryKey)

        // ⑩ 城市（09-18 五订）：深圳在广东下，不该混进别的省；没数据的省
        //    回空数组（"选完省就收工"这条路径靠这个判断，不能被一个总不为空
        //    的假象糊弄过去）。
        if cityList.isEmpty { bad.append("城市表是空的——bundle 里没找到最新的 profile_codes.json？") }
        let gdCities = cities(of: "CN-GD").map { $0.code }
        if !gdCities.contains(where: { cityById[$0]?.en == "Shenzhen" }) {
            bad.append("广东省下没有深圳——城市按 region 精确匹配可能失效了")
        }
        // 反向对照：一个真实存在但没有城市数据的省份（用一个编造的省码测）
        // 该回空，不该凑出结果。
        if !cities(of: "ZZ-ZZ").isEmpty {
            bad.append("凭空编的省码不该有城市，可能过滤条件太宽")
        }
        if dataLicenseText.isEmpty || !dataLicenseText.contains("GeoNames") {
            bad.append("GeoNames 署名文本读不出来——CC BY 4.0 要求的署名会显示不出来")
        }

        return bad.isEmpty ? nil : bad.joined(separator: "; ")
    }
}

/// 只用来定位这个类型所在的 bundle（键盘扩展 vs 主 App）。
private final class ProfileCodesBundleAnchor {}
