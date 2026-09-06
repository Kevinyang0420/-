import XCTest

/// 录音诊断**他粘出来的那一行**。
///
/// 🚨 0 从 Kevin 手机上那份诊断查出来的坏形状：
/// ```
/// 09-06 13:24:27  0.0s 0KB  出稿完成：（第 1 段未转出，无内容）
/// 09-06 14:52:35  0.0s 0KB  出稿完成：Testing, testing.   ← 成功那次也是 0
/// ```
///    「出稿完成 / 出稿失败」这两行写死传 0 —— 值不是没记，是**记在别的行上**。
///    而这份诊断存在的唯一理由，就是分开「麦克风没收到」和「收到了但没转出」。
///
/// 🚨 判据挂在**渲染出来的那行字**上，不挂在「`RecLog.add` 被调用了」上。
///    「记了」和「他看得见」是两件事。
final class RecLineTests: XCTestCase {

    /// 真值进去，粘出来就要看得见秒数和体积。
    func testRealValuesShowUp() {
        let s = RecLine.render(when: "09-06 16:03:21", sec: 120.0,
                               bytes: 3_840_044, result: "出稿完成",
                               detail: "送出 2 段｜Testing")
        XCTAssertTrue(s.contains("120.0s"), "🚨 秒数没出现在他粘出来的文本里：\(s)")
        XCTAssertTrue(s.contains("3750KB"), "🚨 体积没出现：\(s)")
        XCTAssertTrue(s.contains("送出 2 段"), "🚨 段数没出现：\(s)")
    }

    /// 🚨 **坏样本 = 他手机上那个真实形状**：sec/bytes 传 0。
    ///    判据必须认出它，否则这条判据等于没有。
    func testZeroLineIsRecognised() {
        let bad = RecLine.render(when: "09-06 13:24:27", sec: 0, bytes: 0,
                                 result: "出稿完成", detail: "（第 1 段未转出，无内容）")
        XCTAssertTrue(bad.contains("0.0s 0B"),
                      "🚨 复现不出他看到的那个形状，说明我在测别的东西：\(bad)")
        XCTAssertFalse(RecLine.carriesAudioFacts(bad),
                       "🚨 判据认不出 `0.0s 0B` —— 那它永远不会失败")
    }

    /// 反向对照：有数的那行必须被判为**带了音频事实**。
    /// 🚨 只测"能认出 0"的话，一个恒返回 false 的实现也会绿。
    func testNonZeroLinePasses() {
        let good = RecLine.render(when: "09-06 16:03:21", sec: 12.3,
                                  bytes: 393_600, result: "出稿完成", detail: "hi")
        XCTAssertTrue(RecLine.carriesAudioFacts(good),
                      "🚨 有数的行被判成没数 —— 判据恒为假，比没有更糟：\(good)")
    }

    /// 边界：只有秒数为 0、体积不为 0（传了但极短）→ 仍算带了事实。
    func testPartialZeroStillCounts() {
        let s = RecLine.render(when: "x", sec: 0, bytes: 44,
                               result: "出稿失败", detail: "")
        XCTAssertTrue(s.contains("44B"),
                      "🚨 不足 1KB 被整除成 0KB —— 「传了 44 字节」和"
                      + "「一个字节都没传」在他眼里就一样了：\(s)")
        XCTAssertTrue(RecLine.carriesAudioFacts(s),
                      "🚨 体积有数却被判成没事实 —— 会把'传了 44 字节'误当'什么都没传'")
    }

    /// detail 为空时不许留下一个尾巴冒号。
    func testEmptyDetail() {
        let s = RecLine.render(when: "x", sec: 1, bytes: 1024,
                               result: "起录闸通过", detail: "")
        XCTAssertTrue(s.hasSuffix("起录闸通过"), "🚨 空 detail 留了尾巴：\(s)")
    }
}
