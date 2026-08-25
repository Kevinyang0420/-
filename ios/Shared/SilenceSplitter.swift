import Foundation

/// 静音切分：连续模式下判断「这句说完了」。
///
/// 🚨🚨 **这是安卓 `SilenceSplitter.java` 的逐条翻译，不是重新设计。**
///    三个常量、`feed` 的判断顺序、`hasVoice()` 的语义，全部一一对应。
///    两端不一致的话，同一句话在 iOS 上被切成两句、在安卓上是一句 ——
///    而这种差别用户会当成"iOS 版不好用"，很难查。
///    `gate_ios_parity.py` 读安卓当真值，比对这三个常量。
///
/// 判据：**攒够 MIN_VOICE_MS 的有声、再静够 SILENCE_MS**，才算一句。
///
/// 🚨 安卓那版第一稿还有一条 `if (!heardVoice) return false`，
///    坏样本注入证明它从来没起过作用（`heardVoice` 恒等于 `voiceMs > 0`），
///    已删。**这边不要把它加回来。**
final class SilenceSplitter {

    /// 低于这个音量算静音。跟安卓 `SILENCE_LEVEL` 一致。
    static let silenceLevel: Float = 0.08
    /// 静音持续多久算一句结束（毫秒）。跟安卓 `SILENCE_MS` 一致。
    static let silenceMs = 700
    /// 一句至少要有多少毫秒的**有声**，才值得发出去。跟安卓 `MIN_VOICE_MS` 一致。
    static let minVoiceMs = 400

    private var silentMs = 0
    /// 这一句累计的**有声**毫秒。它 >0 就等于「已经开口过」，不用再存一个布尔。
    private var voiceMs = 0

    /// 喂一帧。返回 true 表示**这一句到此结束**。
    func feed(_ level: Float, _ frameMs: Int) -> Bool {
        if level >= Self.silenceLevel {
            voiceMs += frameMs
            silentMs = 0
            return false
        }
        // 静音帧。
        // 🚨 `voiceMs >= minVoiceMs` 同时管两件事：
        //    ① 还没开口就静音 → voiceMs=0，不切（否则一开就发一段空的给后端）
        //    ② 只咳嗽了一下 → voiceMs 太小，不切
        silentMs += frameMs
        if silentMs >= Self.silenceMs && voiceMs >= Self.minVoiceMs {
            reset()
            return true
        }
        return false
    }

    func reset() {
        silentMs = 0
        voiceMs = 0
    }

    /// 当前这一句有没有值得发的内容（用户主动停止录音时，末尾那半句用得上）。
    var hasVoice: Bool { voiceMs >= Self.minVoiceMs }

    // MARK: - 自测

    /// 自测。**拿构造出来的波形跑**，不依赖麦克风。
    /// 六组跟安卓 `selfTest()` 一一对应，改任何一边都要两边同时改。
    /// 返回 nil = 全过；返回字符串 = 哪一组挂了。
    static func selfTest() -> String? {
        let F = 20                       // 每帧 20ms

        // ① 正常一句：静 100ms → 有声 800ms → 静 800ms
        let s = SilenceSplitter()
        var cuts = 0
        for _ in 0..<5 { if s.feed(0.01, F) { cuts += 1 } }      // 开头静音
        if cuts != 0 { return "开头静音不该切" }
        for _ in 0..<40 { if s.feed(0.5, F) { cuts += 1 } }      // 说话 800ms
        if cuts != 0 { return "说话时不该切" }
        var at = -1
        for i in 0..<50 {
            if s.feed(0.01, F) { at = (i + 1) * F; break }
        }
        if at < silenceMs || at > silenceMs + F * 2 {
            return "该在静音 \(silenceMs)ms 左右切，实际 \(at)ms"
        }

        // ② 只有静音：**一次都不该切**（否则一点开就发空音频给后端）
        let s2 = SilenceSplitter()
        var c2 = 0
        for _ in 0..<200 { if s2.feed(0.005, F) { c2 += 1 } }
        if c2 != 0 { return "全程静音不该切，实际切了 \(c2) 次" }

        // ③ 太短的声音（200ms）+ 长静音：**不该切**（咳嗽、碰一下手机）
        let s3 = SilenceSplitter()
        var c3 = 0
        for _ in 0..<10 { if s3.feed(0.6, F) { c3 += 1 } }       // 200ms
        for _ in 0..<100 { if s3.feed(0.01, F) { c3 += 1 } }
        if c3 != 0 { return "太短的声音不该成句，实际切了 \(c3) 次" }

        // ④ 说话中间短暂停顿（300ms < 700ms）：**不该切断**
        let s4 = SilenceSplitter()
        var c4 = 0
        for _ in 0..<30 { if s4.feed(0.5, F) { c4 += 1 } }       // 说
        for _ in 0..<15 { if s4.feed(0.01, F) { c4 += 1 } }      // 停 300ms
        if c4 != 0 { return "句中 300ms 停顿不该切，实际切了 \(c4) 次" }
        for _ in 0..<30 { if s4.feed(0.5, F) { c4 += 1 } }       // 接着说
        if c4 != 0 { return "接着说仍不该切" }

        // ⑤ 连着两句：该切两次
        let s5 = SilenceSplitter()
        var c5 = 0
        for _ in 0..<2 {
            for _ in 0..<40 { if s5.feed(0.5, F) { c5 += 1 } }
            for _ in 0..<40 { if s5.feed(0.01, F) { c5 += 1 } }
        }
        if c5 != 2 { return "两句该切两次，实际 \(c5) 次" }

        // ⑥ 长句之后紧跟一声咳嗽：**咳嗽不该成句**。
        //    🚨 这一组是坏样本注入逼出来的：把 `reset()` 改成只清 silentMs、
        //       不清 voiceMs，上面五组**全部照样通过**（"连两句"只要求切两次，
        //       而 voiceMs 不清零只会让门槛更容易满足）。
        //       真正的危害是**下一句的"太短不成句"保护失效**，只有这一组抓得到。
        let s6 = SilenceSplitter()
        var c6 = 0
        for _ in 0..<40 { if s6.feed(0.5, F) { c6 += 1 } }       // 长句 800ms
        for _ in 0..<40 { if s6.feed(0.01, F) { c6 += 1 } }      // 静音 → 切
        if c6 != 1 { return "长句该切一次，实际 \(c6) 次" }
        for _ in 0..<10 { if s6.feed(0.6, F) { c6 += 1 } }       // 咳嗽 200ms
        for _ in 0..<100 { if s6.feed(0.01, F) { c6 += 1 } }
        if c6 != 1 {
            return "长句后的咳嗽不该成句（reset 没清 voiceMs），实际共 \(c6) 次"
        }

        return nil
    }
}
