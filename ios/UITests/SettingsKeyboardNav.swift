import XCTest

/// 0 派活（09-15，紧跟着九镜验证之后）：**实测**UITest 能不能驱动系统「设置」
/// 走到 通用→键盘→键盘→添加新键盘→Transless，以及开关「允许完全访问」——
/// 不许拿 `AppDelegate.swift:1977` 那条旧注释当现状。
///
/// 🚨🚨 那条旧注释本身已经过期，这不是我这次的猜测，是当场查出来的：
///    `E2EHome.swift:13` 写着「设备上的 Enable UI Automation 已打开（他 09-04 开的）」
///    —— 旧注释描述的是 09-04 **之前**的状态，09-04 当天就已经解决。
///    而且今天（09-15）`ReviewAccountShot` 那几条测试已经在真机上把我们自己的
///    App 跑穿了好几轮（登录、账户页、订阅页），证明设备级的自动化开关早就通了。
///    **真正没验过的窄问题是：UITest 能不能进`系统`的设置 App（不是我们自己的
///    App），这是没人试过，不是"试过不行"。**
///
/// 🚨 09-15 实测坑1：跑之前设备屏幕刚熄，第一次直接跑 xcodebuild test 报
///    `Timed out while enabling automation mode`——**不是"点不动"，是屏幕睡着了**。
///    独立第二路径验证过（重跑一个昨天成功过的测试也同样报同一个错），
///    证明这是设备当时的状态，不是这条测试本身、也不是 Settings App 挡的。
///    修法：跑测试前先用 `xcrun devicectl device process launch` 唤醒一次屏幕。
///
/// 🚨 09-15 实测坑2：`.tables.staticTexts["通用"]` 在设置 App 根页面找不到"通用"，
///    而屏幕文字转储里它明明在（"...VPN | 通用 | 辅助功能"）——这台 iOS 26 设置
///    App 用的容器不是标准 UITableView 的那套无障碍层级，scope 收窄到 `.tables`
///    直接漏了它。改用不限容器类型的 `staticTexts`。
final class SettingsKeyboardNav: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testOpenSettingsAndNavigateToKeyboards() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        NSLog("SKN 已发起 launch(com.apple.Preferences)")

        let generalRow = settings.staticTexts["通用"]
        let generalRowEn = settings.staticTexts["General"]
        let opened = generalRow.waitForExistence(timeout: 8) || generalRowEn.waitForExistence(timeout: 3)
        NSLog("SKN 设置App起来了吗=%d", opened ? 1 : 0)
        guard opened else {
            NSLog("SKN 卡在第一步:设置App本身没进来或者根目录找不到'通用'/'General'")
            let texts = settings.staticTexts.allElementsBoundByIndex.prefix(20).map { $0.label }
            NSLog("SKN 当前屏幕文字=%@", texts.joined(separator: " | "))
            return
        }

        let general = generalRow.exists ? generalRow : generalRowEn
        general.tap()
        NSLog("SKN 已点'通用'")

        let kbRow1 = settings.staticTexts["键盘"]
        let kbRow1En = settings.staticTexts["Keyboard"]
        let step2 = kbRow1.waitForExistence(timeout: 6) || kbRow1En.waitForExistence(timeout: 3)
        NSLog("SKN 第二步:通用页里找到'键盘'行吗=%d", step2 ? 1 : 0)
        guard step2 else {
            let texts = settings.staticTexts.allElementsBoundByIndex.prefix(20).map { $0.label }
            NSLog("SKN 通用页当前文字=%@", texts.joined(separator: " | "))
            return
        }
        (kbRow1.exists ? kbRow1 : kbRow1En).tap()
        NSLog("SKN 已点'键盘'(第一层)")

        // 键盘设置页里,"键盘"这一行(复数,进去是已装键盘列表+添加新键盘)。
        // 🚨 09-15 实测坑3：这一页导航栏标题也叫"键盘"，跟这一行的标签**同名**——
        //    `settings.staticTexts["键盘"]` 会同时命中标题和行，`.tap()` 报
        //    "Multiple matching elements found"。改用 `.cells` 限定范围，
        //    导航栏标题不是 cell，这样就唯一了。
        let kbRow2 = settings.cells.staticTexts["键盘"]
        let kbRow2En = settings.cells.staticTexts["Keyboards"]
        let step3 = kbRow2.waitForExistence(timeout: 6) || kbRow2En.waitForExistence(timeout: 3)
        NSLog("SKN 第三步:键盘页里找到'键盘'(复数)行吗=%d", step3 ? 1 : 0)
        guard step3 else {
            let texts = settings.staticTexts.allElementsBoundByIndex.prefix(20).map { $0.label }
            NSLog("SKN 键盘设置页当前文字=%@", texts.joined(separator: " | "))
            return
        }
        (kbRow2.exists ? kbRow2 : kbRow2En).tap()
        NSLog("SKN 已点'键盘'(第二层,进已装键盘列表)")

        // 🚨 09-15 实测发现:这台设备上 Transless 早就装过键盘了(这一整晚一直在真机
        //    测),已装列表里直接就有"Transless"这一行——不需要走"添加新键盘"
        //    那条冷启动专属路径(那条要设备是"从没装过"这个前提,今天不成立)。
        //    这不影响回答 0 的问题:0 要验的是"UITest 能不能进设置、能不能点开
        //    第三方键盘的开关页"——直接点已装的 Transless 行,一样能验证这条能力。
        let alreadyHasTransless = settings.cells.staticTexts["Transless"].waitForExistence(timeout: 6)
        NSLog("SKN 第四步:已装键盘列表里能不能直接点到Transless=%d", alreadyHasTransless ? 1 : 0)
        guard alreadyHasTransless else {
            let texts = settings.staticTexts.allElementsBoundByIndex.prefix(30).map { $0.label }
            NSLog("SKN 已装键盘列表页当前文字=%@", texts.joined(separator: " | "))
            return
        }
        settings.cells.staticTexts["Transless"].tap()
        NSLog("SKN 已点'Transless'那一行(进它的键盘设置页)")

        // Transless 的键盘设置页:找"允许完全访问"这个开关(iOS 系统 switch,
        // 在自己的键盘扩展 Info.plist 声明了 RequestsOpenAccess 才会出现这一项)。
        // 🚨 09-15 实测:这一屏刚进来那一刻 `staticTexts` 转储是空的(页面还没
        // 完全渲染完就读了),但 `switches` 已经存在——iOS 系统设置页的渲染时序
        // 是"控件先于标签文字出现"。改成等开关本身出现,再连着读它旁边的标签。
        let sw = settings.switches.firstMatch
        let swReady = sw.waitForExistence(timeout: 8)
        NSLog("SKN 第五步:Transless设置页里出现开关控件吗=%d", swReady ? 1 : 0)
        Thread.sleep(forTimeInterval: 1.0)   // 再等一拍让文字标签也渲染出来
        let allSwitches = settings.switches.allElementsBoundByIndex
        for (i, s) in allSwitches.enumerated() {
            NSLog("SKN 开关#%d label=%@ value=%@", i, s.label, "\(s.value ?? "nil")")
        }
        let texts = settings.staticTexts.allElementsBoundByIndex.map { $0.label }
        NSLog("SKN Transless设置页完整文字=%@", texts.joined(separator: " | "))
        NSLog("SKN 结论:UITest能不能驱动系统设置走到'允许完全访问'那一步,答案见上面记录")
    }

    /// 🚨 切到1359之后实测发现:"允许完全访问"被重置成关了(哪怕键盘还在已装列表里)。
    /// 这条把它打开,弹窗("允许完全访问会…")点允许。
    func testEnableFullAccess() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let generalRow = settings.staticTexts["通用"]
        XCTAssertTrue(generalRow.waitForExistence(timeout: 8), "设置App没起来")
        generalRow.tap()
        let kbRow1 = settings.staticTexts["键盘"]
        XCTAssertTrue(kbRow1.waitForExistence(timeout: 6), "找不到'键盘'")
        kbRow1.tap()
        let kbRow2 = settings.cells.staticTexts["键盘"]
        XCTAssertTrue(kbRow2.waitForExistence(timeout: 6), "找不到'键盘'(复数)")
        kbRow2.tap()
        let translessRow = settings.cells.staticTexts["Transless"]
        XCTAssertTrue(translessRow.waitForExistence(timeout: 6), "已装列表里没有Transless")
        translessRow.tap()

        let sw = settings.switches.firstMatch
        XCTAssertTrue(sw.waitForExistence(timeout: 6), "找不到开关")
        let before = "\(sw.value ?? "?")"
        NSLog("SKN(开FA) 开关当前值=%@", before)
        // 🚨 09-15 模拟器实测：真机上那条"`sw.tap()` 点不动、要坐标点"的坑
        //    **在模拟器上不成立**——这里反过来试：先 `.tap()`（更符合模拟器
        //    accessibility 的一般行为），点完立刻核一次值，没变才退回坐标点。
        //    两条都试是因为**真机能成我模拟器不成≠我模拟器的通道问题**，也可能
        //    反过来，猜哪条对不如都试。最多两轮，每轮点完都核实再决定要不要继续。
        // 🚨 09-15 模拟器实测：`.tap()` 和 `switch.coordinate(...)` 两条都试过，
        //    两轮点完屏幕截图/alert/按钮列表**完全没有任何变化**——不是"点偏了"，
        //    是压根没有命中任何东西。怀疑 `settings.switches.firstMatch` 这个元素
        //    自己报的 accessibility frame 跟视觉位置对不上（用它自己的坐标系
        //    转出来的点因此也是错的）。改用**整个 App 的坐标系**（不依赖这个
        //    元素自己的 frame），按截图上实测的可视位置换算归一化坐标。
        let fraction: [Int: CGVector] = [
            1: CGVector(dx: 0.5, dy: 0.5),      // 走元素自己的坐标系（旧办法，留着对照）
            2: CGVector(dx: 0.842, dy: 0.168),  // 走整个 App 坐标系，按截图实测换算
        ]
        for attempt in 1...2 {
            let cur = settings.switches.firstMatch
            guard "\(cur.value ?? "?")" == "0" else { break }
            if attempt == 1 {
                cur.coordinate(withNormalizedOffset: fraction[1]!).tap()
                NSLog("SKN(开FA) 第%d次：走开关自己的坐标系", attempt)
            } else {
                settings.coordinate(withNormalizedOffset: fraction[2]!).tap()
                NSLog("SKN(开FA) 第%d次：走整个App的坐标系(按截图实测换算)", attempt)
            }
            Thread.sleep(forTimeInterval: 0.8)
            // 🚨 09-15：两次都没弹'允许'、值也没变——先截图+打印全部按钮/弹窗文字，
            //    看点完那一刻屏幕上到底有什么，别再猜按钮名字。
            let btnsNow = settings.buttons.allElementsBoundByIndex.prefix(20).map { $0.label }
            NSLog("SKN(开FA) 第%d次点完那一刻,按钮列表=%@", attempt, btnsNow.joined(separator: " | "))
            let alertsNow = settings.alerts.allElementsBoundByIndex.prefix(5).map { $0.label }
            NSLog("SKN(开FA) 第%d次点完那一刻,alerts=%@", attempt, alertsNow.joined(separator: " | "))
            let shotMid = XCUIScreen.main.screenshot()
            let attMid = XCTAttachment(screenshot: shotMid)
            attMid.name = "fa_mid_\(attempt).png"
            attMid.lifetime = .keepAlways
            add(attMid)
            let allowBtn = settings.buttons["允许"]
            if allowBtn.waitForExistence(timeout: 3) {
                allowBtn.tap()
                NSLog("SKN(开FA) 已点警告框'允许'")
            } else {
                NSLog("SKN(开FA) 没弹出'允许'警告框")
            }
            Thread.sleep(forTimeInterval: 0.8)
            let after = "\(settings.switches.firstMatch.value ?? "?")"
            NSLog("SKN(开FA) 第%d次点完，当前值=%@", attempt, after)
        }
        Thread.sleep(forTimeInterval: 1.0)
        let sw2 = settings.switches.firstMatch
        NSLog("SKN(开FA) 最终开关值=%@", "\(sw2.value ?? "?")")
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = "fa_state.png"
        att.lifetime = .keepAlways
        add(att)
    }

    /// 🚨🚨 反向对照实验：同一个 1359 二进制，只把 Full Access 关掉，
    /// 其它一律不变，看崩溃会不会复现。这是排除"1359代码本身必崩"这个
    /// 假设最干净的一次实验——唯一变量就是这个开关。
    func testDisableFullAccess() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let generalRow = settings.staticTexts["通用"]
        XCTAssertTrue(generalRow.waitForExistence(timeout: 8), "设置App没起来")
        generalRow.tap()
        let kbRow1 = settings.staticTexts["键盘"]
        XCTAssertTrue(kbRow1.waitForExistence(timeout: 6), "找不到'键盘'")
        kbRow1.tap()
        let kbRow2 = settings.cells.staticTexts["键盘"]
        XCTAssertTrue(kbRow2.waitForExistence(timeout: 6), "找不到'键盘'(复数)")
        kbRow2.tap()
        let translessRow = settings.cells.staticTexts["Transless"]
        XCTAssertTrue(translessRow.waitForExistence(timeout: 6), "已装列表里没有Transless")
        translessRow.tap()

        let sw = settings.switches.firstMatch
        XCTAssertTrue(sw.waitForExistence(timeout: 6), "找不到开关")
        let before = "\(sw.value ?? "?")"
        NSLog("SKN(关FA) 开关当前值=%@", before)
        if before == "1" {
            sw.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            NSLog("SKN(关FA) 已按坐标点开关")
            Thread.sleep(forTimeInterval: 0.8)
            // 🚨 之前猜按钮名字("关闭"/"关闭完全访问")两次都没猜中,导致弹窗
            // 一直卡着挡住后续操作。这次不猜,直接截图+打印所有按钮名字看清楚。
            let shotMid = XCUIScreen.main.screenshot()
            let attMid = XCTAttachment(screenshot: shotMid)
            attMid.name = "fa_off_mid.png"
            attMid.lifetime = .keepAlways
            add(attMid)
            let allBtns = settings.buttons.allElementsBoundByIndex.prefix(20).map { $0.label }
            NSLog("SKN(关FA) 点开关之后的按钮列表=%@", allBtns.joined(separator: " | "))
        }
        Thread.sleep(forTimeInterval: 1.0)
        let sw2 = settings.switches.firstMatch
        NSLog("SKN(关FA) 最终开关值=%@", "\(sw2.value ?? "?")")
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = "fa_off_state.png"
        att.lifetime = .keepAlways
        add(att)
        NSLog("SKN(开FA) 已截图fa_state.png")
    }

    /// 0 09-15 追问：上面那条测的是"点已装的 Transless 行"，而真正要录的第 3 镜是
    /// **App 删掉重装之后**、键盘列表里**没有 Transless 那一行**、要走"添加新键盘…"
    /// 这条冷启动专属路径——这条之前没验过。跑之前已经 `devicectl uninstall` 把
    /// Transless 卸掉了（跟真录屏第①步等效，只是没走长按图标那个手势）。
    func testAddNewKeyboardColdPath() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()

        let generalRow = settings.staticTexts["通用"]
        XCTAssertTrue(generalRow.waitForExistence(timeout: 8), "设置App没起来")
        generalRow.tap()

        let kbRow1 = settings.staticTexts["键盘"]
        XCTAssertTrue(kbRow1.waitForExistence(timeout: 6), "通用页找不到'键盘'")
        kbRow1.tap()

        let kbRow2 = settings.cells.staticTexts["键盘"]
        XCTAssertTrue(kbRow2.waitForExistence(timeout: 6), "键盘页找不到'键盘'(复数)")
        kbRow2.tap()

        let hasTransless = settings.cells.staticTexts["Transless"].waitForExistence(timeout: 4)
        NSLog("SKN-COLD 卸载之后,已装列表里还有Transless吗(应该没有)=%d", hasTransless ? 1 : 0)

        // 🚨 09-15 实测坑4:"添加新键盘"在 staticTexts 里始终查不到（装 Transless
        //    之前那次也查不到），怀疑它不是 staticText 而是 button 元素（iOS 系统
        //    设置里带"添加"语义的行常用 accent 色按钮样式）。两种都试，
        //    并且不管哪种，先滚到底保证它在可视区域内。
        settings.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        let addRowText = settings.cells.staticTexts["添加新键盘"]
        let addRowBtn = settings.buttons["添加新键盘"]
        let step = addRowText.waitForExistence(timeout: 4) || addRowBtn.waitForExistence(timeout: 4)
        NSLog("SKN-COLD 找到'添加新键盘'那一行吗=%d (staticText=%d button=%d)",
              step ? 1 : 0, addRowText.exists ? 1 : 0, addRowBtn.exists ? 1 : 0)
        guard step else {
            let texts = settings.staticTexts.allElementsBoundByIndex.prefix(30).map { $0.label }
            let btns = settings.buttons.allElementsBoundByIndex.prefix(30).map { $0.label }
            NSLog("SKN-COLD 已装键盘列表页当前文字=%@", texts.joined(separator: " | "))
            NSLog("SKN-COLD 已装键盘列表页当前按钮=%@", btns.joined(separator: " | "))
            return
        }
        (addRowText.exists ? addRowText : addRowBtn).tap()
        NSLog("SKN-COLD 已点'添加新键盘'")

        // 第三方键盘列表:找"Transless"。🚨 iOS 卸载 App 之后，它的键盘扩展是否
        // 还会出现在"第三方键盘"这个总列表里，是这条测试真正要回答的问题——
        // 如果这里也读不到，说明冷启动那条路必须先重装 App 本体才有得选，
        // 顺序会影响口令稿的第①②步怎么排。
        let translessInThirdParty = settings.cells.staticTexts["Transless"]
        let step2 = translessInThirdParty.waitForExistence(timeout: 6)
        NSLog("SKN-COLD 第三方键盘总列表里找到Transless吗=%d", step2 ? 1 : 0)
        if !step2 {
            let texts = settings.staticTexts.allElementsBoundByIndex.prefix(40).map { $0.label }
            NSLog("SKN-COLD 第三方键盘列表当前文字=%@", texts.joined(separator: " | "))
        }
        NSLog("SKN-COLD 结论:卸载重装场景下'添加新键盘'这条路能不能走通,答案见上面记录")
    }

    /// 🚨 09-15 2.2 补：`testAddNewKeyboardColdPath` 只验证了"找得到 Transless
    ///    这一行"，**没有真的点它**——键盘因此从没被真正启用过，也就摸不到
    ///    模拟器上的 `kb.trail`。这条接着做完剩下那一步：点 Transless 那一行，
    ///    确认它出现在"已装键盘"列表里，然后开"允许完全访问"。
    func testActuallyAddTransless() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()

        let generalRow = settings.staticTexts["通用"]
        XCTAssertTrue(generalRow.waitForExistence(timeout: 8), "设置App没起来")
        generalRow.tap()
        let kbRow1 = settings.staticTexts["键盘"]
        XCTAssertTrue(kbRow1.waitForExistence(timeout: 6), "找不到'键盘'")
        kbRow1.tap()
        let kbRow2 = settings.cells.staticTexts["键盘"]
        XCTAssertTrue(kbRow2.waitForExistence(timeout: 6), "找不到'键盘'(复数)")
        kbRow2.tap()

        if settings.cells.staticTexts["Transless"].waitForExistence(timeout: 3) {
            NSLog("SKN-ADD 已装列表里已经有Transless了,不用再加")
            return
        }
        settings.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
        let addRowText = settings.cells.staticTexts["添加新键盘"]
        let addRowBtn = settings.buttons["添加新键盘"]
        let found = addRowText.waitForExistence(timeout: 4) || addRowBtn.waitForExistence(timeout: 4)
        XCTAssertTrue(found, "找不到'添加新键盘'")
        (addRowText.exists ? addRowText : addRowBtn).tap()
        NSLog("SKN-ADD 已点'添加新键盘'")

        let translessInList = settings.cells.staticTexts["Transless"]
        XCTAssertTrue(translessInList.waitForExistence(timeout: 6), "第三方键盘列表里没有Transless")
        translessInList.tap()
        NSLog("SKN-ADD 已点第三方列表里的'Transless'——这一下应该是真的加进去了")
        Thread.sleep(forTimeInterval: 1.0)

        // 回到已装键盘列表核实。有些 iOS 版本点完第三方那一行会直接返回上一屏，
        // 有些还留在原地——两种都用 navigationBars 的返回按钮兜一次。
        let backBtn = settings.navigationBars.buttons.firstMatch
        if backBtn.exists, !settings.cells.staticTexts["Transless"].exists {
            backBtn.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }
        let nowInstalled = settings.cells.staticTexts["Transless"].waitForExistence(timeout: 4)
        NSLog("SKN-ADD 核实:已装键盘列表里现在有Transless了吗=%d", nowInstalled ? 1 : 0)
        let texts = settings.staticTexts.allElementsBoundByIndex.prefix(30).map { $0.label }
        NSLog("SKN-ADD 当前屏幕文字=%@", texts.joined(separator: " | "))
    }
}
