import Foundation

/// 生日下拉里「日」那一档有几个选项。**纯逻辑，跟安卓一字不差**
/// （安卓那份在 `android/java/com/kevin/shuoyingwen/BirthDays.java`）。
///
/// Kevin 2026-08-26：「出生日期加个下拉项目嘛，就是哪一年、哪一月、哪一日」。
/// 年、月一变，日的档数要跟着变 —— 2 月只有 28 天，闰年 29 天。
///
/// 🚨 为什么单独抽出来：这条规则**必须能拿正负样本量一遍**，而它原来
///    埋在界面里，只能靠在模拟器上点开下拉、滚到底、数最大的数字来验。
///    那个测法在安卓上试过，两次都翻车（一次量到的"最大日子"其实是
///    年份下拉的 2024；一次为了滚到底狂发 swipe 把模拟器灌成 ANR）。
///    抽成纯函数之后，1900 / 2000 / 2024 / 2023 一秒钟全量跑完。
///
/// 🚨 用 `Calendar.range(of:in:for:)`，**不自己写闰年规则** ——
///    「四年一闰、百年不闰、四百年再闰」手写必出错，而错的恰恰是
///    1900-02（不闰）和 2000-02（闰）这两个没人会去测的边界。
enum BirthDays {

    /// 年份下拉的下限。1920 往前对这个产品没有意义。
    static let minYear = 1920

    /// 年或月还没选时给的档数。先让人随便选，选全了再校正。
    static let unknown = 31

    /// 固定公历 + GMT。
    /// 🚨 不锁的话，用户切成佛历/回历时算出来的月份天数会完全不同，
    ///    而安卓那边用的是 `GregorianCalendar` —— 两端会静静地走散。
    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    /// 这个年月有几天。`y`/`m` 传 0 表示还没选。
    static func daysIn(_ y: Int, _ m: Int) -> Int {
        guard y > 0, m > 0, m <= 12 else { return unknown }
        var c = DateComponents()
        c.year = y
        c.month = m
        c.day = 1
        guard let d = cal.date(from: c),
              let r = cal.range(of: .day, in: .month, for: d) else {
            return unknown
        }
        return r.count
    }

    /// 三个都选了才算填了；少一个就当没填，返回空串。
    ///
    /// 🚨 **不许用"年填了就补个 01-01"糊弄** —— 那样存进去的是垃圾数据，
    ///    以后没法区分"他生日就是元旦"和"他只选了年份"。
    ///
    /// 🚨 日超出这个月的天数时也返回空串（比如 2 月 31 日）。
    ///    界面上换月会把不存在的日退回"没选"，但这里再挡一道 ——
    ///    界面那条路以后改了，这里的口径不该跟着松。
    static func format(_ y: Int, _ m: Int, _ d: Int) -> String {
        guard y > 0, m > 0, d > 0 else { return "" }
        guard m <= 12, d <= daysIn(y, m) else { return "" }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// 年份下拉的选项，**从今年往回排**到 `minYear`。
    ///
    /// 🚨 倒序不是随手写的：生日更可能落在近几十年，正序的话每个人
    ///    一进来都要往下滑一百多格。
    ///
    /// 🚨 「今年」从系统时钟取，所以这个函数**不是**纯函数，自测里
    ///    只断言它的**形状**，不写死具体年份 —— 写死的话明年 1 月 1 日
    ///    这个测试会自己变红。
    static func years() -> [Int] {
        let now = cal.component(.year, from: Date())
        return Array(stride(from: now, through: minYear, by: -1))
    }

    // MARK: - 自测（跟安卓 `selfTest()` 逐条对应）

    /// 跟安卓 `selfTest()` 一一对应。返回 nil = 全过。
    ///
    /// 🚨 1900 / 2000 这两条是**手写闰年规则必错的地方**。
    ///    坏样本注入验过：换成手写版时响的正是「2000-02 四百年再闰」。
    static func selfTest() -> String? {
        if daysIn(2024, 2) != 29 { return "2024-02 闰年" }
        if daysIn(2023, 2) != 28 { return "2023-02 平年" }
        if daysIn(2000, 2) != 29 { return "2000-02 四百年再闰" }
        if daysIn(1900, 2) != 28 { return "1900-02 百年不闰" }
        if daysIn(2026, 1) != 31 { return "2026-01 大月" }
        if daysIn(2026, 4) != 30 { return "2026-04 小月" }
        if daysIn(2026, 12) != 31 { return "2026-12 大月" }
        if daysIn(0, 2) != 31 { return "年没选给 31" }
        if daysIn(1990, 0) != 31 { return "月没选给 31" }
        if daysIn(0, 0) != 31 { return "都没选给 31" }
        if daysIn(1990, 13) != 31 { return "月越界给 31" }
        if format(1990, 7, 15) != "1990-07-15" { return "三个都选" }
        if format(1990, 7, 5) != "1990-07-05" { return "补零" }
        if format(1990, 0, 0) != "" { return "只选年不存" }
        if format(1990, 7, 0) != "" { return "只选年月不存" }
        if format(0, 0, 0) != "" { return "一个都没选不存" }
        if format(2023, 2, 30) != "" { return "2 月 30 日不存" }
        if format(2024, 2, 29) != "2024-02-29" { return "闰年 2-29 该存" }
        if format(2023, 2, 29) != "" { return "平年 2-29 不存" }
        // years()：只断言**形状**，不写死年份 ——
        // 写死的话明年 1 月 1 日这个测试会自己变红。
        let ys = years()
        if ys.first! <= ys.last! { return "年份该倒序" }
        // 🚨🚨 期望值**写死 1920**，不写 `minYear` ——
        //    `ys.last! != minYear` 是**同源自比**：把常量改成 1970，
        //    两边一起变，断言照样成立，检查永远不会响。
        //    坏样本注入当场抓到过这一条（「年份下限写错」没响）。
        //    ——「今年」不写死是因为它每年会变；1920 是产品定的下限，不会变。
        if minYear != 1920 { return "年份下限该是 1920" }
        if ys.last! != 1920 { return "年份该排到 1920" }
        if ys.count != ys.first! - 1920 + 1 { return "年份长度不对" }
        if Set(ys).count != ys.count { return "年份有重复" }
        return nil
    }
}
