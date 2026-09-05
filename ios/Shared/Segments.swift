import Foundation

/// 长录音的分段转写：**边录边传**，最后按序拼起来。
///
/// 🚨🚨 **这是安卓 `Segments.java` 的逐条移植，不是重新设计。**
///    两个常量（`SEG_SECONDS` / `OVERLAP_MS`）、`join` 的去重规则、
///    失败段的占位文案，全部一一对应。两端不一致的话，同一段话在
///    iOS 上被拼错、在安卓上是对的 —— 而这种差别他会当成"iOS 版不好用"。
///
/// 存在的理由（Kevin 2026-08-24）：「我说的要最大支持 15 分钟的这个需求
/// （语音输入支持录 15 分钟），有考虑吗」——
/// **iOS 一直是 60 秒**，他 2026-08-31 撞到：「怎么才一分钟不到就停了」。
///
/// 为什么不能整段传（安卓那边打线上实测的表，iOS 走同一个后端，同样适用）：
/// ```
///   60s/1.8MB ✅ · 90s/2.7MB ✅ · 120s/3.6MB ✅ · 180s/5.5MB ✅
///   240s/7.3MB 🚨 HTTP 504 upstream request timeout
/// ```
/// 所以每段切 **60 秒**：离天花板留 3 倍余量。网关 504 是偶发的
/// （120 秒那档也偶尔撞），卡着线切必然时不时失败。
///
/// 🚨 **边录边传**是关键，不只是为了绕开体积：他说到第 2 分钟时第 1 段
///    已经转完了，停下之后只需等最后一段 —— 而不是等 15 分钟的音频从头传一遍。
///    内存也因此有界：只留当前这一段。
///
/// 🚨 一段失败**不许静默丢掉**。整段音频是他说的话，丢了他不知道丢在哪。
///    失败的那段在拼接结果里留一句「【第 N 段没转出来】」，让他看得见。
final class Segments {

    /// 每段多少秒。见上面那张实测表 —— **不许拍脑袋改大**。
    static let SEG_SECONDS = 60

    /// 段与段之间重叠多少毫秒。
    ///
    /// 🚨 不重叠的话，正好被切在中间的那个字**两边都丢**：
    ///    前一段听到半个音、后一段也听到半个音，谁都认不出来。
    ///    重叠 0.5 秒让那个字至少在一边是完整的；重复出来的字由 `join` 去掉。
    static let OVERLAP_MS = 500

    private final class Slot {
        let index: Int
        var text: String?
        var error: String?
        let done = DispatchSemaphore(value: 0)
        init(_ i: Int) { index = i }
    }

    private let lock = NSLock()
    private var slots: [Slot] = []

    /// 转写一段的实现。默认走 `Backend.transcribe`；自测时替换成假的。
    private let transcribe: (Data, @escaping (Result<String, Error>) -> Void) -> Void

    init(transcribe: @escaping (Data, @escaping (Result<String, Error>) -> Void) -> Void) {
        self.transcribe = transcribe
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return slots.count }

    /// 交一段进来，**立刻去转**，不等。
    /// - Parameter wav: 已经封好 WAV 头的一段音频
    func submit(wav: Data) {
        lock.lock()
        let s = Slot(slots.count)
        slots.append(s)
        lock.unlock()
        transcribe(wav) { r in
            switch r {
            case .success(let t): s.text = t
            // 🚨 记下来，不吞。拼接时会把它显式写出来。
            case .failure(let e): s.error = String(describing: e)
            }
            s.done.signal()
        }
    }

    /// 等所有段跑完，按序拼成一整篇中文。
    /// - Parameter waitSec: 最多等多久（墙钟）。超时的段按失败处理。
    func awaitAll(waitSec: TimeInterval) -> String {
        let deadline = Date().addingTimeInterval(waitSec)
        lock.lock(); let copy = slots; lock.unlock()
        for s in copy {
            let left = max(0.1, deadline.timeIntervalSinceNow)
            if s.done.wait(timeout: .now() + left) == .timedOut, s.text == nil {
                s.error = "等太久了"
            }
        }
        var parts: [String] = []
        for s in copy {
            let t = (s.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                parts.append(t)
            } else {
                // 🚨 显式留痕：他得知道哪一段没了，而不是莫名其妙少一截
                parts.append("【第 \(s.index + 1) 段没转出来："
                             + (s.error ?? "空结果") + "】")
            }
        }
        return Segments.join(parts)
    }

    /// 全部成功了吗（给台账用）。
    var failedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return slots.filter { ($0.text ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines).isEmpty }.count
    }

    /// 按序拼接，并去掉重叠段造成的重复。
    ///
    /// 🚨 重叠 0.5 秒会让接缝处的几个字在两段里各出现一次。
    ///    做法：拿前一段的**结尾**和后一段的**开头**找最长的重复串（有上限），
    ///    找到就把后一段那一份删掉。
    /// 🚨 上限必须有：不设的话，两段开头都是「嗯那个」这种口水词时，
    ///    会把后一段真正的内容当成重复删掉 —— **删多了比留着重复糟得多**。
    static func join(_ parts: [String]) -> String {
        var sb = ""
        for p in parts where !p.isEmpty {
            if sb.isEmpty { sb = p; continue }
            let cut = overlapLen(sb, p)
            sb += String(p.dropFirst(cut))
        }
        return sb
    }

    /// 前文结尾和 `next` 开头重复了多少个字（0 表示没重复）。
    static func overlapLen(_ prev: String, _ next: String) -> Int {
        let a = Array(prev), b = Array(next)
        // 🚨 0.5 秒最多也就三五个字，给到 8 已经很松。再大就开始误删。
        let maxK = min(8, min(a.count, b.count))
        guard maxK >= 2 else { return 0 }
        // 🚨 至少 2 个字才算重复 —— 单字重复太常见（「的」「了」）
        for k in stride(from: maxK, through: 2, by: -1) {
            let from = a.count - k
            var same = true
            for i in 0..<k where a[from + i] != b[i] { same = false; break }
            if same { return k }
        }
        return 0
    }

    // ------------------------------------------------------------ 自测

    /// 由 `gate_all_selftests.py` 自动发现并运行。
    /// 🚨 判据全部挂在**他会看到的那段文字**上，不是"函数有没有被调用"。
    static func selfTest() -> String? {
        var bad: [String] = []

        // ① 去重：接缝处重复的几个字要被删掉一份
        let a = join(["今天我们开个会讨论", "讨论一下审计进度"])
        if a != "今天我们开个会讨论一下审计进度" { bad.append("去重：拼错了 -> " + a) }

        // ② 🚨 单字重复**不许**当成重叠删掉（"的""了"太常见）
        let b = join(["他来了", "了不起的事情"])
        if !b.hasSuffix("了不起的事情") { bad.append("单字：不该删 -> " + b) }

        // ③ 没有重叠时原样接上，一个字都不能少
        let c = join(["第一段内容", "完全不同的第二段"])
        if c != "第一段内容完全不同的第二段" { bad.append("无重叠：丢字了 -> " + c) }

        // ④ 🚨 上限：重复超过 8 个字也只删 8 个，绝不整段吞掉
        let long = "一二三四五六七八九十"
        let d = join([long, long])
        if d.count <= long.count { bad.append("上限：把整段吞了 -> " + d) }

        // ⑤ 空段跳过，不产生空洞
        let e = join(["甲", "", "乙"])
        if e != "甲乙" { bad.append("空段：处理错了 -> " + e) }

        // ⑥ 🚨 **失败的段必须看得见**（安卓那条「不许静默丢掉」）
        let segs = Segments { _, done in done(.failure(NSError(
            domain: "t", code: 1, userInfo: [NSLocalizedDescriptionKey: "假失败"]))) }
        segs.submit(wav: Data([1, 2, 3]))
        let f = segs.awaitAll(waitSec: 3)
        if !f.contains("第 1 段没转出来") { bad.append("失败段：被静默吞了 -> " + f) }
        if segs.failedCount != 1 { bad.append("失败计数不对：\(segs.failedCount)") }

        // ⑦ 阴性对照：成功的段不该出现「没转出来」
        let ok = Segments { _, done in done(.success("正常内容")) }
        ok.submit(wav: Data([1]))
        let g = ok.awaitAll(waitSec: 3)
        if g != "正常内容" { bad.append("正常段：拼错了 -> " + g) }
        if ok.failedCount != 0 { bad.append("正常段却记成失败") }

        // ⑧ 🚨 顺序必须按提交顺序，不是完成顺序 —— 先提交的先慢一点
        let ord = Segments { d, done in
            let first = (d.first ?? 0) == 1
            DispatchQueue.global().asyncAfter(deadline: .now() + (first ? 0.3 : 0.05)) {
                done(.success(first ? "前面" : "后面"))
            }
        }
        ord.submit(wav: Data([1])); ord.submit(wav: Data([2]))
        let h = ord.awaitAll(waitSec: 5)
        if h != "前面后面" { bad.append("顺序：按完成顺序拼了 -> " + h) }

        return bad.isEmpty ? nil : bad.joined(separator: "; ")
    }
}
