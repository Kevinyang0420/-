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

    /// 自检结果落在 App Group 容器里的文件名 ——
    /// `devicectl device copy from --domain-type appGroupDataContainer` 拉它。
    static let selfTestFile = "selftest.txt"

    /// 往共享容器写一行结果。**写文件不是写 UserDefaults** ——
    /// `copy from` 拉的是文件，拉不到偏好。
    static func writeSelfTest(_ text: String) {
        guard let dir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group) else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        try? (stamp + "  " + text + "\n")
            .write(to: dir.appendingPathComponent(selfTestFile),
                   atomically: true, encoding: .utf8)
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
    }

    static func levels() -> [Float] {
        guard let s = store else { return [] }
        return (s.array(forKey: K.levels) as? [Double] ?? []).map { Float($0) }
    }

    /// 🚨 收工必须清。不清的话下次一按麦克风，波形会**先闪一下上一轮的形状**
    ///    —— 那正好是「看起来在听」的假象，跟这条波形要解决的问题反着来。
    static func clearLevels() { store?.removeObject(forKey: K.levels) }

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
