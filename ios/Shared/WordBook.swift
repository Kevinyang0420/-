import Foundation

/// 单词本的**存储层**。**存本机**（Kevin 2026-08-26 拍板：「存本机」）。
///
/// 🚨 **一行纯逻辑都不许写在这里** —— 去重键、插入、封顶、该不该复习
///    全在 `WordBookCore`，那份两端一致且进了 `gate_pure_logic.py`。
///    这里只做「读 App Group → 交给 Core → 写回」。
///
/// 🚨🚨 **存储走 App Group，不是 `UserDefaults.standard`**：
///    历史记录和"收进单词本"这个动作发生在**键盘扩展**里，
///    而单词本的三个视图在**主 App** 里 —— 两个进程。
///    用 `.standard` 的话，键盘收的词主 App 一条都读不到，
///    而且**不会报错**，只会显示"本子是空的"。
enum WordBook {

    private static let key = "wordbook_json"

    /// App Group 标识。**两个 target 的 entitlements 都要有它**。
    static let appGroup = "group.com.kevin.transless"

    typealias Item = WordBookCore.Item

    /// 存哪儿：**App Group 能用就用它，不能用就退回本进程的 `.standard`**。
    ///
    /// 🚨🚨 这里的取舍变过一次，两个版本都对，但对的是不同的问题：
    ///
    ///    · 旧版：拿不到 App Group 就返回 `nil`、**一条都不存**。
    ///      那时候 iOS 唯一的收词入口设想在**键盘扩展**里，
    ///      退回 `.standard` 会变成"键盘写扩展本地、主 App 读自己那份"，
    ///      两边各存各的，界面上只表现为"本子是空的" —— 最贵的一类错。
    ///
    ///    · 现在：收词入口在**主 App 的随手翻译**里，读和写都在同一个进程。
    ///      这时候不退回就成了"App Group 没配好 → 一条都存不进去"，
    ///      而 Kevin 2026-08-28 明确说「**单词本那个功能我是要用的**」。
    ///      **拒绝存**比"暂时不能跨进程"糟得多。
    ///
    /// 🚨 但退回**必须是看得见的**，不许静默：`groupReady` 为假时
    ///    单词本列表顶部用危险色写明「键盘里收的词现在同步不过来」。
    ///    退回本身不是问题，**退回而不说**才是。
    private static var store: UserDefaults? {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// App Group 真的能用吗。
    ///
    /// 🚨 判据是**真写进去再读出来**，不是"`UserDefaults(suiteName:)` 不为 nil"
    ///    —— 没在 entitlements 里声明那个 group 时，这个构造器**照样给对象**，
    ///    只是读写落不到共享容器。拿"不为 nil"当判据是典型的假检查。
    static var groupReady: Bool {
        guard let s = store else { return false }
        let probe = "__wb_probe__"
        s.set(1, forKey: probe)
        let ok = s.integer(forKey: probe) == 1
        s.removeObject(forKey: probe)
        return ok
    }

    /// 收一条。返回 `added` / `added_evicted` / `same` / `empty`。
    /// 🚨 不再有 `nogroup` —— App Group 没配好时退回本进程存，
    ///    而不是拒绝。见 `store` 的注释。
    @discardableResult
    static func add(zh: String, en: String, span: String = "full",
                    tone: String = "", today: String) -> String {
        // 🚨 判据是**英文有没有内容**，不是"id 是不是空串" ——
        //    `WordId.make` 对空英文照样算得出非空哈希，
        //    原来那句 `id.isEmpty` 恒为假，空句子会被收进本子。
        if !WordBookCore.usable(en) { return "empty" }
        let id = WordBookCore.idOf(zh, en)
        let cur = list()
        if cur.contains(where: { $0.id == id }) { return "same" }
        let it = Item(id: id, zh: zh,
                      en: en.trimmingCharacters(in: .whitespacesAndNewlines),
                      span: span, tone: tone, on: today, rev: Srs.Rev(today))
        save(WordBookCore.insert(cur, it))
        // 🚨 满了之后仍然是**加成功了**（挤掉最旧的那条），不能报"本子满了"。
        return cur.count >= WordBookCore.max ? "added_evicted" : "added"
    }

    static func list() -> [Item] {
        guard let s = store,
              let raw = s.string(forKey: key),
              let data = raw.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data))
                  as? [[String: Any]]
        else { return [] }
        return arr.map { o in
            let on = (o["on"] as? String) ?? ""
            let rev = Srs.Rev(on)
            if let r = o["rev"] as? [String: Any] {
                rev.n = (r["n"] as? Int) ?? 0
                rev.due = (r["due"] as? String) ?? ""
                rev.last = (r["last"] as? String) ?? ""
                rev.done = (r["done"] as? Bool) ?? false
                rev.dayList = (r["days"] as? [String]) ?? []
            }
            return Item(id: (o["id"] as? String) ?? "",
                        zh: (o["zh"] as? String) ?? "",
                        en: (o["en"] as? String) ?? "",
                        span: (o["span"] as? String) ?? "full",
                        tone: (o["tone"] as? String) ?? "",
                        on: on, rev: rev)
        }
    }

    static func save(_ list: [Item]) {
        guard let s = store else { return }
        let arr: [[String: Any]] = list.map { x in
            ["id": x.id, "zh": x.zh, "en": x.en, "span": x.span,
             "tone": x.tone, "on": x.on,
             "rev": ["n": x.rev.n, "due": x.rev.due, "last": x.rev.last,
                     "done": x.rev.done, "days": x.rev.dayList]]
        }
        if let d = try? JSONSerialization.data(withJSONObject: arr),
           let str = String(data: d, encoding: .utf8) {
            s.set(str, forKey: key)
        }
    }

    /// 答完一张卡，写回。
    static func answer(id: String, ok: Bool, today: String) {
        let cur = list()
        for x in cur where x.id == id { Srs.apply(x.rev, ok, today) }
        save(cur)
    }

    static func remove(id: String) { save(list().filter { $0.id != id }) }

    static func count() -> Int { list().count }

    static func dueCount(_ today: String) -> Int {
        WordBookCore.due(list(), today).count
    }
}
