import Foundation

/// **「最常用」的排序规则** —— 纯函数，不碰存储、不碰 UI。
///
/// 🚨🚨 **「最常用」≠「最近用」。** Kevin 2026-09-06 01:40 的原话是
///    「最近的语言要支持左右滑动，**永远前面放最常用的前三个**，
///      用过的都可以左右滑取出来」——「最常用」是**用过的次数最多**。
///    两者在他的用法下会给出完全不同的顺序：偶尔试一次的语言
///    会把天天用的那门顶下去。
///
/// 🚨 **抽成纯函数是为了让判据不依赖存储。** 原来这段逻辑长在
///    `LangRecents` 里，而它要读 `KbBridge.prefs`（App Group）——
///    UI 测试跑在独立进程、`@testable import` 链接不到 App 符号，
///    要测就得把整条存储链搬进测试包。
///    **判据该挂在规则上，不该挂在"能不能读到那份偏好"上。**
///    （同款做法：`SpellFold` / `WordKind` 也是这么编进测试包的。）
enum LangRank {

    /// - Parameters:
    ///   - used: 用过的语言码，**最近用的在前**（只用于平局判定）
    ///   - counts: 每门用过多少次
    ///   - all: 当前引擎支持的全部语言码
    /// - Returns: 次数降序；次数相同时最近用的在前；**不在 `all` 里的剔除**
    static func rank(used: [String],
                     counts: [String: Int],
                     all: [String]) -> [String] {
        return used.filter { all.contains($0) }.sorted { a, b in
            let ca = counts[a] ?? 0, cb = counts[b] ?? 0
            // 次数多的在前
            if ca != cb { return ca > cb }
            // 🚨 平局才看最近。只按次数的话，两门都用过 1 次时
            //    顺序会随数组/字典的遍历顺序乱跳，他会觉得"位置每次都不一样"。
            let ia = used.firstIndex(of: a) ?? Int.max
            let ib = used.firstIndex(of: b) ?? Int.max
            return ia < ib
        }
    }

    /// 老用户升级时给「最近用过」补一份计数。**要迁移就回那份新计数，不用则回 nil。**
    ///
    /// 🚨 计数是 2026-09-06 才加的。升级前的用户只有顺序、没有次数 ——
    ///    不补的话所有老语言都是 0 次，他之后随手用一门新的就立刻 1 分
    ///    **冲到最前，把天天用的那门顶下去**，看起来就是"排序乱了"。
    ///
    /// 🚨 每门只记 **1 次**，不按位置编 3/2/1：位置信息**已经在 `used` 里**，
    ///    平局时由它决定顺序。再按位置编一套次数就是**同一件事两个来源**，
    ///    以后两边一改就走散。
    static func seedCounts(used: [String],
                           existing: [String: Int]) -> [String: Int]? {
        guard existing.isEmpty, !used.isEmpty else { return nil }
        var seeded: [String: Int] = [:]
        for c in used { seeded[c] = 1 }
        return seeded
    }
}
