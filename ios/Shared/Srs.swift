import Foundation

/// 单词本的**间隔重复**规则。纯逻辑，跟安卓一字不差
/// （安卓那份在 `android/java/com/kevin/shuoyingwen/Srs.java`）。
///
/// Kevin 2026-08-26 拍板：单词本按 Alex 那边的形态做，**存本机**，
/// 复习卡「两面都能当正面」（加个切换）。
///
/// 🚨 参数**照抄 Alex**（`english_coach/web/alex-online.html:18854`）：
///    `REV_STEPS = [1, 3, 7, 21]`  `REV_HITS = 3`  `REV_DAYS = 3`
///    不是偷懒 —— 那套他已经用了两个月、踩过坑改对了。
///    自己另起一套只会把「同一天刷完假装记住了」重新踩一遍。
///
/// 🚨 三条容易写漏的规则，每条都有自测样本：
///    ① **同一天再点「记住了」不算数**，否则一天连点三次就"毕业"
///    ② **答错清零**，不是退一档
///    ③ **毕业要两个条件同时成立**：次数 ≥3 **且** 分布在 ≥3 天
enum Srs {

    /// 答对第 n 次之后，隔几天再问。超出表长就一直用最后一档。
    static let steps = [1, 3, 7, 21]

    /// 毕业要答对几次。
    static let hits = 3

    /// 毕业要分布在几天。
    static let days = 3

    /// 一条记录的复习进度。**故意是 class（引用语义）**，
    /// 跟安卓的 `Rev` 一样原地改，存储层整条写回。
    final class Rev {
        /// 连续答对次数。答错清零。
        var n: Int
        /// 下次该问的日期，`yyyy-MM-dd`。
        var due: String
        /// 最后一次答的日期。用来挡"同一天再点"。
        var last: String
        /// 答对过的日期（去重、升序）。**天数**用它算，不是用 n。
        var dayList: [String]
        /// 毕业了没。
        var done: Bool

        init(_ today: String) {
            n = 0
            due = today
            last = ""
            dayList = []
            done = false
        }
    }

    /// 固定公历 + GMT，跟安卓 `GregorianCalendar` 对齐。
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)!
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// 日期加天数。`d` 必须是 `yyyy-MM-dd`。
    ///
    /// 🚨 用 `Calendar` 算，不自己拼字符串 ——
    ///    跨月跨年跨闰日手写必错，而错的那几天没人会去测。
    static func addDays(_ d: String, _ n: Int) -> String {
        guard let base = fmt.date(from: d),
              let out = cal.date(byAdding: .day, value: n, to: base)
        else { return d }
        return fmt.string(from: out)
    }

    /// 答完一张卡，推进进度。
    static func apply(_ r: Rev, _ ok: Bool, _ today: String) {
        if !ok {
            // ② 答错清零 —— 不是退一档。明天再来。
            r.n = 0
            r.done = false
            r.last = today
            r.due = addDays(today, 1)
            return
        }
        // ① 同一天再点不算数。见类型注释。
        if r.last == today { return }
        r.last = today
        if !r.dayList.contains(today) { r.dayList.append(today) }
        r.n += 1
        r.due = addDays(today, steps[min(r.n - 1, steps.count - 1)])
        r.done = graduated(r.n, r.dayList.count)
    }

    /// 毕业了没：答对次数 ≥ `hits` **且** 分布在 ≥ `days` 天。
    ///
    /// 🚨 **单独一个函数，不写在 `apply` 里面**，因为写在里面的话
    ///    「跨天」那一半**测不到**：规则①保证 `n` 每天最多 +1，
    ///    于是 `n` 和天数永远相等，天数那个条件不可能单独为假。
    ///    坏样本注入当场抓到了这一点（把天数条件删掉，所有测试照样过）。
    ///
    /// 🚨 为什么不干脆删掉天数那一半：它本身是对的。以后接跨设备同步、
    ///    合并两台机器的记录时（`n = max(两边)`、天数取并集）两者**会**分叉。
    static func graduated(_ n: Int, _ dayCount: Int) -> Bool {
        n >= hits && dayCount >= days
    }

    /// 今天该不该问这一条。毕业了就不问了。
    static func isDue(_ r: Rev, _ today: String) -> Bool {
        if r.done { return false }
        return r.due.isEmpty || r.due <= today
    }

    /// 今天，`yyyy-MM-dd`。
    static func todayString() -> String { fmt.string(from: Date()) }

    // MARK: - 自测（跟安卓 `selfTest()` 逐条对应）

    /// 返回 nil = 全过。
    static func selfTest() -> String? {
        // ---- addDays：跨月 / 跨年 / 闰日 ----
        if addDays("2026-01-01", 1) != "2026-01-02" { return "加一天" }
        if addDays("2026-02-28", 1) != "2026-03-01" { return "平年 2 月底跨月" }
        if addDays("2024-02-28", 1) != "2024-02-29" { return "闰年该有 2-29" }
        if addDays("2026-12-31", 1) != "2027-01-01" { return "跨年" }
        if addDays("2026-01-01", 21) != "2026-01-22" { return "加 21 天" }

        // ---- 档位：1 -> 3 -> 7 -> 21 -> 21 ----
        let r = Rev("2026-01-01")
        apply(r, true, "2026-01-01")
        if r.due != "2026-01-02" { return "第 1 次答对该隔 1 天" }
        apply(r, true, "2026-01-02")
        if r.due != "2026-01-05" { return "第 2 次该隔 3 天" }
        apply(r, true, "2026-01-05")
        if r.due != "2026-01-12" { return "第 3 次该隔 7 天" }
        if !r.done { return "答对 3 次且跨 3 天该毕业" }
        apply(r, true, "2026-01-12")
        if r.due != "2026-02-02" { return "第 4 次该隔 21 天" }
        apply(r, true, "2026-02-02")
        if r.due != "2026-02-23" { return "第 5 次该还是 21 天（用最后一档）" }

        // ---- ① 同一天再点不算数 ----
        let s = Rev("2026-01-01")
        apply(s, true, "2026-01-01")
        apply(s, true, "2026-01-01")
        apply(s, true, "2026-01-01")
        if s.n != 1 { return "同一天点三次该只算一次" }
        if s.done { return "同一天点三次不该毕业" }

        // ---- ② 答错清零 ----
        let t = Rev("2026-01-01")
        apply(t, true, "2026-01-01")
        apply(t, true, "2026-01-02")
        apply(t, false, "2026-01-05")
        if t.n != 0 { return "答错该清零" }
        if t.due != "2026-01-06" { return "答错该明天再来" }
        if t.done { return "答错不该还是毕业状态" }
        if t.dayList.count != 2 { return "答错不该抹掉答对过的天" }

        // ---- ③ 毕业要两个条件同时成立 ----
        let u = Rev("2026-01-01")
        apply(u, true, "2026-01-01")
        apply(u, true, "2026-01-02")
        if u.done { return "只答对 2 次不该毕业" }
        // 🚨 **直接打 `graduated`**，不经过 `apply` —— 经过 `apply` 的话
        //    n 和天数永远相等，「跨天」那一半测不到（见 graduated 的注释）。
        if graduated(2, 2) { return "2 次 2 天不该毕业" }
        if graduated(3, 2) { return "3 次但只跨 2 天不该毕业" }
        if graduated(2, 3) { return "跨 3 天但只答对 2 次不该毕业" }
        if !graduated(3, 3) { return "3 次 3 天该毕业" }
        if !graduated(9, 9) { return "远超门槛该毕业" }

        // ---- isDue ----
        let v = Rev("2026-01-01")
        if !isDue(v, "2026-01-01") { return "新收的当天就该问" }
        apply(v, true, "2026-01-01")
        if isDue(v, "2026-01-01") { return "答过之后当天不该再问" }
        if !isDue(v, "2026-01-02") { return "到期那天该问" }
        if !isDue(v, "2026-01-09") { return "过期了更该问" }
        let w = Rev("2026-01-01")
        apply(w, true, "2026-01-01")
        apply(w, true, "2026-01-02")
        apply(w, true, "2026-01-05")
        if isDue(w, "2030-01-01") { return "毕业了就不该再问" }
        return nil
    }
}
