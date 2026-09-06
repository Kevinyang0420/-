import XCTest

/// **历史面板每行的高度必须一致** —— Kevin 2026-09-06 18:28 带图亲口：
/// > 「你看这个为啥中间要隔这么开的距离呢？**这个中间这个转写要把它压平，
/// >   距离保持一致，不要隔这么开。**」
///
/// 🚨 **判据要同时喂两种行**（跨语言带收藏钮 / 同语言不带）才算数 ——
///    只喂一种的话，"两种行高度不同"和"高度一致"两个实现都会绿。
///    种子里 en / zh 两种 `mode` 都有，正好覆盖。
final class HistoryRowHeight: XCTestCase {

    func testAllRowsSameHeight() {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        app.launchEnvironment["TRANSLESS_PAGE"] = "kb"
        app.launchEnvironment["TRANSLESS_NO_ARM"] = "1"
        app.launchEnvironment["TRANSLESS_SEED_HIST"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 25), "App 没起来")
        Thread.sleep(forTimeInterval: 3.5)

        let hist = app.buttons["kb.hist"]
        XCTAssertTrue(hist.waitForExistence(timeout: 8), "🚨 找不到历史钮")
        hist.tap()
        Thread.sleep(forTimeInterval: 1.5)
        XCTAssertTrue(app.otherElements["kb.hist.panel"].waitForExistence(timeout: 4),
                      "🚨 历史面板没开 —— 下面量的就不是这一屏")

        let rows = app.buttons.matching(
            NSPredicate(format: "identifier == %@", "transless.hist.row"))
        XCTAssertGreaterThan(rows.count, 2,
                             "🚨 只有 \(rows.count) 行 —— 量不出行与行的差")

        // 🚨 **先确认那条会触发问题的数据真的在场。**
        //    种子曾被 `isEmpty` 守卫静默挡掉，判据于是一直在量旧的短句数据、
        //    一直绿 —— 而现象在他手机上明摆着。
        //    **喂不到数据的判据 = 不存在的判据。**
        let multiline = app.buttons.matching(
            NSPredicate(format: "identifier == %@ AND label CONTAINS %@",
                        "transless.hist.row", "测试语音录入")).firstMatch
        XCTAssertTrue(multiline.waitForExistence(timeout: 5),
                      "🚨 带换行的整理档那条没在列表里 —— 种子没生效，"
                      + "下面量出来的都不算数")

        var heights: [CGFloat] = []
        var detail: [String] = []
        let keeps = app.descendants(matching: .any)
            .matching(identifier: "transless.hist.keep")
        for i in 0..<rows.count {
            let r = rows.element(boundBy: i)
            guard r.exists else { continue }
            heights.append(r.frame.height)
            detail.append("第\(i + 1)行 y=\(Int(r.frame.minY)) h=\(r.frame.height)")
        }
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "HISTH_01_行高"; a.lifetime = .keepAlways; add(a)

        // 🚨🚨 **他说的是「中间隔这么开」= 行与行之间的间距，不是行本身的高。**
        //    第一版我量的是行按钮的高度 —— 绿了，而现象还在。**量错了对象。**
        //    行高一致 + 间距不一致，看起来就是"有的挨着、有的隔一大块"。
        var gaps: [CGFloat] = []
        var gapDetail: [String] = []
        for i in 0..<max(0, rows.count - 1) {
            let a0 = rows.element(boundBy: i).frame
            let b0 = rows.element(boundBy: i + 1).frame
            let g = b0.minY - a0.maxY
            gaps.append(g)
            gapDetail.append("第\(i + 1)→\(i + 2) 行间距 \(g)")
        }
        if let glo = gaps.min(), let ghi = gaps.max() {
            XCTAssertLessThanOrEqual(ghi - glo, 1.0,
                "🚨 **行间距不一致**（他说的就是这个）：最小 \(glo) / 最大 \(ghi)，"
                + "差 \(ghi - glo)pt｜" + gapDetail.joined(separator: "，"))
            // 反向对照：间距一致但**整体过大**也是他抱怨的一半（「不要隔这么开」）
            XCTAssertLessThanOrEqual(ghi, 14,
                "🚨 行间距 \(ghi)pt 太开了 —— 他原话「不要隔这么开」"
                + "｜" + gapDetail.joined(separator: "，"))
        }

        let lo = heights.min() ?? 0
        let hi = heights.max() ?? 0
        // 🚨 先把读数打出来 —— 「差多少」比「差了」有用得多。
        //    容差 1pt：同一种行在不同位置有半像素抖动是正常的，
        //    而"带按钮 vs 不带按钮"的差是十几 pt 级别，这个容差分得开。
        XCTAssertLessThanOrEqual(hi - lo, 1.0,
            "🚨 行高不一致，最矮 \(lo) / 最高 \(hi)，差 \(hi - lo)pt"
            + "｜收藏钮 \(keeps.count) 个 / 共 \(rows.count) 行"
            + "｜" + detail.joined(separator: "，"))
    }
}
