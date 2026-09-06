import XCTest

/// 「字节 → 零占比」这半 —— **用合成的真 PCM 字节测，不是手打的百分数。**
///
/// 🚨 我原来只测了「数字 → 判定」那半（`SilenceVerdictTests`）。
///    那些数是我手打的，**证明不了解析对不对** ——
///    偏移算错、按字节而不是按采样点数、忘了跳 44 字节 WAV 头，
///    这些错在那一组用例里全都看不见。
///
/// 🚨 仓库里没有现成录音，**真机正向验证要 Kevin 对着手机说一段**（我做不了）。
///    这一组是我能做到的最接近的一层：**造真的 PCM 字节**，
///    走真正在跑的那个函数。
final class AudioStatsTests: XCTestCase {

    /// 造一段 16-bit 单声道 PCM（带 44 字节头）。
    /// - Parameter sample: 每个采样点的值；`nil` = 数字零。
    private func wav(samples: [Int16]) -> Data {
        var d = Data(repeating: 0x41, count: AudioStats.headerBytes)  // 头填非零
        for s in samples {
            var v = s.littleEndian
            withUnsafeBytes(of: &v) { d.append(contentsOf: $0) }
        }
        return d
    }

    /// 正弦波 = "真的录到了声音"。
    private func tone(_ n: Int) -> [Int16] {
        (0..<n).map { i in
            Int16(8000 * sin(Double(i) * 0.2))
        }
    }

    // MARK: - 真数字静音

    /// `setInputMuted` 真生效时，整段是数字零 → 100%。
    func testDigitalSilenceIsHundred() {
        XCTAssertEqual(AudioStats.zeroPct(wav(samples: [Int16](repeating: 0, count: 4000))),
                       100)
    }

    /// 🚨 **头必须被跳过**：头里我填的是非零字节，
    ///    没跳的话它们会被算成"有声音"，把 100% 拉下来。
    ///    这正是"忘了跳 44 字节头"那种错，手打百分数的用例抓不到。
    func testHeaderIsSkipped() {
        let d = wav(samples: [Int16](repeating: 0, count: 4000))
        XCTAssertEqual(AudioStats.zeroPct(d), 100,
                       "🚨 WAV 头被算进采样点了 —— 真静音会读不出 100%")
    }

    // MARK: - 真有声音

    func testToneIsMostlyNonZero() {
        let z = AudioStats.zeroPct(wav(samples: tone(4000)))
        XCTAssertLessThan(z, 20,
                          "🚨 正弦波被读成大片零 —— 说明按字节而不是按采样点在数")
        XCTAssertFalse(SilenceVerdict.micGotNothing(zeroPct: z),
                       "🚨 真有声音的一段被判成'麦克风没收到' —— 他说的话会被扔掉")
    }

    /// 🚨 **反向对照**：真有声音时，`respeak` 也必须留住音频。
    ///    这条把两半接起来验 —— 只验其中一半，接错了也全绿。
    func testRealAudioKeepsRetry() {
        let z = AudioStats.zeroPct(wav(samples: tone(4000)))
        XCTAssertTrue(
            SilenceVerdict.keepAudioForRetry(needsRespeak: true, zeroPct: z),
            "🚨 他说了一大段，后端说没听出来，我们把音频扔了")
    }

    // MARK: - 边角

    /// 太短的数据不下结论（回 -1），**并且按"有声音"处理**。
    func testTooShortIsUnknown() {
        XCTAssertEqual(AudioStats.zeroPct(Data(repeating: 0, count: 10)), -1)
        XCTAssertEqual(AudioStats.zeroPct(nil), -1)
        XCTAssertFalse(SilenceVerdict.micGotNothing(zeroPct: -1))
    }

    /// 半静音（前一半有声、后一半零）应当落在中间，**不该被判死**。
    func testHalfSilenceIsNotDead() {
        let z = AudioStats.zeroPct(
            wav(samples: tone(2000) + [Int16](repeating: 0, count: 2000)))
        XCTAssertGreaterThan(z, 30)
        XCTAssertLessThan(z, 80)
        XCTAssertFalse(SilenceVerdict.micGotNothing(zeroPct: z),
                       "🚨 他说了半句然后停下 —— 那也是说了话")
    }
}
