import AVFoundation
import UIKit

/// 后台起录自测：**让手机自己跑 S 判据，不用 Kevin 点 30 次。**
///
/// ## 它回答的那个问题
///
/// 新架构里唯一没定论的是：**主 App 在后台（只放着静音）时，
/// 收到命令能不能从零开始打开麦克风。** iOS 对后台起录有限制，
/// 竞品 Typeless 绕到画中画 PiP 很可能正是因为这一条。
///
/// 产品经理 2026-08-28 定的 S 判据是「**5 分钟 / 30 分钟 / 锁屏一整夜，
/// 每档各 10 次**，任一档 ≤9/10 就必须上 PiP」。
///
/// 🚨 **那是 30 次真机操作。** 压给 Kevin 不现实 ——
///    而"让他做 30 次"最可能的结果是做了三五次就算了，
///    然后我们拿一个样本量不足的结论去决定要不要上 PiP。
///
/// **所以让手机自己做**：受限的动作是「这个进程在后台起录」，
/// 跟"谁按的"无关 —— 定时器触发和键盘触发面对的是同一条系统限制。
/// 他只要：打开自测 → 把手机放着 → 第二天把结果复制给我们。**零次点击。**
///
/// ## 为什么不按"档"排，而是每 5 分钟一次、事后分档
///
/// 「5 分钟 / 30 分钟 / 一夜」真正的变量是**进后台多久了**（iOS 的后台
/// 限制随时间加严）。所以固定每 5 分钟试一次、把「距离进后台多久」一起记下来，
/// 跑一夜就三档全有了。**按档分别安排反而要他管三次。**
///
/// ## 🚨 记的是什么
///
/// 每次都记 **`当时 App 在前台还是后台`** —— 没有这一条，
/// 「后台起不了录」和「我们音频配置有问题」分不开，
/// 一整夜的数据会得不出结论。这跟 `KbVoiceHost.where_()` 是同一个理由。
///
/// 🚨 **录到的音频一个字节都不留**：只判起没起得来，起来了立刻停。
///    自测不是录音功能，别让它变成"它整夜在录我"。
final class BgRecProbe {

    static let shared = BgRecProbe()

    /// 每隔多久试一次。
    /// 🚨 5 分钟不是随便选的：它同时是 S 判据里最短的那一档，
    ///    跑一夜（约 12 小时）能拿到约 140 个样本，三档都够 10 个。
    ///
    /// 🚨 允许用环境变量 `TRANSLESS_PROBE_EVERY`（秒）压短 ——
    ///    **只为在模拟器上验这个自测本身跑不跑得起来**。
    ///    不验就发，等于再造一个"诊断自己瞎了"的 557。
    ///    真机上用户设不了环境变量（只有 Xcode / simctl 能注入）。
    static var every: TimeInterval {
        let raw = ProcessInfo.processInfo.environment["TRANSLESS_PROBE_EVERY"]
        if let s = raw, let v = Double(s), v >= 1 { return v }
        return 300
    }

    /// 启动时自动开跑（同样只给模拟器验收用）。
    static var autoStart: Bool {
        ProcessInfo.processInfo.environment["TRANSLESS_PROBE_AUTOSTART"] == "1"
    }
    /// 每次录多久就停。只为判"起不起得来"，不为拿声音。
    private static let hold: TimeInterval = 1.0
    /// 最多留多少条。留太多既没用又撑大存储。
    private static let cap = 400

    private(set) var running = false
    private var timer: Timer?
    private var bgSince: Date?
    private let voice = Voice()

    /// 状态变了喊一声，界面跟着变。
    var onChange: (() -> Void)?

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(didEnterBg),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(willEnterFg),
            name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func didEnterBg() { bgSince = Date() }
    @objc private func willEnterFg() { bgSince = nil }

    // ------------------------------------------------------------ 开关

    func start() {
        if running { return }
        running = true
        // 🚨 电量要**先打开监测**才读得到，否则恒为 -1。
        //    产品经理的 E1/E2 判据是"开着 vs 关着的差值"，
        //    所以开跑那一刻的电量必须记下来 —— 事后补不回来。
        UIDevice.current.isBatteryMonitoringEnabled = true
        UserDefaults.standard.set(UIDevice.current.batteryLevel,
                                  forKey: "bgprobe.batt0")
        // 🚨 自测期间**必须关掉待机的 10 分钟超时**，否则第二档还没到
        //    宿主自己就停了 —— 那样测出来的"起不了录"是我们自己关的，
        //    不是 iOS 拦的。**这类"被自己的设计伪装成故障"最难查。**
        KbVoiceHost.shared.setStandby(true)
        KbVoiceHost.shared.suspendTimeout = true
        timer = Timer.scheduledTimer(withTimeInterval: BgRecProbe.every,
                                     repeats: true) { [weak self] _ in
            self?.attempt()
        }
        onChange?()
    }

    func stop() {
        running = false
        timer?.invalidate(); timer = nil
        KbVoiceHost.shared.suspendTimeout = false
        if voice.running { voice.stop() }
        onChange?()
    }

    // ------------------------------------------------------------ 一次尝试

    private func attempt() {
        Speaker.stop()   // 🚨 起录前停播放（诊断探针也算一个出口）
        guard running else { return }
        let state = UIApplication.shared.applicationState
        let mins = bgSince.map { Int(Date().timeIntervalSince($0) / 60) } ?? -1
        // 让开保活占的音频会话，跟真实链路同一条路
        KbVoiceHost.shared.yieldMic()
        var settled = false
        voice.start(onPartial: { _ in }) { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self, !settled else { return }
                settled = true
                switch r {
                case .success:
                    self.record(ok: true, note: "", state: state, bgMin: mins)
                case .failure(let f):
                    // 🚨 "没听清，再说一次"是**录成功了但太短**，
                    //    那恰恰说明起录成功 —— 别把它记成失败，
                    //    否则整夜的数据全是假的失败。
                    let s = "\(f)"
                    let reallyOK = s.contains("没听清")
                    self.record(ok: reallyOK, note: reallyOK ? "" : s,
                                state: state, bgMin: mins)
                }
                KbVoiceHost.shared.reclaimMic()
            }
        }
        // 起来了就赶紧停 —— 只判起不起得来，不要声音
        DispatchQueue.main.asyncAfter(deadline: .now() + BgRecProbe.hold) {
            [weak self] in
            guard let self = self else { return }
            if self.voice.running { self.voice.stop() }
        }
    }

    // ------------------------------------------------------------ 记账

    private func record(ok: Bool, note: String,
                        state: UIApplication.State, bgMin: Int) {
        let where_: String
        switch state {
        case .active: where_ = "前台"
        case .inactive: where_ = "过渡"
        case .background: where_ = "后台"
        @unknown default: where_ = "未知"
        }
        var rows = raw()
        // 🚨 自增序号：防"同一条被重复读进来"把分母撑虚，而它看起来完全正常。
        //    （产品经理提醒；跟 Y2 那次读到上一轮结果是同一族。）
        let seq = (UserDefaults.standard.integer(forKey: "bgprobe.seq")) + 1
        UserDefaults.standard.set(seq, forKey: "bgprobe.seq")
        rows.append(["seq": seq, "at": Date().timeIntervalSince1970, "ok": ok,
                     "where": where_, "bgMin": bgMin, "note": note,
                     // 电量每条都记 —— 只记首尾的话，中途被杀过就什么都没有了
                     "batt": Double(UIDevice.current.batteryLevel)])
        if rows.count > BgRecProbe.cap {
            rows.removeFirst(rows.count - BgRecProbe.cap)
        }
        UserDefaults.standard.set(rows, forKey: "bgprobe.rows")
        // 🚨 报告也落一份：不落的话它**只能从界面点出来**，
        //    我就没法在发给他之前验一眼这份报告长什么样 ——
        //    而"没验过的诊断件"正是 557 那个坑。
        UserDefaults.standard.set(report(), forKey: "bgprobe.report")
        onChange?()
    }

    private func raw() -> [[String: Any]] {
        (UserDefaults.standard.array(forKey: "bgprobe.rows")
            as? [[String: Any]]) ?? []
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: "bgprobe.rows")
        onChange?()
    }

    var count: Int { raw().count }

    /// 汇总成一段可以直接复制发出来的文字。
    ///
    /// 🚨 **按 S 判据的三档分**，并且**每档都把分母打出来** ——
    ///    只写"成功率 90%"的话，10 次里 9 次和 100 次里 90 次长得一样，
    ///    而产品经理的判据是"任一档 ≤9/10 就上 PiP"，分母不能少。
    func report() -> String {
        let rows = raw()
        if rows.isEmpty { return "还没有样本。打开自测、把手机放着，过一会儿再来看。" }
        var out = ["=== 后台起录自测 ===",
                   "样本 \(rows.count) 条",
                   "",
                   // 🚨 产品经理 2026-08-28 点名要写在报告里：
                   //    **判据的名字不许比它的覆盖面大。**
                   "🚨 覆盖范围：本自测只验「宿主在后台能不能起录」，",
                   "   **不覆盖 键盘→App Group→宿主 那一跳**",
                   "   （键盘能不能叫醒宿主、宿主能不能在键盘等得起的时间内回话，都没测）。",
                   ""]
        // 🚨🚨 档名写「保活持续开启」而不是「进后台多久」——
        //    自测期间关掉了 10 分钟超时，**生产版本 10 分钟就停保活**，
        //    所以后两档对应的状态今天的生产版根本到不了。
        //    写成"进后台 2 小时"会让人以为生产里真会出现那个状态。
        //    产品经理指出：这反而让这份数据回答了一个更值钱的问题 ——
        //    **「保活一直开着的话，后台起录还灵不灵？」**
        //    ＝「能不能干脆把 10 分钟调大，而不上 PiP？」（那正是 H4）
        let buckets: [(String, ClosedRange<Int>)] = [
            ("保活持续开启 5–30 分钟", 5...30),
            ("保活持续开启 30 分钟–2 小时", 31...120),
            ("保活持续开启 2 小时以上", 121...100000),
        ]
        // 🚨🚨 **一个后台样本都没有时，不许打印那三行 `0/0` 和「没有失败」。**
        //    产品经理 2026-08-28 指出：那样出来的是一份
        //    「三档 0/0、对照组全绿、没有失败」的报告 ——
        //    **读起来像"跑完了没问题"，而它一个后台样本都没采到。**
        //    「没有失败」是因为「没有测试」，这两件事在报告里长得一模一样。
        //    （同族第三次：朗读报"没播出声"其实是没点中；
        //     等高报"全部相等"其实是没切档。）
        let bgTotal = buckets.reduce(0) { acc, b in
            acc + rows.filter { b.1.contains(($0["bgMin"] as? Int) ?? -1) }.count
        }
        if bgTotal == 0 {
            out.insert("🚨🚨 本轮无效：**一个后台样本都没采到**。", at: 2)
            out.insert("   别把它读成「没问题」—— 它是「没测到」。", at: 3)
            out.insert("   多半是 App 没真正进后台，或自测中途被停了。", at: 4)
            return out.joined(separator: "\n")
        }
        for (name, r) in buckets {
            let sub = rows.filter { r.contains(($0["bgMin"] as? Int) ?? -1) }
            let ok = sub.filter { ($0["ok"] as? Bool) ?? false }.count
            // 🚨 样本不足时**不许换算成成功率**：3/3 不是 100%，是"样本不足"。
            let tag = sub.count < 10 ? "  ← 样本不足 10，不作数" : ""
            out.append("\(name)：\(ok)/\(sub.count)\(tag)")
        }
        out.append("🚨 后两档写的是「保活一直开着」的情形 —— **生产版本 10 分钟就停保活**，")
        out.append("   所以那两档对应的状态今天的生产版到不了。它回答的是：")
        out.append("   「保活一直开着的话还灵不灵」＝「能不能把 10 分钟调大而不上 PiP」。")
        out.append("")
        // 序号连续性：有断号或重号就说出来，别让分母虚高而无人知道
        let seqs = rows.compactMap { $0["seq"] as? Int }
        if seqs.count == rows.count && !seqs.isEmpty {
            let uniq = Set(seqs).count
            let span = (seqs.max() ?? 0) - (seqs.min() ?? 0) + 1
            if uniq != rows.count || span != rows.count {
                out.append("🚨 样本序号不连续（\(rows.count) 条 / 去重 \(uniq) / "
                           + "跨度 \(span)）—— 分母可能虚高或丢过样本")
            }
        }
        let fg = rows.filter { ($0["where"] as? String) == "前台" }
        let fgOK = fg.filter { ($0["ok"] as? Bool) ?? false }.count
        // 🚨 前台那组是**对照组**：如果前台也起不来，
        //    那就不是"后台限制"，是我们自己的音频配置坏了。
        //    产品经理定的规矩：对照组 <3 个 或 有失败 → **本轮数据作废**。
        out.append("（对照组）在前台时：\(fgOK)/\(fg.count)")
        if fg.count < 3 || fgOK < fg.count {
            out.append("🚨 对照组不合格（要 ≥3 且全成功）——"
                       + "**本轮数据作废，先查我们自己的音频配置**，别拿它去判 PiP。")
        }

        // 电量（产品经理的 E1/E2：判据是**差值**，不是绝对值）
        let b0 = UserDefaults.standard.object(forKey: "bgprobe.batt0") as? Float
        let b1 = rows.last?["batt"] as? Double
        if let b0 = b0, let b1 = b1, b0 >= 0, b1 >= 0 {
            out.append("电量：开始 \(Int(b0 * 100))% → 现在 \(Int(b1 * 100))%"
                       + "（掉了 \(Int(b0 * 100) - Int(b1 * 100)) 个点）")
            out.append("🚨 这个数**单独没有意义** —— 要跟"
                       + "「不开自测的同样一夜掉多少」比才说明得了问题。")
        } else {
            out.append("电量：拿不到（模拟器上没有电量）")
        }

        // 🚨 H4：多久撞一次「待机过期」。产品经理说得对 ——
        //    「该不该这么频繁地需要恢复」比「恢复得顺不顺」重要。
        //    **报间隔，不报次数**：次数脱离时间跨度没有意义
        //    （一天 5 次和一个月 5 次是完全不同的两件事）。
        let exp = (UserDefaults.standard.array(forKey: "standby.expiredAt")
                   as? [Double]) ?? []
        if exp.count >= 2 {
            var gaps: [Double] = []
            for i in 1..<exp.count { gaps.append(exp[i] - exp[i - 1]) }
            let avg = gaps.reduce(0, +) / Double(gaps.count)
            out.append("待机过期 \(exp.count) 次，平均隔 \(Int(avg / 60)) 分钟一次")
        } else {
            out.append("待机过期 \(exp.count) 次（不足 2 次，算不出间隔）")
        }
        out.append("")
        out.append("--- 失败的样本（最多 8 条）")
        let bad = rows.filter { !(($0["ok"] as? Bool) ?? false) }
        if bad.isEmpty {
            out.append("（没有失败）")
        } else {
            for row in bad.suffix(8) {
                out.append("进后台 \(row["bgMin"] as? Int ?? -1) 分钟 · "
                           + "\(row["where"] as? String ?? "?") · "
                           + "\(row["note"] as? String ?? "")")
            }
        }
        return out.joined(separator: "\n")
    }
}
