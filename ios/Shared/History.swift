import Foundation

/// 说过的话的历史记录。**照搬安卓 `History.java`**。
///
/// 🚨 存在的理由（Kevin 2026-08-21）：「我说话说了一次，然后不小心删没了，
///    想再去复制一遍的时候，发现之前说的那段话已经找不到了」。
///    所以**上屏成功的那一刻就落盘**，不是等他主动保存 ——
///    他不会去按保存，等他发现丢了的时候就已经晚了。
///
/// 🚨 只存本机，**绝不上传**：他说的内容里有工作信息。
enum History {

    /// 老存法的键（`UserDefaults` 里一整个 JSON 数组）。**只用来一次性搬家**。
    private static let key = "history_json"

    /// 留多少条。**2000**（Kevin 2026-09-03：「留 2000 句，本地滚动」）。
    ///
    /// 🚨🚨 **光把 50 改成 2000 是错的，而且错在他最能感觉到的地方。**
    ///    老存法是 `UserDefaults` 里一整个 JSON 数组，**每次说完话都全量
    ///    解析 + 序列化一遍**，而 `add()` 跑在 `commitText` **之前**
    ///    （「先落历史再上屏」是刻意的顺序，不能挪到后台）。
    ///    安卓真机实测（条目按真实尺寸：zh≈40 字、out≈60 字）：
    ///      50 条    10 KB    每次 add ≈ **0 ms**
    ///      500 条  104 KB    每次 add ≈ **31 ms**
    ///      2000 条 416 KB    每次 add ≈ **33–72 ms**   ← 每说一句都卡这么久
    ///
    /// 🚨 所以存法换成**一行一条追加**（`history.jsonl`）：
    ///    `add` 只写这一条（O(1)，约 200 字节），
    ///    **全量解析只发生在他打开历史面板那一刻**。
    private static let maxItems = 2000

    /// 文件涨到多少行才整理一次。**只在 `list()` 里做** ——
    /// 那是他打开面板的时刻，多花几十毫秒他感觉不到；
    /// 放 `add()` 里就等于把刚省下的开销又还回去了。
    private static let trimAt = maxItems + maxItems / 2

    /// 一行一条，放 **App Group** 的 Application Support。
    ///
    /// 🚨🚨 **这里 2026-09-04 改过口径，别按老注释改回去**：
    ///    原来放「扩展自己的容器」，理由是"历史面板本来就在键盘里、App Group 在模拟器装不上"。
    ///    那个理由**在 09-04 失效了** —— 说话记录屏和 KPI 都搬进了**主 App**，
    ///    而扩展和主 App 是两个容器，键盘写的主 App 根本读不到（交叉审查 H1）。
    ///    现在：**有共享容器就用它**（真机），拿不到才回落本进程容器（模拟器）
    ///    **并留一行日志**，绝不静默回落；老位置的数据由 `migrateToGroup()` 合并搬过来。
    /// 🚨 **不用 `.cachesDirectory`** —— 系统会清，那是丢他的数据。
    private static func fileURL() -> URL? {
        let fm = FileManager.default
        // 🚨🚨 **必须放 App Group**（2026-09-04 交叉审查 H1 抓出来的）。
        //    键盘扩展和主 App 是**两个数据容器**：本来这份历史只在键盘里看，
        //    放各自容器没问题；但 09-04 把「说话记录屏」和 KPI 搬进了**主 App**，
        //    于是键盘写的落在扩展容器、主 App 读自己那份空文件 ——
        //    真机上说十句，回主 App 打开说话记录是**空态卡**。
        //    🚨 而我的模拟器截图带 `TRANSLESS_SEED_HIST` 种子，
        //       **结构性地抓不到这条** —— 判据只能是端到端「键盘说一句 → 主 App 看得见」。
        if let g = fm.containerURL(forSecurityApplicationGroupIdentifier: KbBridge.group) {
            let dir = g.appendingPathComponent("Library/Application Support",
                                               isDirectory: true)
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            // 🚨🚨 **成功这条也要留痕**（2026-09-04 补）。原来只有失败分支写日志，
            //    于是"没看到回落告警"什么都证明不了 —— 可能是没回落，也可能是
            //    **这段代码压根没跑过**（真机上实测就是后者：三个容器都没有
            //    history.jsonl，因为 `History.add` 一次都没被调用过）。
            //    **缺失 ≠ 0**，正面证据要自己造出来。
            // 🚨 带上**进程身份**：这条日志写进共享区，键盘和主 App 都会写。
            //    不标是谁写的，就分不出"键盘也解析到了共享容器"这个关键事实 ——
            //    而 H1 的要害恰恰是**两个进程解析到同一个地方**。
            noteResolvedOnce(dir.appendingPathComponent("history.jsonl"))
            return dir.appendingPathComponent("history.jsonl")
        }
        // 🚨 只有拿不到共享容器（模拟器没装 entitlement）才回落本进程容器，
        //    **而且要留一行**：静默回落就会变成"两台设备各存各的"而没人知道。
        KbBridge.note("🚨 History 回落到本进程容器（App Group 拿不到）—— "
                      + "键盘和主 App 会各存各的，只应该在模拟器上发生")
        guard let dir = fm.urls(for: .applicationSupportDirectory,
                                in: .userDomainMask).first else { return nil }
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("history.jsonl")
    }

    /// 每个进程**只记一次**「我把 history.jsonl 解析到了哪」。
    ///
    /// 🚨 为什么值得单独一个函数：`fileURL` 每次 add/list 都会调，
    ///    不去重的话这条日志会把诊断区刷爆（那个区是有上限的，
    ///    刷爆等于把别的线索挤掉）。
    /// 🚨 判据设计：H1 要证的是**键盘和主 App 解析到同一个地方**。
    ///    所以这条日志必须带**进程身份**，否则两条一模一样的记录
    ///    分不出是"两个进程各写了一条"还是"一个进程写了两次"。
    private static var noted = false
    private static func noteResolvedOnce(_ url: URL) {
        guard !noted else { return }
        noted = true
        // 扩展的 bundle id 以 `.keyboard` 结尾，主 App 没有 —— 用它区分。
        let who = (Bundle.main.bundleIdentifier ?? "?").hasSuffix(".keyboard")
            ? "键盘扩展" : "主App"
        KbBridge.note("History 落点[\(who)]：\(url.path)")
    }

    /// **公开入口**：把本进程老位置的历史搬进 App Group。
    ///
    /// 🚨 为什么要有这个口子：`migrateToGroup()` 原来只在 `list()` 里被调用，
    ///    而键盘的 `list()` 只有他点开键盘历史面板才跑 —— 键盘容器里的旧记录
    ///    就一直搬不过来。**每个进程的老位置是它自己的**，主 App 那边的迁移
    ///    搬不动键盘那份。所以键盘要在启动时自己调一次。
    /// 🚨 幂等且便宜：老位置没文件就立刻返回。
    /// 🚨 **先解析一次落点再迁移**：`migrateToGroup()` 在"老位置没文件"时会
    ///    提前返回、根本不碰 `fileURL`，那条「History 落点[谁]：<路径>」的日志
    ///    就不会写 —— 而那正是 H1 要的**正面证据**（键盘进程解析到了共享容器）。
    ///    不这么排的话，绝大多数设备上（没有老文件）这条证据永远拿不到。
    static func migrateFromOldContainer() {
        _ = fileURL()
        migrateToGroup()
    }

    /// 把**老位置**（本进程容器）的历史搬进 App Group，只搬一次。
    ///
    /// 🚨 不搬的话，改成 App Group 那一刻他之前说过的所有话就"凭空消失"了 ——
    ///    而他不会知道是升级弄的，只会觉得东西没了。
    private static func migrateToGroup() {
        let fm = FileManager.default
        guard let g = fm.containerURL(forSecurityApplicationGroupIdentifier: KbBridge.group)
        else { return }                       // 没有共享容器就没什么可搬的
        guard let oldDir = fm.urls(for: .applicationSupportDirectory,
                                   in: .userDomainMask).first else { return }
        let old = oldDir.appendingPathComponent("history.jsonl")
        guard fm.fileExists(atPath: old.path) else { return }
        let newURL = g.appendingPathComponent("Library/Application Support/history.jsonl")
        // 🚨 新位置已经有东西：把两份**按行合并**再按时间排，别直接覆盖 ——
        //    键盘和主 App 可能各写过一段，覆盖就丢一半。
        var merged = readLines(at: old)
        merged.append(contentsOf: readLines(at: newURL))
        guard !merged.isEmpty else { try? fm.removeItem(at: old); return }
        merged.sort { (($0["ts"] as? Double) ?? 0) < (($1["ts"] as? Double) ?? 0) }
        var s = ""
        for o in merged {
            guard let d = try? JSONSerialization.data(withJSONObject: o),
                  let ln = String(data: d, encoding: .utf8) else { continue }
            s += ln + "\n"
        }
        let dir = newURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        guard (try? s.data(using: .utf8)?.write(to: newURL, options: .atomic)) != nil
        else { return }                       // 写失败就**别删老的**
        try? fm.removeItem(at: old)
        KbBridge.note("History 已搬进 App Group：\(merged.count) 条")
    }

    /// 读指定文件的每一行（给搬家用）。坏行跳过。
    private static func readLines(at url: URL) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        var out: [[String: Any]] = []
        for ln in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let o = try? JSONSerialization.jsonObject(with: Data(ln))
                    as? [String: Any] else { continue }
            out.append(o)
        }
        return out
    }

    struct Item {
        let ts: Double          // 毫秒时间戳，跟安卓同口径
        let mode: String        // en / zh / raw
        let tone: String
        let zh: String          // 识别到的原话
        let out: String         // 最终上屏的结果
        /// **他说话的时长**（毫秒）。🚨 `0` 表示「不知道」，不是「说了 0 秒」——
        /// 旧记录没有这个字段，读回来就是 0。算平均时必须把 0 排除掉。
        let durMs: Int
        /// **目标语言码**。空 = 不知道。跟安卓一致存成键 `"lg"`。
        let lang: String
        /// **这条是不是「再发一次」重译出来的**（存成键 `"re"`）。
        /// 🚨 重译**没有再说一遍话**：KPI ③「累计说话」④「说了多少字」都要跳过它，
        /// 否则连点几次「再发一次」，那两个数就凭空翻倍（交叉审查 M5）。
        /// ① 词数仍计 —— 那确实是又翻译了一次。
        let isRetranslate: Bool
    }

    private static var store: UserDefaults { .standard }

    /// 上屏成功后立刻调。**任何异常都不许影响主流程** ——
    /// 记不上不是塌天的事，但崩了是。
    /// - Parameter durMs: **他说话的时长**（毫秒），不是端到端处理耗时。
    ///   跟安卓 `durMs` 同一个口径（`VoiceImeService.java:2127`）。
    /// 🚨 **`durMs <= 0` 不写进 JSON** —— 读回来是 0 表示「不知道」，
    ///   不是「说了 0 秒」。算平均时必须排除 0，否则一条旧记录就能把语速拉垮
    ///   （安卓 `HomeStatsCore.java:108` 为这个专门留了坏样本用例）。
    /// 🚨 **只存本地，绝不上传** —— 不进任何上行请求。
    /// - Parameter lang: 目标语言码（KPI ④ 按它去重）。空则不写这个键。
    static func add(mode: String, tone: String, zh: String, out: String,
                    durMs: Int = 0, lang: String = "",
                    isRetranslate: Bool = false) {
        guard !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        // 🚨 键名写死 `"zh"`。安卓那份写成了
        //    `o.put(c.getString(R.string.ui_lang), zh)` ——
        //    用**界面语言的值**（"zh"/"en"/"hant"）当 JSON 键名，
        //    于是换一次界面语言，之前的历史就读不出来了。那是笔误，别照抄。
        var item: [String: Any] = [
            "ts": Date().timeIntervalSince1970 * 1000,
            "mode": mode.isEmpty ? "en" : mode,
            "tone": tone,
            "zh": zh,
            "out": out,
        ]
        // 🚨 键名 `dur`，跟安卓一致（`History.java:105`）。
        //    不知道就整个不写这个键 —— 写个 0 进去，读回来分不清
        //    「没记过」和「说了 0 秒」。
        if durMs > 0 { item["dur"] = durMs }
        // 🚨 键名 `lg`，跟安卓一致（`History.java:127`）。不知道就不写这个键（别写空串充数）。
        if !lang.isEmpty { item["lg"] = lang }
        // 🚨 重译标记：只在为真时写（跟 dur/lg 同口径，不写空值充数）。
        if isRetranslate { item["re"] = 1 }
        // 🚨🚨 KPI ③④ 的累加挂在这里（2026-09-04 口径「甲」：四格统一 lifetime 累加器、
        //    清历史不动 KPI）。**挂在 History.add 是因为它是所有说话事件的唯一必经之路** ——
        //    键盘/随手翻译/面对面都走它，挂在这一处就不会漏入口、也不会重复。
        //    🚨 重译条跳过：他没有再说一遍话（交叉审查 M5）。
        //    🚨 `isTranslate` 从 `mode` 判 —— 判据在 `KpiWords.isTranslateMode`
        //       那一个地方，别在这里写 `mode == "en"`（那就是第二份实现）。
        if !isRetranslate {
            KpiWords.addSpoken(durMs: durMs, zh: zh,
                               isTranslate: KpiWords.isTranslateMode(item["mode"] as? String ?? ""))
        }
        // 🚨 **只写这一条**（追加一行）。老写法在这里要把整份重新序列化，
        //    2000 条时就是每说一句卡 33–72ms —— 而且卡在文字上屏之前。
        guard let d = try? JSONSerialization.data(withJSONObject: item),
              let json = String(data: d, encoding: .utf8) else { return }
        append(json + "\n")
    }

    /// 追加一行。文件不在就创建。
    private static func append(_ line: String) {
        guard let url = fileURL(), let d = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? d.write(to: url, options: .atomic)
            return
        }
        // 🚨🚨 用 throwing 版 `seekToEnd()`/`write(contentsOf:)`（iOS 13.4+，本工程 16.0）。
        //    旧的 `seekToEndOfFile()`/`write(_:)` 是**废弃的非 throwing API**，
        //    存储满(ENOSPC)/只读/写中容器被回收时抛 `NSFileHandleOperationException` ——
        //    **Objective-C 异常，Swift 的 `try?`/`do-catch` 抓不住 → 直接终止进程**，
        //    而 `add()` 跑在 `commitText` 之前 → 表现是「打字打一半键盘整个消失」。
        //    （交叉审查 H2：原注释"异常一律吞掉"是**不成立的自我保证**，比没注释更糟。）
        do {
            let h = try FileHandle(forWritingTo: url)
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: d)
        } catch {
            // 现在真的吞掉了：历史写失败绝不连累上屏。
        }
    }

    /// 全部历史，**最新的在最前**。只在他打开历史面板时调 ——
    /// 全量解析的开销都在这里，不在 `add()`。
    ///
    /// - Parameter limit: 只要前几条。默认全给。
    ///   🚨 键盘扩展内存紧（约 60MB），面板只铺 8 行，
    ///      **别为了铺 8 行把 2000 个 `Item` 都建出来**。
    static func list(limit: Int = maxItems) -> [Item] {
        migrateToGroup()   // 🚨 先把老位置(本进程容器)的搬进 App Group，再读
        migrate()
        var raw = readLines()
        // 🚨 文件是**追加**的，所以行序是从旧到新 —— 倒过来给界面。
        raw.reverse()
        // 🚨 超了就在**这里**整理（他打开面板的时刻，多几十毫秒感觉不到）。
        //    放 add() 里整理等于把刚省下的开销又还回去。
        if raw.count > trimAt {
            raw = Array(raw.prefix(maxItems))
            writeAll(raw)
        }
        let n = min(limit, min(maxItems, raw.count))
        guard n > 0 else { return [] }
        return raw.prefix(n).map {
            Item(ts: ($0["ts"] as? Double) ?? 0,
                 mode: ($0["mode"] as? String) ?? "",
                 tone: ($0["tone"] as? String) ?? "",
                 // 🚨 读也要用写死的 "zh"。兼容旧数据：
                 //    老版本可能把界面语言当键名存成了 en/hant。
                 zh: firstNonEmpty($0, "zh", "en", "hant"),
                 out: ($0["out"] as? String) ?? "",
                 // 🚨 老记录没有 "dur" → 0 = **不知道**，不是"说了 0 秒"。
                 durMs: ($0["dur"] as? Int) ?? 0,
                 lang: ($0["lg"] as? String) ?? "",
                 isRetranslate: (($0["re"] as? Int) ?? 0) == 1)
        }
    }

    /// 删单条（按时间戳定位）。
    static func remove(ts: Double) {
        migrate()
        var raw = readLines()
        // 🚨 H3 次生防护：读回来是空、但磁盘文件其实非空 = 这次是**解码失败**，
        //    不是真没记录。此时绝不能拿空集合去 `writeAll` —— 那会把真数据抹掉。
        //    （合法的"删掉最后一条"不会走到这：那时 raw 非空，删完才空。）
        if raw.isEmpty, fileNonEmpty() { return }
        raw.reverse()                                   // 新在前，跟 writeAll 对应
        writeAll(raw.filter { (($0["ts"] as? Double) ?? 0) != ts })
    }

    static func clear() {
        // 🚨 两处都要清：新文件 + 还没搬过来的老键。只清一处的话
        //    他"全清"之后一打开面板，老的又被 migrate 搬回来了。
        if let url = fileURL() { try? FileManager.default.removeItem(at: url) }
        store.removeObject(forKey: key)
    }

    /// 给界面用的一行摘要：时间 + 模式。跟安卓 `label()` 同口径。
    static func label(_ it: Item) -> String {
        let m: String
        switch it.mode {
        case "zh":  m = L.kb_transcribe + " " + L.kb_polish
        case "raw": m = L.kb_transcribe + " " + L.kb_verbatim
        default:    m = L.kb_translate
        }
        // 🚨 M8（交叉审查）：50→2000 之后**必须带日期**。原来只有 HH:mm，
        //    2000 条跨几周，满屏 `14:32 · 翻译` 分不出哪天，而这功能存在的理由
        //    就是回去找那段再复制。今天→HH:mm；昨天→昨天 HH:mm；更早→M月d日 HH:mm。
        //    🚨 安卓 `label()` 同型，要一起改（已报 0）。
        let d = Date(timeIntervalSince1970: it.ts / 1000)
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: d)
        let clock = String(format: "%02d:%02d", hm.hour ?? 0, hm.minute ?? 0)
        let day: String
        if cal.isDateInToday(d) {
            day = clock
        } else if cal.isDateInYesterday(d) {
            day = L.hist_yesterday + " " + clock
        } else {
            let md = cal.dateComponents([.month, .day], from: d)
            day = String(format: L.hist_monthday, md.month ?? 0, md.day ?? 0) + " " + clock
        }
        return day + " · " + m
    }

    // MARK: - 存取

    /// 一行一条读回来（**旧到新**）。坏行跳过，
    /// **不因为一行坏就把整份丢了** —— 老写法是整份 JSON，坏一个字节全没。
    private static func readLines() -> [[String: Any]] {
        // 🚨🚨 **按字节读、按 `\n` 切、逐行解码**（交叉审查 H3）。
        //    原来用 `String(contentsOf:encoding:.utf8)` —— 那是**整文件级**解码：
        //    任何一处非法 UTF-8（一次被截断的追加、写中途被 jetsam 杀留下半个汉字）
        //    → 整个返回 nil → **整份历史读成空**，而下面逐行 `try?` 那层永远轮不到。
        //    这个文件存在的唯一理由就是他那句「想再复制一遍时发现找不到了」——
        //    读成空正好把这个理由打穿。字节级逐行解码后，坏字节只毁它自己那一行。
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url) else { return [] }
        var out: [[String: Any]] = []
        for lineData in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let o = try? JSONSerialization.jsonObject(with: Data(lineData))
                    as? [String: Any] else { continue }   // 坏行跳过，不连累整份
            out.append(o)
        }
        return out
    }

    /// 磁盘上的历史文件是不是非空（给 H3 次生防护用）。
    private static func fileNonEmpty() -> Bool {
        guard let url = fileURL(),
              let sz = try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size] as? Int else { return false }
        return sz > 0
    }

    /// 整份重写（**只在整理和删单条时**，不在 add 的热路上）。
    /// 传进来的是**新在前**，落盘写回**旧到新**，跟 `add` 追加的方向一致。
    private static func writeAll(_ items: [[String: Any]]) {
        guard let url = fileURL() else { return }
        var s = ""
        for o in items.reversed() {
            guard let d = try? JSONSerialization.data(withJSONObject: o),
                  let ln = String(data: d, encoding: .utf8) else { continue }
            s += ln + "\n"
        }
        try? s.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    /// 把老的 `UserDefaults` 历史搬进新文件，**只搬一次**。
    ///
    /// 🚨 不搬的话他升级之后以前那些记录凭空消失 —— **那是丢他的数据**，
    ///    而且他不会知道是升级弄的，只会觉得"东西没了"。
    private static func migrate() {
        guard let old = store.string(forKey: key), !old.isEmpty else { return }
        defer {
            // 🚨 不管搬成没搬成都把老键清掉：留着会**每次打开面板都搬一遍**，
            //    而且会跟新记录重复。搬失败时宁可丢老的，也不能每次翻倍。
            store.removeObject(forKey: key)
        }
        guard let d = old.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: d)
                as? [[String: Any]] else { return }
        var items = arr                                  // 老存法就是新在前
        var cur = readLines()
        cur.reverse()                                    // 变成新在前
        items.append(contentsOf: cur)
        // 🚨 顺序按时间排，别靠"哪份先读"来定 —— 两份的时间范围可能交叠。
        items.sort { (($0["ts"] as? Double) ?? 0) > (($1["ts"] as? Double) ?? 0) }
        writeAll(items)
    }

    /// 按顺序找第一个非空的键 —— 兼容改键名之前存下的旧历史。
    private static func firstNonEmpty(_ o: [String: Any],
                                      _ keys: String...) -> String {
        for k in keys {
            if let v = o[k] as? String, !v.isEmpty { return v }
        }
        return ""
    }
}
