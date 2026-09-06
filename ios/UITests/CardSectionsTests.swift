import XCTest

/// `CardSections` 的纯逻辑自测 —— 不需要模拟器、不需要后端。
///
/// 🚨 **后端那半还没上线**（我实测：查整句返回的仍是词卡形状，连 `kind` 都没有），
///    所以这一层**只能用夹具验**。夹具绿 ≠ 功能通 ——
///    端到端等 1.1 上线 `kind` 分流之后再验，我不拿这些绿冒充通过。
final class CardSectionsTests: XCTestCase {

    private func obj(_ s: String) -> [String: Any] {
        return (try? JSONSerialization.jsonObject(with: Data(s.utf8)))
            as? [String: Any] ?? [:]
    }

    private let titles = (meaning: "意思", breakdown: "结构",
                          alternatives: "换个说法", keys: "搭配")

    /// 🚨 **老后端不带 `kind` → 必须仍当词卡**。
    ///    这条是"老行为不变"的保险：`kind` 上线前后，老返回的渲染一个字不许变。
    func testMissingKindIsWord() {
        XCTAssertFalse(CardSections.isSentence(
            obj("{\"word\":\"commute\",\"senses\":[]}")),
            "🚨 不带 kind 的返回被当成句子了 —— 老客户端行为会变")
    }

    func testKindWordIsWord() {
        XCTAssertFalse(CardSections.isSentence(obj("{\"kind\":\"word\"}")))
    }

    func testKindSentenceIsSentence() {
        XCTAssertTrue(CardSections.isSentence(obj("{\"kind\":\"sentence\"}")))
    }

    /// 🚨 **不许按输入形状猜**。规格点名：英文短语有空格、中文句子没空格，
    ///    任何本地规则都会在某一门语言上错**且不报错**。
    ///    这条钉的就是"判据只挂在返回值上"。
    func testDoesNotGuessFromTheQueryShape() {
        // 带空格的短语，模型说它是词 → 必须当词
        XCTAssertFalse(CardSections.isSentence(
            obj("{\"kind\":\"word\",\"word\":\"take issue with\"}")),
            "🚨 带空格就被判成句子了 —— 那是在按输入形状猜")
        // 不带空格的中文句子，模型说它是句 → 必须当句
        XCTAssertTrue(CardSections.isSentence(
            obj("{\"kind\":\"sentence\",\"meaning\":\"麻烦周五前把提案发我\"}")),
            "🚨 没空格就被判成词了 —— 中文句子会全军覆没")
    }

    func testSentenceSectionsInOrder() {
        let o = obj("""
        {"kind":"sentence","meaning":"能不能周五前把提案发给我",
         "breakdown":[{"part":"Could you","role":"提出请求",
                       "note":"比 Can you 客气，套在任何请求前都成立"}],
         "alternatives":[{"en":"Would you mind sending it by Friday?",
                          "when":"更正式"}],
         "keys":[{"en":"by Friday","zh":"周五前"}]}
        """)
        let s = CardSections.sentence(o, titles: titles)
        XCTAssertEqual(s.map { $0.title }, ["意思", "结构", "换个说法", "搭配"],
                       "🚨 段落顺序不对")
        XCTAssertEqual(s[0].rows, ["能不能周五前把提案发给我"])
        XCTAssertTrue(s[1].rows[0].contains("提出请求"), "🚨 role 没画出来")
        XCTAssertTrue(s[1].rows[0].contains("套在任何请求前"),
                      "🚨 note 没画出来 —— 「可参考的句式」他专门提的就是这里")
    }

    /// 🚨 **空段不出现**。先摆标题再填内容的话，没数据时会留一排孤零零的标题。
    func testEmptySectionsAreDropped() {
        let s = CardSections.sentence(
            obj("{\"kind\":\"sentence\",\"meaning\":\"只有意思\"}"), titles: titles)
        XCTAssertEqual(s.map { $0.title }, ["意思"],
                       "🚨 空的段落也画出来了")
    }

    /// 整块都空时**一段都不许有** —— 而不是画一堆空标题。
    func testAllEmptyGivesNothing() {
        XCTAssertTrue(CardSections.sentence(
            obj("{\"kind\":\"sentence\"}"), titles: titles).isEmpty)
    }

    /// 存进单词本的字段（规格第三节）。
    func testWordbookFields() {
        let f = CardSections.wordbookFields(
            obj("{\"kind\":\"sentence\",\"meaning\":\"周五前发我\"}"),
            query: "  Could you send it by Friday?  ")
        XCTAssertEqual(f.zh, "周五前发我")
        XCTAssertEqual(f.en, "Could you send it by Friday?", "🚨 首尾空白没去掉")
        XCTAssertEqual(f.span, "full", "🚨 整句必须是 full")
    }
}
