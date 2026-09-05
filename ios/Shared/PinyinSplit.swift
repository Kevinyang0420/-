import Foundation

/// 连拼：把一串连着打的拼音切成音节，再逐音节取候选字。
///
/// **逐行照搬安卓 `PinyinSplit.java`。** 那边的注释解释了每一处为什么那么写，
/// 这里只保留会影响读代码的那几条，别的去看安卓那份。
///
/// 🚨 音节表和字表不在代码里 —— 由 `gen_pinyin_data.py` 在电脑上生成，
///    打进 `Resources/`（`sync_pinyin_ios.py` 从安卓那份复制过来，
///    `gate_pinyin_sync.py` 守着两边一致）。
enum PinyinSplit {

    /// 最长音节 zhuang/chuang = 6（安卓 `MAX_SYL`）
    private static let maxSyl = 6

    private static var syl: Set<String> = []
    /// 🚨 顺序有意义（安卓那边特意用 LinkedHashMap）：码表本身按常用度排，
    ///    用无序容器的话打 j 出来一把生僻字，而且**不报错**，只是"候选看着怪"。
    ///    Swift 的 Dictionary 也是无序的，所以键的顺序单独存一份。
    private static var dict: [String: String] = [:]
    private static var wubi: [String: String] = [:]
    /// 🚨 `dict` 的键顺序。`prefixWords` 扫到 limit*4 就 break，
    ///    用无序的 Dictionary 遍历会让**同一个输入两次给出不同候选**，
    ///    而且完全不报错 —— 那种 bug 只会被当成"候选看着怪"。
    private static var dictKeys: [String] = []
    private static var wubiKeys: [String] = []
    private static var loaded = false
    private static let lock = NSLock()

    // MARK: - 装载

    /// 后台预热。跟安卓 `preload` 一样：谁先用谁等着，正常情况下早装完了。
    static func preload() {
        DispatchQueue.global(qos: .utility).async { ensureLoaded() }
    }

    /// 🚨 键盘扩展和容器 App 是**两个 bundle**，各自找自己的资源。
    ///    用 `Bundle(for:)` 拿不到（这是 enum 不是 class），
    ///    所以用一个类型锚点。
    private static var bundle: Bundle { Bundle(for: PinyinBundleAnchor.self) }

    static func ensureLoaded() {
        lock.lock()
        defer { lock.unlock() }
        if loaded { return }
        loaded = true

        syl = Set(readLines("syllables")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty })

        for ln in readLines("dict") {
            guard let t = ln.firstIndex(of: "\t") else { continue }
            let k = String(ln[ln.startIndex..<t])
            if dict[k] == nil { dictKeys.append(k) }
            dict[k] = String(ln[ln.index(after: t)...])
        }
        // 🚨 汉字→读音：从**单音节键**反查（键本身就是一个音节时，
        //    它的值里每个单字都读这个音）。实测覆盖 4286 字、141 个多音字，
        //    常用字全在里面。**不另外带一份字表**，少一个会漂的配置点。
        for k in dictKeys where syl.contains(k) {
            for w in (dict[k] ?? "").split(separator: " ") where w.count == 1 {
                let c = w.first!
                var ps = charPy[c] ?? []
                if !ps.contains(k) { ps.append(k); charPy[c] = ps }
            }
        }

        // 🚨 **把他自己收录的常用词学进来**（Kevin 2026-09-04：「词库也要逐渐更新」）。
        //    挂在这里是因为它是**词库唯一的装载点** —— 挂在别处就得靠调用方记得调，
        //    而"靠人记得"这条今天已经栽过好几次。
        //    读不到就当没有：常用词是网络同步来的，第一次装机时本来就是空的。
        learnLocked(VocabCore.wordsFor(KbBridge.loadVocab(), asr: true))

        for ln in readLines("wubi") {
            guard let t = ln.firstIndex(of: "\t") else { continue }
            let k = String(ln[ln.startIndex..<t])
            wubi[k] = String(ln[ln.index(after: t)...])
            wubiKeys.append(k)          // 保住码表原顺序
        }
    }

    private static func readLines(_ name: String) -> [String] {
        guard let u = bundle.url(forResource: name, withExtension: "txt"),
              let s = try? String(contentsOf: u, encoding: .utf8) else {
            // 装不上就是空表 —— 不崩，只是没候选（跟安卓一致）
            return []
        }
        // 🚨🚨 **必须用 `.newlines` 切，不能 `split(separator: "\n")`。**
        //    Swift 把 `\r\n` 当成**一个 Character**（grapheme cluster），
        //    它 `!= "\n"` —— 而这三个文件全是 CRLF，
        //    于是整个文件被当成一行：syl/dict/wubi 各只有 1 个元素。
        //    表现是「码表装载 OK」但所有切分都返回原串、候选全空，
        //    而且**不报任何错**。这是对拍闸门抓出来的。
        //    `components(separatedBy: .newlines)` 认 LF/CR/CRLF 三种，
        //    跟 Java `BufferedReader.readLine()` 同口径。
        return s.components(separatedBy: .newlines)
    }

    /// 🚨 判据要**能失败**。原来写的是 `!syl.isEmpty` —— 换行没切开时
    ///    syl 里躺着 1 个"整个文件"的垃圾元素，它照样返回 true，
    ///    于是自检页头一行打的是「装载 OK」，把真正的故障盖住了。
    ///    真实音节表 409 条，这里卡 100。
    static var ready: Bool { syl.count >= 100 }

    /// 诊断：**直接证据**，不靠推断。装不上时看这个，别猜。
    static func diag() -> String {
        ensureLoaded()
        let b = bundle
        func u(_ n: String) -> String {
            b.url(forResource: n, withExtension: "txt")?.lastPathComponent
                ?? "nil"
        }
        let sample = syl.sorted().prefix(5).map {
            "\($0)(\($0.unicodeScalars.map { String($0.value) }.joined(separator: ",")))"
        }.joined(separator: " ")
        return """
        bundle: \(b.bundleURL.lastPathComponent)
        url syllables=\(u("syllables")) dict=\(u("dict")) wubi=\(u("wubi"))
        syl=\(syl.count) dict=\(dict.count) wubi=\(wubi.count)
        syl 前5(带码点): \(sample)
        contains("ni")=\(syl.contains("ni")) contains("hao")=\(syl.contains("hao"))
        dict["ni"]=\(dict["ni"] ?? "nil")
        """
    }

    // MARK: - 切分

    /// 把一串拼音切成音节。**切不完的尾巴原样返回，绝不吞掉输入。**
    /// 例：`mingtianxiawu` → `[ming, tian, xia, wu]`
    static func split(_ input: String) -> [String] {
        var out: [String] = []
        let s = Array(input.lowercased())
        let n = s.count
        if n == 0 { return out }
        if !ready { return [input.lowercased()] }

        func sub(_ i: Int, _ j: Int) -> String { String(s[i..<j]) }

        // dp：从 i 开始能不能切完；记忆化避免指数回溯（安卓同款）
        var ok = [Bool](repeating: false, count: n + 1)
        var pick = [Int](repeating: 0, count: n + 1)
        ok[n] = true
        for i in stride(from: n - 1, through: 0, by: -1) {
            // 先试长的（最长匹配），切不动再退短的
            for len in stride(from: min(maxSyl, n - i), through: 1, by: -1)
            where syl.contains(sub(i, i + len)) && ok[i + len] {
                ok[i] = true
                pick[i] = len
                break
            }
        }
        if ok[0] {
            var i = 0
            while i < n {
                out.append(sub(i, i + pick[i]))
                i += pick[i]
            }
            return out
        }

        // 整串切不干净：能切的照切，切不动的字符攒起来单独成段。
        // 🚨 别一遇到切不动就把**剩下全部**塞成一段：
        //    "abcnihao" 会整串返回，后面明明能切的 ni/hao 就白扔了。
        var i = 0
        var junk = ""
        while i < n {
            var best = 0
            for len in stride(from: min(maxSyl, n - i), through: 1, by: -1)
            where syl.contains(sub(i, i + len)) {
                best = len
                break
            }
            if best == 0 {
                junk.append(s[i])
                i += 1
                continue
            }
            if !junk.isEmpty { out.append(junk); junk = "" }
            out.append(sub(i, i + best))
            i += best
        }
        if !junk.isEmpty { out.append(junk) }
        return out
    }

    // MARK: - 取候选

    /// 拼音串的候选（可能是词）。查不到返回空 —— 调用方负责"原样上屏"的出口。
    static func candidates(_ key: String) -> [String] {
        // 🚨 **他自己的词排在系统词前面** —— 他收录过的词就是他常打的词。
        //    去重在 `refreshCandidates` 那边统一做（`seen` 集合），这里只管顺序。
        userWords[key].map { $0 + lookup(dict, key) } ?? lookup(dict, key)
    }

    // MARK: - 个人词库（他自己的词，免费、不上传、边用边长）

    /// 他收录的常用词长出来的拼音键 → 词。
    /// 🚨 跟系统词库**分开存**：系统词库是只读资源，个人词随时会变；
    ///    混在一起就分不清"哪些是他的"，也没法单独清掉。
    private static var userWords: [String: [String]] = [:]
    /// 汉字 → 读音（可能多个）。从**系统词库自己的单音节键**反查出来的，
    /// 不额外带一份字表（多一份数据就多一个会漂的配置点）。
    private static var charPy: [Character: [String]] = [:]

    /// 给一批中文词，算出它们的拼音键并收进个人词库。
    ///
    /// 🚨🚨 立这个的原因（Kevin 2026-09-04）：
    ///    「不能够只有词库里的词。你这个词库也要逐渐更新」。
    ///    他**已经在维护常用词**（PressLogic / circle back / 李文彬），
    ///    但打字时一个都没用上 —— 现成的东西没接。
    ///
    /// 🚨 **多音字只展开到 4 个组合**：`会` 有 hui/kuai、`文` 有 wen/weng，
    ///    一个长词全排列会炸。超过就只取每个字的第一个读音 ——
    ///    宁可少一条键，不许把词库撑爆。
    /// 🚨 反查不到读音的字（生僻字）**整词放弃**，不拿半截拼音去凑。
    static func learn(_ words: [String]) {
        ensureLoaded()
        lock.lock(); defer { lock.unlock() }
        learnLocked(words)
    }

    /// 🚨 **不带锁的那一半** —— `ensureLoaded()` 自己已经持锁，
    ///    在里面再调带锁的 `learn` 会当场自锁死（`NSLock` 不可重入）。
    ///    这类"一个函数两种调用场景"的锁，拆成壳+核是唯一稳妥的写法。
    private static func learnLocked(_ words: [String]) {
        for w in words {
            let t = w.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.count >= 2, t.count <= 8 else { continue }   // 单字没意义，太长不像词
            var options: [[String]] = []
            var ok = true
            for ch in t {
                guard let ps = charPy[ch], !ps.isEmpty else { ok = false; break }
                options.append(ps)
            }
            guard ok else { continue }
            // 组合数超过 4 就退化成"每字取第一个读音"
            let total = options.reduce(1) { $0 * $1.count }
            let keys: [String]
            if total <= 4 {
                keys = options.reduce([""]) { acc, ps in acc.flatMap { a in ps.map { a + $0 } } }
            } else {
                keys = [options.map { $0[0] }.joined()]
            }
            for k in keys where !k.isEmpty {
                var arr = userWords[k] ?? []
                if !arr.contains(t) { arr.append(t); userWords[k] = arr }
            }
        }
    }

    /// 连拼整句：每个音节取最优，拼成一句。
    ///
    /// 🚨🚨 拼不出字的那一段**绝不原样塞字母进去**
    ///    （Kevin 2026-08-22：「打 WOQ 一打就变成一个『我Q』，这个不行」）。
    ///    "woq" 切成 [wo, q]，q 是个**未完成的音节**，不是要上屏的字母。
    ///    整句猜不出来就返回空串，调用方据此不提供这条候选，
    ///    改用前缀联想（`prefixWords`）去猜他想打的词。
    static func firstGuess(_ s: String) -> String {
        // 🚨🚨 **先走按词解码**（2026-09-04）。Kevin 原话：
        //    「连打的话只能一个词。我想一个句子连打就不行了，
        //     没那么聪明，它这个联想能力还不够」。
        //    根因就在下面那个逐音节取首选的写法里 —— 它**没有"词"的概念**，
        //    `wo jin tian` 会各取一个最常用字拼起来，音节越多越离谱。
        //    词库里本来就有多音节词键（jintian→今天、kaihui→开会），
        //    只是从来没人用它们来覆盖整句。
        let byWord = sentence(s)
        if !byWord.isEmpty { return byWord }
        // 兜底：按词覆盖不出来（生僻组合）才退回逐音节。
        var sb = ""
        for syl in split(s) {
            guard let first = candidates(syl).first else { return "" }
            sb += first
        }
        return sb
    }

    /// **整句按词解码**：把音节序列切成词库里真实存在的**词**，而不是逐字。
    ///
    /// `wo jin tian yao qu kai hui` → 我 / 今天 / 要 / 去 / 开会
    ///
    /// ## 判据：**用最少的词覆盖整串**
    ///
    /// 词越长越可能是他真正想打的（`jintian`＝今天，好过 今+天）。
    /// 所以按"段数最少"做动态规划；段数相同时**靠前的位置优先用长词**，
    /// 这样长词不会被拆在后面。
    ///
    /// 🚨 **拼不出的一段一律整体放弃，返回空串** —— 沿用 `firstGuess` 那条：
    ///    绝不把没配上的字母原样塞进结果（Kevin 2026-08-22：
    ///    「打 WOQ 一打就变成一个『我Q』，这个不行」）。
    ///
    /// 🚨 **不查未登录词、不做概率模型**：那要语言模型和词频，我们没有。
    ///    这一版只保证「词库里有的词会被当成词」—— 比逐字强一个量级，
    ///    但**不许说成"能理解句子"**。
    static func sentence(_ s: String) -> String {
        ensureLoaded()
        let syls = split(s)
        guard syls.count > 1 else { return "" }
        // 🚨 跨度封顶 6：词库里最长的词也就四五个音节，
        //    不封顶的话长串会白扫一堆不可能命中的键。
        let maxSpan = 6
        let n = syls.count
        // best[i] = 覆盖前 i 个音节的最优解；nil = 覆盖不了
        var bestText = [String?](repeating: nil, count: n + 1)
        var bestSegs = [Int](repeating: Int.max, count: n + 1)
        bestText[0] = ""
        bestSegs[0] = 0
        for i in 1...n {
            var j = max(0, i - maxSpan)
            while j < i {
                defer { j += 1 }
                guard bestText[j] != nil, bestSegs[j] != Int.max else { continue }
                let key = syls[j..<i].joined()
                guard let w = candidates(key).first, !w.isEmpty else { continue }
                let segs = bestSegs[j] + 1
                // 段数少的赢；一样多时**长词靠前**（j 小的先来，天然满足）
                if segs < bestSegs[i] {
                    bestSegs[i] = segs
                    bestText[i] = (bestText[j] ?? "") + w
                }
            }
        }
        return bestText[n] ?? ""
    }

    /// 拿**整串**去词表做前缀匹配 —— 拼音没打完也能联想出词。
    ///
    /// 🚨 这是「打一半就要能出词」的解法（Kevin 2026-08-22）：
    ///    `mingt` → 明天、`nih` → 你好、`zhongg` → 中国。
    ///
    /// 🚨 **单个字母也要联想**。安卓原来卡了 `length < 2`，于是打 `x`
    ///    一个候选都没有，只能落到"原样上屏拼音"那个兜底 —— 屏幕上又是个裸字母。
    ///    真输入法打 x 就该出「西 想 下…」，靠的正是前缀匹配。
    ///
    /// 排序：**key 越短排越前**。key 短说明离打完越近，
    /// 也更可能是常用词（zhongguo 比 zhongguodaxue 常用得多）。
    static func prefixWords(_ py: String, limit: Int) -> [String] {
        ensureLoaded()
        if dict.isEmpty || py.isEmpty { return [] }
        let p = py.lowercased()
        var hits: [(String, String)] = []
        // 🚨 按**码表原顺序**扫，不是按 Dictionary 的无序遍历 ——
        //    后者每次跑出来的截断点都不一样（扫到 limit*4 就 break），
        //    于是同一个输入两次给出不同候选，而且不报错。
        for k in dictKeys where k.hasPrefix(p) {
            hits.append((k, dict[k] ?? ""))
            if hits.count > limit * 4 { break }        // 别把整表都扫进来
        }
        hits.sort { a, b in
            a.0.count != b.0.count ? a.0.count < b.0.count : a.0 < b.0
        }
        var seen = Set<String>()
        var out: [String] = []
        outer: for (_, v) in hits {
            for w in v.split(separator: " ") {
                let s = String(w)
                if s.isEmpty || seen.contains(s) { continue }
                seen.insert(s)
                out.append(s)
                if out.count >= limit { break outer }
            }
        }
        return out
    }

    /// 五笔码的精确候选。
    static func wubiCandidates(_ code: String) -> [String] {
        lookup(wubi, code)
    }

    private static func lookup(_ m: [String: String], _ k: String) -> [String] {
        guard let v = m[k.lowercased()] else { return [] }
        return v.split(separator: " ").map(String.init).filter { !$0.isEmpty }
    }

    /// 五笔**前缀匹配**：打 j 就把所有 j 开头的码的候选列出来。
    ///
    /// 🚨 这张码表里**只有 3 码和 4 码**，做精确匹配的话打前一两个字母
    ///    候选区永远空白，看着就像功能坏了。
    static func wubiPrefix(_ prefix: String, limit: Int) -> [String] {
        rankPrefix(wubi, wubiKeys, prefix, limit)
    }

    /// 前缀匹配 + 排序的**纯函数**（不碰任何全局状态，闸门可以拿假表直接测顺序）。
    ///
    /// 排序：**四个桶依次输出** —— 短码常用 → 短码生僻 → 长码常用 → 长码生僻。
    /// 光按码长排出来的是「虹 蚂 蛄 旲 暱 蟒 蠎」这种生僻字堆，能出候选但没人用得下去。
    static func rankPrefix(_ table: [String: String], _ order: [String],
                           _ prefix: String, _ limit: Int) -> [String] {
        if table.isEmpty || prefix.isEmpty { return [] }
        var buckets: [[String]] = [[], [], [], []]
        var collected = 0
        for key in order {
            guard key.hasPrefix(prefix), let val = table[key] else { continue }
            let shortCode = key.count <= 3
            // 🚨 每个码只取前两个候选 —— 计数按**本码**，不是按累计列表大小。
            //    按累计的话，列表没满时一个码能把自己几十个候选全灌进去，
            //    后面的码一个都排不上。
            var taken = 0
            for s in val.split(separator: " ") {
                let str = String(s)
                if str.isEmpty { continue }
                let b = (shortCode ? 0 : 2) + (isCommon(str) ? 0 : 1)
                buckets[b].append(str)
                collected += 1
                taken += 1
                if taken >= 2 { break }
            }
            if collected > limit * 3 { break }
        }
        var seen = Set<String>()
        var out: [String] = []
        for b in buckets {
            for s in b where !seen.contains(s) {
                seen.insert(s)
                out.append(s)
            }
        }
        return out.count > limit ? Array(out.prefix(limit)) : out
    }

    /// 常不常用：整串每个字都落在 **GB2312 一级字区**（首字节 0xB0–0xD7，
    /// 共 3755 个常用字）就算常用。
    ///
    /// 🚨 用这个而不是自带词频表：零额外数据、零装载开销，
    ///    而且"一级/二级"本来就是按使用频度划的。它不精确（「虹」也是一级字），
    ///    但能把「蛄 旲 暱 蟒 蠎」这类压到后面去。
    static func isCommon(_ s: String) -> Bool {
        guard let d = s.data(using: String.Encoding(rawValue:
            CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))))
        else { return false }
        let b = [UInt8](d)
        var i = 0
        while i < b.count {
            if b[i] < 0x80 { i += 1; continue }        // ASCII 不影响判断
            if i + 1 >= b.count { return false }
            if b[i] < 0xB0 || b[i] > 0xD7 { return false }
            i += 2
        }
        return true
    }
}

/// 只为 `Bundle(for:)` 定位当前 bundle 存在。没有别的用途。
final class PinyinBundleAnchor {}
