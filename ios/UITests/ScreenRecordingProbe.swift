import XCTest

/// 0 09-15 再派活：录屏方案改成「Kevin 一下都不碰」，两条路都要试：
/// 路 A = UITest 能不能像驱动系统「设置」App 那样驱动控制中心(SpringBoard)
/// 开/停系统自带录屏。这一条只碰 UITests target，**不碰 App/ 源码、不 rebuild
/// Transless**——跟 STATE.md 那条"录屏用现装的 1375，不许先 rebuild"不冲突。
final class ScreenRecordingProbe: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    /// 🚨 `replayd`/`ReplayKitAngel` 常驻,不是"正在录屏"才有——PID 全程没变,
    /// 说明那两个进程判据是假的,没拿正负样本先验过。改用状态栏本身：录屏中
    /// 状态栏会显示一个带红色计时的胶囊,不录时是普通时钟。直接读文字判断。
    func testCheckRecordingIndicatorNow() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let texts = springboard.staticTexts.allElementsBoundByIndex.prefix(10).map { $0.label }
        NSLog("SRP 此刻状态栏文字=%@", texts.joined(separator: " | "))
        let otherEls = springboard.otherElements.allElementsBoundByIndex.prefix(20).map { $0.label }
        NSLog("SRP 此刻状态栏区域其它元素=%@", otherEls.joined(separator: " | "))
        // 🚨 Kevin 亲眼看着真机说还在录——文字查询不够硬,直接截图肉眼判定。
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = "now_check.png"
        att.lifetime = .keepAlways
        add(att)
        NSLog("SRP 已截图now_check.png")
    }

    /// 🚨🚨 Kevin 亲眼看着真机说还在录。上一条截图控制中心还开着、"录屏"按钮
    /// 是实心红(疑似仍在录)。这条强制:控制中心还没开就打开,读"录屏"按钮的
    /// value/label 判定当前状态(不盲目再点一下,盲目点可能点反方向),
    /// 是"开着"就点停,然后再截一张图肉眼复核确认真的关了。
    func testForceStopAndVerify() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let recBtnCheck = springboard.buttons["录屏"]
        if !recBtnCheck.exists {
            let topRight = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.01))
            topRight.press(forDuration: 0.05, thenDragTo:
                springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.15)))
            Thread.sleep(forTimeInterval: 0.3)
            let mid = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.15))
            mid.press(forDuration: 0.05, thenDragTo:
                springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.55)))
            Thread.sleep(forTimeInterval: 1.0)
        }
        let recBtn = springboard.buttons["录屏"]
        let found = recBtn.waitForExistence(timeout: 4)
        NSLog("SRP(强制停) 控制中心里找到'录屏'按钮吗=%d value=%@", found ? 1 : 0,
              found ? "\(recBtn.value ?? "nil")" : "N/A")
        if found {
            recBtn.tap()
            NSLog("SRP(强制停) 已点'录屏'一次")
        }
        Thread.sleep(forTimeInterval: 1.5)
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = "after_force_stop.png"
        att.lifetime = .keepAlways
        add(att)
        NSLog("SRP(强制停) 已截图after_force_stop.png")
    }

    /// 第一步：确认「屏幕录制」这个控件已经在控制中心里——没加过的话,
    /// 打开控制中心根本看不到那个圆形录制按钮,得先去
    /// 设置→控制中心 把它加进去(这条本身也是纯 UITest 能做的 Settings 操作)。
    func testCheckScreenRecordingInControlCenter() throws {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()

        let ccRow = settings.staticTexts["控制中心"]
        let ccRowEn = settings.staticTexts["Control Center"]
        // 🚨 "控制中心"这一行在设置根页面偏下,第一屏看不到,先滚一下。
        var opened = ccRow.waitForExistence(timeout: 3) || ccRowEn.waitForExistence(timeout: 2)
        if !opened {
            settings.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
            opened = ccRow.waitForExistence(timeout: 4) || ccRowEn.waitForExistence(timeout: 2)
        }
        NSLog("SRP 设置App起来+找到'控制中心'行吗=%d", opened ? 1 : 0)
        guard opened else {
            let texts = settings.staticTexts.allElementsBoundByIndex.prefix(20).map { $0.label }
            NSLog("SRP 设置根页当前文字=%@", texts.joined(separator: " | "))
            return
        }
        (ccRow.exists ? ccRow : ccRowEn).tap()
        Thread.sleep(forTimeInterval: 0.5)

        let hasScreenRecording = settings.staticTexts["屏幕录制"].exists
            || settings.staticTexts["Screen Recording"].exists
        NSLog("SRP 控制中心配置页里'屏幕录制'这一项存在吗=%d", hasScreenRecording ? 1 : 0)
        let texts = settings.staticTexts.allElementsBoundByIndex.prefix(40).map { $0.label }
        NSLog("SRP 控制中心配置页完整文字=%@", texts.joined(separator: " | "))

        // 这一层只有开关,真正的模块列表在"自定义控制中心"里面。
        // 🚨 跟"添加新键盘"同一个坑:这行大概率是 button 不是 staticText。
        let customizeText = settings.cells.staticTexts["自定义控制中心"]
        let customizeBtn = settings.buttons["自定义控制中心"]
        let customizeFound = customizeText.waitForExistence(timeout: 3) || customizeBtn.waitForExistence(timeout: 3)
        NSLog("SRP 找到'自定义控制中心'吗(staticText=%d button=%d)",
              customizeText.exists ? 1 : 0, customizeBtn.exists ? 1 : 0)
        if customizeFound {
            (customizeText.exists ? customizeText : customizeBtn).tap()
            Thread.sleep(forTimeInterval: 0.8)
            let inList = settings.staticTexts["屏幕录制"].exists
                || settings.staticTexts["Screen Recording"].exists
            NSLog("SRP 自定义控制中心页里'屏幕录制'存在吗(已包含=已启用)=%d", inList ? 1 : 0)
            let texts2 = settings.staticTexts.allElementsBoundByIndex.prefix(60).map { $0.label }
            NSLog("SRP 自定义控制中心页完整文字=%@", texts2.joined(separator: " | "))
        } else {
            NSLog("SRP 没找到'自定义控制中心'那一行")
        }
    }

    /// 第二步(不管第一步结果如何都先试一次)：直接驱动 SpringBoard，
    /// 尝试从右上角下滑打开控制中心，看看 UITest 能不能摸到里面的控件。
    func testOpenControlCenterViaSpringBoard() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // SpringBoard 一直在跑,不需要 launch,直接查询它的元素树。
        // 🚨 09-15 实测坑:dx:0.5(正中间)下滑打开的是**通知中心**不是控制中心——
        //    这台灵动岛机型,控制中心的触发区在**右上角**靠边缘那一小块。
        //    上一版误开了通知中心,屏幕上出现了 Kevin 的真实通知内容(短信/新闻/
        //    Claude通知等)——这是隐私数据,后续不再重复触发这条,也别在报告里
        //    复述具体内容。
        // 🚨 09-15 第二次实测坑:dx:0.94/dy:0.005 一次拖拽完全没反应(按钮和文字
        //    列表都是空的,只有状态栏时钟)——单次 press-drag 手势没被识别成
        //    "打开控制中心"这个系统级边缘手势。改用 swipeDown(),它内部是多点
        //    采样的连续滑动,更接近真实手指划走的物理特征,系统边缘手势对这种
        //    手势识别率通常更高。从右上角一小块区域发起。
        let topRight = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.01))
        topRight.press(forDuration: 0.05, thenDragTo:
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.15)))
        Thread.sleep(forTimeInterval: 0.3)
        let mid = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.15))
        mid.press(forDuration: 0.05, thenDragTo:
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.55)))
        Thread.sleep(forTimeInterval: 1.0)

        // 🚨 09-15 实测:控制中心按钮列表里真实标签是"录屏"(不是设置App描述文字
        //    里那个"屏幕录制")。两个不同的字符串,踩了一次同类的坑。
        let recBtn = springboard.buttons["录屏"]
        let found = recBtn.waitForExistence(timeout: 4)
        NSLog("SRP 下滑打开控制中心后找到'录屏'按钮吗=%d", found ? 1 : 0)
        let allBtns = springboard.buttons.allElementsBoundByIndex.prefix(40).map { $0.label }
        NSLog("SRP 控制中心当前按钮列表=%@", allBtns.joined(separator: " | "))

        guard found else { return }
        recBtn.tap()
        NSLog("SRP 已点'录屏'")
        // 系统录屏有 3 秒倒计时才真正开始,倒计时期间控制中心会自动收起。
        Thread.sleep(forTimeInterval: 4.0)

        // 验证录屏是不是真的开始了:再次打开控制中心,"录屏"按钮通常会变成
        // 高亮/选中状态,且顶部状态栏会出现红色录制指示胶囊。用 exists 查一下
        // 状态栏那颗红点(它的 accessibility 一般叫"正在录制屏幕"之类)。
        let recIndicator = springboard.otherElements.matching(
            NSPredicate(format: "label CONTAINS[c] '录制' OR label CONTAINS[c] 'Recording'")
        ).firstMatch
        NSLog("SRP 状态栏录制指示存在吗=%d (label=%@)",
              recIndicator.exists ? 1 : 0, recIndicator.exists ? recIndicator.label : "N/A")
    }

    /// 停止录屏——跟开录同一个按钮,再点一次就是停。这条只做「验证开/停都能摸到」,
    /// 不管上一条测试是不是真的开着(找不到就如实报,不假装停成功了)。
    func testStopScreenRecording() throws {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let topRight = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.01))
        topRight.press(forDuration: 0.05, thenDragTo:
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.15)))
        Thread.sleep(forTimeInterval: 0.3)
        let mid = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.15))
        mid.press(forDuration: 0.05, thenDragTo:
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.55)))
        Thread.sleep(forTimeInterval: 1.0)

        let recBtn = springboard.buttons["录屏"]
        let found = recBtn.waitForExistence(timeout: 4)
        NSLog("SRP 停录:控制中心打开+找到'录屏'按钮吗=%d", found ? 1 : 0)
        guard found else { return }
        recBtn.tap()
        NSLog("SRP 已再点一次'录屏'(应为停止)")
        Thread.sleep(forTimeInterval: 2.0)
    }
}
