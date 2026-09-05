import Foundation

/// 状态行显示哪一条 —— **纯函数，带坏实现自测**。
///
/// 🚨🚨 **这里是判断的唯一一份。** `applyHint()` 只负责取数再调它。
///    工程里已经有过教训（`KbBridge.hostAlive` 的注释）：
///    **判断写两遍，就等于"测的那份"和"跑的那份"是两码事。**
///
/// 优先级（2.1《裁定 · setPhase 的 hint 归哪一档》）：
/// ```
/// ① 一次性提示（只来自 .idle 的非空 hint —— 刚发生完的事）
/// ② 当前 phase 的描述
///      listening → 录音计时 > 连续模式提示
///      thinking  → 识别中 / 翻译中 / 润色中 / 上屏中
///      idle      → （iOS 暂无自动判方向，留空）
/// ③ 空
/// ```
/// 🚨 **判据是 `phase`，不是文案内容。**
///    2.1 第一版给的是**按内容列举**，而落地只能**按调用点**归类 ——
///    于是「识别中」这类**阶段描述**被归成了一次性提示，
///    **等于让它去压「录音计时」，而两者本来同级。**
///    **内容清单永远列不全 —— 跟"关键词表补不完"是同一族。**
enum HintPolicy {

    /// 跟 `MainViewController.Phase` 一一对应。**这里不 import UI，保持可单测。**
    enum Phase: String { case idle, listening, thinking }

    /// 显示哪一条。
    ///
    /// - Parameters:
    ///   - oneOff: 一次性提示（`.idle` 的非空 hint）
    ///   - phase: 当前阶段
    ///   - listening: 录音计时那行
    ///   - phaseText: 当前阶段自己的描述
    ///   - continuousText: 连续模式提示；没开就传空串
    static func pick(oneOff: String, phase: Phase, listening: String,
                     phaseText: String, continuousText: String) -> String {
        // 🚨🚨 **一次性提示【只在 .idle】生效**（审查 M1）。
        //    2.1 的表本来就写着「只来自 `.idle` 的非空 hint」，
        //    但上一版是**无条件优先**，那个前提没人强制。
        //    后果：录音中点 🔊 失败 → `setOneOff("朗读失败…")` →
        //    **本次录音剩下的时间里计时行再也不出现**。
        //    → 把它挪进 `.idle`，让"前提"变成结构，不再靠调用方自觉。
        switch phase {
        case .listening:
            // 🚨 判据 S12：**录音期间计时优先** ——
            //    正在发生的事不能被"设定"挤掉。
            if !listening.isEmpty { return listening }
            return continuousText.isEmpty ? phaseText : continuousText
        case .thinking:
            return phaseText
        case .idle:
            // 刚发生完的事（错误/成功提示）只在这一档露面
            return oneOff
        }
    }

    // MARK: - 自测（坏实现必须各自被抓到）

    /// 回失败项；空数组 ＝ 全过。
    ///
    /// 🚨 **每条用例都要能指出"哪个坏实现会让它红"** ——
    ///    否则就是一条不会失败的检查。
    static func selfTest() -> [String] {
        var f: [String] = []

        // 🚨🚨 ① **这一条上一版断言反了** —— 它要求"一次性提示压过计时"，
        //    而那正是审查 M1 抓到的 bug（录音中一条朗读失败会把计时永久压住）。
        //    **自测不但没拦住它，还把错误行为钉死成了契约** ——
        //    比没有自测更糟：它让下一个人以为这是设计。
        if pick(oneOff: "错误", phase: .listening, listening: "00:05",
                phaseText: "识别中", continuousText: "连续") != "00:05" {
            f.append("录音中一次性提示压住了计时（M1：正在发生的事不能被盖掉）")
        }
        // ①b 一次性提示在 .idle 下才该露面
        if pick(oneOff: "错误", phase: .idle, listening: "",
                phaseText: "", continuousText: "") != "错误" {
            f.append("idle 下一次性提示没显示出来")
        }
        // ② 录音中计时 > 连续（坏实现：把 continuousText 提到 listening 前面）
        if pick(oneOff: "", phase: .listening, listening: "00:05",
                phaseText: "", continuousText: "连续") != "00:05" {
            f.append("录音中【连续提示】压过了计时（S12）")
        }
        // 🚨 ②b **判据 S12 的原样形状**（2.1 要手工验的那个）：
        //    录音中调 `setPhase(.listening, hint: "测试")` → hint 进 `phaseText`，
        //    **屏上必须仍然是计时**。
        //    上一版只验了"连续提示不许压过计时"，**没验"阶段描述不许压过计时"**
        //    —— 而 `setPhase(.listening, hint:)` 走的恰好是后者那条路。
        if pick(oneOff: "", phase: .listening, listening: "00:05",
                phaseText: "测试", continuousText: "") != "00:05" {
            f.append("录音中的阶段描述压住了计时（S12：setPhase(.listening, hint:) 那条路）")
        }
        // ③ 录音中没计时时才轮到连续
        if pick(oneOff: "", phase: .listening, listening: "",
                phaseText: "", continuousText: "连续") != "连续" {
            f.append("录音中没有计时时，连续提示没顶上")
        }
        // ④ thinking 显示阶段描述（坏实现：thinking 也去读 listening）
        if pick(oneOff: "", phase: .thinking, listening: "00:05",
                phaseText: "识别中", continuousText: "连续") != "识别中" {
            f.append("thinking 没有显示阶段描述")
        }
        // ⑤ idle 一律空（坏实现：idle 落到 phaseText）
        if pick(oneOff: "", phase: .idle, listening: "00:05",
                phaseText: "识别中", continuousText: "连续") != "" {
            f.append("idle 不是空的")
        }
        // ⑥ 🚨 全空时必须是空串，不许返回占位符
        if pick(oneOff: "", phase: .idle, listening: "",
                phaseText: "", continuousText: "") != "" {
            f.append("全空时返回了非空")
        }
        return f
    }
}
