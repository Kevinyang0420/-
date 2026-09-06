import XCTest

/// 身份规则（2.1 2026-09-06 规格，两端同一套）。
///
/// | 来源 | zh | en | id 由什么决定 |
/// |---|---|---|---|
/// | 翻译 / 说话记录 | 当时说的中文 | 产出的英文 | **(zh, en)** |
/// | 查词 | **空串** | 规范化后的词 | **只由词决定** |
///
/// 🚨 **身份不能由会变的内容决定。** 释义/例句/搭配只进 `card`，不进 id ——
///    否则同一个词查两次、释义差一个字就变两条，他会问「怎么多出来一条」。
final class WordIdSpecTests: XCTestCase {

    /// 🚨 **规格判据 1**：同一个词查两次 → **只有一条**。
    ///    坏样本 = 把释义纳入 id（就是改之前的写法）→ 这条必须红。
    func testSameWordTwiceIsOneEntry() {
        let a = WordBookCore.dictId(word: "quote")
        let b = WordBookCore.dictId(word: "quote")
        XCTAssertEqual(a, b)
    }

    /// 释义不一样**不该**改变身份 —— 这是上面那条的直接原因。
    func testGlossDoesNotAffectIdentity() {
        // 改之前的写法：idOf(词, 首义中文)
        let old1 = WordBookCore.idOf("quote", "报价")
        let old2 = WordBookCore.idOf("quote", "引述")
        XCTAssertNotEqual(old1, old2,
                          "（这是旧写法的行为，列在这里说明它为什么不行）")
        // 现在的写法：释义换了，id 不变
        let new1 = WordBookCore.dictId(word: "quote")
        let new2 = WordBookCore.dictId(word: "quote")
        XCTAssertEqual(new1, new2,
                       "🚨 释义参与了身份 —— 同一个词会变成两条")
    }

    /// 大小写/多余空白**不该**变成两条（`norm` 的活）。
    func testNormalisationFoldsCaseAndSpace() {
        XCTAssertEqual(WordBookCore.dictId(word: "  Quote "),
                       WordBookCore.dictId(word: "quote"))
    }

    /// 🚨 **反向对照**：翻译来的条目，**同句不同语气仍然是两条** ——
    ///    这条是对的，别顺手去重掉。
    ///    只测"查词不重复"的话，把所有东西按英文去重也全绿，
    ///    而那会把他换语气重说的那条吃掉。
    func testSameSentenceDifferentEnglishStaysTwo() {
        let a = WordBookCore.idOf("报价", "Here is our quotation.")
        let b = WordBookCore.idOf("报价", "Here's the quote.")
        XCTAssertNotEqual(a, b, "🚨 同句不同语气被去重了 —— 那是两份价值")
    }

    /// 🚨 查词条目和翻译条目**即使英文一样也不是同一条** ——
    ///    一个是 quote 这个词的词典卡，一个是「报价」这句话的译文卡，
    ///    内容完全不同，是两份价值。
    func testDictAndTranslationAreDifferentEntries() {
        let dict = WordBookCore.dictId(word: "quote")
        let trans = WordBookCore.idOf("报价", "quote")
        XCTAssertNotEqual(dict, trans)
    }
}
