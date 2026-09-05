import XCTest

/// **拼字母 vs 说单词的判断**（纯逻辑，跑得快）。
///
/// 🚨 这是 2.1 规格点名的薄弱处：今天早上 Kevin 说「选**乙**」，
///    我们自己的转写听成了「**E**」—— 单字母/拼读序列正是 ASR 链路最容易错的地方。
///    2.1：「不是不做的理由，是**必须先验**的理由」。
///
/// 🚨 这里验的是**收敛这一层**（拿到文本之后判断得对不对），
///    **不是** ASR 本身准不准。两件事，别混为一谈 ——
///    这一层全绿也不代表真机上拼 `K-U-C-Y-N` 能查到 `KUCYN`。
///    真机那条我会单独报，过不了就如实说。
final class SpellFoldTests: XCTestCase {

    func testSpelledForms() {
        // ASR 会把拼读转成各种样子，这几种都要认
        XCTAssertEqual(SpellFold.fold("K U C Y N"), "KUCYN")
        XCTAssertEqual(SpellFold.fold("K-U-C-Y-N"), "KUCYN")
        XCTAssertEqual(SpellFold.fold("k、u、c、y、n"), "KUCYN")
        XCTAssertEqual(SpellFold.fold("  K U C Y N  "), "KUCYN")
    }

    /// 🚨 **反向控制：说单词的时候绝不许被拼起来。**
    ///    没有这一条的话，一个"永远拼接"的实现会让上面全绿，
    ///    而他说 `ubiquitous` 会被查成 `UBIQUITOUS`… 更糟的是
    ///    说一句话会被拼成一串乱码。
    func testWordsAreNotFolded() {
        XCTAssertEqual(SpellFold.fold("ubiquitous"), "ubiquitous")
        XCTAssertEqual(SpellFold.fold("take issue with"), "take issue with")
        XCTAssertEqual(SpellFold.fold("报价"), "报价")
        // 两段单字母不算拼读 —— 更可能是缩写或真词
        XCTAssertEqual(SpellFold.fold("I T"), "I T")
        // 有一段是完整单词 → 那就是在说话
        XCTAssertEqual(SpellFold.fold("K U CAT Y"), "K U CAT Y")
    }

    func testLooksSpelledItself() {
        XCTAssertTrue(SpellFold.looksSpelled("A B C"))
        XCTAssertFalse(SpellFold.looksSpelled("A B"), "两段不该算拼读")
        XCTAssertFalse(SpellFold.looksSpelled("hello world there"))
        XCTAssertFalse(SpellFold.looksSpelled(""))
    }
}
