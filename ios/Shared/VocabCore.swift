import Foundation

/// 常用词的核心结构与规则。
///
/// 🚨🚨 **这是安卓 `VocabCore.java` 的逐条翻译，不是重新设计。**
///    字段名、顺序、常量取值、每条判定，全部一一对应。
///    一期数据只存本地，但**结构现在就定死、三端一字不差**
///    —— 二期加同步时只加传输、不改结构。
///    不这么做的话，二期合并就是三张不同的表往一起凑，
///    那才是真正的第二配置点（`_方案_常用词_一期_20260902.md`）。
///
/// 🚨 出处：`android/java/com/kevin/shuoyingwen/VocabCore.java`。
///    改任何一条**必须两端一起改**，只改一边＝已经散了。
enum VocabCore {

    // ---- kind：这个词喂给谁（VOC-1）----
    /// 只喂识别（例：「PressLogic」要让它听对）。
    static let KIND_ASR = "asr"
    /// 只喂出稿（例：「circle back」要让它写出来）。
    static let KIND_STYLE = "style"
    /// 两个都喂 —— **默认**。
    static let KIND_BOTH = "both"

    // ---- src：这条是怎么来的（VOC-1 / VOC-6）----
    /// 他手动加的。
    static let SRC_MANUAL = "manual"
    /// 从单词本流过来的（**单向**，常用词绝不回流单词本）。
    static let SRC_BOOK = "book"
    /// 二期自动收录的。一期不产生，但结构里先留着。
    static let SRC_AUTO = "auto"

    // ---- status：这条现在是什么态（候选常用词「丙」）----
    /// 已收录 —— **只有这一档的词会被送给模型**。
    static let ST_ON = "on"
    /// 候选：后端发现的新词，等他点一下。
    static let ST_CAND = "cand"
    /// 他否掉的。留着是为了别再推荐第二次。
    static let ST_NO = "no"

    /// status 合法化。**认不出、或老数据没这个字段 → 当已收录**
    /// （老数据里的词本来就是他自己加的，当候选会让它们凭空要求他再点一遍）。
    static func statusOf(_ s: String?) -> String {
        if s == ST_CAND || s == ST_NO { return s! }
        return ST_ON
    }

    /// 一条常用词。**字段名和顺序三端一致。**
    ///
    /// 🚨🚨 2026-09-04 补 `status` / `count`：安卓 `VocabCore.java` 早就有了，
    ///    iOS 这份一直停在五个字段。差这两个的后果不是"少个功能"——
    ///    是**二期同步时 iOS 做 replace 会把另一台设备上的 cand/no 全抹平成 on**，
    ///    他否掉过的词会成片复活。这正是本文件抬头说的
    ///    「结构现在就定死、三端一字不差」要挡的事。
    struct Term {
        let id: String
        let text: String
        let kind: String
        let src: String
        /// 加入时间，毫秒。
        let at: Int64
        /// on / cand / no。
        let status: String
        /// 自动收录时后端给的出现次数；他手动加的是 0。
        let count: Int

        /// 五参构造 = 他手动加的词，直接就是**已收录**（跟安卓五参构造一致）。
        init(id: String, text: String, kind: String, src: String, at: Int64) {
            self.init(id: id, text: text, kind: kind, src: src, at: at,
                      status: VocabCore.ST_ON, count: 0)
        }

        init(id: String, text: String, kind: String, src: String, at: Int64,
             status: String, count: Int) {
            self.id = id
            self.text = text
            self.kind = kind
            self.src = src
            self.at = at
            self.status = VocabCore.statusOf(status)
            self.count = count
        }

        func withStatus(_ s: String) -> Term {
            Term(id: id, text: text, kind: kind, src: src, at: at,
                 status: s, count: count)
        }
    }

    /// id：**跟单词本同源，不新造算法**（VOC-1 明写「别新造」）。
    ///
    /// 🚨 `WordId.make` 要两个字段（单词本一条卡有中英两面），而常用词只有一个 ——
    ///    这里第二个传**空串**。这是安卓那边做的决定，**iOS 必须原样照做**：
    ///    否则同一个词两端算出两个 id，二期一合并就变成两条。
    ///    （`WordId` 的抬头写着两端曾经为了一个不可见分隔符走散过，
    ///     而且两边自测还都通过了 —— 就是这一类。）
    static func idOf(_ text: String) -> String {
        WordId.make(text, "")
    }

    /// 归一化：跟单词本同一套（手写的那 6 个 ASCII 空白，不用各语言的「空白」定义）。
    static func norm(_ text: String) -> String {
        WordId.norm(text)
    }

    /// 这条值不值得收：得有实际内容。
    static func usable(_ text: String) -> Bool {
        !norm(text).isEmpty
    }

    /// kind 合法化：不认识的一律当默认 `both`，**不抛异常**
    /// （存档可能是别的版本写的）。
    static func kindOf(_ k: String?) -> String {
        if k == KIND_ASR || k == KIND_STYLE { return k! }
        return KIND_BOTH
    }

    /// 这个词该不该喂给**识别**那一步（VOC-2）。
    ///
    /// 🚨 `style` 的词**不许**进识别提示 —— 这是 2.1 点名的坏样本②。
    static func forAsr(_ t: Term?) -> Bool {
        let k = kindOf(t?.kind)
        return k == KIND_ASR || k == KIND_BOTH
    }

    /// 这个词该不该写进**出稿**指令（VOC-3）。
    static func forStyle(_ t: Term?) -> Bool {
        let k = kindOf(t?.kind)
        return k == KIND_STYLE || k == KIND_BOTH
    }

    /// 按 id 去重后的列表（**后来的覆盖先前的**）。
    ///
    /// 🚨 用途是「单词本流过来的」跟「他手动加的」撞在一起时只留一条 ——
    ///    留**后面**那条，因为调用方按「先旧后新」的顺序拼。
    static func dedup(_ input: [Term]?) -> [Term] {
        var out: [Term] = []
        guard let input = input else { return out }
        for t in input {
            guard usable(t.text) else { continue }
            if let hit = out.firstIndex(where: { $0.id == t.id }) {
                out[hit] = t
            } else {
                out.append(t)
            }
        }
        return out
    }

    /// 按 `kind` 挑出词，**返回数组**（VOC-2：后端要的是纯文本数组）。
    ///
    /// 🚨🚨 **过滤规则只有这一份** —— `joinFor` 和识别请求都走它。
    ///    我第一版把过滤在两个函数里各写了一遍，正是安卓注释点名要避免的：
    ///    「识别那条自己再写一遍过滤的话，『style 的词不许进识别提示』
    ///     就会有两个实现，改一处等于没改」。
    ///
    /// 🚨 后端明写：**它不认 `kind` 的语义，过滤归客户端**。
    static func wordsFor(_ list: [Term]?, asr: Bool) -> [String] {
        var out: [String] = []
        guard let list = list else { return out }
        for t in list {
            guard usable(t.text) else { continue }
            // 🚨🚨 **只有【已收录】的词才送给模型**（安卓 `wordsFor` 同一行）。
            //    候选是"后端猜他可能想要"、否掉是"他明确说不要" ——
            //    这两类混进提示词，等于**他还没点头就已经在按它出稿了**，
            //    而否掉的那些更是他亲口拒绝过的。
            //    iOS 之前没有 status，所以也没有这道闸；补 status 就必须一并补它。
            guard statusOf(t.status) == ST_ON else { continue }
            if asr ? !forAsr(t) : !forStyle(t) { continue }
            out.append(norm(t.text))
        }
        return out
    }

    /// 拼成给模型看的词表片段。**空表回空串** —— 调用方据此决定加不加这一段。
    ///
    /// 🚨 **空表必须回空串，不能回「（无）」这类占位**：那会在出稿指令里
    ///    平白多出一段没有内容的话，模型会去解释它。
    static func joinFor(_ list: [Term], asr: Bool) -> String {
        wordsFor(list, asr: asr).joined(separator: "、")
    }

    // ---- 限额（跟后端契约一致：超了后端**静默截断不报错**，所以客户端必须先拦）----
    /// 单条最长多少字（归一化之后算）。
    static let LIMIT_TEXT = 64
    /// 最多收多少条。**只数已收录的**，候选/否掉不占额度。
    static let LIMIT_COUNT = 500

    /// 这条是不是太长了。
    ///
    /// 🚨 用 `utf16.count` 不是 `count`：安卓那边是 `String.length()`，
    ///    数的是 UTF-16 码元。用 Swift 的 `count`（数字素簇）会在表情符号上
    ///    给出跟安卓不同的答案 —— 同一句话一端收得下、另一端拦掉。
    static func tooLong(_ text: String) -> Bool {
        norm(text).utf16.count > LIMIT_TEXT
    }

    // ---- 云同步的四种结局（SYNC-3/4/5）----
    /// 正常拿到云端那份。
    static let PULL_OK = 0
    /// 没登录：后端回 `200 {"terms":[], "anon":true}`。**不是错误。**
    static let PULL_ANON = 1
    /// 读不到（5xx / 断网 / 其它非 2xx）。
    static let PULL_UNREACHABLE = 2
    /// 鉴权不过（401）。
    static let PULL_AUTH = 3

    /// 把 HTTP 结果归成四种结局之一。
    ///
    /// 🚨 **这四种必须分得开**：读不到和"云端确实是空的"长得一样，
    ///    但前者拿来覆盖本地就是把他的词删光。
    static func pullKind(_ httpCode: Int, anon: Bool) -> Int {
        if httpCode == 401 { return PULL_AUTH }
        if httpCode < 0 || httpCode >= 500 { return PULL_UNREACHABLE }
        if httpCode < 200 || httpCode >= 300 { return PULL_UNREACHABLE }
        return anon ? PULL_ANON : PULL_OK
    }

    /// 这次拉取的结果**能不能拿来覆盖本地**。
    ///
    /// 🚨 只有 `PULL_OK` 能。读不到、未登录都不行 ——
    ///    这两种情况下的"空列表"不代表他真的一个词都没有。
    static func canOverwriteLocal(_ pullKind: Int) -> Bool {
        pullKind == PULL_OK
    }

    /// 在**云端那份**上改一个词的态，然后整份写回去（SYNC-1 的"读—改—写"）。
    ///
    /// 🚨 云端没有这个词时要 **upsert**，不能只做映射：
    ///    他在这台设备上新加、还没同步过的词，改个态就会凭空消失。
    static func applyStatus(_ cloud: [Term]?, _ term: Term?,
                            _ status: String) -> [Term] {
        var out: [Term] = []
        var seen = false
        for t in cloud ?? [] {
            if let term = term, term.id == t.id {
                out.append(t.withStatus(status))
                seen = true
            } else {
                out.append(t)
            }
        }
        if !seen, let term = term { out.append(term.withStatus(status)) }
        return out
    }

    /// 在**云端那份**上加一条 / 删一条，然后整份写回去。
    ///
    /// 🚨🚨 SYNC-1b：必须在**云端那份**上改，不能拿本地那份去顶掉云端 ——
    ///    否则"另一台设备离线时加的词"会在我这边删任意一个词时被一起抹掉。
    static func applyChange(_ cloud: [Term]?, added: Term?,
                            removed: String?) -> [Term] {
        var out: [Term] = []
        for t in cloud ?? [] {
            if let removed = removed, removed == t.id { continue }
            out.append(t)
        }
        if let added = added { out.append(added) }
        return dedup(out)
    }

    // MARK: - 自测
    //
    // 🚨 由 `gate_pure_logic.py` 两端各跑一遍并比对；判据挂在**返回值**上。
    //    这是安卓 `VocabCore.selfTest()` 的逐条翻译，**别自己另编一套**——
    //    两端各写各的判据，等于两端各有一套口径，比不测更糟。

    /// 返回 nil = 全过。
    static func selfTest() -> String? {
        var bad = ""

        // ① id 稳定、且跟单词本同一套归一化
        if idOf("PressLogic") != idOf("  PressLogic  ") {
            bad += "id：首尾空白没被归一；"
        }
        if idOf("circle back") == idOf("circle  back  x") {
            bad += "id：不同的词算出同一个 id；"
        }

        // ② kind 合法化：不认识的当 both，不抛
        if kindOf(nil) != KIND_BOTH || kindOf("xxx") != KIND_BOTH {
            bad += "kind：不认识的没退回 both；"
        }

        // ③ 🚨 style 的词不许进识别（2.1 的坏样本②）
        let st = Term(id: idOf("circle back"), text: "circle back",
                      kind: KIND_STYLE, src: SRC_MANUAL, at: 0)
        let asT = Term(id: idOf("PressLogic"), text: "PressLogic",
                       kind: KIND_ASR, src: SRC_MANUAL, at: 0)
        if forAsr(st) { bad += "style 的词进了识别提示；" }
        if !forStyle(st) { bad += "style 的词没进出稿；" }
        if !forAsr(asT) { bad += "asr 的词没进识别；" }
        if forStyle(asT) { bad += "asr 的词进了出稿；" }

        // ④ 拼接按 kind 分流
        let l = [st, asT]
        if joinFor(l, asr: true) != "PressLogic" {
            bad += "识别词表拼错：" + joinFor(l, asr: true) + "；"
        }
        if joinFor(l, asr: false) != "circle back" {
            bad += "出稿词表拼错：" + joinFor(l, asr: false) + "；"
        }

        // ⑤ 🚨 空表回空串，不是占位符
        if !joinFor([], asr: true).isEmpty { bad += "空表没回空串；" }

        // ⑥ 去重留后来的
        let d = [Term(id: idOf("李文彬"), text: "李文彬", kind: KIND_BOTH,
                      src: SRC_BOOK, at: 1),
                 Term(id: idOf("李文彬"), text: "李文彬", kind: KIND_ASR,
                      src: SRC_MANUAL, at: 2)]
        let r = dedup(d)
        if r.count != 1 { bad += "去重：剩了 \(r.count) 条；" }
        else if r[0].src != SRC_MANUAL { bad += "去重：留错了那条；" }

        // ⑦ 空文本不该被收
        if usable("   ") { bad += "全空白被当成有效词；" }

        // ⑧ 🚨 SYNC-3/4/5：四种结局要分得开
        if pullKind(503, anon: false) != PULL_UNREACHABLE { bad += "503 没判成读不到；" }
        if pullKind(-1, anon: false) != PULL_UNREACHABLE { bad += "断网没判成读不到；" }
        if pullKind(200, anon: true) != PULL_ANON { bad += "未登录没判成 anon；" }
        if pullKind(401, anon: false) != PULL_AUTH { bad += "401 没判成鉴权；" }
        if pullKind(200, anon: false) != PULL_OK { bad += "正常 200 没判成 OK；" }
        if canOverwriteLocal(PULL_UNREACHABLE) { bad += "读不到却允许覆盖本地；" }
        if canOverwriteLocal(PULL_ANON) { bad += "未登录却允许覆盖本地；" }
        if !canOverwriteLocal(PULL_OK) { bad += "正常 200 反而不许覆盖；" }

        // ⑨ 🚨🚨 SYNC-1b：**别的设备离线时加的词，我删别的词之后必须还在**
        let cloud = [Term(id: idOf("B设备的词"), text: "B设备的词",
                          kind: KIND_BOTH, src: SRC_MANUAL, at: 5),
                     Term(id: idOf("要删的词"), text: "要删的词",
                          kind: KIND_BOTH, src: SRC_MANUAL, at: 6)]
        let after = applyChange(cloud, added: nil, removed: idOf("要删的词"))
        var keptB = false, killed = true
        for t in after {
            if t.id == idOf("B设备的词") { keptB = true }
            if t.id == idOf("要删的词") { killed = false }
        }
        if !keptB { bad += "SYNC-1b：把别的设备的词抹掉了；" }
        if !killed { bad += "SYNC-1a：删除没传播出去；" }
        let added = applyChange(cloud,
                                added: Term(id: idOf("新词"), text: "新词",
                                            kind: KIND_BOTH, src: SRC_MANUAL,
                                            at: 7),
                                removed: nil)
        if added.count != 3 { bad += "加词把云端那份弄丢了：\(added.count)；" }

        // ⑨.2 🚨🚨 `applyStatus` 的 **upsert**：云端还没有这个词时也要落进去。
        //    这条判据是 2026-09-04 补的 —— 闸门的坏样本「改态时云端没有就丢掉」
        //    **没抓到**，回头一查是**两端的自测都没测过 applyStatus 的这一半**
        //    （安卓那份也漏了，已同步给 2.3）。坏样本没响先查判据在不在，
        //    别急着以为是注入失配。
        //    真实场景：他在这台设备上刚加的词还没同步，就点了「不要」——
        //    没有 upsert 的话这个动作等于什么都没发生，那个词下次还会冒出来。
        let fresh = Term(id: idOf("本机新词"), text: "本机新词", kind: KIND_BOTH,
                         src: SRC_MANUAL, at: 10)
        let up = applyStatus(cloud, fresh, ST_NO)
        guard let hit = up.first(where: { $0.id == idOf("本机新词") }) else {
            bad += "applyStatus：云端没有这个词时没 upsert 进去；"
            return bad
        }
        if hit.status != ST_NO { bad += "applyStatus：upsert 进去了但态没改；" }
        if up.count != cloud.count + 1 {
            bad += "applyStatus：upsert 把云端别的词弄丢了：\(up.count)；"
        }
        // 云端**已有**那个词时只改态，不许多出一条
        let dup = applyStatus(cloud, cloud[0], ST_CAND)
        if dup.count != cloud.count {
            bad += "applyStatus：云端已有还多加了一条：\(dup.count)；"
        }
        if dup.first(where: { $0.id == cloud[0].id })?.status != ST_CAND {
            bad += "applyStatus：云端已有的那条没改成 cand；"
        }

        // ⑨.5 🚨 数组那条跟拼句那条必须**同一套过滤**（VOC-2 坏样本②的另一面）
        let aw = wordsFor(l, asr: true), sw = wordsFor(l, asr: false)
        if aw.count != 1 || aw.first != "PressLogic" {
            bad += "识别词数组挑错了：\(aw)；"
        }
        if sw.count != 1 || sw.first != "circle back" {
            bad += "出稿词数组挑错了：\(sw)；"
        }
        if let a0 = aw.first, joinFor(l, asr: true) != a0 {
            bad += "拼句和数组走的不是同一套过滤；"
        }

        // ⑨.7 🚨🚨 **候选和否掉的词绝不许进提示词**（iOS 2026-09-04 补 status 时一并补）
        let cand = Term(id: idOf("候选词"), text: "候选词", kind: KIND_BOTH,
                        src: SRC_AUTO, at: 8, status: ST_CAND, count: 3)
        let no = Term(id: idOf("否掉的"), text: "否掉的", kind: KIND_BOTH,
                      src: SRC_AUTO, at: 9, status: ST_NO, count: 1)
        if !wordsFor([cand], asr: true).isEmpty { bad += "候选词进了识别提示；" }
        if !wordsFor([cand], asr: false).isEmpty { bad += "候选词进了出稿提示；" }
        if !wordsFor([no], asr: true).isEmpty { bad += "否掉的词进了识别提示；" }
        if !wordsFor([no], asr: false).isEmpty { bad += "否掉的词进了出稿提示；" }
        // 老数据没有 status → 兜底成 on，**不能**被这道闸误杀
        if wordsFor([asT], asr: true).count != 1 { bad += "老数据(无status)被误当成非收录；" }
        // 收回候选写的是 cand 不是 on（还要再点一次才收录）
        if statusOf(cand.withStatus(ST_CAND).status) != ST_CAND {
            bad += "withStatus 没改成 cand；"
        }

        // ⑩ 限额
        let lng = String(repeating: "a", count: LIMIT_TEXT + 1)
        if !tooLong(lng) { bad += "超长没被拦；" }
        if tooLong("PressLogic") { bad += "正常长度被误判成超长；" }

        return bad.isEmpty ? nil : bad
    }
}
