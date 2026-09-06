import XCTest

/// 单词本卡片的解析。Kevin 2026-09-06 连问三次「单词卡片在哪儿呢」。
///
/// 🚨 这里测的是**解析**，不是"卡片好不好看"。好不好看要看截图。
final class WordCardTests: XCTestCase {

    // MARK: - 形态 A · 查词

    func testParsesDictCard() {
        let raw = """
        {"kind":"word","phonetic":"juːˈbɪkwɪtəs","pos":"adj.",
         "senses":[{"en":"present everywhere","zh":"无处不在的"}],
         "examples":[{"en":"Phones are ubiquitous.","zh":"手机随处可见。"}],
         "collocations":["ubiquitous presence"]}
        """
        let c = WordCard.parse(raw)
        XCTAssertEqual(c.phonetic, "juːˈbɪkwɪtəs")
        XCTAssertEqual(c.pos, "adj.")
        XCTAssertEqual(c.senses.count, 1)
        XCTAssertEqual(c.senses.first?.1, "无处不在的")
        XCTAssertEqual(c.examples.count, 1)
        XCTAssertEqual(c.collocations, ["ubiquitous presence"])
        XCTAssertFalse(c.isEmpty)
    }

    // MARK: - 形态 B · 句子 / 词组

    func testParsesSentenceCard() {
        let raw = """
        {"kind":"sentence",
         "breakdown":[{"part":"I'd like to","role":"礼貌开头","note":"比 I want 客气"}],
         "alternatives":[{"en":"Could I get","when":"更随意"}],
         "keys":[{"en":"I'd like to","zh":"我想要"}]}
        """
        let c = WordCard.parse(raw)
        XCTAssertEqual(c.breakdown.count, 1)
        XCTAssertEqual(c.breakdown.first?.role, "礼貌开头")
        XCTAssertEqual(c.alternatives.first?.when, "更随意")
        XCTAssertEqual(c.keys.first?.0, "I'd like to")
        XCTAssertFalse(c.isEmpty)
    }

    // MARK: - 🚨 坏数据不许把详情页搞崩

    /// 空串 = 老条目（收藏时还没这功能）。**要如实回空卡片**，详情页说"还没有"。
    func testEmptyStringIsEmptyCard() {
        XCTAssertTrue(WordCard.parse("").isEmpty)
    }

    /// 存进去半份坏 JSON —— **回空卡片，不许抛**。
    /// 🚨 详情页打不开比没有卡片严重得多。
    func testBrokenJsonDoesNotCrash() {
        XCTAssertTrue(WordCard.parse("{\"senses\":[{\"en\":").isEmpty)
        XCTAssertTrue(WordCard.parse("不是 JSON").isEmpty)
        XCTAssertTrue(WordCard.parse("[1,2,3]").isEmpty)
    }

    /// 字段在但**类型不对**（后端改了字段类型）—— 同样不许崩。
    func testWrongTypesAreIgnored() {
        let c = WordCard.parse("{\"senses\":\"不是数组\",\"collocations\":42}")
        XCTAssertTrue(c.isEmpty)
    }

    /// 🚨 **只有壳没有内容也算空** —— 画个空框会让他以为坏了。
    func testEmptyArraysCountAsEmpty() {
        XCTAssertTrue(WordCard.parse(
            "{\"senses\":[],\"examples\":[],\"breakdown\":[]}").isEmpty)
    }

    /// 缺字段的条目按空串补，不整条丢掉 —— 有一半也比没有强。
    func testMissingSubfieldsFallBackToEmpty() {
        let c = WordCard.parse("{\"senses\":[{\"zh\":\"只有中文\"}]}")
        XCTAssertEqual(c.senses.count, 1)
        XCTAssertEqual(c.senses.first?.0, "")
        XCTAssertEqual(c.senses.first?.1, "只有中文")
        XCTAssertFalse(c.isEmpty)
    }
}
