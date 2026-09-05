import Foundation

/// 首页四格 KPI 的**纯计算核**（翻译口径，Kevin 09-03 推翻旧的 Typeless 口径后重做）。
///
/// 权威：`_方案_首页四格KPI改成翻译口径`（KPI-10/11/14）+ 2.1 2026-09-04 定的**最终 ③④**。
/// 🚨 不是安卓旧 `HomeStatsCore`（字数/天数/语速）。也不是我 09-03 写的旧口径
///    （统计天数/语种去重）——那两个 2.1 都砍了。以下是**最终锁死**的四格：
///
/// ```
/// ① 翻译了多少词 = **后端 `words` 的累加器**（`KpiWords`），从外面传进来
/// ② 省下多少时间 = ①词数 ÷ 40 词/分钟  −  ③说话时长(分钟)
/// ③ 说话时长     = **累加器** `KpiWords.spokenMs`
/// ④ 说的字数     = **累加器** `KpiWords.chars`
///      脚注「按平均打字 40 词/分钟算」——40 从 `typingWPM` 取，不写死文案
/// ```
/// 🚨🚨 **① 不在端上数词**（2026-09-04 最终口径，规格 `_后端_词数字段_客户端规格.md`）：
///    三端各写一套数词规矩的话，`don't` 算 1 还是 2 会给出三个不同的总数，
///    **而他会拿这个数去跟别人说**。所以 ① 只由后端算、客户端累加。
///    并且**只有翻译档累加** —— 他说英文走逐字档时后端也回 `words>0`，
///    但那是转写不是翻译（宁可少算，不许多算）。累加的闸在 `Backend` 那两条结果链上。
/// 🚨🚨 **四格统一走 lifetime 累加器、不遍历 History**（2.1 2026-09-04 定的「甲」）：
///    他清历史时 KPI **不动** —— 清掉的是记录，不是"我这辈子说了多少"。
///    累加点只有一个：`History.add`（键盘/随手翻译/面对面都走它），重译条跳过。
///
/// ## null ≠ 0（KPI-13）
/// - 一条数据都没有 → **整块空态卡**（`enough == false`），不是四个 0。
/// - `durMs == 0` 是「不知道」不是「说了 0 秒」——③②排除掉。
/// - ①为 0 或 nil → ② 不成立（`savedValid == false`），不拿 0÷40 报「省了 0 分钟」。
/// - ② 算出**非正数**（说得比打字慢）也不叫「省下」，走「还没有数据」。
enum HomeStatsCore {

    /// 🚨 **单一配置点**：**平均英文打字速度，词/分钟**。脚注文案里那个数从这儿取。
    /// 🚨 2026-09-04 口径换过一次：原来是「专业译者 300 词/小时」，2.1 改成
    ///    **「平均打字 40 词/分钟」**（打字测试通用均值、可引用，不是编的）——
    ///    对比的对象从"找人翻译"变成"自己打字"。改这个数只改这一处。
    static let typingWPM = 40

    // 🚨 `Rec` 已删（2026-09-04 口径「甲」）：四格全走累加器，不再遍历 History。
    //    删掉是因为它零调用点了 —— 留着就是死代码，下一个人会以为还该往里传记录。


    struct Stats {
        /// 🚨 false = 一条都没有 → **整块空态卡**（KPI-13）。
        let enough: Bool
        let words: Int              // ① 翻译了多少词
        /// ② 省下多少**分钟**。🚨 只有 `savedValid` 为真才显示，否则那格「还没有数据」。
        let savedMinutes: Double
        let savedValid: Bool
        let spokenMs: Int           // ③ 说话时长（毫秒；UI 自己折算成时/分）
        let chars: Int              // ④ 说的字数
    }

    // 🚨 端上数词的 `wordCount` **已删**（2026-09-04 最终口径）：客户端各数一套的话，
    //    `don't` 算 1 还是 2 会在三台设备上给出三个不同的总数，而他会拿这个数去跟别人说。
    //    ① 一律由后端 `words` 累加（`KpiWords`），从外面传进来。

    /// 数一段原话里说了多少字：**去掉标点和空白**，只留真正说出来的字（跟安卓 `countChars` 同口径）。
    static func charCount(_ zh: String) -> Int {
        var n = 0
        for u in zh.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(u) { continue }
            if CharacterSet.punctuationCharacters.contains(u) { continue }
            if CharacterSet.symbols.contains(u) { continue }
            n += 1
        }
        return n
    }

    /// 算四格。🚨 **四个数全部来自累加器**（2026-09-04 口径「甲」：lifetime、清历史不动 KPI）。
    /// - Parameters:
    ///   - words: ① 翻译词数（`KpiWords.total`，后端 `words` 累加，只翻译档）
    ///   - spokenMs: ③ 累计说话毫秒（`KpiWords.spokenMs`）
    ///   - chars: ④ 累计说了多少字（`KpiWords.chars`）
    /// 🚨 任一为 `nil` = 从来没记过 → 那格写「还没有数据」，**不许当 0 算**。
    /// 🚨 **不再遍历 History**：以前那样做，他一清历史 KPI 就跟着归零 ——
    ///    而"我这辈子说了多少"不该被"清掉记录"抹掉（2.1 定的「甲」）。
    ///    累加发生在 `History.add`（所有说话事件的唯一必经之路），重译条跳过。
    /// - Parameter transMs: ② 的减数＝**只有翻译档**的说话毫秒（`KpiWords.transMs`）。
    ///   🚨 不是 `spokenMs`。见下面 M1 那段。
    static func compute(words: Int?, spokenMs: Int?, chars: Int?,
                        transMs: Int? = nil) -> Stats {
        let w = words ?? 0
        let sp = spokenMs ?? 0
        let ch = chars ?? 0
        let tr = transMs ?? 0
        // 🚨 M4：`enough` 要含**时长**这一维 —— zh 为空但说了 2 分钟也不算「没有数据」。
        let enough = w > 0 || ch > 0 || sp > 0
        // ② = 词数/40（分钟） − 说话时长（分钟）。
        // 🚨 必须**真拿到过词数**（不是 nil）且有真时长才叫得出「省下」——
        //    词数是 nil 时不许拿 0÷40 报「省了 0 分钟」（规格 §3：缺失≠0）。
        // 🚨🚨 **M1 那条口径 2026-09-05 被 Kevin 当场推翻，这里记清为什么。**
        //    原来是「① 只是翻译档的词、③ 是全部说话时长，两者不同源，
        //    算出负数就走『还没有数据』」——
        //    **"不同源"才是真正的病，"显示破折号"只是在给病打掩护。**
        //    他大量用转写-整理：那些时长全进减数、一个词都不进分子
        //    ⇒ ② 结构性偏负 ⇒ **恒 ≤0 ⇒ 恒显一个杠**，这一格从来没出过数。
        //    他的原话：「省下时间这个指标所有的终端显示的都是一个杠，没有数字」。
        //
        //    改两处：
        //    ① 减数换成 `transMs`（**只有翻译档**的说话时长），分子分母同源了；
        //    ② 有活动就出数，负的按 0 分显示（`KpiGridView` 里 `max(0,)`），
        //       **不再出现裸破折号**。
        let saved = Double(w) / Double(typingWPM) - Double(tr) / 60_000.0
        // 🚨 判据是"有没有活动"，不是"结果是不是正的"——
        //    拿结果本身当有效性判据，就是让指标自己决定要不要出现，
        //    结构性偏负时它永远选择不出现。
        let savedValid = enough
        return Stats(enough: enough, words: w,
                     savedMinutes: saved, savedValid: savedValid,
                     spokenMs: sp, chars: ch)
    }

    // MARK: - 自测（纯逻辑）

    /// 返回 nil = 全过。判据是**每个数落到哪**，不是"返回了个结构体"。
    static func selfTest() -> String? {
        // 全 nil = 从来没记过 → 空态卡，且 ② 不成立
        let e = compute(words: nil, spokenMs: nil, chars: nil)
        if e.enough { return "全 nil 该判空态卡" }
        if e.savedValid { return "全 nil 不该有省时" }

        // 正常一组：翻了 100 词、翻译档说了 90 秒、一共说了 200 秒、说了 200 字
        // 🚨 `spokenMs`(200s) 故意跟 `transMs`(90s) **不一样** ——
        //    两个都填成 90 秒的话，"② 到底减的是哪一个"这条就测不出来了。
        let s = compute(words: 100, spokenMs: 200_000, chars: 200, transMs: 90_000)
        if s.words != 100 { return "① 该 100，实得 \(s.words)" }
        if s.spokenMs != 200_000 { return "③ 该 200000ms，实得 \(s.spokenMs)" }
        if s.chars != 200 { return "④ 该 200，实得 \(s.chars)" }
        // ② = 100/40 − 90000/60000 = 2.5 − 1.5 = 1.0 分钟
        let want = 100.0 / 40.0 - 90_000.0 / 60_000.0
        if abs(s.savedMinutes - want) > 0.0001 {
            return "② 该 \(want) 分钟，实得 \(s.savedMinutes)"
        }
        if !s.savedValid { return "有词有时长且为正，该能报省下" }

        // 🚨🚨 **② 减的必须是 `transMs`，不是 `spokenMs`。**
        //    这条就是他 09-05 报的那个病的判据：同一组数，只把"全部说话"
        //    调大而"翻译档说话"不变，② **不许跟着变**。
        //    变了 = 又回到"分子只数翻译档、减数含全部说话"的旧口径。
        let more = compute(words: 100, spokenMs: 9_999_000, chars: 200, transMs: 90_000)
        if abs(more.savedMinutes - s.savedMinutes) > 0.0001 {
            return "🚨 ② 跟着「全部说话」变了 —— 减数还在用 spokenMs"
        }

        // 🚨🚨 **坏样本（2.1 点名的那个）：只用转写档说十句、一句翻译都不做。**
        //    → 词数 nil、翻译档时长 0、但说了 10 分钟。
        //    **必须出数（界面上显示「0 分」），不许显示裸「—」** ——
        //    旧口径在这里恒判无效，于是那一格从来没出过数。
        let onlyRaw = compute(words: nil, spokenMs: 600_000, chars: 300, transMs: nil)
        if !onlyRaw.savedValid {
            return "🚨 只用转写档也该出数（显示 0 分），不该是破折号"
        }

        // 🚨 坏样本：说得比打字慢 → ② 算出来是负的。
        //    **仍然要出数**（界面 `max(0,)` 显示 0 分），负数不许摆到首页上。
        let slow = compute(words: 10, spokenMs: 600_000, chars: 50, transMs: 600_000)
        if !slow.savedValid { return "🚨 算出负数也该出数（界面按 0 分显示）" }
        if slow.savedMinutes >= 0 { return "🚨 这一组本来就该是负的，样本设计废了" }

        // 🚨 坏样本：**什么都没记过** → 这才是唯一该显示「—」的世界
        let none = compute(words: nil, spokenMs: nil, chars: nil, transMs: nil)
        if none.savedValid { return "🚨 一条记录都没有时不该出数" }

        // 🚨 坏样本：只有时长、没词没字 → 仍算"有数据"（M4：enough 要含时长维）
        let onlyDur = compute(words: nil, spokenMs: 120_000, chars: nil)
        if !onlyDur.enough { return "🚨 说了 2 分钟不该被当成「一条数据都没有」" }

        // 真的是 0（记过但都是 0）→ 空态，而不是崩
        let zero = compute(words: 0, spokenMs: 0, chars: 0)
        if zero.enough { return "全 0 该判空态卡" }
        return nil
    }
}
