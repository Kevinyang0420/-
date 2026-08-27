import Foundation

/// 单词本的**纯逻辑**：一条记录长什么样、怎么去重、怎么插入、哪些该复习。
/// 安卓那份在 `android/java/com/kevin/shuoyingwen/WordBookCore.java`，一字不差。
///
/// 🚨 **跟存储严格分开，而且是分在两个文件里**。
///    第一版把两者写在一个 `WordBook.swift` 里，注释还写着"纯逻辑跟存储分开、
///    所以能进闸门" —— 而闸门是**单文件编译**，那份文件里的存储代码
///    带着 `UserDefaults` 和对 `Srs` 的引用，编不过。
///    **注释说分开了 ≠ 真的分开了**，跟"注释里写着必须同步"是同一族的自欺。
///
/// 存储层在 `WordBook.swift`（App Group + JSON）。
enum WordBookCore {

    /// 上限。跟 Alex 同口径（他那边 `NB_MAX = 500`）。
    static let max = 500

    // MARK: - 一条记录

    struct Item {
        /// 去重键 = `idOf(zh, en)`。
        let id: String
        /// 你当时说的中文原话。复习卡的一面。
        let zh: String
        /// 产出的英文。复习卡的另一面。
        let en: String
        /// `full` = 整句收，`part` = 只收了其中一段。
        let span: String
        /// 当时的语气档。同一句话换个语气就是另一条，所以要记。
        let tone: String
        /// 收进来那天，`yyyy-MM-dd`。
        let on: String
        /// 复习进度。规则全在 `Srs`。
        let rev: Srs.Rev
    }

    // MARK: - 纯逻辑（不碰存储，所以能进闸门）

    /// 去重键。**转调 `WordId.make`，这里不写第二份实现。**
    ///
    /// 🚨 我一度在这儿自己写了一版（`split(whereSeparator: { $0.isWhitespace })`），
    ///    而 `WordId` 早就存在、已经在闸门里，并且**比那一版对**：
    ///      · 它把 `zh` 和 `en` **一起**算 —— 同一句英文可能是从不同中文
    ///        说出来的，那是两张不同的卡；只用英文会并成一条
    ///      · 它把 6 个 ASCII 空白**按码点写死**，因为 Java 的 `\s` 和
    ///        Swift 的 `.whitespacesAndNewlines` **不是同一个集合**
    ///        （后者还含全角空格）—— 用各自的定义会让同一条记录在两端
    ///        算出两个 id，**而两边各自的自测都会通过**
    static func idOf(_ zh: String, _ en: String) -> String {
        WordId.make(zh, en)
    }

    /// 这条值不值得收：英文得有实际内容。
    static func usable(_ en: String?) -> Bool {
        guard let en = en else { return false }
        return !WordId.norm(en).isEmpty
    }

    /// 把一条插进列表，返回**新列表**。
    ///
    /// 规则：已有同 `id` → **原样返回**（不重复收、不置顶、**不重置进度**）；
    /// 新的放最前；超过 `max` 丢最旧的。
    ///
    /// 🚨 已存在时不动它 —— "我又说了一遍这句话"不该让它从头再背一次。
    static func insert(_ list: [Item], _ it: Item?) -> [Item] {
        // 🚨 守卫改看**英文有没有内容**，不看 id 是否为空。
        //    换成 `WordId.make` 之后，空英文照样算得出非空哈希 ——
        //    原来那句 `!it.id.isEmpty` 从此**恒为真**，空句子会被收进本子。
        guard let it = it, usable(it.en) else { return list }
        if list.contains(where: { $0.id == it.id }) { return list }
        var out = [it]
        for x in list {
            if out.count >= max { break }
            out.append(x)
        }
        return out
    }

    /// 今天该复习的。顺序照列表原顺序（新的在前）。
    static func due(_ list: [Item], _ today: String) -> [Item] {
        list.filter { Srs.isDue($0.rev, today) }
    }


    // MARK: - 自测（跟安卓 `selfTest()` 逐条对应）

    private static func mk(_ en: String, _ zh: String) -> Item {
        Item(id: idOf(zh, en), zh: zh, en: en, span: "full", tone: "",
             on: "2026-01-01", rev: Srs.Rev("2026-01-01"))
    }

    /// 返回 nil = 全过。**只测纯逻辑**，不碰 UserDefaults。
    static func selfTest() -> String? {
        // ---- id 用 zh + en 两个字段一起算 ----
        // 🚨 **不写 `WordId.make(a,b) == idOf(a,b)`** —— `idOf` 就是转调它，
        //    那是同源自比，永远相等、永远不会响。要测的是组合口径的后果：
        if idOf("我看一下", "Let me check.") == idOf("我确认下", "Let me check.") {
            return "同一句英文、不同中文该算两条"
        }
        if idOf("我看一下", "Let me check.")
            != idOf(" 我看一下 ", "  Let me check.  ") {
            return "只差空白该算同一条"
        }

        // ---- usable ----
        if usable(nil) { return "nil 不该收" }
        if usable("   ") { return "全空白不该收" }
        if !usable("ok") { return "有内容该收" }

        // ---- insert：去重 / 置顶 / 封顶 ----
        var l: [Item] = []
        l = insert(l, mk("We may push it back.", "往后推一下"))
        if l.count != 1 { return "第一条该进去" }
        l = insert(l, mk("Let me check.", "我看一下"))
        if l.count != 2 { return "第二条该进去" }
        if l[0].en != "Let me check." { return "新的该在最前" }
        // 🚨 同一条：zh 和 en 都一样，只是空白/大小写不同。
        l = insert(l, mk("  Let me check.  ", "我看一下"))
        if l.count != 2 { return "只差空白该算同一条" }
        // 已存在时**原样返回**：不覆盖、不置顶、不重置进度。
        if l[0].zh != "我看一下" { return "重复收不该覆盖原来的中文" }
        if l[0].en != "Let me check." { return "重复收不该改写英文" }
        let before = l.count
        l = insert(l, mk("   ", "空的"))
        if l.count != before { return "空英文不该收进来" }

        // 封顶
        var big: [Item] = []
        for i in 0..<(max + 20) { big = insert(big, mk("s\(i)", "c\(i)")) }
        if big.count != max { return "该封顶在 \(max)" }
        if big[0].en != "s\(max + 19)" { return "封顶后最新的该还在最前" }

        // ---- due ----
        var d: [Item] = []
        d = insert(d, mk("x", "y"))
        if due(d, "2026-01-01").count != 1 { return "新收的当天就该复习" }
        Srs.apply(d[0].rev, true, "2026-01-01")
        if due(d, "2026-01-01").count != 0 { return "答过之后当天不该再出现" }
        if due(d, "2026-01-02").count != 1 { return "到期那天该出现" }
        return nil
    }
}
