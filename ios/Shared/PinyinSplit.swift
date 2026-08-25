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
        lookup(dict, key)
    }

    /// 连拼整句：每个音节取最优，拼成一句。
    ///
    /// 🚨🚨 拼不出字的那一段**绝不原样塞字母进去**
    ///    （Kevin 2026-08-22：「打 WOQ 一打就变成一个『我Q』，这个不行」）。
    ///    "woq" 切成 [wo, q]，q 是个**未完成的音节**，不是要上屏的字母。
    ///    整句猜不出来就返回空串，调用方据此不提供这条候选，
    ///    改用前缀联想（`prefixWords`）去猜他想打的词。
    static func firstGuess(_ s: String) -> String {
        var sb = ""
        for syl in split(s) {
            guard let first = candidates(syl).first else { return "" }
            sb += first
        }
        return sb
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
