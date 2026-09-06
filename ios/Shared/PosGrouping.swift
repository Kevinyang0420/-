import Foundation

/// **按词性分节** —— 查词卡和单词本卡**共用这一份**。
///
/// 🚨 2026-09-06：Kevin 先报「commute 只给了动词」，改完查词卡之后又报
///    「单词本里连动词也没了，完全没标是动词还是名词」。
///    **两次是同一条链的前后两半**：
/// ```
/// 删 fallback 前：单词本显示第一条义项的词性 → "只有动词"
/// 删 fallback 后：顶层 pos 恒空          → "连动词也没了"
/// ```
///    根因是**词性被当成整卡级的**，而它是**义项级**的。
///
/// 🚨 抽出来是因为两个界面都要分节。**写第二份分组代码 = 下次只改一处。**
///    今天这条链上「同一规矩两处实现」已经栽了四次。
enum PosGrouping {

    /// 第 `i` 条义项要不要起一个新的词性节；要的话返回该显示的标题。
    ///
    /// - poses: 各条义项自己的词性，顺序即显示顺序
    ///
    /// 🚨 依赖「同词性的义项相邻」（1.1 已在 prompt 里保证）。
    ///    不相邻也不会错，只是同一个词性会出现两节 —— **宁可多一节，
    ///    也不能把不同词性的义项塞进同一节**，后者正是他报的那个 bug。
    static func sectionTitle(at i: Int, poses: [String]) -> String? {
        guard i >= 0, i < poses.count else { return nil }
        let cur = poses[i].trimmingCharacters(in: .whitespaces)
        if cur.isEmpty { return nil }
        if i == 0 { return cur }
        let prev = poses[i - 1].trimmingCharacters(in: .whitespaces)
        return cur == prev ? nil : cur
    }

    /// 这组义项**有没有词性信息**。
    ///
    /// 🚨 存量卡片（今天早些时候收藏的）里 sense 级 pos 根本不存在 ——
    ///    代码改对了，他打开老卡片还是没有词性，然后会说"又没修好"。
    ///    调用方据此决定**重新取一次卡片**。
    static func hasAnyPos(_ poses: [String]) -> Bool {
        return poses.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
