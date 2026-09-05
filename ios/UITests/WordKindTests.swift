import XCTest

/// **单词本自动归类的判据本身**（纯逻辑，不开界面，跑得快）。
///
/// 🚨 2.1 点名的坏样本放在最后一条：灌 3 条单词 + 3 条带句号长句，
///    **「词组」整段必须不出现**。它打的是"标题写死"——
///    那种 bug 数据齐全时看不出来，只有让某一段真的空掉才会现形。
final class WordKindTests: XCTestCase {

    func testKinds() {
        XCTAssertEqual(WordKind.of("hello"), .word)
        XCTAssertEqual(WordKind.of("  hello  "), .word, "首尾空白不该改变判定")
        XCTAssertEqual(WordKind.of("kick the bucket"), .phrase, "3 个词无句末标点＝词组")
        XCTAssertEqual(WordKind.of("as soon as possible"), .phrase, "4 个词＝词组上限")
        XCTAssertEqual(WordKind.of("I would like to know"), .sentence, "5 个词＝句子")
        // 🚨 标点优先于词数：2 个词但带句号，是句子不是词组
        XCTAssertEqual(WordKind.of("Thanks."), .sentence)
        XCTAssertEqual(WordKind.of("Really?"), .sentence)
        // 🚨 中文句末标点也要认 —— 只写 ASCII 的话中文句子会被判成词组
        XCTAssertEqual(WordKind.of("好的。"), .sentence)
        XCTAssertEqual(WordKind.of("是吗？"), .sentence)
    }

    /// 🚨🚨 **2.1 的坏样本**：只有词和句子时，「词组」整段不许出现。
    func testEmptySectionDisappears() {
        let items = ["hello", "world", "book",
                     "I would like to know more.",
                     "Could you please repeat that.",
                     "This is a long sentence here."]
        let g = WordKind.group(items) { $0 }
        let kinds = g.map { $0.kind }
        XCTAssertEqual(kinds, [.word, .sentence],
                       "🚨 「词组」是空的，整段就不该出现（现在是 \(kinds)）")
        XCTAssertEqual(g.first?.items.count, 3)
        XCTAssertEqual(g.last?.items.count, 3)
    }

    /// 反向控制：三段都有内容时，三段都要在 —— 否则上一条可能是
    /// 「分组根本没工作」而不是「空段被正确藏起来」。
    func testAllThreeAppear() {
        let items = ["hello", "kick the bucket", "I would like to know more."]
        let g = WordKind.group(items) { $0 }
        XCTAssertEqual(g.map { $0.kind }, [.word, .phrase, .sentence])
    }
}
