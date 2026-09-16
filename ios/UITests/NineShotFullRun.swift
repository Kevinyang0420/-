import XCTest

/// 0 09-15 派活：把 App Store 审核录屏九镜串成**一条能一次跑完**的 UITest。
///
/// 🚨🚨 这个文件是**准备件，不在真机上跑**——0 说了「你现在可以做的（不碰他
///    手机，只准备）」。写完只在模拟器上编译+跑一遍确认逻辑通（模拟器摸不到
///    真实系统设置的"完全访问"开关变化、也没有真人声音，那两段在模拟器上
///    天然走不完整，这是已知边界，不是这条测试的缺陷）。**真正在他手机上
///    跑这条的人是 0**，不是我。
///
/// 对照 `compliance/_录屏对照卡_20260915.md` 那张表，九镜逐一对应：
///   1 冷启动 / 2 麦克风权限 / 3 系统设置加键盘 / 4 点麦录一句(需要真人声)
///   5 三档语气各说一句(需要真人声) / 6 关完全访问后仍能打字 / 7 登录
///   8 注销账号 / 9 订阅页
///
/// 🚨 4/5 两镜要**真人开口说话**，UITest 摸不到麦克风也编不出声音——
///    这条测试做的是**自动化那部分**（点麦克风/等/点停/切档），
///    中间留出等待窗（`shot4WaitSecs`/`shot5WaitSecs`，环境变量可调），
///    **窗口期间由跑这条测试的人（0）对着手机说话**，跟 Kevin 原计划
///    「他只说约 20 秒」的口径一致——不是这条测试自己能闭环的部分。
///
/// 🚨 第 8 镜（注销账号）默认**只走到确认弹窗为止，不真的点"确认删除"**——
///    对照卡自己写着「录完必须撤销（否则 7 天后账号真没）」，这条审核账号
///    要留着反复排练用。真正录像那一次如果要拍到"看到结果"，
///    把 `TRANSLESS_NINESHOT_REAL_DELETE=1` 传进去才会真点到底；
///    默认（不传）在确认弹窗那一步就停，安全。
///
/// 🚨🚨🚨 0 09-15 首次真机跑出来的教训（第 N 次假绿，这次是不该再犯的那种）：
///    **第 4/5/9 镜原来失败时只 `NSLog` 一句，没有任何断言** —— 于是关键镜头
///    （说中文出英文）整段没发生，测试终态却是 `passed`。**一条报"过"的测试，
///    如果它连正在发生什么都不判断，比没有测试更糟：它让人以为录成了。**
///    现在这三镜（连同第 7 镜的登录）都改成硬断言，`continueAfterFailure = true`
///    保留 —— 断言失败不会中止整条测试（后面的镜头还是会尝试跑，方便一次性
///    看清哪几镜坏），但**只要有一镜真断了，测试终态必须是 FAILED**。
///    反向控制：把任何一镜的定位串故意改错，模拟器上重跑一次，
///    这条测试必须变成 `** TEST FAILED **`——不做这一步，不知道断言是不是真的挂上了。
final class NineShotFullRun: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    /// 🚨 只做一件事：把【允许完全访问】开回去。
    ///    九镜跑到一半出任何意外，都能用它在一分钟内把 Kevin 的键盘救回来，
    ///    不用再跑一遍四分钟的全流程。
    /// 🚨 只跑第 4 镜那一段（开键盘 → 点麦克风 → 等 → 点停），约 60 秒。
    ///    用途：查「手机到底收不收得到声音」这类问题时，不用每次都烧 4 分钟跑全套九镜。
    ///    判据看 `kb.trail` 里的「这一段电平 peak」，**不看「第一帧有声」**——
    ///    后者 09-16 实测会被一个恒定 0.1 的伪迹喂饱（3 毫秒就报有声）。
    func testMicLevelProbeOnly() {
        let notes = XCUIApplication(bundleIdentifier: "com.apple.mobilenotes")
        notes.launch()
        XCTAssertTrue(notes.wait(for: .runningForeground, timeout: 15), "快测：备忘录没起来")
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(openNewNoteWithKeyboard(notes), "快测：输入框没找到")
        XCTAssertTrue(switchToTranslessKeyboard(notes), "快测：没切到 Transless 键盘")
        let host = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        host.activate(); Thread.sleep(forTimeInterval: 1.5)
        notes.activate()
        XCTAssertTrue(notes.wait(for: .runningForeground, timeout: 8), "快测：切不回备忘录")
        let mic = notes.buttons["transless.mic"]
        XCTAssertTrue(mic.waitForExistence(timeout: 5), "快测：找不到麦克风")
        mic.tap()
        NSLog("NSFR 快测：已点麦克风，等录音态")
        _ = waitForMicPhase(notes, "phase.listening", timeout: 6)
        NSLog("NSFR 快测：进录音态，等 14 秒")
        Thread.sleep(forTimeInterval: 14)
        if notes.buttons["transless.mic"].exists { notes.buttons["transless.mic"].tap() }
        NSLog("NSFR 快测：已点停，等出稿")
        Thread.sleep(forTimeInterval: 12)
        NSLog("NSFR 快测完")
    }

    /// 🚨 九镜里第 8 镜把删号**真的演完整**（进 7 天冷静期）之后，用这条把它撤销。
    ///    判据是 `del.hint` 变成「已撤销」那句，不是「我点了 del.cancel」。
    ///    🚨 录屏里不出现这一步 —— 它单独跑，免得审核员以为删号是假的。
    func testUndoPendingDelete() {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "account"
        app.launch(); Thread.sleep(forTimeInterval: 2.0)
        let del = app.buttons["account.delete"]
        XCTAssertTrue(del.waitForExistence(timeout: 8), "撤销：进不去账户页")
        del.tap(); Thread.sleep(forTimeInterval: 1.5)
        let cancel = app.buttons["del.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8), "撤销：找不到 del.cancel")
        cancel.tap()
        var hint = ""
        for _ in 0..<25 {
            Thread.sleep(forTimeInterval: 1.0)
            hint = app.staticTexts["del.hint"].label
            if hint.contains("撤销") || hint.contains("不会被删除") { break }
        }
        NSLog("NSFR 撤销删号：del.hint = 「%@」", hint)
        XCTAssertTrue(hint.contains("撤销") || hint.contains("不会被删除"),
                      "撤销失败 —— 🚨 审核账号还在 7 天冷静期里，必须处理")
    }

    func testRestoreFullAccessOnly() {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch(); Thread.sleep(forTimeInterval: 1.5)
        restoreFullAccess(settings)
    }

    private func shotLog(_ n: Int, _ what: String) {
        NSLog("NSFR ===== 第%d镜：%@ =====", n, what)
    }

    /// 定位失败时把**看得到的元素全部**打出来——0 那次报「反复 Checking existence」
    /// 却没有任何一条日志说清楚屏幕上到底有什么，下一次不能再靠猜。
    ///
    /// 🚨 模拟器实测踩到的坑：`allElementsBoundByIndex.map { $0.label }` 在 UI
    ///    还没稳定（比如切键盘失败、系统弹层刚收起）时会各元素分别按下标去取
    ///    ——期间树一变就是 `Failed to get matching snapshot: No matches found
    ///    for Element at index N`，**这条失败是诊断代码自己的时序问题，
    ///    跟被测对象是否正常没关系**，却会把测试拖成 FAILED，等于诊断件本身
    ///    制造了假故障。先等一拍让树稳定，再一次性拿快照，别逐元素分别查。
    /// 🚨🚨🚨 0 09-15 抓到的真事故：这个 dump 把整屏文字原样打进了 `NSLog`，
    ///    进了 xcodebuild 日志和 `.xcresult`——今晚已经借着别的探针泄过一次
    ///    （状态栏转储带出了 Kevin 联系人的真名和聊天片段）。这些转储最后可能被
    ///    打包发苹果或贴进文档，**"当时屏幕上显示过"不等于"现在没存着"**。
    ///    → 只放行我们自己的元素（identifier 以 "transless." 开头，或
    ///    label 以 "Transless" 开头——这两条正是这个 App 自己控件的命名规矩，
    ///    见 `transless.mic`/`account.delete`/`tone.*`），其余一律打成
    ///    `<已隐去 n 个非本App元素>`，不打原文、连数目带类型都不细分（数目本身
    ///    不构成隐私，但没必要多给信息）。
    private func dumpElements(_ app: XCUIApplication, _ tag: String) {
        Thread.sleep(forTimeInterval: 0.5)
        func safeLabel(_ e: XCUIElement) -> String? {
            e.identifier.hasPrefix("transless.") || e.label.hasPrefix("Transless")
                ? e.label : nil
        }
        func summarize(_ all: [XCUIElement]) -> String {
            let ours = all.compactMap(safeLabel)
            let hidden = all.count - ours.count
            var parts = ours
            if hidden > 0 { parts.append("<已隐去 " + String(hidden) + " 个非本App元素>") }
            return parts.joined(separator: " | ")
        }
        let btns = Array(app.buttons.allElementsBoundByIndex.prefix(30)).filter { $0.exists }
        let cells = Array(app.cells.allElementsBoundByIndex.prefix(30)).filter { $0.exists }
        let texts = Array(app.staticTexts.allElementsBoundByIndex.prefix(30)).filter { $0.exists }
        NSLog("NSFR [%@] buttons=%@", tag, summarize(btns))
        NSLog("NSFR [%@] cells=%@", tag, summarize(cells))
        NSLog("NSFR [%@] staticTexts=%@", tag, summarize(texts))
        // 🚨🚨🚨 0 09-15 第七遍之后纠回来的：这个数**不是"键盘在不在"的可靠判据**——
        //    它看不见别的进程渲染的键盘（真机上 Kevin 当前选中的是「Typeless」，
        //    键盘明明在屏幕上这个数也恒为 0）。留着当诊断参考可以，
        //    但别再拿它当门（本文件已经不这么用了），标题就写清楚这层局限。
        NSLog("NSFR [%@] keyboards.count=%d（🚨看不见别的进程渲染的键盘，别当判据用）",
              tag, app.keyboards.count)
    }

    func testNineShotFullRun() throws {
        let shot4Wait = Double(ProcessInfo.processInfo.environment["TRANSLESS_SHOT4_WAIT"] ?? "8") ?? 8
        let shot5Wait = Double(ProcessInfo.processInfo.environment["TRANSLESS_SHOT5_WAIT"] ?? "6") ?? 6
        let realDelete = ProcessInfo.processInfo.environment["TRANSLESS_NINESHOT_REAL_DELETE"] == "1"

        // 🚨🚨 0 09-15 从真机日志找到的第二个真因：t=72.49s 一条通知横幅
        //    （identifier `NotificationShortLookView`）弹出来，正好盖住第4镜
        //    长按切键盘那一下的命中区域，把 XCUITest 的元素查询打断——
        //    两次"没切到"都卡在同一处，不只是定位写法的问题。
        //    这条监控**全程挂着**（不像麦克风权限那个只在第2镜局部挂），
        //    命中就把横幅划走，不打开它（划开而不是点开，点开会把他导去别的App）。
        let bannerMonitor = addUIInterruptionMonitor(withDescription: "系统通知横幅") { element in
            guard element.elementType != .alert else { return false }   // 交给别的 monitor 管
            NSLog("NSFR 拦到系统横幅，划走（不读内容，隐私）")
            element.swipeUp()
            return true
        }
        defer { removeUIInterruptionMonitor(bannerMonitor) }

        // ---- 第 1 镜：主屏点开 Transless（冷启动） ----
        shotLog(1, "主屏点开 Transless")
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "第1镜：App没起来")
        Thread.sleep(forTimeInterval: 2.0)
        NSLog("NSFR 第1镜完")

        // ---- 第 2 镜：给权限（只有一个弹窗：麦克风） ----
        shotLog(2, "给麦克风权限")
        app.terminate(); Thread.sleep(forTimeInterval: 1.0)
        let app2 = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app2.launchEnvironment["TRANSLESS_PAGE"] = "setup"
        let monitor = addUIInterruptionMonitor(withDescription: "麦克风权限弹窗") { alert in
            NSLog("NSFR 第2镜：系统弹窗文案=%@", alert.label)
            for label in ["好", "OK", "允许", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap(); return true
            }
            return false
        }
        app2.launch()
        let micRow = app2.staticTexts["允许录音"]
        if micRow.waitForExistence(timeout: 8) {
            micRow.tap()
            for _ in 0..<6 { Thread.sleep(forTimeInterval: 0.5); _ = app2.staticTexts.count }
        } else {
            NSLog("NSFR 🚨 第2镜：引导页第3步(允许录音)没找到——手动核实一下这一屏")
        }
        removeUIInterruptionMonitor(monitor)
        NSLog("NSFR 第2镜完")

        // ---- 第 3 镜：系统设置加键盘 + 打开完全访问 ----
        shotLog(3, "系统设置加键盘 + 打开完全访问")
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        navigateToKeyboardsList(settings)
        if !settings.cells.staticTexts["Transless"].waitForExistence(timeout: 4) {
            addTranslessKeyboard(settings)
        } else {
            NSLog("NSFR 第3镜：已装列表里已经有Transless了")
        }
        openFullAccessToggleAndEnable(settings)
        NSLog("NSFR 第3镜完")

        // ---- 第 4 镜：点麦录一句、再点停（需要真人声）----
        shotLog(4, "点麦录一句、再点停（真机上这段等真人说话，模拟器上只等空档）")
        // 🚨🚨🚨 0 09-15 第二轮真机反馈：换"信息"当宿主是错的——真因不是"没点输入框"
        //    这么简单，是**它还停在会话列表页，从没真的进到某一条会话里面**
        //    （`cells` 数量对得上列表行数，`keyboards.count` 恒 0）。列表页上点什么
        //    都不会弹键盘，先进列表再进会话再点输入框，多一整层不确定，而这一层
        //    正是三遍都没跨过去的地方。改用"备忘录"：`新建备忘录` 一步到位，
        //    输入框立刻聚焦、键盘立刻弹出，没有"先选中哪一条"这层。
        //    bundle id `com.apple.mobilenotes`。这也顺带避免读到他的真实聊天内容——
        //    新建的笔记是空的。
        // 🚨🚨🚨 0 09-15 第八遍真机之后纠回来的：这里原来先 `app2.terminate()`
        //    把主 App 杀掉，再启备忘录——**这一杀把演示逼进了最慢、最容易出错的
        //    那条路**（主 App 死→按麦克风走跳转→冷启动→架引擎，好几秒），而这
        //    正是今晚修 P0 的那条路径（主 App 被杀后的第一次按）。真机演示要的是
        //    "宿主活着、引擎架着"那条快路径，所以**不再主动杀主 App**——
        //    直接启备忘录，iOS 自己会把前一个 App 切到后台（不等于杀掉）。
        //
        // 🚨🚨🚨 0 09-16 算出来的：早前这里在切备忘录**之前**就把 Transless
        //    拉回前台刷新一次——但切键盘那一步（长按 3 次 + 等列表 + 等键盘）
        //    实测要花 ~21 秒，而 `KbBridge.hostArmed(maxAge: 12)` 的新鲜期只有
        //    12 秒。**刷新完到真正按麦克风之间隔的是切键盘那一大段耗时**，
        //    等按下去时信号早过期了——第十四遍真机十四遍全部撞在这（00:11:37
        //    刷新 → 00:11:58 按麦克风，差 21 秒 > 12 秒）。
        //    → 顺序倒过来：**先把慢的切键盘做完，刷新动作挪到最后、紧贴在
        //    按麦克风前面**，让"刷新"和"按下"之间的耗时降到几乎为零。
        //    这条不改产品代码，只是让测试别踩在这个过期窗口上——真实用户
        //    也只在"上次选中 Transless 键盘"时付一次切键盘的代价，之后每次
        //    用键盘都不用重切，所以把这个代价挪到"刷新"前面才是测试该照的
        //    真实节奏，不是作弊。
        let notes = XCUIApplication(bundleIdentifier: "com.apple.mobilenotes")
        notes.launch()
        XCTAssertTrue(notes.wait(for: .runningForeground, timeout: 15), "第4镜：备忘录App没起来")
        Thread.sleep(forTimeInterval: 1.5)
        let openedKb = openNewNoteWithKeyboard(notes)
        if !openedKb { dumpElements(notes, "第4镜-输入框没找到") }
        // 🚨 这条断言是这次的核心教训：**前置条件要有断言，不能直接去操作依赖它的东西。**
        //    🚨🚨🚨 0 09-15 第七遍之后纠回来的：断言原文本来是"键盘根本没弹出来"，
        //    判据挂在 `notes.keyboards.element`——**这个判据本身没验证过就拿来当门**。
        //    真机上 Kevin 当前选中的键盘是「Typeless」（另一个 App 的扩展进程），
        //    XCUITest 的 `keyboards` 查询看不到**别的进程**渲染的键盘 UI，
        //    所以哪怕键盘明明在屏幕上，这个数恒为 0——七遍里至少四遍死在这条
        //    从没被验证过的判据上，不是死在"键盘真的没弹出来"。
        //    → 前置条件改判**我们自己够得着的东西**：输入框本身找到了、点了。
        //    键盘（不管是谁的）弹没弹、Transless 在不在，交给下面
        //    `switchToTranslessKeyboard` 里`transless.mic`那条去判——
        //    那条读的是键盘扩展渲染进宿主视图树里的**我们自己的控件**，
        //    不受"扩展属于哪个进程"影响，这也是它在本会话别的地方一直有效的原因。
        XCTAssertTrue(openedKb, "第4镜：输入框没找到或者点不进去")
        let switched4 = openedKb && switchToTranslessKeyboard(notes)
        if !switched4 { dumpElements(notes, "第4镜-切键盘失败") }
        // 🚨🚨 硬断言——0 09-15 撞的假绿正是这里原来只 NSLog 不断言。
        //    `continueAfterFailure=true` 保着，断了也会往下跑完剩下几镜方便一次看全。
        XCTAssertTrue(switched4, "第4镜：三次长按都没切到Transless键盘，麦克风一次都没点到")
        if switched4 {
            // 🚨🚨🚨 0 09-16：切键盘这段慢活干完了，**这里才做"刷新"**——
            //    紧贴在按麦克风前面，让 `hostArmed(maxAge: 12)` 那个新鲜期
            //    覆盖住按下去的那一刻，不再被切键盘的 21 秒耗光。
            //    `app2.activate()` 会把 Transless 真的切到前台（不是后台信号），
            //    这样它自己的 `didBecomeActiveNotification` 链才会真的跑一遍、
            //    把"架着"时间戳写新；随后立刻切回备忘录——**不重新切键盘**，
            //    因为 Transless 已经是这个输入框选中的键盘，短暂背景一下不会
            //    丢失这个选择（真机上验证：`transless.mic` 应该原地还在）。
            app2.activate()
            NSLog("NSFR 第4镜：切完键盘 → 刷新主App前台信号，等1.5秒给它写新时间戳")
            Thread.sleep(forTimeInterval: 1.5)
            notes.activate()
            XCTAssertTrue(notes.wait(for: .runningForeground, timeout: 8),
                          "第4镜：刷新完切回备忘录没成功")
            let micStillThere = notes.buttons["transless.mic"].waitForExistence(timeout: 4)
            if !micStillThere {
                // 🚨 这不该断言死——如果真机上证明"背景一下键盘就丢了"，
                //    这行日志就是证据本身，留给下一轮判要不要在这里补一次
                //    `switchToTranslessKeyboard`，别悄悄吞掉这个信号。
                NSLog("NSFR 🚨 第4镜：刷新+切回备忘录之后 transless.mic 消失了——"
                      + "键盘选择没能扛过这次短暂背景，这是新发现，不是本来就有的")
                dumpElements(notes, "第4镜-刷新后键盘丢失")
            }
            let micBtn = notes.buttons["transless.mic"]
            XCTAssertTrue(micBtn.waitForExistence(timeout: 4), "第4镜：切到键盘了但找不到麦克风按钮")
            if micBtn.exists {
                micBtn.tap()
                NSLog("NSFR 第4镜：已点麦克风，等待真的进入录音态")
                // 🚨🚨🚨 0 09-15 第八遍纠回来的另一条：这里原来点完麦克风就立刻
                //    `sleep(shot4Wait)` 硬等，而 0 的驱动脚本看到"已点麦克风"这行
                //    日志就放音频——**两边对不上**：录音引擎真正起来、宿主真的在
                //    听之前有几秒延迟，音频有可能放给一台还没开始录的手机。
                //    现在等一个**真信号**：`transless.mic` 的 `accessibilityValue`
                //    变成 "phase.listening"（`KeyboardViewController.setPhase`
                //    新加的，跟 `accessibilityValue` 当状态载体是这个文件已有的
                //    规矩，见语言按钮/历史行）。这行日志之后才是真的在录，
                //    0 的驱动脚本应该等**这一行**再放音频，不是等"已点麦克风"。
                let becameListening = waitForMicPhase(notes, "phase.listening", timeout: 6)
                if becameListening {
                    NSLog("NSFR 第4镜：✅ 确认进入录音态(phase=listening)，现在开始才是真的在录")
                    // 🚨🚨🚨 Kevin 09-16 12:3x 一句点破的根因：
                    //    「你每次放声音，和点录音的时间不同步，导致没录上。」
                    //    驱动原来盯的是【已点麦克风】那一行 —— 那是**点下去**的时刻，
                    //    而真正开录还在 `waitForMicPhase` 之后，中间可能差好几秒。
                    //    → 专门吐一个只在【确认进了录音态】之后才出现的标记，
                    //      驱动只认它，且认到就立刻放、不再额外等。
                    NSLog("NSFR READY-AUDIO")
                } else {
                    NSLog("NSFR 🚨 第4镜：等了6秒也没见 phase 变成 listening——"
                          + "可能宿主没活着走了跳转路，这里不断言（真机上跳转路本身合法，"
                          + "只是慢），但接下来的等待窗口没有一个可靠的「真的在录」锚点了")
                }
                NSLog("NSFR 第4镜：等 %.0f 秒（这段真机上留给真人说话）", shot4Wait)
                Thread.sleep(forTimeInterval: shot4Wait)
                if notes.buttons["transless.mic"].exists { notes.buttons["transless.mic"].tap() }
                NSLog("NSFR 第4镜：已点停，等出稿")
                // 🚨🚨🚨 0 09-16：这里原来只是 `sleep(5)` 然后就「第4镜完」——
                //    **没有任何一条判据检查文字有没有落进输入框**。
                //    而回苹果那份答复稿第 3 项写的就是「点一下说、再点一下停，
                //    文字落进输入框」—— 整个演示的核心声称，却是整条测试里唯一没人查的。
                //    第 25 遍的录屏里备忘录正文从头到尾是空的，history 却有结果，
                //    两边对不上都没人发现。
                // 🚨 判据挂在**备忘录自己的输入框**上，不是 history（那是我们自己写的，同源）。
                let body = notes.textViews.firstMatch
                var landed = ""
                for _ in 0..<40 {
                    Thread.sleep(forTimeInterval: 1.0)
                    landed = (body.value as? String) ?? ""
                    if !landed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { break }
                }
                NSLog("NSFR 第4镜：输入框里现在有 %d 个字", landed.count)
                XCTAssertFalse(landed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               "第4镜：点停后等了 40 秒，**文字没有落进输入框** —— "
                               + "这正是答复稿第 3 项声称的那件事")
            }
        }
        NSLog("NSFR 第4镜完")

        // ---- 第 5 镜：三个语气档各说同一句（需要真人声）----
        shotLog(5, "三个语气档各说一句")
        // 🚨🚨 0 09-15 撞的另一处假绿：`buttons["casual"]` 这几个键名是
        //    `Prompts.all` 的**内部 key**，从没设过 `accessibilityIdentifier`——
        //    能查到的只有本地化中文标题（"随意"/"工作"/"邮件"）。
        //    已在 `KeyboardViewController.swift` 补上 `tone.<key>` 的稳定 identifier
        //    （跟 `transless.mic`/`account.delete` 同一个规矩），这里跟着改。
        // 🚨🚨 0 09-16 第十八遍挖出的真根因：语气按钮只在【翻译档】才显示
        //    （`KeyboardViewController.swift` 里 `toneRow?.isHidden = !isTranslate`）。
        //    第 4 镜录完之后面板不在翻译档，于是三个语气档全找不到，
        //    而日志把它读成了「键盘退回系统键盘」—— 错得离谱：
        //    `switchToTranslessKeyboard` 其实第一句就找到了 `transless.mic`。
        var inTranslate = false
        for n in 1...3 {
            dismissSystemAlerts("第5镜切档前")
            let tabT = notes.buttons["kb.tab.translate"]
            guard tabT.waitForExistence(timeout: 6) else {
                NSLog("NSFR 第5镜：没找到 kb.tab.translate（老包？）"); break
            }
            tabT.tap(); Thread.sleep(forTimeInterval: 1.0)
            // 🚨 反向校验：档真的切了的唯一证据是【语气按钮出现】。
            //    只报「我点了」等于没查 —— 第 25 遍就是这么结结实实骗过我一次的。
            if notes.buttons["tone.casual"].waitForExistence(timeout: 5) {
                inTranslate = true
                NSLog("NSFR 第5镜：第%d 次点翻译档 → 语气按钮出来了（这才算切成）", n)
                break
            }
            NSLog("NSFR 第5镜：第%d 次点了翻译档，但语气按钮没出来 —— 弹层吃掉了？重试", n)
        }
        XCTAssertTrue(inTranslate, "第5镜：三次都没切进翻译档（语气按钮始终不出现）")
        for tone in ["casual", "work", "email"] {
            // 🚨🚨 模拟器实测踩到的坑：第一档（casual）找得到，第二档（work）就找
            //    不到了——不是定位错了（跟 casual 用的是同一套 "tone."+key 写法），
            //    是**时序**：上一档停麦克风之后要等后端出稿/回收，键盘从
            //    "处理中" 回到可以再选语气档的状态需要的时间，明显比固定的
            //    4 秒长（真机走真实网络更可能久）。改成**轮询等它回来**
            //    （最长 15 秒），而不是等一个写死的固定时长就假定它已经好了。
            var toneBtn = notes.buttons["tone." + tone]
            var found = toneBtn.waitForExistence(timeout: 15)
            if !found {
                // 再给键盘扩展一个刷新的机会：有时候需要一次多余的查询才会重新出现。
                Thread.sleep(forTimeInterval: 1.0)
                toneBtn = notes.buttons["tone." + tone]
                found = toneBtn.waitForExistence(timeout: 5)
            }
            // 🚨🚨🚨 0 09-15 第二轮真机反馈之后又核出一层：光加长等待治不好——
            //    第4镜自己那次 `keyboards.count` 检查在这一轮跑出了 0（键盘一度
            //    真的不在了），但紧接着 casual 那档又找到了键盘，work/email 又找
            //    不到——**键盘在录完一段之后会整个消失/回退成系统键盘**，不是"还没
            //    刷新出来"。原来这里只会傻等同一个（已经不存在的）Transless 键盘
            //    重新出现，等不到就是等不到。真正要做的是：等不到就当它已经退回
            //    系统键盘了，**照第4镜那一套流程再切回来一次**。
            if !found {
                NSLog("NSFR 第5镜[%@]：等不到语气按钮，怀疑键盘已经回退成系统键盘，尝试重新切回Transless", tone)
                if switchToTranslessKeyboard(notes) {
                    toneBtn = notes.buttons["tone." + tone]
                    found = toneBtn.waitForExistence(timeout: 6)
                }
            }
            if !found { dumpElements(notes, "第5镜-" + tone + "找不到") }
            XCTAssertTrue(found, "第5镜：语气按钮 tone." + tone + " 没找到（等了最多20秒）")
            guard found else { continue }
            toneBtn.tap(); Thread.sleep(forTimeInterval: 0.5)
            let micBtn = notes.buttons["transless.mic"]
            XCTAssertTrue(micBtn.waitForExistence(timeout: 4), "第5镜[" + tone + "]：找不到麦克风按钮")
            guard micBtn.exists else { continue }
            // 🚨🚨 0 09-16 12:2x：第 26 遍【九镜全过】，但 history 只多了 2 条，
            //    第 5 镜三次录音基本没出东西（一条还是空的）。两个原因，
            //    都是第 4 镜早就修过、而这里没跟上的：
            //    ① 点完麦克风**不等真进录音态**就开始数 13 秒 → 音频放给了还没开录的手机
            //    ② 三次录音**一条判据都没有** → 全空也照样报「第5镜完」
            //    📌 「九镜 passed」不等于「片子能看」—— 判据没覆盖到的地方就是盲区。
            let before = ((notes.textViews.firstMatch.value as? String) ?? "").count
            micBtn.tap()
            let rec5 = waitForMicPhase(notes, "phase.listening", timeout: 8)
            NSLog("NSFR 第5镜[%@]：已点麦克风，真进录音态=%@，等 %.0f 秒",
                  tone, rec5 ? "是" : "否", shot5Wait)
            if rec5 { NSLog("NSFR READY-AUDIO") }   // 见第4镜那段注释：只在真进录音态后才吐
            Thread.sleep(forTimeInterval: shot5Wait)
            if notes.buttons["transless.mic"].exists { notes.buttons["transless.mic"].tap() }
            NSLog("NSFR 第5镜[%@]：已点停，等出稿", tone)
            var after = before
            for _ in 0..<30 {
                Thread.sleep(forTimeInterval: 1.0)
                after = ((notes.textViews.firstMatch.value as? String) ?? "").count
                if after > before { break }
            }
            NSLog("NSFR 第5镜[%@]：输入框 %d 字 → %d 字", tone, before, after)
            XCTAssertGreaterThan(after, before,
                                 "第5镜[" + tone + "]：录了一段、等了 30 秒，**输入框一个字都没多**")
        }
        NSLog("NSFR 第5镜完")

        // ---- 第 6 镜：关完全访问后仍能打字 ----
        shotLog(6, "关完全访问后仍能打字")
        settings.activate(); Thread.sleep(forTimeInterval: 1.0)
        disableFullAccess(settings)
        notes.activate(); Thread.sleep(forTimeInterval: 2.5)
        let field = notes.textViews.firstMatch
        let fieldFound = field.waitForExistence(timeout: 10)
        if !fieldFound { dumpElements(notes, "第6镜-输入框没找到") }
        if fieldFound {
            field.tap()
            // 🚨🚨🚨 0 09-15 抓到的真事故：这条断言原来把"读回来的整段文字"直接拼进了
            //    失败消息——而 `field` 定位错了会读到别的控件（上一轮就读到了一条
            //    运营商短信的完整正文 + 手机号），断言消息又会进 xcodebuild 日志和
            //    `.xcresult`。**不许把屏幕读回来的内容原样打进任何日志/断言消息**，
            //    要证明"打进去了"，比我们自己写下去的那个串在不在、或者长度对不对，
            //    不比"读回来到底是什么"。
            let marker = "TRANSLESS_SHOT6_" + String(Int(Date().timeIntervalSince1970))
            field.typeText(marker)
            let typed = (field.value as? String) ?? ""
            let ok = typed.contains(marker)
            XCTAssertTrue(ok, "第6镜：关完全访问后打字没有真的落进输入框（标记串未命中，"
                          + "读回长度=" + String(typed.count) + "）")
        } else {
            XCTFail("第6镜：找不到输入框")
        }
        Thread.sleep(forTimeInterval: 1.0)
        // 🚨 录完「关了也能打字」这一镜就立刻开回去，别拖到测试末尾——
        //    后面任何一镜崩了，都不能把他的键盘留在坏的状态。
        settings.activate(); Thread.sleep(forTimeInterval: 1.0)
        restoreFullAccess(settings)
        NSLog("NSFR 第6镜完")
        // 🚨 0 09-15："写完那一条笔记，跑完删掉"——这条笔记是我们自己新建+打了标记串
        //    的空白笔记，不含 Kevin 的内容，但用完清理掉，别留垃圾在他的备忘录里。
        deleteCurrentNote(notes)

        // ---- 第 7 镜：登录 ----
        shotLog(7, "登录审核账号")
        notes.terminate(); Thread.sleep(forTimeInterval: 1.0)
        let app3 = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app3.launchEnvironment["TRANSLESS_PAGE"] = "login"
        app3.launch()
        let emailField = app3.textFields.firstMatch
        var loggedIn = false
        if emailField.waitForExistence(timeout: 8) {
            emailField.tap()
            emailField.typeText("apple-review@transless.net")
            let sendBtn = app3.buttons["获取验证码"]
            if sendBtn.waitForExistence(timeout: 5) {
                sendBtn.tap()
                let codeField = app3.textFields.matching(
                    NSPredicate(format: "placeholderValue == %@", "6 位验证码")).firstMatch
                if codeField.waitForExistence(timeout: 15) {
                    codeField.tap()
                    codeField.typeText("583920")
                    let loginBtn = app3.buttons["登录"]
                    if loginBtn.waitForExistence(timeout: 5) { loginBtn.tap() }
                    // 🚨 0 09-15 点名：这镜原来**连失败都不报**。现在给它一个真正
                    //    只有登录态才成立的判据——登录按钮消失（复用 ReviewAccountShot
                    //    验过的同一条：跳登录页说明真的走完了）。
                    let loginGone = NSPredicate(format: "exists == false")
                    let exp = XCTNSPredicateExpectation(predicate: loginGone, object: loginBtn)
                    loggedIn = XCTWaiter.wait(for: [exp], timeout: 15) == .completed
                }
            }
        }
        if !loggedIn { dumpElements(app3, "第7镜-登录失败") }
        XCTAssertTrue(loggedIn, "第7镜：登录没走完（登录按钮15秒后仍在）")
        NSLog("NSFR 第7镜完")

        // ---- 第 8 镜：注销账号 ----
        shotLog(8, "注销账号")
        app3.terminate(); Thread.sleep(forTimeInterval: 1.0)
        let app4 = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app4.launchEnvironment["TRANSLESS_PAGE"] = "account"
        app4.launch()
        let delBtn = app4.buttons["account.delete"]
        let delFound = delBtn.waitForExistence(timeout: 8)
        if !delFound { dumpElements(app4, "第8镜-注销入口没找到") }
        // 🚨 这镜不强制断言——8 镜本身要求"不真的删到底"（账号要留着反复排练），
        //    找不到入口时多半是第7镜没登进去，第7镜的断言已经会把测试判红，
        //    这里再重复断言一次会掩盖真正的根因（同一件事两处判据，改一处漏一处）。
        if delFound {
            delBtn.tap()
            Thread.sleep(forTimeInterval: 1.5)
            NSLog("NSFR 第8镜：已点注销入口，走到确认这一步——%@",
                  realDelete ? "TRANSLESS_NINESHOT_REAL_DELETE=1，继续往下点到底"
                             : "默认不继续（账号要留着反复排练），停在这一屏")
            if realDelete {
                // 🚨🚨🚨 0 09-16 13:0x：答复稿第 1 项写着删号是「initiated **and
                //    confirmed** inside the app」并且录屏里看得到 —— 而这里原来
                //    **故意停在确认前不点**，等于拿一段没有这件事的录屏去支持那句话。
                //    那正是 09-15 冻结整份答复的同一类错。
                // ✅ 安全的做法（产品自己写明的）：确认后进入 **7 天冷静期**，
                //    同一屏上就有 `del.cancel` 可以撤销。所以镜头里把删号演完整，
                //    跑完再用 `testUndoPendingDelete` 撤销，审核账号原样留着。
                // 🚨 判据不是「我点了确认」，是 **del.hint 真的变成冷静期那句话**。
                // 🚨 0 09-16 13:3x 第 37 遍：hint 停在「验证码发出去了」——
                //    确认那一下没生效。原来只等 1.5 秒就去填码、填完不回读就点确认，
                //    三处都在「我做了」而不是「真成了」。照 ReviewAccountShot 验过的写法改。
                let send = app4.buttons["del.send"]
                XCTAssertTrue(send.waitForExistence(timeout: 6), "第8镜：找不到 del.send")
                send.tap()
                // ① 等服务端**真的回了**（hint 变成「验证码发出去了」）再往下走
                var sent = false
                for _ in 0..<20 {
                    Thread.sleep(forTimeInterval: 1.0)
                    if app4.staticTexts["del.hint"].label.contains("验证码") { sent = true; break }
                }
                NSLog("NSFR 第8镜：发码回执=%@", sent ? "到了" : "20 秒没等到")
                let code = app4.textFields["del.code"]
                XCTAssertTrue(code.waitForExistence(timeout: 6), "第8镜：找不到 del.code")
                code.tap(); Thread.sleep(forTimeInterval: 0.4)
                code.typeText("583920")
                // ② 回读验证码框 —— ReviewAccountShot 就栽过「键入被 splice 到别的框」
                let typed = (code.value as? String) ?? ""
                NSLog("NSFR 第8镜：验证码框读回=「%@」", typed)
                XCTAssertEqual(typed, "583920", "第8镜：验证码没打进 del.code，点确认没意义")
                // 🚨🚨 0 09-16 13:4x 第 38 遍：发码到了、验证码也确实填进去了、
                //    按钮也不是灰的 —— 可 hint 纹丝不动。因为**填完码软键盘还杵在那儿，
                //    正好盖住确认按钮**；XCUITest 按元素坐标点，元素在键盘底下也照点，
                //    点到的是键盘。`isEnabled` 真、`isHittable` 假。
                // 📌 「能点」和「点得到」是两件事 —— 判据要挂在后者上。
                let confirm = app4.buttons["del.confirm"]
                XCTAssertTrue(confirm.waitForExistence(timeout: 6), "第8镜：找不到 del.confirm")
                if !confirm.isHittable {
                    NSLog("NSFR 第8镜：确认按钮被挡住了（多半是软键盘），先收键盘")
                    if app4.keyboards.buttons["return"].exists {
                        app4.keyboards.buttons["return"].tap()
                    } else if app4.keyboards.buttons["换行"].exists {
                        app4.keyboards.buttons["换行"].tap()
                    } else {
                        app4.staticTexts["del.body"].tap()   // 点正文收键盘
                    }
                    Thread.sleep(forTimeInterval: 1.0)
                }
                NSLog("NSFR 第8镜：确认按钮 可点=%@ 点得到=%@",
                      confirm.isEnabled ? "是" : "否", confirm.isHittable ? "是" : "否")
                XCTAssertTrue(confirm.isEnabled, "第8镜：确认按钮是灰的（填码之后本该可点）")
                XCTAssertTrue(confirm.isHittable, "第8镜：确认按钮点不到（被挡着），点了也是白点")
                confirm.tap()
                // 🚨🚨🚨 0 09-16 13:5x 第 39 遍查出来的：点 `del.confirm` 之后**还有一层
                //    系统确认弹框**（`tapConfirm` 里 present 的 UIAlertController，
                //    「取消 / 确认删除账号」），真正发请求的是弹框里那个 destructive。
                //    测试从来没点过那一层 —— 所以按钮可点、点得到、也点了，
                //    而 hint 连变都没变。**「点到了按钮」不等于「动作发生了」。**
                //    （产品这么设计是对的：删号该二次确认。录屏里也会拍到这一层。）
                let alertOK = app4.alerts.buttons["确认删除账号"]
                XCTAssertTrue(alertOK.waitForExistence(timeout: 8),
                              "第8镜：二次确认弹框没出来（或按钮文案变了）")
                alertOK.tap()
                NSLog("NSFR 第8镜：二次确认弹框已点「确认删除账号」")
                var hint = ""
                for _ in 0..<25 {
                    Thread.sleep(forTimeInterval: 1.0)
                    hint = app4.staticTexts["del.hint"].label
                    if hint.contains("7") { break }
                }
                NSLog("NSFR 第8镜：删号确认后 del.hint = 「%@」", hint)
                XCTAssertTrue(hint.contains("7"),
                              "第8镜：点了确认但 del.hint 没出现 7 天冷静期那句话（删号没真的受理）")
            }
        }
        NSLog("NSFR 第8镜完")

        // ---- 第 9 镜：付费入口 ----
        shotLog(9, "订阅页")
        // 🚨 0 09-16：第 8 镜点完注销入口后停在【确认弹层】上，那一层盖着账户页。
        //    第十八遍就是倒在这里（account.row.pro 找不到），而断言文案把锅甲了
        //    第 7 镜「多半是没登进去」—— 第 7 镜实际上过了。直接重开账户页，
        //    比去猜确认层的取消按钮叫什么名字稳。
        app4.terminate(); Thread.sleep(forTimeInterval: 1.0)
        app4.launchEnvironment["TRANSLESS_PAGE"] = "account"
        app4.launch(); Thread.sleep(forTimeInterval: 1.5)
        let proRow = app4.otherElements["account.row.pro"]
        let proFound = proRow.waitForExistence(timeout: 8)
        if !proFound { dumpElements(app4, "第9镜-账户页没起来") }
        XCTAssertTrue(proFound, "第9镜：账户页没起来(account.row.pro)，多半是第7镜没登进去")
        if proFound {
            proRow.tap()
            Thread.sleep(forTimeInterval: 2.5)
            let subTexts = app4.staticTexts.allElementsBoundByIndex.map { $0.label }
            NSLog("NSFR 第9镜：订阅页文字=%@", subTexts.joined(separator: " | "))
        }
        NSLog("NSFR 第9镜完")
        NSLog("NSFR ===== 九镜跑完 =====")
    }

    // MARK: - 复用的小工具（都是这一晚在别的文件里验过的写法，原样搬过来）

    /// 🚨🚨 0 09-16 12:1x 第 25 遍抽帧抳出来的：一个【"Transless" 想给你发送通知】
    ///    的系统弹层**正好盖在键盘的档位行上**，把「点翻译档」那一下吃掉了。
    ///    日志里却写着「已切到翻译档」—— 因为那句话只证明**我发出了点击**，
    ///    不证明**档真的切了**。又一次把「做了动作」当成「事情成了」。
    private func dismissSystemAlerts(_ tag: String) {
        let sb = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for word in ["不允许", "稍后", "好", "OK", "关闭"] {
            let b = sb.buttons[word]
            if b.exists && b.isHittable {
                NSLog("NSFR 清系统弹层[%@]：点了「%@」", tag, word)
                b.tap(); Thread.sleep(forTimeInterval: 0.8)
                return
            }
        }
    }

    private func navigateToKeyboardsList(_ settings: XCUIApplication) {
        let generalRow = settings.staticTexts["通用"]
        if generalRow.waitForExistence(timeout: 8) { generalRow.tap() }
        let kbRow1 = settings.staticTexts["键盘"]
        if kbRow1.waitForExistence(timeout: 6) { kbRow1.tap() }
        let kbRow2 = settings.cells.staticTexts["键盘"]
        if kbRow2.waitForExistence(timeout: 6) { kbRow2.tap() }
    }

    private func addTranslessKeyboard(_ settings: XCUIApplication) {
        settings.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        let addRowText = settings.cells.staticTexts["添加新键盘"]
        let addRowBtn = settings.buttons["添加新键盘"]
        guard addRowText.waitForExistence(timeout: 4) || addRowBtn.waitForExistence(timeout: 4) else {
            NSLog("NSFR 第3镜：找不到'添加新键盘'"); return
        }
        (addRowText.exists ? addRowText : addRowBtn).tap()
        let translessInList = settings.cells.staticTexts["Transless"]
        if translessInList.waitForExistence(timeout: 6) { translessInList.tap() }
    }

    /// 🚨 09-15 模拟器实测写法：开关自己的坐标系不可靠，走 App 整体坐标系。
    ///    **这个坐标是模拟器截图量出来的，真机上大概率要重新量一次**
    ///    ——两台设备的屏幕比例/系统 UI 布局不保证一样，这是留给 0 在真机上
    ///    核实的已知坑，不是我漏做。0 09-15 真机跑确认这一镜本身是好的
    ///    （开关最终值=1），坐标暂不用改。
    private func openFullAccessToggleAndEnable(_ settings: XCUIApplication) {
        // 🚨 0 09-16 12:1x 实测：第 23/24 遍都在这里挂掉，报
        //    `kAXErrorServerNotFound`。抽当时的录屏帧看了——**屏幕上是别的 App**，
        //    Kevin 正在用手机，设置被切走了。
        //    🚨 我先把这当成「可复现的代码 bug」，因为两遍报错一模一样——
        //    但两遍中间只隔两分钟，同一个人在用同一台手机，
        //    同一个原因本来就会连着出两次。**「可复现」不等于「不是外部干扰」。**
        //    → 他随时会用自己的手机，测试不能要求他别动。被切走就拉回来重试。
        if !settings.wait(for: .runningForeground, timeout: 2) {
            NSLog("NSFR 第3镜：设置不在前台（手机被人用了？）——拉回来重试")
            settings.activate(); Thread.sleep(forTimeInterval: 1.5)
            if !settings.wait(for: .runningForeground, timeout: 5) {
                settings.terminate(); Thread.sleep(forTimeInterval: 1.0)
                settings.launch(); Thread.sleep(forTimeInterval: 1.5)
            }
        }
        // 🚨🚨 0 09-16 13:3x：第 35、36 两遍都死在这个函数里的【多余那次导航】上
        //    （一次 kAXErrorServerNotFound、一次 continuity 超时）。
        //    第 3 镜自己已经导航到键盘列表了，这里再调一次 `navigateToKeyboardsList`
        //    就是在两个**根本不存在的元素**上各等 6–8 秒 —— 14 秒的空窗，
        //    偶发故障全落在这段里。它不是「保险」，它是故障面。
        // 📌 已经在目标页就别再走一遍路：先看 Transless 那一行在不在。
        var translessRow = settings.cells.staticTexts["Transless"]
        if !translessRow.waitForExistence(timeout: 3) {
            NSLog("NSFR 第3镜：不在键盘列表页，导航一次")
            navigateToKeyboardsList(settings)
            translessRow = settings.cells.staticTexts["Transless"]
            guard translessRow.waitForExistence(timeout: 6) else {
                NSLog("NSFR 第3镜：已装列表里没有Transless，打不开完全访问那一屏"); return
            }
        }
        translessRow.tap()
        let sw = settings.switches.firstMatch
        guard sw.waitForExistence(timeout: 6) else { NSLog("NSFR 第3镜：找不到开关"); return }
        if "\(sw.value ?? "?")" == "0" {
            settings.coordinate(withNormalizedOffset: CGVector(dx: 0.842, dy: 0.168)).tap()
            Thread.sleep(forTimeInterval: 0.8)
            let allowBtn = settings.buttons["允许"]
            if allowBtn.waitForExistence(timeout: 3) { allowBtn.tap() }
            Thread.sleep(forTimeInterval: 0.8)
        }
        let after = "\(settings.switches.firstMatch.value ?? "?")"
        NSLog("NSFR 第3镜：完全访问开关最终值=%@（1=开）", after)
    }

    private func disableFullAccess(_ settings: XCUIApplication) {
        navigateToKeyboardsList(settings)
        let translessRow = settings.cells.staticTexts["Transless"]
        guard translessRow.waitForExistence(timeout: 6) else { return }
        translessRow.tap()
        let sw = settings.switches.firstMatch
        guard sw.waitForExistence(timeout: 6) else { return }
        if "\(sw.value ?? "?")" == "1" {
            settings.coordinate(withNormalizedOffset: CGVector(dx: 0.842, dy: 0.168)).tap()
            Thread.sleep(forTimeInterval: 0.8)
        }
        let after = "\(settings.switches.firstMatch.value ?? "?")"
        NSLog("NSFR 第6镜：完全访问开关最终值=%@（0=关）", after)
    }

    /// 🚨🚨🚨 0 09-16 01:1x 抳出来的真事故：第 6 镜把【允许完全访问】
    ///    关掉之后【从来没有开回去】—— 也就是说，**每跑完一遍九镜，
    ///    Kevin 手机上的键盘就是坏的**（没网络、共享区拿不到、按麦克风
    ///    直接退回系统键盘）。他 09-15 晚上看屏指出的那行红字，极可能
    ///    就是上一遍测试留下的，而我当时把它当成了「他自己没开」。
    /// 🚨 判据不是「我点了」，是**读回来的开关值=1**。
    private func restoreFullAccess(_ settings: XCUIApplication) {
        // 🚨 0 09-16 01:2x 第二十遍实测掉进去的坑：`navigateToKeyboardsList`
        //    假设设置停在**根页**（找"通用"→"键盘"），而第 6 镜跑完时
        //    它还停在 Transless 详情页里 → 找不到"通用" → 一路空点 →
        //    最后报"没找到 Transless 那一行"，**他的键盘就被留在关着的状态**。
        //    → 先把设置杀掉重开，回到确定的起点再导航。
        settings.terminate(); Thread.sleep(forTimeInterval: 1.2)
        settings.launch(); Thread.sleep(forTimeInterval: 1.5)
        navigateToKeyboardsList(settings)
        let translessRow = settings.cells.staticTexts["Transless"]
        guard translessRow.waitForExistence(timeout: 6) else {
            NSLog("NSFR 🚨 还原完全访问：没找到 Transless 那一行，**他手机可能被留在关着的状态**")
            return
        }
        translessRow.tap()
        let sw = settings.switches.firstMatch
        guard sw.waitForExistence(timeout: 6) else { return }
        if "\(sw.value ?? "?")" != "1" {
            settings.coordinate(withNormalizedOffset: CGVector(dx: 0.842, dy: 0.168)).tap()
            Thread.sleep(forTimeInterval: 0.8)
        }
        let after = "\(settings.switches.firstMatch.value ?? "?")"
        NSLog("NSFR 还原完全访问：读回开关值=%@（1=开，必须是 1）", after)
        XCTAssertEqual(after, "1", "收工时没把【允许完全访问】开回去，他的键盘会是坏的")
    }

    /// 🚨🚨🚨 0 09-15 找到的真因：`switchToTranslessKeyboard` 从来没检查过
    ///    "系统键盘此刻在不在屏幕上"就直接去长按地球键的坐标——调用方现在
    ///    已经在长按之前保证了键盘存在（见 `openConversationWithKeyboard`），
    ///    这里再把地球键的定位也从**写死的屏幕归一化坐标**改成**先找真元素，
    ///    找不到才退回坐标，而且坐标相对键盘自己的 frame 算，不是相对整个屏幕**
    ///    ——键盘在屏幕上的位置本来就只占下半部分，用屏幕归一化坐标去点
    ///    键盘内部的键，比例会跟着屏幕尺寸变，换个机型就可能点偏。
    private func switchToTranslessKeyboard(_ host: XCUIApplication) -> Bool {
        if host.buttons["transless.mic"].waitForExistence(timeout: 4) { return true }
        let pred = NSPredicate(format: "label BEGINSWITH[c] 'Transless'")
        for n in 0..<3 {
            pressGlobeKey(host)
            Thread.sleep(forTimeInterval: 1.8)
            let rowCell = host.cells.matching(pred).firstMatch
            let rowBtn = host.buttons.matching(pred).firstMatch
            let rowOther = host.otherElements.matching(pred).firstMatch
            if rowCell.waitForExistence(timeout: 2) { rowCell.tap() }
            else if rowBtn.waitForExistence(timeout: 2) { rowBtn.tap() }
            else if rowOther.waitForExistence(timeout: 2) { rowOther.tap() }
            else { host.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap() }
            Thread.sleep(forTimeInterval: 3.5)
            NSLog("NSFR 长按切键盘第%d次", n + 1)
            if host.buttons["transless.mic"].waitForExistence(timeout: 4) { return true }
        }
        return false
    }

    /// 长按"下一个键盘"（地球键）。优先找真元素，找不到才退回坐标。
    ///
    /// 🚨🚨🚨 0 09-15 第七遍真机之后纠回来的：原来"找不到具名元素就退回
    /// `keyboards.element.frame` 算坐标，`kb.exists` 都不成立就干脆不按"这个
    /// 设计本身就是错的——`host.keyboards` 这整棵树**看不见别的进程渲染的
    /// 键盘**（Kevin 手机当前选中的是「Typeless」，键盘明明在屏幕上，
    /// `keyboards.count` 却恒为 0）。原来的写法在这种、也是真机上**实际发生**
    /// 的场景里，会直接放弃长按，跟"键盘真的不存在"长得一模一样，
    /// 但原因完全不同。
    /// → 退回坐标不再依赖 `keyboards.element` 的 frame，改用**绝对屏幕坐标**
    ///   （地球键在系统键盘布局里固定在左下角），不管 `keyboards` 这棵树
    ///   看不看得见，这个坐标都按得到。
    private func pressGlobeKey(_ host: XCUIApplication) {
        let kb = host.keyboards.element
        if kb.exists {
            for label in ["Next keyboard", "下一个键盘", "切换键盘"] {
                let btn = kb.buttons[label]
                if btn.waitForExistence(timeout: 1) {
                    btn.press(forDuration: 1.3)
                    return
                }
            }
        } else {
            NSLog("NSFR pressGlobeKey：keyboards.element 看不见（可能是别的进程渲染的键盘，"
                  + "不代表键盘真的不在）——直接走绝对坐标兜底")
        }
        NSLog("NSFR pressGlobeKey：没找到具名的地球键，退回绝对屏幕坐标")
        host.coordinate(withNormalizedOffset: CGVector(dx: 0.07, dy: 0.945)).press(forDuration: 1.3)
    }

    /// 🚨🚨🚨 0 09-15 第二轮真机反馈的修法：第一版用"信息"，点的是会话**列表**里
    ///    第一条 cell——**列表页本身不会弹键盘**，得先真正点进某一条会话、
    ///    再点它里面的输入框，多一整层不确定。换成"备忘录"：`新建备忘录`
    ///    一步到位，新建的笔记本身就是一个聚了焦的空白输入框。而且新建笔记是
    ///    空的，不会像"信息"那样意外读到 Kevin 的真实聊天内容。
    ///
    /// 🚨🚨🚨 0 09-15 第七遍真机之后纠回来的：这里原来还拿
    ///    `notes.keyboards.element.waitForExistence` 当"键盘弹出来了没有"的
    ///    判据——**这个判据没被验证过就拿来当门**。真机上 Kevin 当前选中的
    ///    键盘属于「Typeless」（另一个 App 的扩展进程），`keyboards` 这棵树
    ///    结构性地看不到别的进程渲染的键盘 UI，键盘明明在屏幕上这个数也恒为
    ///    0——七遍里至少四遍死在这条假阴性上。
    ///    → 这个函数现在只负责**我们自己够得着的那一半**：新建笔记、点输入框、
    ///    输入框真的存在且点了。键盘是谁的、Transless 在不在，交给调用方
    ///    `switchToTranslessKeyboard` 里对 `transless.mic` 的检查——那条判据
    ///    读的是键盘扩展渲染进宿主视图树里的**我们自己的控件**，不受"扩展属于
    ///    哪个进程"影响，这也是它在本会话其它地方一直有效的原因。
    /// - Returns: 输入框真的找到且点了才是 true（不代表任何键盘已经弹出）。
    private func openNewNoteWithKeyboard(_ notes: XCUIApplication) -> Bool {
        let newNoteBtn = firstExisting(in: notes,
            [notes.buttons["新建备忘录"], notes.buttons["新建"], notes.buttons["New Note"]])
        if let btn = newNoteBtn {
            btn.tap()
        } else {
            // 找不到具名按钮就退回坐标——"新建"一般在右下角。
            NSLog("NSFR openNewNoteWithKeyboard：没找到具名的新建按钮，退回坐标（右下角）")
            notes.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.95)).tap()
        }
        Thread.sleep(forTimeInterval: 1.0)
        let field = notes.textViews.firstMatch
        guard field.waitForExistence(timeout: 5) else {
            NSLog("NSFR openNewNoteWithKeyboard：连输入框都没找到")
            return false
        }
        field.tap()
        Thread.sleep(forTimeInterval: 1.0)
        NSLog("NSFR openNewNoteWithKeyboard：输入框找到了、点了（键盘是谁的、"
              + "在不在，留给后面 transless.mic 那条判）")
        return true
    }

    private func firstExisting(in app: XCUIApplication, _ candidates: [XCUIElement]) -> XCUIElement? {
        for c in candidates where c.waitForExistence(timeout: 2) { return c }
        return nil
    }

    /// 轮询 `transless.mic` 的 `accessibilityValue`（`KeyboardViewController.setPhase`
    /// 里新写的 "phase.<idle|listening|thinking>"）直到等于目标值或超时。
    /// 0 09-15 要的"真信号"：别拿"点了麦克风"当"已经在录"，两者之间隔着
    /// 引擎架起来那几秒（尤其宿主是冷启动的时候）。
    private func waitForMicPhase(_ app: XCUIApplication, _ want: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let mic = app.buttons["transless.mic"]
            if mic.exists, let v = mic.value as? String, v == want { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    /// 🚨 0 09-15："写完那一条笔记，跑完删掉"——用完这条新建的空白笔记
    ///    （只含我们自己打进去的测试标记串，不含 Kevin 的内容）就清掉，
    ///    别在他的备忘录里留垃圾。**尽力而为**：删不掉只记一笔，不让清理步骤
    ///    本身的失败盖过前面几镜真正的判据。
    private func deleteCurrentNote(_ notes: XCUIApplication) {
        let moreBtn = firstExisting(in: notes,
            [notes.buttons["更多"], notes.buttons["More"],
             notes.navigationBars.buttons.matching(
                NSPredicate(format: "label CONTAINS[c] 'more'")).firstMatch])
        guard let more = moreBtn else {
            NSLog("NSFR deleteCurrentNote：没找到'更多'菜单，笔记没清——手动删一下"); return
        }
        more.tap()
        Thread.sleep(forTimeInterval: 0.5)
        let delBtn = firstExisting(in: notes,
            [notes.buttons["删除"], notes.buttons["Delete"]])
        guard let del = delBtn else {
            NSLog("NSFR deleteCurrentNote：菜单里没找到'删除'，笔记没清——手动删一下"); return
        }
        del.tap()
        Thread.sleep(forTimeInterval: 0.5)
        // 有的系统版本删除还要二次确认。
        let confirmBtn = firstExisting(in: notes,
            [notes.buttons["删除备忘录"], notes.buttons["Delete Note"], notes.buttons["删除"]])
        confirmBtn?.tap()
        NSLog("NSFR deleteCurrentNote：已尝试清理测试笔记")
    }
}
