import Foundation

/// 单词本存储。**只存本机**（Kevin 2026-08-26 拍板：「存本机」）。
/// 结构跟安卓 `WordBook.java` 一一对应，复习规则在共用的 `Srs`。
///
/// 🚨 **跟 Alex 的单词本互不相干**。Kevin 原话：「我是说借鉴 Alex 那边的
///    一个单词本，它的功能并不是让你把这个产品跟 Alex 的英语训练去打通，
///    而是放在你这个 APP 里面应用」。不读它的数据、不调它的后端。
///
/// 🚨 **一条记录两面都存全**：`zh`（你当时说的中文）和 `en`（产出的英文）。
///    Kevin 2026-08-26 拍的是**「两面都能当正面」**（加个切换），
///    所以哪面当正面由界面上的开关决定 —— **存储层不预设方向**。
///
/// 🚨 换手机会丢这件事他知道并接受了（选项里写明了代价）。所以这里
///    **不做**任何"过期清理"，只有 `maxCount` 这个上限，超了丢**最旧**的。
enum WordBook {

    private static let key = "wordbook_json"

    /// 上限。Alex 那边是 500，照抄 —— 他用了两个月没抱怨过不够。
    /// 🚨 超了丢**最旧的**，不是拒绝新增：拒绝新增会让人在最需要收的时候收不了。
    static let maxCount = 500

    /// 一条记录。字段名跟安卓那份一模一样。
    struct Item {
        /// 稳定 id，用来去重和定位。
        var id: String
        /// 你当时说的中文原话。
        var zh: String
        /// 产出的英文（整句，或你划选的那一段）。
        var en: String
        /// `sentence`=整句，`phrase`=片段。
        var span: String
        /// 当时的语气档。同一句话换个语气就是另一句，得分开记。
        var tone: String
        /// 收进来的日期 `yyyy-MM-dd`。
        var on: String
        /// 复习进度。规则在 `Srs`。
        var rev: Srs.Rev
    }

    /// id 算法在 `WordId`，**这里不留第二份实现**。
    static func makeId(_ zh: String, _ en: String) -> String {
        WordId.make(zh, en)
    }

    static func norm(_ s: String) -> String { WordId.norm(s) }

    // MARK: - 自测（跟安卓 `selfTest()` 逐条对应）

    /// 返回 nil = 全过。
    ///
    /// 🚨 **只测不碰存储的那一半**（`makeId` / `norm`）。读写那一半要
    ///    `UserDefaults`，在闸门那个裸环境里不可靠 —— 与其造个假的让它
    ///    "看起来覆盖全"，不如老实说这半没覆盖：读写由端到端来验。
    /// 这一层的自测。**id 算法那部分在 `WordId.selfTest()`** ——
    /// 那才是两端必须一致的东西，也只有它进了 `gate_pure_logic`。
    static func selfTest() -> String? {
        if WordId.make("a", "b") != makeId("a", "b") {
            return "WordBook.makeId 没走 WordId"
        }
        if maxCount != 500 { return "上限该是 500（照 Alex）" }
        return nil
    }

    // MARK: - 读写

    static func all() -> [Item] {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let data = raw.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data))
                as? [[String: Any]] else { return [] }
        return arr.compactMap(fromJSON)
    }

    /// 收一条。已经有了就**不动它的复习进度**，返回 false。
    ///
    /// 🚨 重复收不许重置进度：他可能在不同场合说了同一句话，
    ///    每次都重置的话这张卡永远毕不了业。
    @discardableResult
    static func add(zh: String, en: String, span: String = "sentence",
                    tone: String = "", today: String) -> Bool {
        guard !norm(en).isEmpty else { return false }
        var list = all()
        let id = makeId(zh, en)
        if list.contains(where: { $0.id == id }) { return false }
        list.insert(Item(id: id, zh: norm(zh), en: norm(en), span: span,
                         tone: tone, on: today, rev: Srs.Rev(today)), at: 0)
        if list.count > maxCount { list = Array(list.prefix(maxCount)) }
        return save(list)
    }

    @discardableResult
    static func remove(_ id: String) -> Bool {
        var list = all()
        guard let i = list.firstIndex(where: { $0.id == id }) else { return false }
        list.remove(at: i)
        return save(list)
    }

    /// 答完一张卡，把进度写回去。
    @discardableResult
    static func answer(_ id: String, _ ok: Bool, today: String) -> Bool {
        let list = all()
        guard let it = list.first(where: { $0.id == id }) else { return false }
        Srs.apply(it.rev, ok, today)
        return save(list)
    }

    /// 今天该复习的。**毕业的不出现**（见 `Srs.isDue`）。
    static func due(_ today: String) -> [Item] {
        all().filter { Srs.isDue($0.rev, today) }
    }

    /// 首页那个小红点用的数字。
    static func dueCount(_ today: String) -> Int { due(today).count }

    // MARK: - 内部

    @discardableResult
    private static func save(_ list: [Item]) -> Bool {
        let arr = list.map(toJSON)
        guard let d = try? JSONSerialization.data(withJSONObject: arr),
              let s = String(data: d, encoding: .utf8) else { return false }
        UserDefaults.standard.set(s, forKey: key)
        return true
    }

    private static func toJSON(_ x: Item) -> [String: Any] {
        ["id": x.id, "zh": x.zh, "en": x.en, "span": x.span,
         "tone": x.tone, "on": x.on,
         "rev": ["n": x.rev.n, "due": x.rev.due, "last": x.rev.last,
                 "done": x.rev.done, "days": x.rev.dayList]]
    }

    private static func fromJSON(_ o: [String: Any]) -> Item? {
        guard let id = o["id"] as? String else { return nil }
        let on = o["on"] as? String ?? ""
        // 🚨 老记录没有 rev 时给一个新进度，不是丢掉这条。
        let rev = Srs.Rev(on.isEmpty ? "1970-01-01" : on)
        if let r = o["rev"] as? [String: Any] {
            rev.n = r["n"] as? Int ?? 0
            rev.due = r["due"] as? String ?? rev.due
            rev.last = r["last"] as? String ?? ""
            rev.done = r["done"] as? Bool ?? false
            rev.dayList = r["days"] as? [String] ?? []
        }
        return Item(id: id,
                    zh: o["zh"] as? String ?? "",
                    en: o["en"] as? String ?? "",
                    span: o["span"] as? String ?? "sentence",
                    tone: o["tone"] as? String ?? "",
                    on: on, rev: rev)
    }
}
