import Foundation

/// **「到点提醒我」** —— 整理档顺带从他说的话里认出一个时间点。
///
/// 契约（1.1 的后端，0 转来的）：整理档的 JSON 里多一个键
/// ```
/// "remind": {"at": "2026-09-08T15:00:00+08:00", "what": "跟客户开会"}
/// "remind": null       // 绝大多数时候
/// ```
/// `at` 是**完整 ISO 带时区**，客户端不用自己解析中文时间。
/// 🚨 请求体里**必须传 `now`**（带时区），不传后端一律回 null。
///
/// ## 🚨 为什么这一层要自己再判一次（1.1 踩出来的，对我同样成立）
/// > 不传 `now` 时**模型自己脑补了一个「今天」还给了提醒** ——
/// > 而提示词里明写「没有 Now 就一律 null」。**靠提示词约束＝没约束。**
///
/// 所以：**拿到 `remind` 不许假设它合法**。`at` 可能是过去的时刻、
/// 可能缺时区、可能压根不是时间。**判据在别人的提示词里 ≠ 我这端安全。**
///
/// 🚨 **本地通知不是闹钟**（不响铃、不穿透静音）。Kevin 说的是「定闹钟」，
///    0 已经当面跟他说清了这个差别 —— **但文案里一个「闹钟」都不许写**。
struct Remind: Equatable {
    let at: Date
    let what: String

    /// 太远的不收：一年以后多半是模型算错了年份（`2027-09-08` 那种）。
    static let maxAhead: TimeInterval = 365 * 24 * 3600
    /// 太近的不收：已经过去、或者两分钟内 —— 通知还没排上就到点了。
    static let minAhead: TimeInterval = 120

    /// **认出一条提醒之后交给谁**。默认没人接。
    ///
    /// 🚨 用注入而不是直接调通知接口：这个文件**也编进键盘扩展和测试目标** ——
    ///    键盘不该去排通知（它是另一个进程，排了主 App 也管不着），
    ///    测试目标更不该。今天已经因为纯逻辑文件依赖只有 App 才有的东西
    ///    把测试目标编崩过一次（Segments 直接调 KbBridge）。
    ///    **纯逻辑文件不许依赖只有 App 才有的能力。**
    static var onParsed: ((Remind) -> Void)?

    /// 请求体里的 `now`。**必须带时区** —— 不带的话后端一律回 null。
    static func nowISO(_ d: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone.current
        return f.string(from: d)
    }

    /// 从整理档那份 JSON 里认出 `remind`，**并且自己判一遍合不合法**。
    ///
    /// - Parameter now: 判"是不是过去了"的基准。测试可以喂固定值。
    /// - Returns: 合法才返回；任何一处判不过都返回 `nil`（当没有）。
    ///
    /// 🚨 **判不过一律当 null，不报错、不猜** —— 这一条是给用户的提醒，
    ///    宁可不弹，也不能在错的时刻弹一个他没约过的东西。
    static func parse(_ obj: [String: Any]?, now: Date = Date()) -> Remind? {
        guard let r = obj?["remind"] as? [String: Any] else { return nil }
        guard let atStr = (r["at"] as? String)?
                .trimmingCharacters(in: .whitespaces), !atStr.isEmpty,
              let what = (r["what"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !what.isEmpty
        else { return nil }
        guard let at = parseISO(atStr) else { return nil }
        let ahead = at.timeIntervalSince(now)
        // 🚨 过去的、马上就到的、一年以后的，全不收。
        guard ahead >= minAhead, ahead <= maxAhead else { return nil }
        return Remind(at: at, what: what)
    }

    /// 🚨 **必须带时区才收**。
    ///
    ///    `ISO8601DateFormatter` 不带 `.withTimeZone` 时会把无时区的串
    ///    **按 UTC 解**，于是「明天下午三点」在东八区会变成晚上十一点 ——
    ///    **它不报错，只是悄悄差八小时**。这正是"解析成功≠解析对了"。
    static func parseISO(_ s: String) -> Date? {
        // 末尾必须是 Z 或 ±HH:MM / ±HHMM
        let tz = s.hasSuffix("Z")
            || s.range(of: "[+-][0-9]{2}:?[0-9]{2}$", options: .regularExpression) != nil
        guard tz else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    /// 自测：好样本过 + 每种坏样本各因**不同**原因被挡。
    ///
    /// 🚨 判据要能失败：下面每一条坏样本，只要我把对应那道判断删掉，
    ///    它就会变成"通过" —— 这就是"什么输入能让它失败"的答案。
    static func selftest() -> [String] {
        var bad: [String] = []
        let base = Date(timeIntervalSince1970: 1_757_000_000)   // 固定基准
        let ok = Remind.parseISO("2026-09-08T15:00:00+08:00")!
        func mk(_ at: String, _ what: String) -> [String: Any] {
            return ["remind": ["at": at, "what": what]]
        }
        // 好样本
        let good = mk(Remind.nowISO(base.addingTimeInterval(3600)), "跟客户开会")
        if Remind.parse(good, now: base)?.what != "跟客户开会" {
            bad.append("好样本没通过")
        }
        // 坏①：null
        if Remind.parse(["remind": NSNull()], now: base) != nil {
            bad.append("null 竟然收了")
        }
        // 坏②：过去的时刻
        if Remind.parse(mk(Remind.nowISO(base.addingTimeInterval(-3600)), "x"),
                        now: base) != nil {
            bad.append("过去的时刻竟然收了")
        }
        // 坏③：缺时区（会被当 UTC 悄悄差 8 小时）
        if Remind.parse(mk("2026-09-08T15:00:00", "x"), now: base) != nil {
            bad.append("缺时区竟然收了")
        }
        // 坏④：what 是空的
        if Remind.parse(mk(Remind.nowISO(base.addingTimeInterval(3600)), "  "),
                        now: base) != nil {
            bad.append("空 what 竟然收了")
        }
        // 坏⑤：太远（模型把年份算错那种）
        if Remind.parse(mk(Remind.nowISO(base.addingTimeInterval(400 * 86400)),
                           "x"), now: base) != nil {
            bad.append("一年以后的竟然收了")
        }
        // 坏⑥：at 根本不是时间
        if Remind.parse(mk("明天下午三点", "x"), now: base) != nil {
            bad.append("中文时间串竟然收了")
        }
        // 反向对照：合法的解析结果要跟直接解出来的一致
        if Remind.parseISO("2026-09-08T15:00:00+08:00") != ok {
            bad.append("同一个串两次解出不同结果")
        }
        return bad
    }
}
