import XCTest

/// **词性要按义项分节** —— Kevin 2026-09-06：「commute 只给了动词，名词没写上来」。
///
/// 🚨 1.1 实测后端数据是**对的**（v./n./v. 三条，名词义在、pos 也对），
///    丢在渲染这一层：整卡只标第一条的词性，名词那条摆在 `v.` 标题底下。
///
/// 🚨 判据要**两个方向**：
///    · 多词性的词（commute）→ 解析出来必须有 n.，且同 pos 相邻
///    · 单词性的词（elapse）→ **不许凭空多出一个词性**
///      （1.1 实测模型真的编过 `{"pos":"n.","en":"the passing of time"}`）
///    只验前者的话，一个"总是多给一个 n."的实现也会绿 —— 那正是修之前的毛病。
final class PosSectionTests: XCTestCase {

    private func parse(_ word: String, _ json: String) -> DictEntry? {
        return DictParse.entry(word: word, raw: json)
    }

    /// commute：三条义项各自带词性，**n. 那条必须在**。
    func testEachSenseKeepsItsOwnPos() {
        let e = parse("commute", """
        {"word":"commute","phonetic":"kəˈmjuːt",
         "senses":[
           {"pos":"v.","en":"to travel regularly between home and work","zh":"通勤"},
           {"pos":"n.","en":"the journey to and from work","zh":"通勤路程"},
           {"pos":"v.","en":"to reduce a legal punishment","zh":"减刑"}]}
        """)
        XCTAssertNotNil(e, "🚨 解析失败，下面都测不到")
        let poses = e?.senses.map { $0.pos } ?? []
        XCTAssertEqual(poses, ["v.", "n.", "v."],
                       "🚨 逐条词性没保住：\(poses)")
        XCTAssertTrue(poses.contains("n."),
                      "🚨 名词那条的词性丢了 —— 他看到的就是「名词没写上来」")
    }

    /// 🚨 **整卡词性不许再从第一条义项推出来。**
    ///    那个 fallback 正是「commute 整卡标成 v.」的成因。
    func testCardPosNotDerivedFromFirstSense() {
        let e = parse("commute", """
        {"word":"commute",
         "senses":[{"pos":"v.","en":"a","zh":"甲"},{"pos":"n.","en":"b","zh":"乙"}]}
        """)
        XCTAssertEqual(e?.pos, "",
                       "🚨 整卡词性又是从第一条义项来的（拿到 \(e?.pos ?? "?")）"
                       + " —— 页头会标成 v.，名词那条就藏在它底下")
    }

    /// 反向对照：**旧结构**（顶层有 pos）要照常能用，别为了修新的把旧的弄坏。
    func testLegacyTopLevelPosStillWorks() {
        let e = parse("quaint", """
        {"word":"quaint","pos":"adj.",
         "senses":[{"en":"attractively unusual","zh":"古雅的"}]}
        """)
        XCTAssertEqual(e?.pos, "adj.",
                       "🚨 旧结构的整卡词性被一起删掉了 —— 存量卡片会没有词性")
    }

    /// 单词性的词：**不许多出一个**。
    /// 🚨 只测"多词性能显示"的话，一个总是多给一个 n. 的实现也会绿。
    func testSinglePosStaysSingle() {
        let e = parse("elapse", """
        {"word":"elapse",
         "senses":[{"pos":"v.","en":"to pass by","zh":"流逝"}]}
        """)
        let uniq = Set((e?.senses.map { $0.pos } ?? []).filter { !$0.isEmpty })
        XCTAssertEqual(uniq, ["v."],
                       "🚨 单词性的词冒出了别的词性：\(uniq)")
    }
}

/// **例句要收全** —— 2.1 2026-09-06 指出的根因层：`DictParse` 原来 `arr.first`
/// 只取第一条，后端给多条，界面只显示一条、收藏也只存得下一条。
///
/// 🚨 2.1 点出：**现有自测样本全都只有一条例句**，所以"解析多条对不对"
///    从来没被测过。改错了没人拦 —— 这条就是补那个缺口。
final class MultiExampleTests: XCTestCase {

    private func parse(_ w: String, _ j: String) -> DictEntry? {
        return DictParse.entry(word: w, raw: j)
    }

    /// 三条例句要全部解出来。
    func testAllExamplesParsed() {
        let e = parse("commute", """
        {"word":"commute","senses":[{"pos":"v.","en":"a","zh":"甲"}],
         "examples":[{"en":"one","zh":"一"},{"en":"two","zh":"二"},
                     {"en":"three","zh":"三"}]}
        """)
        XCTAssertEqual(e?.examples.count, 3,
                       "🚨 只解出 \(e?.examples.count ?? -1) 条 —— "
                       + "改回 `arr.first` 这条必须红")
        XCTAssertEqual(e?.examples.first?.0, "one")
        XCTAssertEqual(e?.examples.last?.0, "three")
    }

    /// 🚨 旧结构那对平铺字段仍要认，当**第一条**。
    ///    缓存里存着按旧结构存下的条目，不认它会让"以前查过的词打不开"。
    func testLegacyFlatExampleStillWorks() {
        let e = parse("take", """
        {"word":"take","senses":[{"en":"a","zh":"甲"}],
         "example_en":"Take your time.","example_zh":"慢慢来。"}
        """)
        XCTAssertEqual(e?.examples.count, 1, "🚨 老结构的例句读不出来了")
        XCTAssertEqual(e?.exampleEn, "Take your time.",
                       "🚨 兼容取值坏了 —— 老调用点会拿到空串")
    }

    /// 反向对照：一条都没有时不许凭空造出一条空的。
    func testNoExamplesStaysEmpty() {
        let e = parse("x", """
        {"word":"x","senses":[{"en":"a","zh":"甲"}]}
        """)
        XCTAssertEqual(e?.examples.count, 0,
                       "🚨 没有例句却造出了 \(e?.examples.count ?? -1) 条空的")
    }

    /// 收藏往返：三条存下去，读回来还是三条。
    func testExamplesSurviveSaveAndLoad() {
        let e = parse("commute", """
        {"word":"commute","senses":[{"pos":"v.","en":"a","zh":"甲"}],
         "examples":[{"en":"one","zh":"一"},{"en":"two","zh":"二"},
                     {"en":"three","zh":"三"}]}
        """)!
        let back = WordCard.parse(WordCard.fromDict(e))
        XCTAssertEqual(back.examples.count, 3,
                       "🚨 落盘一轮只剩 \(back.examples.count) 条 —— "
                       + "单词本读的正是这份数据")
    }
}
