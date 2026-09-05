import Foundation

/// KPI ①「我翻译了多少个单词？」的**累加器**。
///
/// 权威：`_后端_词数字段_客户端规格.md`（1.1）+ 0 2026-09-04 的最终口径。
///
/// ## 三条硬规矩（都是规格点名的）
///
/// 1. 🚨 **后端算、客户端只累加，绝不自己数词**。三端各写一套数词规矩的话，
///    `don't` 算 1 还是 2 会在三台设备上给出三个不同的总数 ——
///    **而他会拿这个数去跟别人说**。
/// 2. 🚨 **只有翻译档累加**。后端回的 `words` 是**中性事实**（这段文字里有几个英文词），
///    它分不出「他说英文走逐字档」——那种情况 `words > 0` 但**那是转写不是翻译**。
///    只有客户端知道自己按的是哪一档。**往多了算是不可接受的方向：宁可少算，不许多算。**
/// 3. 🚨 **字段缺失 ≠ 0**。老服务端不给 `words` → 显示「还没有数据」；
///    真的是 0 才显示 0。**这两种世界必须分得开**，不许用 0 顶替。
///
/// ## 存哪
/// **只存本机**（跟历史一样），累加一个总数，不逐条存（规格 §4）。
/// 🚨 存在 **App Group** 里：键盘扩展和主 App 是两个进程，
///    键盘里翻译的词必须能被主 App 的 KPI 看见 —— 存各自的 `standard` 就分家了。
/// 跨设备合并先不做（规格 §4）。
enum KpiWords {

    private static let key = "kpi.words.total"
    private static let keySpoken = "kpi.spokenMs.total"
    private static let keyChars = "kpi.chars.total"
    /// **翻译档**的说话时长（毫秒）—— KPI②「省下时间」的减数。
    /// 🚨 跟 `keySpoken`（③ 全部说话）**是两个键**，不许复用。
    private static let keyTransMs = "kpi.transMs.total"
    private static let keyTransSeeded = "kpi.transMs.seeded"

    /// 累计翻译词数。**`nil` = 从来没拿到过 `words`**（老服务端／还没翻译过）
    /// → 界面写「还没有数据」，**不显示 0**。
    static var total: Int? {
        let d = KbBridge.prefs
        guard d.object(forKey: key) != nil else { return nil }
        return d.integer(forKey: key)
    }

    /// 累加一次翻译的词数。
    /// - Parameter n: 后端回的 `words`。🚨 调用方**必须已经确认这是翻译档**。
    /// 从**响应体**累加 —— 带上"这个响应是不是失败"这道守卫。
    ///
    /// 🚨🚨 **立它是因为 KPI① 的安全性原来是个跨组件不变式，客户端一侧没有守卫。**
    ///    ①（翻译的词）不在 `History.add` 里（③④ 才在那儿），它挂在
    ///    `Backend` 解析返回体那条路上，只被 `done == true` 挡着。
    ///    也就是说「不会为一段静音瞎加词数」这件事，**全靠后端永远不在错误响应里
    ///    带 `done:true`** —— 那个前提在后端，我们这边什么都没挡。
    ///    哪天后端某个分支为了别的目的带上它，**KPI① 就会悄悄 +N，而且不报错**。
    ///    （2.1 2026-09-04 核出来的缺口；我原来说"四格都到不了"是**结论对、理由错**。）
    ///
    /// 🚨 **收成一个函数，不是在两个调用点各加一个 if** ——
    ///    `Backend.swift` 里有两处累加（单句 / 轮询），同一条规矩两处实现必漂。
    static func addFromBody(_ obj: [String: Any]?) {
        // 失败体一律不计：判据跟 `JobErrorParse.parse` 同口径（error 非空 = 失败）
        if let e = obj?["error"] as? String,
           !e.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        guard let n = obj?["words"] as? Int else { return }
        add(n)
    }

    static func add(_ n: Int) {
        guard n > 0 else { return }
        let d = KbBridge.prefs
        let cur = d.object(forKey: key) == nil ? 0 : d.integer(forKey: key)
        d.set(cur + n, forKey: key)
    }

    /// ③ 累计说话时长（毫秒）。`nil` = 从来没记过。
    static var spokenMs: Int? {
        let d = KbBridge.prefs
        guard d.object(forKey: keySpoken) != nil else { return nil }
        return d.integer(forKey: keySpoken)
    }

    /// ② 的减数：**只有翻译档**的说话时长（毫秒）。`nil` = 从来没记过。
    ///
    /// 🚨🚨 立这个键是因为 KPI② 原来**分子分母不同源**：
    ///    分子 ①「翻译的词」只在翻译档累加，减数却用了 ③「全部说话」
    ///    （键盘所有档含逐字 / 随手转写 / 面对面）。
    ///    Kevin 大量用「转写-整理」→ 那些时长全进减数、一个词都不进分子
    ///    ⇒ ② 结构性偏负 ⇒ 恒 ≤0 ⇒ 首页那一格恒显一个杠。
    ///    （他 2026-09-05 的原话：「省下时间这个指标所有的终端显示的都是一个杠，
    ///     没有数字」。安卓 `HomeStats.java` 是同一个病，2.1 已同步。）
    ///
    /// 🚨 **③「累计说话」保持原值不动** —— 那一格问的是"我这辈子说了多少"，
    ///    本来就该含所有档。改的是 ② 的减数，不是 ③。
    static var transMs: Int? {
        seedTransFromHistoryOnce()
        let d = KbBridge.prefs
        guard d.object(forKey: keyTransMs) != nil else { return nil }
        return d.integer(forKey: keyTransMs)
    }

    /// **一次性回填**：这个键是今天才加的，老用户从 0 起会让 ② 只有分子、
    /// 没有减数，凭空报出一个大得离谱的"省下"。所以第一次读之前，
    /// 先拿历史里 `mode == "en"` 且非重译的 `dur` 求和当种子。
    ///
    /// 🚨 **它可能少算**：口径「甲」下清历史不动 KPI，所以清过历史的部分补不回来。
    ///    少算的方向是让 ② 偏大 —— 这一点我说明白，不藏着。
    ///    但比"减数为 0"好得多，而且往后每条新记录都会正常累加。
    private static func seedTransFromHistoryOnce() {
        let d = KbBridge.prefs
        if d.bool(forKey: keyTransSeeded) { return }
        d.set(true, forKey: keyTransSeeded)
        var sum = 0
        for it in History.list() where isTranslateMode(it.mode) && !it.isRetranslate {
            if it.durMs > 0 { sum += it.durMs }
        }
        if sum > 0 { d.set(sum, forKey: keyTransMs) }
    }

    /// 这一条记录算不算「翻译档」。
    ///
    /// 🚨 **读枚举定义得来的，不是猜的**：`Backend.Mode` 只有 `.en`（译）/
    ///    `.zh`（整理）/ `.raw`（逐字）三个 case，目标语言另存在 `lang` 里，
    ///    所以 `.en` 就是翻译档，跟译成哪一门语言无关。
    /// 🚨 用 `rawValue` 比字面量 `"en"` 好：枚举改了这里跟着改，不会各写一份。
    static func isTranslateMode(_ m: String) -> Bool {
        return m == Backend.Mode.en.rawValue
    }

    /// ④ 累计说了多少字。`nil` = 从来没记过。
    static var chars: Int? {
        let d = KbBridge.prefs
        guard d.object(forKey: keyChars) != nil else { return nil }
        return d.integer(forKey: keyChars)
    }

    /// 记一次**说话事件**：累加时长和字数（③④）。
    ///
    /// 🚨 2026-09-04 口径「甲」：四格统一走 **lifetime 累加器、不清零** ——
    ///    他清历史时 KPI 不动（清的是记录，不是"我这辈子说了多少"）。
    ///    所以 ③④ **不再遍历 History**，跟 ①② 同口径。
    /// 🚨 `durMs <= 0` 是「不知道」不是「说了 0 秒」，不累加。
    /// 🚨 **重译不算**（交叉审查 M5）：他没有再说一遍话，调用方别在重译路径上调这个。
    /// - Parameter isTranslate: 这一条是不是翻译档 —— 只有它才计入 ② 的减数。
    static func addSpoken(durMs: Int, zh: String, isTranslate: Bool = false) {
        let d = KbBridge.prefs
        if durMs > 0 {
            let cur = d.object(forKey: keySpoken) == nil ? 0 : d.integer(forKey: keySpoken)
            d.set(cur + durMs, forKey: keySpoken)
            // 🚨 ② 的减数**另记一个键**，只收翻译档。
            if isTranslate {
                _ = transMs      // 先让回填跑完，别把种子盖掉
                let t = d.object(forKey: keyTransMs) == nil ? 0 : d.integer(forKey: keyTransMs)
                d.set(t + durMs, forKey: keyTransMs)
            }
        }
        let n = HomeStatsCore.charCount(zh)
        if n > 0 {
            let cur = d.object(forKey: keyChars) == nil ? 0 : d.integer(forKey: keyChars)
            d.set(cur + n, forKey: keyChars)
        }
    }

    // MARK: - 自测（纯逻辑，判据是每种输入落到哪）

    /// 返回 nil = 全过。🚨 用独立的键跑，不碰真实累计值。
    static func selfTest() -> String? {
        let d = KbBridge.prefs
        let k = "kpi.words.selftest"
        d.removeObject(forKey: k)

        func t() -> Int? {
            guard d.object(forKey: k) != nil else { return nil }
            return d.integer(forKey: k)
        }
        func addT(_ n: Int) {
            guard n > 0 else { return }
            let cur = d.object(forKey: k) == nil ? 0 : d.integer(forKey: k)
            d.set(cur + n, forKey: k)
        }

        // 🚨 没写过 → nil（「还没有数据」），**不是 0**
        if t() != nil { return "没写过该是 nil（还没有数据），不是 0" }
        addT(12)
        if t() != 12 { return "累加 12 该得 12，实得 \(String(describing: t()))" }
        addT(8)
        if t() != 20 { return "再加 8 该得 20，实得 \(String(describing: t()))" }
        // 🚨 坏样本：0 / 负数不许改动累计（后端没给或异常值）
        addT(0)
        if t() != 20 { return "🚨 加 0 不该改动累计" }
        addT(-5)
        if t() != 20 { return "🚨 加负数不该改动累计" }
        // 真的是 0：写过之后 total 是 0 而不是 nil —— 两种世界分得开
        d.set(0, forKey: k)
        if t() != 0 { return "🚨 真的是 0 时该显示 0，不是 nil" }

        d.removeObject(forKey: k)
        if t() != nil { return "清掉后该回到 nil" }
        return nil
    }
}
