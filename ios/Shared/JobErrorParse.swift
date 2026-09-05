import Foundation

/// 从 job 响应体里判断「这是不是一次失败」——**纯函数，带坏实现自测**。
///
/// 🚨🚨 **这个文件存在的唯一原因，是一个我犯过的错**：
///
///    我把失败判断写成了 `if obj["done"] == true, let f = failureFrom(obj)`，
///    **而真实的错误体根本没有 `done` 字段**（实读 `server_api.py:783-787`）：
///    ```python
///    if j.get("error"):
///        _b = {"error": j["error"]}
///        if j.get("kind"): _b["kind"] = j["kind"]
///        return self._send(502, _b)          # ← 没有 done
///    ```
///    后果：**所有 job 级失败都磨满轮询变成「等太久了」，整套 `kind` 分类不可达。**
///
///    **而我当时"验过"了 —— 我验的是代码结构，不是真实响应的形状。**
///    → 把判断挪到这里，**并把"错误体没有 done"写成断言**，
///      这样同样的错**下次会被自测拦住**，不用等审查。
/// 一次轮询过程中的「上一轮看到了什么」。
///
/// 🚨 存在的理由：**单次观测不足以下终结结论**。
///    · 断网：一次读不到可能只是抖动，连着两次才是真断（复审 M3）
///    · 网关错误信封：跟 job 自己的错**形状一模一样**，
///      一次就判死会把还在跑的 job 掐掉（复审 M4）
///
/// 用 class 是因为四个 poll 是**递归 + escaping 闭包**，`inout` 过不去。
final class PollState {
    var prevError: String?
    private var netStreak = 0

    /// 记一次网络错。回 `true` = 连着两次了，可以终结。
    func noteNetwork() -> Bool {
        netStreak += 1
        return netStreak >= 2
    }

    /// 拿到了**任何 HTTP 响应**（含错误体、含空 body）—— 传输层连击清零。
    ///
    /// 🚨 复审 高-1：这件事和「错误连续性」**是两件事，不能一个方法管**。
    ///    上一版 `noteOK()` 两件一起做，而调用点在**解析错误体之前** ——
    ///    错误体本身就是一次正常 HTTP 响应，于是每轮开头都把上一轮刚写的
    ///    `prevError` 抹掉，`isTerminal` 退化成 `!kind.isEmpty`，
    ///    **「连着两次才终结」永不可达**，四条轮询链全中。
    func noteTransportOK() { netStreak = 0 }

    /// **体里没有 error** —— 错误的连续性被打断。
    ///
    /// 🚨 只在「解析不出错误体」那一侧调。放错位置的后果见 `noteTransportOK`。
    func noteCleanBody() { prevError = nil }

    // MARK: - 自测（由 JobErrorParse.selfTest 调，跟着一起跑）

    static func selfTest() -> [String] {
        var f: [String] = []
        let a = PollState()
        // 🚨 第一次网络错**不许**终结（那可能只是抖了一下）
        if a.noteNetwork() { f.append("第一次网络错就终结了（M3：一次抖动不算断网）") }
        if !a.noteNetwork() { f.append("连着两次网络错仍不终结") }
        // 中间成功过一次，计数要清零
        let b = PollState()
        _ = b.noteNetwork()
        b.noteTransportOK()
        if b.noteNetwork() { f.append("中间成功过一次，连续计数没清零") }
        // 🚨🚨 高-1 的坏样本：**拿到错误体也算「拿到响应」**，
        //    这时只能清传输层连击，**不许清 `prevError`** ——
        //    清了的话「连着两次才终结」永不可达（上一版就是这么废掉的）。
        let e2 = PollState()
        e2.prevError = "upstream request timeout"
        e2.noteTransportOK()
        if e2.prevError == nil {
            f.append("noteTransportOK 把 prevError 也清了 —— "
                     + "「连着两次」会永不可达（高-1）")
        }
        // 🚨 中-2 的坏样本：**正常响应必须打断错误的连续性**。
        //    这一条在上一版实现上会红 —— 因为 `prevError` 从不清零。
        let c = PollState()
        c.prevError = "upstream request timeout"
        c.noteCleanBody()
        if JobErrorParse.isTerminal(kind: "", message: "upstream request timeout",
                                    previous: c.prevError) {
            f.append("错A→正常→错A 被判成终结 —— 「连着两次」名不副实（中-2）")
        }
        // 对照：错A→错A（中间没有正常响应）必须终结
        let d = PollState()
        d.prevError = "upstream request timeout"
        if !JobErrorParse.isTerminal(kind: "", message: "upstream request timeout",
                                     previous: d.prevError) {
            f.append("错A→错A 仍不终结 —— 会磨满轮询变成「等太久了」")
        }
        return f
    }
}

enum JobErrorParse {

    /// 响应体里带没带失败。回 `(kind, message)`；`kind` 为空串表示后端没给分类。
    ///
    /// 🚨 **判据只看有没有 `error`，不看 `done`、也不看 HTTP 状态码。**
    ///    状态码同样靠不住：后端 `_send` 会把网关会吃掉的码（502…）
    ///    **改写成 500** 并塞 `intended_status`（`_GATEWAY_EATS`）。
    /// - Returns: `retryKind` 是后端**显式**给的重试语义，空串 = 没给。
    ///
    /// 🚨🚨 **`retryKind` 必须从返回体里读，不许由 `kind` 推**（1.1 规格 §二）。
    ///    「`no_speech` 就是 respeak」这种映射写死在客户端的话，后端哪天
    ///    改了语义我们就静默错，而且**测试改不动行为**（2.1 的坏样本 2 专治它：
    ///    把 `retry_kind` 去掉或改成 `resend`，客户端行为必须跟着变；
    ///    **怎么改都一样 = 分叉根本没接上**）。
    ///
    /// 🚨 为什么这件事要紧：老的「可重试」路径动作是**重传同一段音频**。
    ///    静音那段重传必然还是没人说话 → **无限重试、每次都花 Kevin 的钱**，
    ///    而他什么也拿不到。
    static func parse(_ obj: [String: Any]?)
        -> (kind: String, message: String, retryKind: String)? {
        guard let obj = obj, let e = obj["error"] as? String, !e.isEmpty else {
            return nil
        }
        let k = (obj["kind"] as? String) ?? ""
        let rk = (obj["retry_kind"] as? String) ?? ""
        return (k, e, rk)
    }

    /// 这一次的失败，要不要**终结整个 job**。

    /// 🚨🚨 **判据变宽是有代价的，这个函数就是那笔代价的账单。**
    ///
    ///    H-A 把终结条件从「done + 有 error」放宽成「体里有 error 就算失败」。
    ///    但 `/api/job` 上的 `error` **有两个可能的作者**：
    ///      · job 自己（后端 `job_set(..., kind=...)`，**必带 `kind`**）
    ///      · **网关**（`_send` / `_GATEWAY_EATS` 证明它会往响应里塞东西）
    ///    两者形状一模一样，靠形状分不开。
    ///
    ///    放宽之前：网关抖一次只损失一次 poll。
    ///    放宽之后：**网关抖一次就把还在跑的 job 判死**，而结果两秒后就好了。
    ///
    /// **所以终结要满足其一**：
    ///   ① `kind` 非空 —— 后端明确分类过，是 job 自己的错；
    ///   ② 同一条 `error` **连着出现两次** —— 不是一次性抖动。
    ///
    /// - Parameter previous: 上一轮轮询读到的 `error` 原文（没有就传 nil）
    static func isTerminal(kind: String, message: String, previous: String?) -> Bool {
        // 🚨🚨 `expired` 是**唯一一个可能由"打到了别的实例"产生**的分类。
        //    后端 `JOBS` 是**进程内 dict**（实读 `server_api.py:504`），
        //    取不到就回 404 + `kind=expired`（`:873/:912`）——
        //    而火山 FaaS 多实例时，轮询完全可能打到一个没有这个 job 的实例。
        //    **一次就判死 = 把一个还在跑的 job 当场掐掉，他看到「过期了」。**
        //    这条对 iOS 比安卓更致命：我们多一次跨进程往返，窗口更大。
        //    → 跟"没有 kind"同一个口径：**连着两次同一条才终结**。
        //    真过期的话也只是多轮询一次，代价是几百毫秒。
        if kind == "expired" { return previous == message }
        if !kind.isEmpty { return true }
        return previous == message
    }

    // MARK: - 自测

    static func selfTest() -> [String] {
        var f: [String] = []

        // 🚨 ① **错误体没有 `done`** —— 这就是那个 bug 的原样形状
        if parse(["error": "boom", "kind": "internal"]) == nil {
            f.append("错误体不带 done 时判不出失败 —— 整套 kind 分类会不可达")
        }
        // ② 分类要透出来
        if parse(["error": "boom", "kind": "internal"])?.kind != "internal" {
            f.append("kind 没被读出来")
        }
        // ③ 后端没给分类时，kind 是空串而不是丢掉整条失败
        guard let noKind = parse(["error": "boom"]) else {
            f.append("没有 kind 时整条失败被丢掉了")
            return f
        }
        if !noKind.kind.isEmpty { f.append("没有 kind 时 kind 不是空串") }
        // ④ 成功体不许被判成失败
        if parse(["done": true, "text": "hi"]) != nil {
            f.append("成功体被判成了失败")
        }
        // ⑤ 还没完成（done=false）也不是失败
        if parse(["done": false]) != nil {
            f.append("还没完成被判成了失败")
        }
        // 🚨 ⑥ 空 error 不算失败 —— 否则 `{"error":""}` 会变成一次假失败
        if parse(["error": ""]) != nil {
            f.append("空的 error 被判成了失败")
        }
        // ⑦ nil 响应体
        if parse(nil) != nil { f.append("nil 响应体被判成了失败") }

        // ---- isTerminal（M4：判据变宽之后的收口）----
        // ⑧ 后端明确分类过 → 一次就终结
        if !isTerminal(kind: "internal", message: "boom", previous: nil) {
            f.append("有 kind 却没终结 —— job 自己报的错要一次就停")
        }
        // 🚨 ⑨ **没有 kind 的第一次，不许终结** —— 那可能是网关抖了一下，
        //    终结掉等于把还在跑的 job 判死（复审 M4 的原样）
        if isTerminal(kind: "", message: "upstream request timeout", previous: nil) {
            f.append("网关抖一次就把 job 判死了（M4）")
        }
        // ⑩ 同一条错连着两次 → 终结
        if !isTerminal(kind: "", message: "same", previous: "same") {
            f.append("同一条错连出两次仍不终结 —— 会磨满轮询变成「等太久了」")
        }
        // ⑪ 两次错不一样 → 还不终结（更像抖动）
        if isTerminal(kind: "", message: "a", previous: "b") {
            f.append("两次不同的错就终结了 —— 判据太松")
        }
        // 🚨 `expired` 不许一次就终结（它可能只是打到了别的实例）
        if isTerminal(kind: "expired", message: "没有这个 job", previous: nil) {
            f.append("expired 一次就终结 —— 跨实例轮询会把还在跑的 job 判死")
        }
        // 但连着两次同一条要终结（真过期）
        if !isTerminal(kind: "expired", message: "没有这个 job",
                       previous: "没有这个 job") {
            f.append("expired 连着两次仍不终结 —— 真过期时会磨满轮询")
        }
        // 其余 kind 仍然一次就终结（它们由 job 自己产生，不会因实例不同而出现）
        if !isTerminal(kind: "blocked", message: "x", previous: nil) {
            f.append("blocked 没有一次终结 —— 别把这条口径放宽到所有 kind")
        }
        // 🚨 PollState 的自测挂在这里 —— 单独放会变成**零调用点**，
        //    闸门按文件扫 `selfTest()`，同文件里的第二个类型不会被单独发现。
        f += PollState.selfTest().map { "PollState: " + $0 }
        return f
    }
}
