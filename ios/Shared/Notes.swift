import Foundation

/// **记事本的存储层** —— 只管读写，**一行纯逻辑都不写在这里**。
///
/// 规则全在 `NotesCore`（可单测）；这一层跟 `WordBook` 是同一个分工，
/// 也**照它的形状**：同一个 App Group、同一套退回策略、同一个 JSON 存法。
///
/// 🚨 **不另造存储方案** —— 单词本那套已经踩过两轮坑并写在注释里：
///    ① App Group 拿不到时**退回 `.standard` 但要说出来**（拒绝存更糟）
///    ② `groupReady` 不许拿"不为 nil"当判据（那是恒真的假检查）
///    我这里直接复用它的判据，不重写。
enum Notes {

    private static let key = "notes_json"

    typealias Item = NotesCore.Item

    /// 🚨 跟单词本同一个 store：App Group 能用就用，不能用退回本进程。
    ///    判据走 `WordBook.groupReady`（它转的是 `KbBridge.available`，
    ///    唯一实现），**不在这儿再写一遍**。
    private static var store: UserDefaults? {
        WordBook.groupReady ? UserDefaults(suiteName: WordBook.appGroup)
                            : .standard
    }

    static func list() -> [Item] {
        guard let raw = store?.string(forKey: key),
              let d = raw.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: d))
                as? [[String: Any]] else { return [] }
        return arr.map { o in
            Item(id: (o["id"] as? String) ?? "",
                 title: (o["title"] as? String) ?? "",
                 body: (o["body"] as? String) ?? "",
                 tags: (o["tags"] as? [String]) ?? [],
                 at: (o["at"] as? Double) ?? 0,
                 mtime: (o["mtime"] as? Double) ?? 0,
                 fromHistoryId: (o["from"] as? String) ?? "",
                 remindAt: (o["remind"] as? Double) ?? 0)
        }.filter { !$0.id.isEmpty }
    }

    private static func save(_ list: [Item]) {
        let arr: [[String: Any]] = list.map { i in
            var o: [String: Any] = ["id": i.id, "title": i.title,
                                    "body": i.body, "tags": i.tags,
                                    "at": i.at, "mtime": i.mtime]
            if !i.fromHistoryId.isEmpty { o["from"] = i.fromHistoryId }
            // 🚨 第二步才用；**没设就不写这个键**，免得存量数据里全是 0。
            if i.remindAt > 0 { o["remind"] = i.remindAt }
            return o
        }
        guard let d = try? JSONSerialization.data(withJSONObject: arr),
              let s = String(data: d, encoding: .utf8) else { return }
        store?.set(s, forKey: key)
    }

    /// 把一条说话记录「留下来」。
    ///
    /// 🚨 **同一条重复点不长第二条**（id 只跟历史 id 有关，见 `NotesCore`）。
    ///    重复点时**更新 mtime**，让它冒到列表最前 —— 他再点一次多半是
    ///    "我又想到这条了"，而不是"我要两条"。
    /// 🚨 空正文**拒绝**，返回 false 让调用方能说话（静默失败是他最烦的那类）。
    @discardableResult
    static func keep(historyId: String, body: String,
                     at: TimeInterval) -> Bool {
        let title = NotesCore.titleOf(body)
        guard !title.isEmpty else { return false }
        let id = NotesCore.idFromHistory(historyId)
        guard !id.isEmpty else { return false }
        let now = Date().timeIntervalSince1970
        let old = list().first { $0.id == id }
        let it = Item(id: id, title: old?.title ?? title, body: body,
                      tags: old?.tags ?? [], at: at, mtime: now,
                      fromHistoryId: historyId,
                      remindAt: old?.remindAt ?? 0)
        save(NotesCore.upsert(list(), it))
        return true
    }

    /// 这条说话记录是不是已经留下来了（列表上要显示成"已留下"）。
    static func kept(historyId: String) -> Bool {
        let id = NotesCore.idFromHistory(historyId)
        guard !id.isEmpty else { return false }
        return list().contains { $0.id == id }
    }

    /// 改标题 / 改正文 / 改标签 —— 三样都走这一个出口。
    @discardableResult
    static func update(id: String, title: String? = nil, body: String? = nil,
                       tags: [String]? = nil) -> Bool {
        guard var it = list().first(where: { $0.id == id }) else { return false }
        if let t = title { it.title = t.trimmingCharacters(in: .whitespaces) }
        if let b = body { it.body = b }
        if let g = tags { it.tags = NotesCore.normTags(g) }
        it.mtime = Date().timeIntervalSince1970
        save(NotesCore.upsert(list(), it))
        return true
    }

    static func remove(id: String) {
        save(NotesCore.remove(list(), id: id))
    }

    static func search(_ q: String) -> [Item] {
        return NotesCore.search(list(), q)
    }
}
