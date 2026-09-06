import Foundation

/// **记事本的纯逻辑** —— 不碰存储、不碰界面，可单测。
///
/// 规格 `_规格_记事本_20260907.md` 第一步（Kevin 09-07 批「三步同步走」）：
/// 说话记录能「留下来」+ 一个记事本列表页 + 改标题/加标签 + **搜索要搜得到原话**。
///
/// 🚨 **规则照抄安卓 `NotesCore.java`**（2.3 先做的），不自己另定一套：
///    id 怎么算、标题怎么截、重复怎么去、搜索搜哪几个字段、封顶多少 ——
///    这摊活在「同一规矩两端各写一份」上栽过好几次
///    （话筒比例三处、语言表手抄、`apply_overrides` 写了没接）。
///    两端各有一份实现是没办法的事（语言不同），**但规则必须逐条对齐**。
///
/// 🚨 边界（Kevin 已批的收窄版）：一条笔记最多挂一个提醒；
///    **不做**日历视图 / 共享 / 重复规则 / 富文本 / 文件夹。
enum NotesCore {

    /// 封顶。跟安卓同一个数。
    static let max = 500

    struct Item {
        var id: String
        var title: String
        var body: String
        var tags: [String]
        /// 说这句话的时间（来自历史）。
        var at: TimeInterval
        /// 最后改动时间 —— 列表按它倒序。
        var mtime: TimeInterval
        /// 来自哪条说话记录（手动新建时为空）。
        var fromHistoryId: String
        /// 🚨 **第二步才用**，第一步只占位 —— 字段现在就留好，
        ///    免得第二步再改一次存储格式（存量数据要迁移）。
        var remindAt: TimeInterval

        init(id: String, title: String, body: String, tags: [String] = [],
             at: TimeInterval = 0, mtime: TimeInterval = 0,
             fromHistoryId: String = "", remindAt: TimeInterval = 0) {
            self.id = id
            self.title = title
            self.body = body
            self.tags = tags
            self.at = at
            self.mtime = mtime
            self.fromHistoryId = fromHistoryId
            self.remindAt = remindAt
        }
    }

    /// 从一条说话记录来的 id。
    ///
    /// 🚨 **同一条历史重复点「留下来」不该长出两条** —— 所以 id 只跟
    ///    历史 id 有关，不掺时间。掺了时间就会每点一次多一条。
    static func idFromHistory(_ historyId: String) -> String {
        let h = historyId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return "" }
        return "h" + String(UInt32(bitPattern: Int32(truncatingIfNeeded:
            stableHash(h))), radix: 16)
    }

    /// 手动新建时的 id（时间 + 正文，够稳也够散）。
    static func idManual(body: String, at: TimeInterval) -> String {
        let b = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return "m" + String(Int(at), radix: 16)
            + String(UInt32(bitPattern: Int32(truncatingIfNeeded:
                stableHash(b))), radix: 16)
    }

    /// 🚨 **跨端稳定的哈希** —— 不用 Swift 的 `hashValue`：
    ///    它每次进程启动都会变（有随机种子），存下来的 id 下次就对不上，
    ///    「同一条历史不长出两条」这条保证会**在重启后失效**。
    ///    用 Java `String.hashCode` 那套（31 进制），跟安卓算出同样的数。
    static func stableHash(_ s: String) -> Int {
        var h: Int32 = 0
        for u in s.utf16 { h = 31 &* h &+ Int32(u) }
        return Int(h)
    }

    /// 从正文取标题：第一句，最多 24 字。
    ///
    /// 🚨 **空正文不许留下来**（返回空串，调用方据此拒绝）——
    ///    一条没有内容的笔记在列表里就是一行空白，他会以为坏了。
    static func titleOf(_ body: String) -> String {
        let s = body.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return "" }
        let chars = Array(s)
        var cut = chars.count
        for i in 0..<min(chars.count, 24) {
            if "。！？.!?".contains(chars[i]) { cut = i; break }
        }
        cut = min(cut, 24)
        let t = String(chars[0..<cut]).trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? String(chars[0..<min(24, chars.count)]) : t
    }

    /// 加一条或就地更新。**按 id 去重**，按 `mtime` 倒序，超过 `max` 砍最旧的。
    static func upsert(_ list: [Item], _ it: Item) -> [Item] {
        guard !it.id.isEmpty else { return list }
        var out = list.filter { $0.id != it.id }
        out.append(it)
        out.sort { $0.mtime > $1.mtime }
        // 🚨 砍的是**最旧的**，最新那条必须还在第一位。
        if out.count > max { out = Array(out.prefix(max)) }
        return out
    }

    static func remove(_ list: [Item], id: String) -> [Item] {
        return list.filter { $0.id != id }
    }

    /// 搜索。
    ///
    /// 🚨 **必须搜得到原话**（规格判据：只搜标题 = FAIL）——
    ///    他留下来的东西大多没起过标题，标题是从正文截的，
    ///    只搜标题等于只搜前 24 个字。
    /// 🚨 大小写不敏感；**空关键词返回全部**（不是返回空）。
    static func search(_ list: [Item], _ q: String) -> [Item] {
        let k = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !k.isEmpty else { return list }
        return list.filter { x in
            if x.title.lowercased().contains(k) { return true }
            if x.body.lowercased().contains(k) { return true }
            return x.tags.contains { $0.lowercased().contains(k) }
        }
    }

    /// 标签去重（大小写不敏感，保留先出现的那个写法）。
    static func normTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for t in tags {
            let s = t.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { continue }
            let k = s.lowercased()
            if seen.contains(k) { continue }
            seen.insert(k)
            out.append(s)
        }
        return out
    }
}
