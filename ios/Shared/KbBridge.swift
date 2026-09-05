import Foundation

/// 键盘 ⇄ 主 App 的跨进程通道。**整套协议只在这一个文件里定义。**
///
/// ## 为什么需要它（根因，别当成设计偏好）
///
/// **iOS 禁止扩展进程录音。** 苹果技术问答 QA1872 原文：
/// 「App extensions in iOS 8 are not allowed to record audio」，并逐条点名了
/// 会返错的 API —— 其中就有 `AVAudioEngine startAndReturnError:`（用了 inputNode 时），
/// 那正是 `Voice.start()` 走的路。
/// 系统日志里的判词是 `CMSUtility_IsAllowedToStartRecording: ... was NOT allowed
/// to start recording **because it is an extension**`
/// （苹果开发者论坛 thread 742601，2023-12，现代 iOS 上仍然如此）。
///
/// 🚨 **系统检查的是「调用方是不是扩展」**，跟音频会话怎么配、Full Access 开没开、
///    麦克风权限给没给**全都无关**。所以 2026-08-28 之前那三次真机失败
///    （`2003329396` = `AVAudioSessionErrorCodeUnspecified`）不是配置问题，
///    也不是「引擎在会话激活前创建」—— 那个假设是错的，557 修了个不存在的病。
///
/// 于是只剩一条路，也是 Typeless / Wispr Flow 在用的那条：
/// **主 App 在后台保住音频通道并负责录音，键盘退化成一个遥控器。**
///
/// ## 通道
///
/// - **载荷**：App Group 共享 `UserDefaults`（命令、结果、心跳都在这儿）
/// - **提醒**：Darwin 通知（跨进程、免 entitlement，但**不能带数据**，
///   所以它只负责「去看一眼共享区」，真正的内容一律从共享区读）
///
/// 🚨 Darwin 通知只是**降低延迟**，不是唯一路径。两边都还有轮询兜底 ——
///    通知在进程被挂起时会丢，只靠它的话表现是「有时候能用」，
///    那种间歇性故障比彻底不能用还难查。
enum KbBridge {

    // ------------------------------------------------------------ 配置

    /// 🚨 **唯一配置点。** 改这里就够了，别在 entitlements 之外的任何地方再抄一份。
    ///    这个组要先在苹果开发者门户里建出来 —— App Store Connect API
    ///    **没有** App Group 这个资源（`/v1/appGroups` 返回 404，
    ///    而同一把密钥同一次请求 `/v1/bundleIds` 返回 200，有正控）。
    static let group = "group.com.kevin.transless"

    /// 心跳多久算还活着。
    /// 主 App 每 `beatEvery` 秒写一次，键盘认 `staleAfter` 秒。
    static let beatEvery: TimeInterval = 2
    static let staleAfter: TimeInterval = 6

    // ------------------------------------------------------------ 可用性

    /// 共享容器到底能不能用。
    ///
    /// 🚨🚨 判据必须是 `containerURL(...)` —— 缺 entitlement 时它返回 **nil**。
    ///    **不能**写成 `UserDefaults(suiteName: group) != nil`：那个在没有权限时
    ///    **照样给你一个对象**，写进去无声无息地丢掉。
    ///    那是个永远为真的检查，比没有检查更糟。
    static var available: Bool {
        if fakeHost != nil { return true }
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group) != nil
    }

    /// 🚨🚨 **只为在模拟器上验「宿主在线 / 离线」那两条分支真的会翻。**
    ///
    /// App Group 在模拟器里装不上（没有描述文件时 Xcode 会把这类受限
    /// entitlement 剥掉，2026-08-28 实测清理重签后 `codesign -d --entitlements`
    /// 仍然是空的）→ `available` 恒 false → **那两条分支在模拟器上一条都走不到**。
    /// 而「没验过的诊断」正是 557 栽的地方：真机上看到"离线"时，
    /// 我们分不清是宿主真死了、还是那行显示本身坏了。
    ///
    /// 🚨 用**环境变量**而不是 `#if DEBUG`：今天实测发现这个工程里
    ///    `#if <自定义标志>` 有意外行为（本以为会被跳过的一段被编进了 iOS 构建）。
    ///    环境变量在运行时读，没有编译期的意外。
    ///    真机上用户设不了它（只有 Xcode / simctl 启动时能注入），
    ///    而且它只能**伪造在线状态**，拿不到也泄不了任何东西。
    ///
    /// 取值：`alive` / `dead`。不设就是真实行为。
    static var fakeHost: String? {
        let v = ProcessInfo.processInfo.environment["TRANSLESS_KB_FAKE_HOST"]
        return (v == "alive" || v == "dead") ? v : nil
    }

    private static var store: UserDefaults? {
        guard available else { return nil }
        return UserDefaults(suiteName: group)
    }

    // ------------------------------------------------------------ 键名

    private enum K {
        static let beat = "kb.host.beatAt"        // 主 App 心跳（Double，秒）
        static let cmdSeq = "kb.cmd.seq"          // 命令序号（Int，只增）
        static let cmdAct = "kb.cmd.action"       // "start" / "stop" / "cancel"
        static let cmdAt = "kb.cmd.at"            // 命令时间（Double）
        static let cmdArg = "kb.cmd.args"         // 命令参数（JSON 串）
        static let resSeq = "kb.res.seq"          // 这条结果回的是哪条命令
        static let resKind = "kb.res.kind"        // "partial" / "text" / "error"
        static let resBody = "kb.res.body"        // 正文
        static let resAt = "kb.res.at"            // 结果时间（Double）
        static let levels = "kb.levels"           // 最近 13 个音量（[Double]）
        // 🚨 自检结果的**备份通道**。文件那条路会静默失败（2026-08-28 实测），
        //    偏好这条路当晚从他手机上真的拉下来过 —— 两条都留。
        /// 🚨🚨 **整段录音的峰值** —— 跟 `levels` 分开存，因为 `levels` 是
        ///    给键盘那 13 根波形柱用的**环形缓冲（只留最后 13 条）**。
        ///    2026-08-29 我拿 `max(levels)` 当「他有没有被录到」的判据，
        ///    **量的其实是 63 秒录音里的最后 1 秒**（他早说完了）——
        ///    数没量错，**量的对象跟结论说的对象不是一个**。
        ///    这个键单调只增、起录时清零，覆盖**整段**。
        static let spanPeak = "kb.peak.span"
        /// 🚨🚨 **正在录音的起始时刻，放共享区。**
        ///    Kevin 2026-08-29 实测：录音、转写、回填全是通的，
        ///    **只有键盘上看不出在录**。根因是键盘扩展在切走时被系统**销毁**，
        ///    切回来是个**新实例**，我把录音状态存在实例内存里，跟着一起没了。
        ///    同一份文件里「回填」那半段早就写着「切回来很可能是新实例」——
        ///    **道理写对了，只落实在稿子上，没落实在状态上。** 又是范围错。
        static let recSince = "kb.rec.since"
        static let recSeq = "kb.rec.seq"      // 在飞那一单的序号（键盘被销毁后靠它接回来）
        static let kbGoneAt = "kb.gone.at"    // 键盘被销毁的时刻
        static let selfTestWhy = "kb.selftest.why"
        static let selfTestBody = "kb.selftest.body"
        /// 面包屑（最近 12 条），见 `note(_:)`。
        static let trail = "kb.trail"
        static let recReqAt = "kb.rec.reqAt"   // 键盘留的起录条子（时间戳）
        static let recReqArgs = "kb.rec.reqArgs" // 键盘随条子送来的语气/档位/语言
        static let pendBody = "kb.pending.body"  // 主App出的稿，等键盘回来取
        static let pendZh = "kb.pending.zh"      // 对应的中文原话
        static let pendAt = "kb.pending.at"
        static let pendFail = "kb.pending.fail"  // 失败原因，也要让他看见
        static let failAt = "kb.pending.failAt"  // 🚨 失败自己的时间戳，别蹭稿子的
        static let pendJSON = "kb.pending.json"    // 🚨 一份稿子＝一个键里的一个 JSON
        static let failJSON = "kb.pending.failJson"
        static let pendSeq = "kb.pending.seq"      // 出了几份稿（只增）
        static let doneSeq = "kb.pending.doneSeq"  // 投递到第几份（只增）
        static let failSeq = "kb.pending.failSeq"      // 出了几条失败
        static let failDoneSeq = "kb.pending.failDone"  // 显示到第几条
    }

    /// 🚨🚨 **从 Mac 触发一次录音自检**（给真机闭环用）。
    ///
    /// `xcrun devicectl device notification post --device <id> --name <这个名字>`
    ///
    /// 为什么不能直接 post `noteCmd`：那条只是「去共享区看一眼」，
    /// **真正的命令内容（序号/动作/语气语言）躺在 App Group 的 `UserDefaults` 里，
    /// 而 Mac 写不进去** —— post 过去宿主 `drain()` 一看没有新命令，什么都不会发生。
    /// **「发了通知」不等于「模拟了按麦克风」，中间差一个载荷。**
    ///
    /// 🚨 **覆盖范围**：这条从 `KbVoiceHost.begin()` 往后跟键盘按麦克风
    /// **是同一条路**（同一个 `Voice.start`、同一套音频会话切换），
    /// 但它**跳过了「键盘 → App Group → 宿主」那一跳**。
    /// 那一跳仍然只能真按一下键盘。**别把这条的绿当成整条链的绿。**
    static let noteSelfTest = "com.kevin.transless.selftest" as CFString

    /// 🚨 **长录实验**：前台起录 → 切后台 → 看还录不录得下去。
    ///    跟快速自检不同，它要跨越"前台→后台"这个边界，所以录 12 秒。
    static let noteLongRec = "com.kevin.transless.longrec" as CFString

    /// 🚨 **让我能给【已经在跑】的 App 再送一次起录 URL。**
    ///    `devicectl` 没有 openurl，而 `process launch` 一定是冷启动 ——
    ///    所以「App 还活着时第二次按麦克风」这条路我本来测不了，
    ///    而**那正是 Kevin 报的那个症状所在的路**。
    static let noteRecURL = "com.kevin.transless.recurl" as CFString

    /// 🚨🚨 **起录意图走 App Group 交接，不靠 URL 送达。**
    ///
    /// 实测（模拟器，冷启动 `openurl transless://rec`）：
    /// ```
    /// 主App启动：url=无        ← launchOptions 里没有 URL
    /// （没有 主App收到URL，也没有 收到起录URL）
    /// ```
    /// **URL 把 App 拉起来了，但意图【没送到】** —— 工程开了
    /// `UIApplicationSceneManifest_Generation`，冷启动的 URL 走的是 scene 那条，
    /// `launchOptions[.url]` 和 `application(_:open:)` **两条都不经过**。
    /// 这正好就是 Kevin 录屏里的样子：**冷启动 splash 全程 → 停在主页不动**。
    ///
    /// → 改成：**键盘在 `open()` 之前先在共享区留一张条子**，
    ///   主 App 起来后自己去取。**URL 只负责"把 App 叫醒"，意图由条子承载。**
    ///   这样不管 URL 走哪条路、甚至没送到，意图都不会丢。
    ///
    /// 🚨 **条子有时效**（10 秒）：过期的不认，免得他明天打开 App 又莫名其妙开始录音。
    // MARK: - 回填：主 App 出稿 → 键盘上屏
    //
    // 🚨🚨 **这一段被推倒重写过两次，别再回到"多个键各写各的"。**
    //    四轮对抗审查的结论收敛到同一句：**`UserDefaults` 跨进程
    //    从不承诺"多个键一起可见"**。先写正文再写序号，键盘完全可能
    //    读到**新序号 + 旧正文**，于是把上一句英文又插一遍。
    //
    //    现在的形状：**一份稿子 = 一个键里的一个 JSON**（序号跟着载荷走），
    //    单键写入是原子的，读出来要么整份新、要么整份旧，没有半份。
    //    去重状态 `doneSeq` 也在共享区 —— 键盘扩展**随时被销毁重建**，
    //    实例内存里的标记靠不住（第三轮审查栽的就是这条）。
    //    失败原因走**自己那一份 JSON + 自己的 doneSeq**，跟稿子完全不相干。

    private static func readJSON(_ key: String) -> [String: Any]? {
        guard let s = store?.string(forKey: key), let d = s.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) else { return nil }
        return o as? [String: Any]
    }

    private static func writeJSON(_ key: String, _ obj: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: d, encoding: .utf8) else { return }
        store?.set(s, forKey: key)      // 🚨 单键单写＝原子
    }

    /// 有没有还没投递的东西（**只看，不动**）。
    static func hasPending() -> Bool {
        peekPending() != nil || peekFailure() != nil
    }

    /// 读一份待投递的稿子。**不改任何状态**；投递后调 `markDelivered(seq:)`。
    static func peekPending(within sec: Double = 90)
        -> (seq: Int, zh: String, out: String)? {
        guard let st = store, let j = readJSON(K.pendJSON) else { return nil }
        let seq = (j["seq"] as? Int) ?? 0
        guard seq > st.integer(forKey: K.doneSeq) else { return nil }
        // 🚨 空值按 **trim 后**判：`polish` 只回空白时，
        //    原来会被当成有稿、消费掉、再报「宿主慢」——**归因完全是错的**。
        let out = ((j["out"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { markDelivered(seq: seq); return nil }
        // 🚨 90 秒：太长会把上一句英文插进一个毫不相干的输入框。
        guard Date().timeIntervalSince1970 - ((j["at"] as? Double) ?? 0) <= sec else {
            note("出稿已过期，跳过")
            markDelivered(seq: seq)
            return nil
        }
        return (seq, (j["zh"] as? String) ?? "", out)
    }

    /// 投递完成。**必须传【刚投的那一份】的序号**。
    ///
    /// 🚨 上一版是在这里现读 `pendSeq` —— 如果主 App 在"投递"和"抬序号"之间
    ///    又出了一份新稿，就会把**那份还没投的新稿一起抬掉**，稿子静默蒸发。
    ///    （第四轮审查 高-1。判据必须挂在**我刚处理的那一份**上，不是"当前最新那份"。）
    static func markDelivered(seq: Int) {
        guard let st = store else { return }
        if seq > st.integer(forKey: K.doneSeq) { st.set(seq, forKey: K.doneSeq) }
    }

    /// 主 App 出稿。
    static func postPending(zh: String, out: String) {
        guard let st = store else { return }
        // 🚨 出稿成功 → 把还没展示的旧失败一并作废（审查 M-5）。
        //    否则他切回键盘会**同时**看到"全屏失败诊断"和"英文已经插进输入框"，
        //    以为失败了、其实字已经进去了。
        st.set(st.integer(forKey: K.failSeq), forKey: K.failDoneSeq)
        let seq = st.integer(forKey: K.pendSeq) + 1
        st.set(seq, forKey: K.pendSeq)
        writeJSON(K.pendJSON, ["seq": seq, "zh": zh, "out": out,
                               "at": Date().timeIntervalSince1970])
        // 🚨 光写不叫醒等于没送到；键盘那边另有有界轮询兜底。**两条都要有。**
        poke(noteRes)
        note("出稿已留在共享区并叫醒键盘（" + String(out.count) + " 字）")
    }

    /// 主 App 报一条失败。**自己一份 JSON、自己的 doneSeq。**
    static func postFailure(_ why: String) {
        guard let st = store else { return }
        let seq = st.integer(forKey: K.failSeq) + 1
        st.set(seq, forKey: K.failSeq)
        writeJSON(K.failJSON, ["seq": seq, "why": why,
                               "at": Date().timeIntervalSince1970])
        poke(noteRes)
    }

    static func peekFailure(within sec: Double = 90) -> (seq: Int, why: String)? {
        guard let st = store, let j = readJSON(K.failJSON) else { return nil }
        let seq = (j["seq"] as? Int) ?? 0
        guard seq > st.integer(forKey: K.failDoneSeq) else { return nil }
        let why = (j["why"] as? String) ?? ""
        guard !why.isEmpty else { markFailShown(seq: seq); return nil }
        guard Date().timeIntervalSince1970 - ((j["at"] as? Double) ?? 0) <= sec else {
            markFailShown(seq: seq); return nil
        }
        return (seq, why)
    }

    static func markFailShown(seq: Int) {
        guard let st = store else { return }
        if seq > st.integer(forKey: K.failDoneSeq) { st.set(seq, forKey: K.failDoneSeq) }
    }

    /// 🚨🚨 **参数必须由键盘送过来**（对抗审查 H4）。
    ///    `send()` 的注释早就写死了这条：「不能让主 App 去读自己的设置」——
    ///    键盘扩展和容器 App **各有各的 `UserDefaults.standard`**，
    ///    表现是「用户在键盘里选了正式语气，出来的却是随意」，
    ///    而键盘上那个按钮还亮着。**跳转路径差点把这条推翻。**
    ///    **单一配置点仍然是键盘那一份。**
    /// 留一张起录条子。**回这次写入的时间戳，当撤销令牌用**（见 `cancelRec(at:)`）。
    @discardableResult
    static func requestRec(args: [String: String] = [:]) -> Double {
        guard let st = store else { return 0 }
        if let d = try? JSONSerialization.data(withJSONObject: args),
           let j = String(data: d, encoding: .utf8) {
            st.set(j, forKey: K.recReqArgs)
        }
        // 🚨 中-3：**回这次写入的时间戳当令牌**。撤条子必须凭令牌，
        //    否则两次跳转在飞时，先失败的那次会把后一次刚写的**有效条子**抹掉
        //    —— 主 App 起来后读到「没有条子」、停在首页什么都不做，
        //    跟他 08-28 录屏里那个症状一模一样，而那次会是我们自己造的。
        let at = Date().timeIntervalSince1970
        st.set(at, forKey: K.recReqAt)
        return at
    }

    /// 取走这张条子。**取走即作废**（返回一次就没了），避免同一张被两个入口各用一次。
    /// 最近一次条子带过来的参数。**取条子时一并取出**，主 App 用它，不读自己的设置。
    static var lastRecArgs: [String: String] = [:]

    /// **撤掉起录条子。**
    ///
    /// 🚨🚨 复审 中-3：条子是**先写后叫醒**的（冷启动送不到 URL，意图只能挂条子）。
    ///    但 `app.open` 可能失败（iOS 26 没开完全访问就是 -54），
    ///    那时条子会**留在 App Group 里没人取** ——
    ///    **他下次自己打开 Transless 就莫名其妙开始录音**。
    ///    这是「装新工具不许劫持他的设备」那条铁规的形状，必须能撤。
    /// - Parameter at: `requestRec` 回的令牌。**只在共享区里的值等于它时才撤**。
    static func cancelRec(at token: Double) {
        // 🚨 用 `store`（跟 `requestRec` 同一个），别凭印象写 `group` ——
        //    那是**组名字符串**，不是 UserDefaults。今天第 N 次凭印象写 API 了，
        //    引用任何跨文件的东西之前先 grep 一遍它自己怎么用的。
        guard let st = store else { return }
        // 🚨 中-3：**凭令牌撤**。不比对的话会撤掉别人刚写的那张。
        let cur = st.double(forKey: K.recReqAt)
        guard cur == token else {
            note("撤条子跳过：共享区里那张不是我写的（我 \(token) / 现 \(cur)）")
            return
        }
        st.removeObject(forKey: K.recReqAt)
        st.removeObject(forKey: K.recReqArgs)
        note("拉起失败，已撤掉起录条子（免得他下次开 App 自己开始录）")
    }

    static func takeRecRequest(within sec: Double = 10) -> Bool {
        guard let st = store else { return false }
        let t = st.double(forKey: K.recReqAt)
        // 🚨 **没有条子也要留一行。** 不然"没取到"和"压根没调这个函数"
        //    在日志上长得一模一样 —— 今晚已经在这族上栽过五次。
        guard t > 0 else { note("取起录条子：共享区里没有条子"); return false }
        st.set(0.0, forKey: K.recReqAt)
        // 2026-09-03 Kevin「我没点它自己开录」：主 App 取走条子＝这一按已由跳转起录兑现，
        //    键盘那张「他想录」(kb.wantrec.at) 必须同时销掉；否则 40s 内键盘再露面且引擎架着，
        //    autoStartIfHeMeantTo 会把旧意图当成他又按了（13:12:39 via=回来自动接上，实锤）。
        st.removeObject(forKey: "kb.wantrec.at")
        lastRecArgs = (st.string(forKey: K.recReqArgs))
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) }
            as? [String: String] ?? [:]
        let age = Date().timeIntervalSince1970 - t
        note("取起录条子：留于 " + String(format: "%.1f", age) + " 秒前，"
             + (age <= sec ? "有效" : "已过期，忽略"))
        return age <= sec
    }

    static func observeRecURL(_ token: UnsafeRawPointer,
                              _ cb: @escaping CFNotificationCallback) {
        observe(token, noteRecURL, cb)
    }

    static func observeLongRec(_ token: UnsafeRawPointer,
                               _ cb: @escaping CFNotificationCallback) {
        observe(token, noteLongRec, cb)
    }

    /// 自检结果落在 App Group 容器里的文件名 ——
    /// `devicectl device copy from --domain-type appGroupDataContainer` 拉它。
    static let selfTestFile = "selftest.txt"

    /// 往共享容器写一行结果。**写文件不是写 UserDefaults** ——
    /// `copy from` 拉的是文件，拉不到偏好。
    /// 一行**面包屑**，写进 App Group 的 UserDefaults（那条通道实测可用）。
    ///
    /// 🚨 为什么要它：2026-08-28 那次，`tryLocalRecord` 返回 false 却
    ///    **一点痕迹都没留**，于是"跑没跑、为什么退出"完全无从判断。
    ///    只保留最近 12 条，够看清一次操作的走向，又不会把偏好撑大。
    /// 读 App Group 里的实验开关（`flags.txt`，一行一个名字）。
    ///
    /// 🚨 为什么要它：实验开关原来**只认环境变量**，而环境变量只有
    ///    `devicectl process launch -e` 能注入 —— **他手动点开 App 时一定没有**。
    ///    于是"让他手点一次"这个排除法根本做不成。
    ///    （而"我远程拉起来的场景"恰恰是 PiP `-1001` 的头号嫌疑。）
    ///
    /// 🚨 仍然影响不到正式包：这个文件只有我能写
    ///    （`devicectl copy to` 要开发签名 + 连线），**默认不存在 = 全关**。
    /// 🚨 **两个位置都读**： 往容器**根目录**写会报
    ///    （实测），**只有已存在的子目录能写** ——
    ///     可以。所以真正落地的是那一份。
    ///    根目录那份留着，是给以后能直接写根目录或手工放文件的情况。
    ///    **两处都读 = 不用记住哪次用了哪条路。**
    private static func flagText(_ dir: URL) -> String? {
        for p in ["Library/Caches/flags.txt", "flags.txt"] {
            if let t = try? String(contentsOf: dir.appendingPathComponent(p),
                                   encoding: .utf8) { return t }
        }
        return nil
    }

    static func flag(_ name: String) -> Bool {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group),
              let t = flagText(dir) else { return false }
        return t.split(separator: "\n").contains { $0.trimmingCharacters(
            in: .whitespaces) == name }
    }

    static func note(_ line: String) {
        guard let st = store else { return }
        // 🚨 原来只有 UTC，读的人要在脑子里 +8 —— 总协调差点因此把一条结果读反。
        //    **给人看的东西就写本地时间。**
        let _f = DateFormatter(); _f.dateFormat = "MM-dd HH:mm:ss"
        let stamp = _f.string(from: Date()) + "(本地)"
        var a = st.array(forKey: K.trail) as? [String] ?? []
        a.append(stamp + "  " + line)
        // 🚨🚨 **12 条太少，这是今天诊断卡住的直接原因。**
        //    2026-08-29：他按完我去读痕迹，开头那几行（Scene 连上/自动切回）
        //    **已经被后面的行冲掉了** —— 于是「到底拿没拿到来源」查不出来，
        //    我只能猜。**观测窗口比事件短 = 等于没观测。**
        //    一条 60 字左右，60 条也就 4KB，代价可以忽略。
        if a.count > 200 { a.removeFirst(a.count - 200) }
        st.set(a, forKey: K.trail)
        // 🚨🚨 **强制落盘。** 不落盘的话，我在 Mac 上用 `devicectl copy from`
        //    拉回来的 plist 是**滞后快照** —— 2026-08-30 04:00 因此把
        //    "7/8 成功"读成了"4/10"，还差点去改一段本来没坏的代码。
        //    **观测手段本身在骗人，比没有观测更糟。**
        st.synchronize()
    }

    static func writeSelfTest(_ text: String) {
        // 🚨🚨 **这个函数原来会静默失败，整晚最想要的那份证据就是这么丢的。**
        //
        //    2026-08-28 从 Kevin 手机上拉容器：`selftest.txt` **一个都没有**，
        //    而同容器的 `Library/Preferences/group.com.kevin.transless.plist`
        //    好好地在（915 字节、时间戳是新的）。
        //    → **App Group 能写，是写文件这条路没成。**
        //    而 `guard ... else { return }` 和 `try?` **把两种失败都吞了** ——
        //    我们只看到"文件不存在"，分不清是「没走到这儿」还是「写失败了」。
        //
        //    改法：① 原子写失败退非原子（沙盒里原子写要建临时文件再改名，可能被拒）
        //         ② **不管成败都记进 App Group 的 UserDefaults** ——
        //            那条通道**今晚实测拉下来过**，别把鸡蛋放一个篮子。
        // 🚨 原来只有 UTC，读的人要在脑子里 +8 —— 总协调差点因此把一条结果读反。
        //    **给人看的东西就写本地时间。**
        let _f = DateFormatter(); _f.dateFormat = "MM-dd HH:mm:ss"
        let stamp = _f.string(from: Date()) + "(本地)"
        let body = stamp + "  " + text + "\n"
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group) else {
            store?.set(stamp + " 拿不到共享容器（containerURL 为 nil）",
                       forKey: K.selfTestWhy)
            store?.set(body, forKey: K.selfTestBody)
            return
        }
        let url = dir.appendingPathComponent(selfTestFile)
        var why = "OK 原子写"
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let e1 = error as NSError
            do {
                try body.write(to: url, atomically: false, encoding: .utf8)
                why = "原子写失败(\(e1.code))，非原子写成功"
            } catch {
                why = "两种写法都失败：原子 \(e1.code) / 非原子 \((error as NSError).code)"
            }
        }
        store?.set(why, forKey: K.selfTestWhy)
        store?.set(body, forKey: K.selfTestBody)
    }

    /// Mac 用 `copy to` 放进共享容器的自检参数（可以没有）。
    ///
    /// 🚨 **为什么是文件不是 UserDefaults**：`copy to` 送的是文件；
    ///    偏好由 `cfprefsd` 缓存着，从底下改文件跑着的 App 不一定看得见。
    static func readSelfTestCmd() -> [String: String] {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group),
              let d = try? Data(contentsOf:
                dir.appendingPathComponent("selftest_cmd.json")),
              let o = (try? JSONSerialization.jsonObject(with: d))
                as? [String: Any] else { return [:] }
        var r: [String: String] = [:]
        for (k, v) in o { r[k] = "\(v)" }
        return r
    }

    static func observeSelfTest(_ token: UnsafeRawPointer,
                                _ cb: @escaping CFNotificationCallback) {
        observe(token, noteSelfTest, cb)
    }

    // ------------------------------------------------------------ 音量（波形）

    /// 🚨 为什么要过 App Group：录音在**主 App**，波形画在**键盘扩展**里。
    ///    安卓那边两者同进程，直接 `push()` 就行；iOS 隔着进程，只能铺一条通道。
    ///    条数跟安卓一样是 13（`WaveView.BARS`），多了没意义、少了画不满。
    static func pushLevel(_ v: Float) {
        guard let s = store else { return }
        var a = s.array(forKey: K.levels) as? [Double] ?? []
        a.append(Double(max(0, min(1, v))))
        if a.count > 13 { a.removeFirst(a.count - 13) }
        s.set(a, forKey: K.levels)
        // 🚨 顺带记整段峰值（`levels` 只留最后 13 条，代表不了整段）。
        let cur = s.object(forKey: K.spanPeak) as? Double ?? 0
        let now = Double(max(0, min(1, v)))
        if now > cur { s.set(now, forKey: K.spanPeak) }
    }

    /// 整段录音的峰值（起录时清零）。0 = 这一轮还没收到任何一帧。
    static func spanPeak() -> Float {
        Float(store?.object(forKey: K.spanPeak) as? Double ?? 0)
    }

    static func levels() -> [Float] {
        guard let s = store else { return [] }
        // 🚨🚨 **跨进程读共享偏好不保证及时刷新。**
        //    波形是**宿主进程写、键盘扩展读**，两个进程各有一份缓存 ——
        //    不强制同步的话键盘可能一直读到起录那一刻的旧值（常见是空的），
        //    表现正是 Kevin 2026-08-29 说的「键变红了，但没有波形」。
        // 🚨 这条只加在 `levels()` 上：它是**唯一一个要求"立刻看到对方刚写的"**
        //    的读取点（稿子那条走 Darwin 通知叫醒，不靠轮询）。
        s.synchronize()
        return (s.array(forKey: K.levels) as? [Double] ?? []).map { Float($0) }
    }

    /// 🚨 收工必须清。不清的话下次一按麦克风，波形会**先闪一下上一轮的形状**
    ///    —— 那正好是「看起来在听」的假象，跟这条波形要解决的问题反着来。
    /// 宿主正在录音吗；返回起始时刻，没在录返回 nil。
    /// 🚨 带**新鲜度**：宿主被系统杀掉时来不及清这个键，
    ///    不设上限的话键盘会永远显示"正在录音"，比不显示更糟。
    static func recordingSince(maxAge: TimeInterval = 900) -> Date? {
        guard let t = store?.object(forKey: K.recSince) as? Double, t > 0 else { return nil }
        let d = Date(timeIntervalSince1970: t)
        return Date().timeIntervalSince(d) <= maxAge ? d : nil
    }

    /// - Parameter seq: 这一单的序号。**键盘被系统销毁后要靠它接回来**，
    ///   所以必须存进共享区 —— 存在键盘进程的内存里，进程一没就跟着没了。
    ///
    /// 🚨🚨 立这个参数的原因（Kevin 2026-09-04 实测复现）：
    ///    他在微信里按录音 → 切到美团 → 切回微信，**录音没了**。
    ///    痕迹显示 iOS 在切走时**把键盘扩展整个销毁**，销毁路径
    ///    (`deinit` → `teardown(cancelRemote: true)`) 主动发了 `cancel`。
    ///    代码里"切走不撤单"那条判断只管**隐藏**，管不住**销毁**。
    ///    → 改成销毁也不撤单；那就必须让回来的那个新键盘知道
    ///      「宿主还在录，单号是几」，否则他按停止没有任何反应。
    static func markRecording(_ on: Bool, seq: Int = -1) {
        if on {
            store?.set(Date().timeIntervalSince1970, forKey: K.recSince)
            if seq >= 0 { store?.set(seq, forKey: K.recSeq) }
        } else {
            store?.removeObject(forKey: K.recSince)
            store?.removeObject(forKey: K.recSeq)
        }
    }

    /// 正在飞的那一单的序号；`-1` = 没有。
    static func recordingSeq() -> Int {
        (store?.object(forKey: K.recSeq) as? Int) ?? -1
    }

    /// 键盘**最后一次还在场**的时刻（被销毁时写）。
    /// 宿主拿它判「他是不是不回来了」—— 不回来就别一直占着麦克风。
    static func markKeyboardGone() {
        store?.set(Date().timeIntervalSince1970, forKey: K.kbGoneAt)
    }

    /// 键盘回来了，清掉离场记号。
    /// 🚨 **不清的话宽限会从上一次离场开始算** —— 他回来了、正说着话，
    ///    宿主却按"他走了 130 秒"把这一单收尾掉。
    ///    （这类"状态量只写不清"的漏，表现是间歇性的、最难查。）
    static func clearKeyboardGone() {
        store?.removeObject(forKey: K.kbGoneAt)
    }

    /// 键盘走了多久（秒）。没走过就返回 0。
    static func keyboardGoneAgo() -> TimeInterval {
        guard let t = store?.object(forKey: K.kbGoneAt) as? Double, t > 0 else { return 0 }
        return Date().timeIntervalSince1970 - t
    }

    /// 「是谁把主 App 叫起来的」—— 自动切回要靠它才能回到**他那个输入框**。
    /// 🚨 存共享区而不是内存：冷启动那一路拿不到来源，只能用上一次的。
    /// 🚨🚨 **档位（`vime.mode` / `vime.tone` / `vime.lang`）的唯一存放处。**
    ///
    /// Kevin 2026-08-29：「点了转写，出来的还是翻译。」
    /// 根因：这三个 key 原来写在 `UserDefaults.standard` 上，而
    /// **键盘扩展和主 App 的 `standard` 根本不是同一份** ——
    /// 他在主 App 里点「转写」，键盘那边一无所知，照旧按 `en`（翻译）发。
    ///
    /// 🚨 代码里那句注释写着「跟主 App 用同一个 key」——
    ///    **key 是同一个，容器不是。注释描述的是意图，实现没做到。**
    ///    （同一族：`_量测规矩` 里那条「注释描述了一个不存在的分支」。）
    ///
    /// → 改用 App Group 的那份，两个进程真的共享。**只留这一个出口**，
    ///   别再有第二处直接写 `UserDefaults.standard` 存档位。
    static var prefs: UserDefaults { store ?? .standard }

    /// **从宿主自己的 `Info.plist` 探到的 URL scheme**（不带 `://`）。
    ///
    /// 🚨🚨 2026-08-31 交叉审查抓到：上一版把 scheme 和 bundle id **塞进同一个字段**，
    ///    而消费端 `backSchemes[src]` 的键是 bundle id —— 于是最常见的那条
    ///    （读到了 scheme）必然查表 miss，「开回来源 App」基本不成立，
    ///    痕迹还打成「表里没有它的 scheme」把人往加表条目上带。
    ///    **一个字段只装一种东西。**
    ///
    /// 分开存还白捡一个好处：**表里没有的 App 也能回得去** ——
    /// 探到什么 scheme 就用什么，`backSchemes` 退化成兜底。
    static func rememberSourceScheme(_ scheme: String) {
        guard !scheme.isEmpty else { return }
        store?.set(scheme, forKey: "kb.src.scheme")
        store?.set(Date().timeIntervalSince1970, forKey: "kb.src.scheme.at")
        store?.synchronize()
    }

    /// 探到的 scheme（带新鲜度；理由同 `sourceBundle`——猜错比不猜更糟）。
    static func sourceScheme(maxAge: TimeInterval = 1800) -> String {
        guard let s = store else { return "" }
        s.synchronize()
        guard let t = s.object(forKey: "kb.src.scheme.at") as? Double,
              Date().timeIntervalSince1970 - t < maxAge else { return "" }
        return s.string(forKey: "kb.src.scheme") ?? ""
    }

    static func rememberSource(_ bundleId: String) {
        store?.set(bundleId, forKey: "kb.src.bundle")
        store?.set(Date().timeIntervalSince1970, forKey: "kb.src.at")
    }

    /// 上一次学到的来源 App。
    ///
    /// 🚨🚨 **带新鲜度，而且必须带。** 冷启动那一路 iOS 不给来源，
    ///    只能沿用上一次学到的 —— 但**沿用一个很旧的值是会出错的**：
    ///    他要是换到别的 App 用键盘，我们会把他"送回微信"，
    ///    **那比落桌面更糟**（落桌面至少他知道发生了什么）。
    /// 🚨 所以只在 `maxAge` 内沿用。过期就老老实实退到后台。
    ///    这条**不是保守，是因为猜错的代价比不猜更高**。
    // MARK: - 热麦（麦克风一直开着，按键盘时不用再起录）

    /// 🚨🚨 **这是「不用跳过去」的地基。**
    ///
    /// 2026-08-29 真机实测（两个独立信号、App 全程后台、连续 3 分钟）：
    /// ```
    /// +30秒  帧 300   话段 12   引擎在跑
    /// +180秒 帧 1807  话段 39   引擎在跑
    /// ```
    /// **麦克风在后台可以一直热着。** 那么键盘按下时就不需要起录 ——
    /// 也就不需要把主 App 拉到前台，**"切走再切回"这个问题整个消失**。
    /// （苹果 DTS 明说没有 API 能切回宿主 App，所以绕开它才是解法。）
    ///
    /// 🚨 带**新鲜度**：宿主被系统杀掉时来不及清这个键。
    ///    读到一个过期的"热着"会让键盘以为不用跳，结果**按了什么都不会发生** ——
    ///    比多跳一次糟得多。
    /// **画中画小窗活着吗** —— 活着＝主 App 没被挂起、而且**能起录**，
    /// 于是键盘按下时**直接发命令，完全不用跳过去**。
    ///
    /// 🚨 这是 2026-08-29 打通的那条：真机对照实验
    /// ```
    /// 不开小窗：App 被挂起，自检根本没跑
    /// 开着小窗：自检跑了，后台起录成功（帧数 12）
    /// ```
    /// 以前后台起录一律 `2003329396 / 输入源 0 个`。
    /// 🚨 带新鲜度：小窗被系统收走时来不及清标志，
    ///    读到过期的"活着"会让这一按**什么都不发生** —— 比多跳一次糟得多。
    /// **灵动岛现在亮着吗** —— 主 App 和键盘扩展**共用这一份**。
    ///
    /// 🚨 为什么必须放共享区：岛可能是**键盘起的**（主 App 在后台起不了岛，
    ///    真机原文 `Target is not foreground`），而宿主要靠"岛亮着"
    ///    才敢在后台起录。两个进程各记各的，规矩就落在错的那一份上。
    /// 🚨 带新鲜度：岛没了而标记还在，会让宿主硬录然后失败 —— 比不录更糟。
    static func markIsland(_ on: Bool) {
        if on { store?.set(Date().timeIntervalSince1970, forKey: "kb.island.at") }
        else { store?.removeObject(forKey: "kb.island.at") }
    }

    static func islandReady(maxAge: TimeInterval = 30) -> Bool {
        guard let s = store else { return false }
        s.synchronize()   // 跨进程读，先同步（波形那次就栽在这）
        guard let t = s.object(forKey: "kb.island.at") as? Double else { return false }
        return Date().timeIntervalSince1970 - t <= maxAge
    }

    /// **宿主的「可录保活」现在开着吗。**
    ///
    /// 🚨 为什么放共享区：`Voice` 是**两个进程共用**的文件（主 App + 键盘扩展），
    ///    它不能直接问 `KbVoiceHost`（那是主 App 独有的）。
    ///    而"要不要关会话"这个决定两边都要做。
    /// 🚨 带新鲜度：保活停了而标记还在，会让人以为会话还活着。
    static func markHold(_ on: Bool) {
        if on { store?.set(Date().timeIntervalSince1970, forKey: "kb.hold.at") }
        else { store?.removeObject(forKey: "kb.hold.at") }
    }

    static func holdAlive(maxAge: TimeInterval = 20) -> Bool {
        guard let s = store else { return false }
        s.synchronize()
        guard let t = s.object(forKey: "kb.hold.at") as? Double else { return false }
        return Date().timeIntervalSince1970 - t <= maxAge
    }

    /// **宿主的录音引擎已经架好、能在后台留声音了吗。**
    ///
    /// 🚨 键盘就靠这一条决定「发命令」还是「跳过去」。
    ///    它比 `hostAlive` 严 —— 宿主活着不等于引擎架着，
    ///    而**只有引擎架着才不用跳**（后台不许新建录音）。
    /// **记下宿主是谁**（键盘写、主 App 读）。
    ///
    /// 🚨 只有键盘那一侧问得到（`UIInputViewController._hostApplicationBundleIdentifier`），
    ///    而真正要开 URL 回去的是主 App —— 所以必须过共享区传一手。
    /// 🚨 带时间戳：**超过 60 秒的旧值一律不认**。宿主是"他刚才在哪个 App"，
    ///    隔了十分钟的旧值会把他送到一个跟这次录音无关的 App 去。
    /// 记下宿主 PID（端上翻不成 bundleID，但我在电脑这边能翻）。
    /// **回程准度埋点**：键盘每次露面时，把「这次的宿主 PID」跟
    /// 「上一次按麦克风时的宿主 PID + 我们当时开了哪个 scheme」对上。
    ///
    /// 🚨 只记录、不做任何判断，也不改行为。
    ///    要回答的问题是：**「键盘再露面时 PID 没变」能不能代表「回程猜对了」**。
    ///    在拿正负样本验过这个指标之前，不许拿它做决策
    ///    （Kevin 的铁规：别拿代理指标下结论）。
    static func logReturnAccuracy(hostPid: Int) {
        guard let d = store else { return }
        d.synchronize()
        let lastPid = d.integer(forKey: "acc.pressPid")
        let lastAt = d.double(forKey: "acc.pressAt")
        let scheme = d.string(forKey: "acc.openedScheme") ?? ""
        if lastPid > 0, !scheme.isEmpty {
            let gap = Date().timeIntervalSince1970 - lastAt
            note("回程准度：按下时宿主=" + String(lastPid)
                 + "｜我们开了 " + scheme
                 + "｜现在宿主=" + String(hostPid)
                 + "｜" + (lastPid == hostPid ? "PID 相同" : "PID 变了")
                 + "｜隔了 " + String(Int(gap)) + " 秒")
            d.removeObject(forKey: "acc.openedScheme")
        }
        d.set(hostPid, forKey: "acc.hostPid")
        d.synchronize()
    }

    /// 按下麦克风那一刻，记住当时的宿主 PID（回程准度用）。
    static func markPressHost() {
        guard let d = store else { return }
        d.set(d.integer(forKey: "acc.hostPid"), forKey: "acc.pressPid")
        d.set(Date().timeIntervalSince1970, forKey: "acc.pressAt")
        d.synchronize()
    }

    /// 回程时我们实际开了哪个 scheme（回程准度用）。
    static func markOpenedScheme(_ scheme: String) {
        store?.set(scheme, forKey: "acc.openedScheme")
        store?.synchronize()
    }

    /// App Group 里 `Library/Caches/<name>.txt` 存在就算开关打开（我用 devicectl copy 推）。
    static func flagFile(_ name: String) -> Bool {
        guard let u = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("Library/Caches/" + name + ".txt") else { return false }
        // 2026-09-02：空文件算【关】。之前只判存在，"清开关"写成空文件照样是开，
        //    结果实验残留的 islandautobegin 让主程序在后台反复起录、麦克风橙点常亮（Kevin 当场撞上）。
        guard let d = FileManager.default.contents(atPath: u.path) else { return false }
        return !d.isEmpty
    }

    static func rememberHostToken(_ d: Data) {
        store?.set(d.base64EncodedString(), forKey: "kb.host.token")
        store?.synchronize()
    }
    static func hostToken() -> Data? {
        guard let s = store else { return nil }
        s.synchronize()
        guard let b64 = s.string(forKey: "kb.host.token") else { return nil }
        return Data(base64Encoded: b64)
    }

    static func rememberHostPid(_ pid: Int32) {
        // 🚨 键名必须跟 `hostPid()` 读的那两个**完全一致**。
        //    我第一版自己起了 `kb.hostPid` —— 写进去了、读的人看的是 `kb.host.pid`，
        //    于是"存了"和"没存"在日志里长得一模一样（`共享区里没有宿主 pid`）。
        //    **同一个东西两个键名 = 两个配置点**，必漂。
        store?.set(Int(pid), forKey: "kb.host.pid")
        store?.set(Date().timeIntervalSince1970, forKey: "kb.host.pid.at")
        store?.synchronize()
    }

    static func rememberHost(_ bundleID: String) {
        store?.set(bundleID, forKey: "kb.hostBundle")
        store?.set(Date().timeIntervalSince1970, forKey: "kb.hostBundleAt")
        store?.synchronize()   // 🚨 不落盘主 App 就读不到
    }

    /// 最近一次记下的宿主；**过期（>60 秒）返回 nil**。
    static func lastHost() -> String? {
        guard let d = store else { return nil }
        d.synchronize()
        guard let b = d.string(forKey: "kb.hostBundle"), !b.isEmpty else { return nil }
        let at = d.double(forKey: "kb.hostBundleAt")
        guard at > 0, Date().timeIntervalSince1970 - at < 60 else { return nil }
        return b
    }

    // MARK: - 常用词（共享区，键盘和主 App 都读）
    //
    // 🚨🚨 存的是**完整的 Term**（带 kind），**不是筛好的字符串数组**。
    //    我 09-03 第一版写成 `saveAsrVocab([String])`，在**存的时候**就把
    //    style 的词滤掉了 —— 那等于**过滤有了第二个实现**，
    //    而 `VocabCore` 的注释白纸黑字点名要避免这件事：
    //    「识别那条自己再写一遍过滤的话，改一处等于没改」。
    //    现在存全量，发请求时统一走 `VocabCore.wordsFor(_:asr:)`。

    private static let vocabKey = "kb.vocab.terms"

    /// 存全量常用词（共享区）。**不在这里做 kind 过滤。**
    static func saveVocab(_ terms: [VocabCore.Term]) {
        // 🚨🚨 `status` **始终写全，哪怕是 "on"**（安卓 `Vocab.toJson` 同款注释）：
        //    省略的话，另一台设备上的客户端做 replace 时会把 cand/no 抹平成 on，
        //    他否掉过的词会成片复活。`count` 为 0 时才省略。
        let arr: [[String: Any]] = terms.map { t -> [String: Any] in
            var d: [String: Any] = ["id": t.id, "text": t.text, "kind": t.kind,
                                    "src": t.src, "at": t.at,
                                    "status": t.status]
            if t.count > 0 { d["count"] = t.count }
            return d
        }
        store?.set(arr, forKey: vocabKey)
        store?.set(Date().timeIntervalSince1970, forKey: "kb.vocab.at")
        store?.synchronize()
        note("常用词：存了 " + String(terms.count) + " 条进共享区（全量，不预筛）")
    }

    /// 读回全量常用词。
    static func loadVocab() -> [VocabCore.Term] {
        store?.synchronize()
        let arr = (store?.array(forKey: vocabKey) as? [[String: Any]]) ?? []
        return arr.compactMap { d in
            guard let t = d["text"] as? String, !t.isEmpty else { return nil }
            return VocabCore.Term(
                id: (d["id"] as? String) ?? VocabCore.idOf(t),
                text: t,
                kind: VocabCore.kindOf(d["kind"] as? String),
                src: (d["src"] as? String) ?? VocabCore.SRC_MANUAL,
                at: (d["at"] as? Int64) ?? Int64((d["at"] as? Double) ?? 0),
                // 🚨 老存档没有 status → `statusOf` 兜底成 `on`（不是 cand）：
                //    那些词本来就是他自己加的，当成候选会要求他再点一遍。
                status: VocabCore.statusOf(d["status"] as? String),
                count: (d["count"] as? Int) ?? 0)
        }
    }

    /// 进识别请求的那份纯文本数组。**过滤走 `VocabCore`，这里不自己判。**
    ///
    /// 🚨 这里**不再**自己去拉单词本 —— 那条流现在挂在 `WordBook.add` 那一刻
    ///    （见 `WordBook.pushToVocab`）。放在读取侧的代价是：`KbBridge` 会引用
    ///    `WordBook`，而**灵动岛 target 是逐个列文件的**，它编不过
    ///    （2026-09-04 实测 `cannot find 'WordBook' in scope`）——
    ///    一个显示录音状态的小组件没道理认识单词本。
    static func asrVocab() -> [String] {
        VocabCore.wordsFor(loadVocab(), asr: true)
    }

    // ---- 墓碑：删过的词不许再流回来（安卓 `Vocab.KEY_DEAD` / `removeAndForget`）----
    //
    // 🚨 只删不记的后果：单词本那条单向流（`pullFromWordBook`）下次又会把
    //    同一个词塞回常用词，表现成**"我删了它自己又回来了"**。
    //    墓碑只存 id，不存原文 —— 存原文等于把他删掉的东西又留了一份。

    private static let vocabDeadKey = "kb.vocab.dead"

    /// 删过哪些词（id 集合）。
    static func vocabTombstones() -> Set<String> {
        store?.synchronize()
        let arr = (store?.array(forKey: vocabDeadKey) as? [String]) ?? []
        return Set(arr.filter { !$0.isEmpty })
    }

    /// 记一个墓碑。**幂等**（同一个 id 记两次不会多出一条）。
    static func addVocabTombstone(_ id: String) {
        guard !id.isEmpty else { return }
        var d = vocabTombstones()
        d.insert(id)
        store?.set(Array(d), forKey: vocabDeadKey)
        store?.synchronize()
    }

    /// 进**出稿指令**的那一串（顿号分隔）。空表回空串。
    ///
    /// 🚨🚨 2026-09-04 补：iOS 之前**只接了识别侧**，出稿侧一直没接 ——
    ///    也就是 `kind = "style"` 的词（「circle back」这种只管写得像、
    ///    不管听得准的）在 iOS 上**一个都没生效**，而界面还照样让人选那一档。
    ///    安卓走 `Api.sysFor()` 里的 `base + Gen.VOCAB_HINT`，iOS 少了这一环。
    /// 🚨 过滤同样只有 `VocabCore` 那一份实现，这里不重写。
    static func styleVocab() -> String {
        VocabCore.joinFor(loadVocab(), asr: false)
    }

    static func markArmed(_ on: Bool) {
        if on { store?.set(Date().timeIntervalSince1970, forKey: "kb.armed.at") }
        else { store?.removeObject(forKey: "kb.armed.at") }
        store?.synchronize()   // 🚨 同上：不落盘我就读不到真值
    }

    static func hostArmed(maxAge: TimeInterval = 12) -> Bool {
        guard let s = store else { return false }
        s.synchronize()
        guard let t = s.object(forKey: "kb.armed.at") as? Double else { return false }
        return Date().timeIntervalSince1970 - t <= maxAge
    }

    /// **键盘最近一次露面的时刻。**
    ///
    /// 🚨 用途：宿主靠它决定「还要不要继续占着麦克风」。
    ///    待命档必须让引擎一直跑（`pause()` 之后后台恢复不了，实测
    ///    `2003329396`），所以**待命 = 麦克风指示灯亮着**。
    ///    Kevin 明确说过「不能一直开着麦克风」——
    ///    收窄成「你最近还在打字才占着」，比一直占着诚实得多。
    /// **他按了录音，但宿主还没准备好，所以我们先去架引擎** —— 把这个意图记下来。
    ///
    /// 🚨🚨 Kevin 2026-08-31：「返回微信后，录音按钮并没有自动开启，
    ///    还是需要我手动再点一次按钮。」痕迹也是这么写的：
    ///    `01:00:13 键盘出现｜宿主在录=false` → `01:00:15 按下麦克风`（他又按了一次）。
    ///    → 跳走前记下意图，回来看到引擎架好了就自动接上，**那一按不该白费**。
    static func markWantRec() {
        store?.set(Date().timeIntervalSince1970, forKey: "kb.wantrec.at")
        store?.synchronize()
    }

    /// 那个意图还新鲜吗？（默认 40 秒；取走即清，**只兑现一次**）
    /// 🚨 必须清 —— 不清的话他下次纯粹想打字、键盘一冒出来就自己开录了。
    /// **只看不取** —— 开屏页用它判断「这次是不是键盘把我拉起来的」。
    /// 🚨 不能用 `takeWantRec`：那个取走即清，会把「他想录」这个意图吃掉。
    static func peekWantRec(maxAge: TimeInterval = 12) -> Bool {
        guard let s = store else { return false }
        s.synchronize()
        guard let t = s.object(forKey: "kb.wantrec.at") as? Double else { return false }
        return Date().timeIntervalSince1970 - t < maxAge
    }

    static func takeWantRec(maxAge: TimeInterval = 12) -> Bool {
        guard let s = store else { return false }
        s.synchronize()
        guard let t = s.object(forKey: "kb.wantrec.at") as? Double else { return false }
        s.removeObject(forKey: "kb.wantrec.at")
        s.synchronize()
        return Date().timeIntervalSince1970 - t < maxAge
    }

    /// **手上有没有一段可以直接重发的音频**（键盘据此改提示、改按下行为）。
    /// 🚨 Kevin：「已经录了，我不想再重新录一遍」。
    // MARK: - 待重发的那段音频（落盘，跨进程存活）
    //
    // 🚨🚨 2026-09-03：原来这段音频**只在内存**（`KbVoiceHost.lastWav`）。
    //    失败后能重发 —— **前提是主 App 进程还活着**。
    //    而 iOS 这一端主 App 被系统清掉是日常，一清就什么都没了，
    //    「一键继续」按钮再好也救不回已经不存在的音频。
    //    Kevin：「说的话没记下来很浪费时间」。
    //
    // 🚨 写进 **App Group 容器**不是沙盒 Documents —— 键盘扩展也要够得着。
    // 🚨 存的是**原样的 wav 字节**，重发时原样发出去：
    //    不重新压、不重新采样（重压一次就等于换了一段音频）。

    private static func pendingURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("pending.wav")
    }

    /// 上传前存一份。失败了他就能重来；成功了立刻删。
    /// - Parameter rid: 幂等 id。🚨 **必须一起存** —— 冷启动捡回来之后重发，
    ///   要用同一个 `X-Req-Id`，否则后端去重失效，他按一下就是又付一次钱。
    static func savePendingAudio(_ data: Data, tone: String,
                                 mode: String, lang: String, rid: String) {
        guard let u = pendingURL() else { return }
        do {
            try data.write(to: u, options: .atomic)
            store?.set(["tone": tone, "mode": mode, "lang": lang, "rid": rid,
                        "at": Date().timeIntervalSince1970],
                       forKey: "kb.pending.meta")
            store?.synchronize()
            note("话存下来了：" + String(data.count) + " 字节落盘（失败也丢不了）")
        } catch {
            // 🚨 存不下不能把整条链带崩 —— 最坏退回原来的「只在内存」。
            note("🚨 存盘失败：" + String("\(error)".prefix(80)))
        }
    }

    /// 读回存货。`maxAge` 跟 `hasRetryAudio` 同一个窗口（默认 10 分钟）——
    /// 过期就当没有，他早就说别的了。
    static func loadPendingAudio(maxAge: TimeInterval = 600)
        -> (data: Data, tone: String, mode: String, lang: String, rid: String)? {
        guard let u = pendingURL(),
              let m = store?.dictionary(forKey: "kb.pending.meta"),
              let at = m["at"] as? Double,
              Date().timeIntervalSince1970 - at <= maxAge,
              let d = try? Data(contentsOf: u), d.count > 44 else { return nil }
        // 🚨 rid 缺了就当没有存货 —— 拿不到原来那个 id 的话，
        //    重发＝新一单＝重新计费，那还不如让他知道要重说。
        guard let rid = m["rid"] as? String, !rid.isEmpty else { return nil }
        return (d, (m["tone"] as? String) ?? "",
                (m["mode"] as? String) ?? "en", (m["lang"] as? String) ?? "en",
                rid)
    }

    /// 出稿成功之后才删。🚨 别在「开始上传」时删 —— 那等于没存过。
    static func clearPendingAudio() {
        if let u = pendingURL() { try? FileManager.default.removeItem(at: u) }
        store?.removeObject(forKey: "kb.pending.meta")
        store?.synchronize()
    }

    static func setHasRetryAudio(_ v: Bool) {
        store?.set(v ? Date().timeIntervalSince1970 : 0, forKey: "kb.retry.at")
        store?.synchronize()
    }

    /// 存货还新鲜吗（默认 10 分钟）。过期就当没有 —— 他早就说别的了。
    static func hasRetryAudio(maxAge: TimeInterval = 600) -> Bool {
        guard let s = store else { return false }
        s.synchronize()
        guard let t = s.object(forKey: "kb.retry.at") as? Double, t > 0 else { return false }
        return Date().timeIntervalSince1970 - t < maxAge
    }

    /// 环境变量那条只探一次（每次键盘露面都刷会把痕迹刷爆）。
    static var probedEnvOnce = false

    static func markKeyboardSeen() {
        store?.set(Date().timeIntervalSince1970, forKey: "kb.kbseen.at")
    }

    /// 键盘多久没露面了（秒）。从没露过返回一个很大的数。
    static func keyboardSeenAgo() -> TimeInterval {
        guard let s = store else { return .greatestFiniteMagnitude }
        s.synchronize()
        guard let t = s.object(forKey: "kb.kbseen.at") as? Double else {
            return .greatestFiniteMagnitude
        }
        return Date().timeIntervalSince1970 - t
    }

    /// **Live Activity 的 push-to-start token**（十六进制串）。
    ///
    /// 🚨 存共享区是因为**键盘要用它**：键盘按麦克风时把它发给后端，
    ///    后端凭它发一条 APNs push-to-start，把灵动岛在**后台**拉起来 ——
    ///    这是「不跳出微信」唯一剩下的路（苹果 DTS 明确答复：
    ///    键盘识别宿主 App / 容器 App 反查来源，都没有公开办法）。
    /// 🚨 token 会变（系统随时可能换），所以每次拿到都覆盖写。
    static func setPushToStartToken(_ hex: String) {
        store?.set(hex, forKey: "kb.pts.token")
        store?.set(Date().timeIntervalSince1970, forKey: "kb.pts.at")
        store?.synchronize()
    }

    static func pushToStartToken() -> String {
        store?.synchronize()
        return store?.string(forKey: "kb.pts.token") ?? ""
    }

    /// **他此刻所在 App 的进程号**（键盘从审计令牌拿到，写给主 App 用）。
    ///
    /// 🚨 为什么要绕这一道：`proc_pidpath` 在键盘扩展里被沙盒挡死（`errno=1`），
    ///    而主 App 的沙盒规则不同 —— 值得让主 App 自己试一次。
    ///    拿到路径就能知道该切回哪个 App，那正是 Kevin 唯一还没解决的那件事。
    static func setHostPid(_ pid: Int) {
        store?.set(pid, forKey: "kb.host.pid")
        store?.set(Date().timeIntervalSince1970, forKey: "kb.host.pid.at")
        store?.synchronize()
    }

    static func hostPid(maxAge: TimeInterval = 60) -> Int {
        guard let s = store else { return 0 }
        s.synchronize()
        guard let at = s.object(forKey: "kb.host.pid.at") as? Double,
              Date().timeIntervalSince1970 - at <= maxAge else { return 0 }
        return s.integer(forKey: "kb.host.pid")
    }

    static func markPip(_ on: Bool) {
        if on { store?.set(Date().timeIntervalSince1970, forKey: "kb.pip.at") }
        else { store?.removeObject(forKey: "kb.pip.at") }
    }

    static func pipReady(maxAge: TimeInterval = 8) -> Bool {
        guard let s = store else { return false }
        // 🚨🚨 **跨进程读必须先同步。**
        //    这个标志是**主 App 写、键盘扩展读**，两个进程各有一份缓存。
        //    不同步的话键盘可能一直读到"没有小窗"，于是**照样跳转** ——
        //    而那正是我们要消灭的那件事，还会表现成"改了没用"。
        //    2026-08-29 波形就是同一个坑（他报「键变红了但没有波形」）。
        s.synchronize()
        guard let t = s.object(forKey: "kb.pip.at") as? Double else { return false }
        return Date().timeIntervalSince1970 - t <= maxAge
    }

    static func markHotMic(_ on: Bool) {
        if on { store?.set(Date().timeIntervalSince1970, forKey: "kb.hotmic.at") }
        else { store?.removeObject(forKey: "kb.hotmic.at") }
    }

    /// 麦克风现在热着吗（键盘据此决定「发命令」还是「跳过去」）。
    /// - Parameter maxAge: 超过这个秒数就当它已经死了。**宿主每次心跳会刷新它。**
    static func hotMicReady(maxAge: TimeInterval = 8) -> Bool {
        guard let t = store?.object(forKey: "kb.hotmic.at") as? Double else { return false }
        return Date().timeIntervalSince1970 - t <= maxAge
    }

    /// 🚨🚨 **默认保质期拉到 7 天**（2026-08-31）。
    ///    上一版 30 分钟一过就当"不知道"，然后落桌面 —— 而落桌面是他明确否掉的。
    ///    他 95% 在微信里：**一个学到过的来源，哪怕旧，也远好过不回去。**
    ///    （原来那句"沿用旧值比落桌面更糟"的前提就是"落桌面可接受"，而那个前提是错的。）
    static func sourceBundle(maxAge: TimeInterval = 7 * 24 * 3600) -> String {
        guard let b = store?.string(forKey: "kb.src.bundle"), !b.isEmpty,
              let at = store?.object(forKey: "kb.src.at") as? Double else { return "" }
        return Date().timeIntervalSince1970 - at <= maxAge ? b : ""
    }

    static func clearLevels() {
        store?.removeObject(forKey: K.levels)
        // 🚨 整段峰值跟波形一起清 —— **两个键必须同一个出口清**，
        //    分开清早晚漏一个，那时读到的是上一轮的峰值。
        store?.removeObject(forKey: K.spanPeak)
    }

    private static let noteCmd = "com.kevin.transless.kb.cmd" as CFString
    private static let noteRes = "com.kevin.transless.kb.res" as CFString

    // ------------------------------------------------------------ 主 App 侧

    /// 主 App 还活着吗（键盘用这个判断能不能录）。
    ///
    /// 🚨 这条**会失败**，而且必须会失败：App 被系统回收、用户没开过开关、
    ///    entitlement 没配好，三种情况都让它返 false。
    ///    如果它恒为真，键盘就会在一个死掉的宿主上按麦克风然后干等。
    static var hostAlive: Bool {
        if let f = fakeHost { return f == "alive" }
        guard let s = store else { return false }
        // 🚨 判断本身在 `KbProtocol`（纯函数、有六个坏实现的自测）。
        //    这里只负责取数 —— **别在这儿再写一遍判断**，
        //    写两遍就等于测的那份和跑的那份是两码事。
        return KbProtocol.hostAlive(beatAt: s.double(forKey: K.beat),
                                    now: Date().timeIntervalSince1970,
                                    staleAfter: staleAfter)
    }

    /// 主 App 报一次「我还在」。
    static func beat() {
        store?.set(Date().timeIntervalSince1970, forKey: K.beat)
    }

    /// 主 App 停止托管时把心跳抹掉 —— 否则键盘会在接下来的
    /// `staleAfter` 秒里以为宿主还在。
    static func clearBeat() {
        store?.removeObject(forKey: K.beat)
    }

    // ------------------------------------------------------------ 命令（键盘 → 主 App）

    /// 键盘下一条命令。返回这条命令的序号，键盘拿它去认结果。
    ///
    /// 🚨🚨 `args` 里必须带上**语气 / 模式 / 目标语言**，不能让主 App 去读自己的设置。
    ///    键盘扩展和容器 App 各有各的 `UserDefaults.standard`（扩展有独立的偏好域），
    ///    两边的值本来就不是同一份。主 App 读自己的那份，就会出现
    ///    「用户在键盘里选了正式语气，出来的却是随意」——
    ///    而键盘上那个按钮还亮着，看起来完全生效了。这类错最难查。
    @discardableResult
    static func send(_ action: String, args: [String: String] = [:]) -> Int {
        guard let s = store else { return -1 }
        let seq = s.integer(forKey: K.cmdSeq) + 1
        s.set(seq, forKey: K.cmdSeq)
        s.set(action, forKey: K.cmdAct)
        let json = (try? JSONSerialization.data(withJSONObject: args))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        s.set(json, forKey: K.cmdArg)
        s.set(Date().timeIntervalSince1970, forKey: K.cmdAt)
        poke(noteCmd)
        return seq
    }

    /// 当前命令序号。
    ///
    /// 🚨 宿主刚开待机时要把 `lastSeen` 对齐到这里，否则会把**上一次待机期间
    ///    残留的那条命令**当成新的立刻执行一遍 —— 表现就是「一打开待机它自己
    ///    就开始录音」。这类错只在第二次使用时才出现，第一次测永远测不到。
    static var currentSeq: Int { store?.integer(forKey: K.cmdSeq) ?? 0 }

    /// 主 App 读命令。返回 nil 表示「没有新的」。
    ///
    /// 🚨 靠**序号**去重，不靠时间戳。时间戳判「新不新」要选个阈值，
    ///    而进程刚被唤醒时时钟差一点就会把旧命令当新的重放一遍。
    ///    序号只增，`lastSeen` 一比就完了。
    static func takeCommand(after lastSeen: Int)
        -> (seq: Int, action: String, args: [String: String])? {
        guard let s = store else { return nil }
        let seq = s.integer(forKey: K.cmdSeq)
        guard KbProtocol.isNewCommand(seq: seq, lastSeen: lastSeen),
              let act = s.string(forKey: K.cmdAct) else {
            return nil
        }
        var args: [String: String] = [:]
        if let raw = s.string(forKey: K.cmdArg),
           let d = raw.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] {
            args = o
        }
        return (seq, act, args)
    }

    // ------------------------------------------------------------ 结果（主 App → 键盘）

    /// 主 App 回一条结果。`kind` = partial / text / error。
    static func reply(seq: Int, kind: String, body: String) {
        guard let s = store else { return }
        s.set(seq, forKey: K.resSeq)
        s.set(kind, forKey: K.resKind)
        s.set(body, forKey: K.resBody)
        s.set(Date().timeIntervalSince1970, forKey: K.resAt)
        poke(noteRes)
    }

    /// 键盘读结果。只认序号对得上、且比上次读到的更新的那条。
    static func takeResult(seq: Int, after lastAt: TimeInterval)
        -> (kind: String, body: String, at: TimeInterval)? {
        guard let s = store else { return nil }
        let at = s.double(forKey: K.resAt)
        guard KbProtocol.acceptResult(resSeq: s.integer(forKey: K.resSeq),
                                      mySeq: seq, resAt: at, lastAt: lastAt),
              let kind = s.string(forKey: K.resKind),
              let body = s.string(forKey: K.resBody) else { return nil }
        return (kind, body, at)
    }

    // ------------------------------------------------------------ Darwin 通知

    private static func poke(_ name: CFString) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name), nil, nil, true)
    }

    /// 订阅命令通知（主 App 用）。
    static func observeCommands(_ token: UnsafeRawPointer,
                                _ cb: @escaping CFNotificationCallback) {
        observe(token, noteCmd, cb)
    }

    /// 订阅结果通知（键盘用）。
    static func observeResults(_ token: UnsafeRawPointer,
                               _ cb: @escaping CFNotificationCallback) {
        observe(token, noteRes, cb)
    }

    private static func observe(_ token: UnsafeRawPointer, _ name: CFString,
                                _ cb: @escaping CFNotificationCallback) {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), token, cb,
            name, nil, .deliverImmediately)
    }

    static func stopObserving(_ token: UnsafeRawPointer) {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), token)
    }
}
