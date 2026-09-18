import Foundation

/// 倉頡＋速成合一的**纯匹配逻辑**——不碰码表怎么来、怎么装，只管「给一张表、给一段输入，
/// 该出哪些候选、排在第几」。
///
/// 规格：`_规格_速成输入法调研_20260918.md`§4.1。
///
/// 🚨 **一套码表、两种打法，不是两个输入法**（0 已拍板，不是 A/B 选项）：
/// - 输入 **1～2 键**：按「速成」解读——把这 1～2 个键当成倉頡码的**首码＋尾码**，
///   在全表里找「派生速成码」等于这段输入的所有字。
/// - 输入 **3 键以上**：缓冲区已经超过速成码的最大长度（2），只剩一种解读站得住——
///   **完整倉頡前缀匹配**，候选随着每多打一键持续收窄。
///
/// 🚨 **派生速成码怎么算**（维基百科·简易输入法，规格§一已标出处）：
///    取倉頡码的第一码和最后一码；倉頡码本身只有 1 码，速成码就是这 1 码。
///    这条规则**只用来判断"这张表里的哪个字，会在用户打 1～2 键时被算作候选"**，
///    不改码表本身、不新生成一张速成码表——码表还是那一张完整倉頡表。
///
/// 🚨 **码表数据源不是这个文件的事**——真实倉頡码表由 1.1 从 Unicode `kCangjie` 字段
///    派生（规格§三，License 是宽松许可）。这个文件的 `selfTest` 用的是**明显不真实**
///    的假码假字（"debug 内部测试专用" 那种），只验证匹配/排序逻辑本身对不对，
///    不对任何具体汉字的倉頡码下结论——那件事只能读权威码表，不能在这里编。
enum CangjieMatch {

    /// 从一个完整倉頡码算出它的派生速成码。
    /// 🚨 **纯函数，不依赖任何全局状态**——闸门能直接拿假码测。
    static func speedCode(of fullCode: String) -> String {
        guard let first = fullCode.first else { return "" }
        guard fullCode.count > 1, let last = fullCode.last else { return String(first) }
        return String(first) + String(last)
    }

    /// 给一段用户输入，从码表里找候选。
    /// - Parameters:
    ///   - input: 用户已经打的键（倉頡字母，已转小写）。
    ///   - table: 码 → 候选（空格分隔，按常用度从前到后），跟 `wubi.txt` 同一种格式。
    ///   - order: 码表原始顺序（`table` 是 Dictionary 天然无序，排序要靠这个）。
    ///   - limit: 最多给几个候选。
    ///
    /// 🚨 **判据只看 `input.count`，不看"用户是不是打算继续打"**——
    ///    调用方每次按键都重新调一次这个函数，不在这里维护"这轮是不是已经决定走速成"
    ///    这种状态；候选会随着继续打键自然从"速成候选"过渡到"倉頡候选"，
    ///    这正是规格§4.1 要的"不需要用户选择我现在用哪个"。
    static func candidates(_ input: String, table: [String: String],
                           order: [String], limit: Int = 40) -> [String] {
        let key = input.lowercased()
        if key.isEmpty || table.isEmpty { return [] }
        if key.count <= 2 {
            return speedMatch(key, table: table, order: order, limit: limit)
        }
        return prefixMatch(key, table: table, order: order, limit: limit)
    }

    /// 速成解读：派生速成码等于 `input` 的所有码，都算命中。
    /// 🚨 **按码表原顺序遍历**（常用度），不是先收集再排序——码表本身已经是
    ///    按常用度编好的，遍历顺序直接决定候选顺序，跟 `rankPrefix` 同一个道理。
    private static func speedMatch(_ input: String, table: [String: String],
                                   order: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for code in order {
            guard speedCode(of: code) == input, let val = table[code] else { continue }
            for w in val.split(separator: " ") {
                let s = String(w)
                if s.isEmpty || seen.contains(s) { continue }
                seen.insert(s); out.append(s)
                if out.count >= limit { return out }
            }
        }
        return out
    }

    /// 倉頡前缀匹配：完整码以 `input` 开头的，候选随着 `input` 变长持续收窄。
    private static func prefixMatch(_ input: String, table: [String: String],
                                    order: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for code in order {
            guard code.hasPrefix(input), let val = table[code] else { continue }
            for w in val.split(separator: " ") {
                let s = String(w)
                if s.isEmpty || seen.contains(s) { continue }
                seen.insert(s); out.append(s)
                if out.count >= limit { return out }
            }
        }
        return out
    }

    // ------------------------------------------------------------ 自测

    /// 由 `gate_all_selftests.py` 自动发现并运行。
    /// 🚨 表里的码/字**全部是编的**，不是真倉頡码——只用来验证匹配和排序的逻辑，
    ///    不许当成任何汉字的真实倉頡码引用。
    static func selfTest() -> String? {
        var bad: [String] = []

        // ① 派生速成码：多码取首尾，单码原样
        if speedCode(of: "abc") != "ac" { bad.append("速成码：多码取首尾算错了") }
        if speedCode(of: "a") != "a" { bad.append("速成码：单码不该变") }
        if speedCode(of: "") != "" { bad.append("速成码：空码该回空") }

        // 假码表：code -> 候选（空格分隔），按"常用度"排（表里越靠前越常用）
        let order = ["ac", "ab", "abc", "abd", "abx", "x"]
        let table: [String: String] = [
            "ac": "假甲 假乙",   // 速成码 "ac"（首a尾c）
            "ab": "假丙",        // 速成码 "ab"（本身只有2码，首尾就是"ab"）
            "abc": "假丁",       // 速成码 "ac"（首a尾c，跟 "ac" 那一行速成码一样）
            "abd": "假戊",       // 速成码 "ad"
            "abx": "假己",       // 速成码 "ax"
            "x": "假庚",         // 单码，速成码 "x"
        ]

        // ② 打 2 键 "ac"：命中所有速成码为 "ac" 的行（"ac" 本身 + "abc"），按码表顺序
        let r2 = candidates("ac", table: table, order: order)
        if r2 != ["假甲", "假乙", "假丁"] {
            bad.append("速成2键：命中或顺序不对 -> \(r2)")
        }

        // ③ 打 1 键 "x"：只命中单码 "x"（"ab"/"abx" 等多码的速成码都不是单字符）
        let r1 = candidates("x", table: table, order: order)
        if r1 != ["假庚"] { bad.append("速成1键：命中不对 -> \(r1)") }

        // ④ 打 3 键 "abc"：切到倉頡前缀匹配，只有完整码以 "abc" 开头的
        let r3 = candidates("abc", table: table, order: order)
        if r3 != ["假丁"] { bad.append("倉頡3键：前缀匹配不对 -> \(r3)") }

        // ⑤ 打 2 键 "ab"：倉頡前缀里 "ab"/"abc"/"abd"/"abx" 都以 "ab" 开头，
        //    但 2 键走的是速成解读不是前缀——只应该命中速成码=="ab" 的那一行
        let r2b = candidates("ab", table: table, order: order)
        if r2b != ["假丙"] { bad.append("2键该走速成不是前缀 -> \(r2b)") }

        // ⑥ 去重：同一个字被两个码同时命中时只出现一次
        let dupOrder = ["p1", "p2"]
        let dupTable = ["p1": "假辛 假壬", "p2": "假辛"]
        let rDup = candidates("p1", table: dupTable, order: dupOrder)
        if rDup != ["假辛", "假壬"] { bad.append("去重：重复了或顺序变了 -> \(rDup)") }

        // ⑦ 空输入/空表：不许崩，回空
        if !candidates("", table: table, order: order).isEmpty {
            bad.append("空输入该回空")
        }
        if !candidates("ac", table: [:], order: []).isEmpty {
            bad.append("空表该回空")
        }

        // ⑧ limit 生效
        let rLimit = candidates("ac", table: table, order: order, limit: 2)
        if rLimit.count != 2 { bad.append("limit 没生效 -> \(rLimit.count)") }

        return bad.isEmpty ? nil : bad.joined(separator: "; ")
    }
}
