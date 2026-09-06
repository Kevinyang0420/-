import XCTest

/// **会被切段的长录音** —— Kevin 撞的那条路，之前只在"两三段"的样本上验过。
///
/// 🚨 0 指出：判据接上了、正反两向也测了，**但没在真的会被切段的长度上跑过**。
///    段数一多，暴露的是另一类问题：
///    段号会不会错位、`sawSound` 会不会被后面的静音段冲掉、
///    全部失败时拼出来的提示是不是每段都有。
///
/// 🚨 **不挂着等他去说话** —— 音频可以合成，段可以直接喂。
///    等真人说话才验的东西，就是永远不会被验的东西。
final class LongRecordingSegmentTests: XCTestCase {

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

    /// 十段真说话：**段号连续、全部发出去、拼接顺序不乱**。
    func testTenAudibleSegments() {
        var sent = 0
        let sg = Segments { _, done in
            sent += 1
            let i = sent
            done(.success("第\(i)段"))
        }
        for _ in 0..<10 { sg.submit(wav: wav(tone(2000))) }
        XCTAssertEqual(sent, 10, "🚨 有声音的段没全发出去")
        XCTAssertEqual(sg.count, 10)
        XCTAssertTrue(sg.sawSound)
        XCTAssertEqual(sg.skippedSilent, 0)
        let out = sg.awaitAll(waitSec: 5)
        XCTAssertTrue(out.contains("第1段"), "第一段丢了：\(out)")
        XCTAssertTrue(out.contains("第10段"), "最后一段丢了：\(out)")
    }

    /// 🚨 **他撞的那一档，长版**：说了十段，后端一段都没转出来。
    ///    必须仍然判成"收到过声音" → 留音频 + 给重发键。
    func testTenAudibleSegmentsAllFail() {
        let sg = Segments { _, done in
            done(.failure(NSError(domain: "t", code: 1)))
        }
        for _ in 0..<10 { sg.submit(wav: wav(tone(2000))) }
        XCTAssertTrue(sg.sawSound,
                      "🚨 判成没收到声音 → 他说了十段的音频会被扔掉、还不给重发")
        let out = sg.awaitAll(waitSec: 5)
        // 每一段都要留痕，他才知道丢了几段
        for i in 1...10 {
            XCTAssertTrue(out.contains("第 \(i) 段"),
                          "🚨 第 \(i) 段没留痕，他不知道哪段丢了")
        }
    }

    /// 🚨 **静音段不许冲掉 `sawSound`**：说一段、停很久、再说一段。
    ///    只要有一段有声音，整轮就算收到过声音。
    ///    坏样本会是"最后一段静音就把整轮判死" —— 那正是他停顿之后的情形。
    func testTrailingSilenceDoesNotEraseSawSound() {
        let sg = Segments { _, done in done(.failure(NSError(domain: "t", code: 1))) }
        sg.submit(wav: wav(tone(2000)))          // 说话
        for _ in 0..<5 { sg.submit(wav: wav(silence(2000))) }  // 停顿很久
        XCTAssertTrue(sg.sawSound,
                      "🚨 尾部静音把整轮判死了 —— 他说完停一会儿就会中招")
        XCTAssertEqual(sg.skippedSilent, 5, "静音段应当被跳过、不发请求")
    }

    /// 全程静音的长录音（麦克风没解开）：**一次请求都不许发**。
    /// 🚨 十段各发一次 = 十次花钱换十个空结果。
    func testAllSilentLongRecordingSendsNothing() {
        var sent = 0
        let sg = Segments { _, done in sent += 1; done(.success("x")) }
        for _ in 0..<10 { sg.submit(wav: wav(silence(2000))) }
        XCTAssertEqual(sent, 0, "🚨 全程静音还发了 \(sent) 次请求")
        XCTAssertFalse(sg.sawSound)
        XCTAssertEqual(sg.skippedSilent, 10)
    }
}
