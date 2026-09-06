import XCTest

/// **分段路径**的静音处理 —— Kevin 撞的就是这条。
///
/// 🚨 他的原话是「提示**第一段**未转出无内容」。「第一段」＝分段。
///    我上一轮把判据装到了短录音那条路上，**这条一行没碰**：
/// ```
/// 短录音（不分段）  ✅ 有闸 · 有留音频
/// 长录音（分段）    ❌ 一样都没有      ← 他撞的
/// ```
///    **同一个功能两条路，修完一条不等于修完。**
///    这次的分叉在**数据路径**上，比 UI 出口更难看见 ——
///    UI 出口能靠 grep 名字找齐，数据路径要读调用链才知道有两条。
final class SegmentsSilenceTests: XCTestCase {

    private func wav(_ samples: [Int16]) -> Data {
        var d = Data(repeating: 0x41, count: AudioStats.headerBytes)
        for s in samples {
            var v = s.littleEndian
            withUnsafeBytes(of: &v) { d.append(contentsOf: $0) }
        }
        return d
    }

    private func tone(_ n: Int) -> [Int16] {
        (0..<n).map { Int16(8000 * sin(Double($0) * 0.2)) }
    }

    private func silence(_ n: Int) -> [Int16] { [Int16](repeating: 0, count: n) }

    // MARK: - 🚨 静音段不许发请求（一次次花钱换同一个空结果）

    func testSilentSegmentIsNotSent() {
        var sent = 0
        let sg = Segments { _, done in
            sent += 1
            done(.success("不该被调到"))
        }
        sg.submit(wav: wav(silence(4000)))
        XCTAssertEqual(sent, 0,
                       "🚨 数字静音也发上去了 —— 每段都在花钱换同一个空结果")
        XCTAssertEqual(sg.skippedSilent, 1)
        XCTAssertFalse(sg.sawSound)
    }

    /// 🚨 **反向对照**：有声音的段**必须照发** ——
    ///    只测"静音不发"的话，把所有段都拦下也全绿，而那等于功能没了。
    func testAudibleSegmentIsSent() {
        var sent = 0
        let sg = Segments { _, done in
            sent += 1
            done(.success("你好"))
        }
        sg.submit(wav: wav(tone(4000)))
        XCTAssertEqual(sent, 1, "🚨 有声音的段被拦下了 —— 他说的话根本没上传")
        XCTAssertTrue(sg.sawSound)
        XCTAssertEqual(sg.skippedSilent, 0)
    }

    // MARK: - 🚨 他撞的那一档：说了话，但每段都转不出来

    func testSawSoundWhenAllSegmentsFail() {
        let sg = Segments { _, done in
            done(.failure(NSError(domain: "t", code: 1)))
        }
        sg.submit(wav: wav(tone(4000)))
        sg.submit(wav: wav(tone(4000)))
        XCTAssertTrue(sg.sawSound,
                      "🚨 `sawSound` 为假的话，收尾会判成'麦克风没收到声音'，"
                      + "而他明明说了话 —— 音频会被扔掉、也不给重发键")
    }

    /// 段号必须**连续**：静音段仍然占一个位置。
    /// 🚨 不占位的话，拼出来的「第 N 段」跟他实际说的第几段对不上，
    ///    他去回想"我第二段说了什么"会对错地方。
    func testSilentSegmentStillTakesAnIndex() {
        let sg = Segments { _, done in done(.success("有")) }
        sg.submit(wav: wav(silence(4000)))   // 第 1 段：静音
        sg.submit(wav: wav(tone(4000)))      // 第 2 段：有声
        XCTAssertEqual(sg.count, 2, "🚨 静音段没占段号 —— 后面的段号会整体前移")
        let out = sg.awaitAll(waitSec: 3)
        XCTAssertTrue(out.contains("第 1 段"),
                      "🚨 静音那段没在结果里留痕，他不知道哪一段丢了：\(out)")
    }

    /// 混合：先静音后说话 → **算收到过声音**（拿不准偏向"他说了话"）。
    func testMixedCountsAsSawSound() {
        let sg = Segments { _, done in done(.success("你好")) }
        sg.submit(wav: wav(silence(4000)))
        sg.submit(wav: wav(tone(4000)))
        XCTAssertTrue(sg.sawSound)
    }
}
