import XCTest

/// **笔记不许被重取吃掉** —— 2.1 方案里点名"最容易漏"的一条。
///
/// > `note` 是卡片上**唯一不会被重取覆盖的字段**。
///
/// 🚨 这条坏掉的样子最阴：他写的笔记在某次重取时悄悄消失，**不报任何错**，
///    等他下次打开才发现，而那时已经不知道是什么时候丢的。
final class NoteSurvivesTests: XCTestCase {

    private let fresh = """
    {"kind":"word","phonetic":"kəˈmjuːt",
     "senses":[{"pos":"v.","en":"a","zh":"甲"},{"pos":"n.","en":"b","zh":"乙"}],
     "examples":[{"en":"one","zh":"一"},{"en":"two","zh":"二"}]}
    """

    /// 写进去读得回来。
    func testNoteRoundTrip() {
        let c = WordCard.withNote(fresh, note: "老板说这个词他常用")
        XCTAssertEqual(WordCard.noteOf(c), "老板说这个词他常用")
        XCTAssertEqual(WordCard.parse(c).note, "老板说这个词他常用")
    }

    /// 🚨 **写笔记不许碰别的字段。**
    func testNoteDoesNotDisturbOtherFields() {
        let c = WordCard.withNote(fresh, note: "n")
        let p = WordCard.parse(c)
        XCTAssertEqual(p.senses.count, 2, "🚨 写笔记把义项弄丢了")
        XCTAssertEqual(p.examples.count, 2, "🚨 写笔记把例句弄丢了")
        XCTAssertEqual(p.phonetic, "kəˈmjuːt", "🚨 写笔记把音标弄丢了")
    }

    /// 🚨 **重取那一刻**：新卡片是后端给的（没有笔记），旧卡片里有笔记 →
    ///    合并之后笔记必须还在，其余字段用新的。
    func testNoteSurvivesRefetch() {
        let old = WordCard.withNote(
            """
            {"kind":"word","senses":[{"en":"旧","zh":"旧"}]}
            """, note: "我的笔记")
        let fromServer = fresh          // 后端刚返回的，没有 note
        // 🚨 走**界面真正调的那个函数**，不在判据里另写一遍合并 ——
        //    另写一遍的话，测的是判据自己，不是真正跑的那段。
        let merged = WordCard.merged(fromServer: fromServer, keepingNoteOf: old)
        let p = WordCard.parse(merged)
        XCTAssertEqual(p.note, "我的笔记",
                       "🚨 重取把他写的笔记吃掉了 —— 不报错，他下次打开才发现")
        XCTAssertEqual(p.senses.count, 2, "🚨 其余字段没换成新的")
    }

    /// 反向对照：**本来就没笔记时不许凭空造一个空 note 字段**
    /// （那会让"有没有笔记"的判断永远为真）。
    func testNoNoteStaysAbsent() {
        XCTAssertEqual(WordCard.noteOf(fresh), "",
                       "🚨 没写过笔记却读出了东西")
        let c = WordCard.withNote(fresh, note: "")
        XCTAssertFalse(c.contains("\"note\""),
                       "🚨 空笔记也写进了 JSON —— 白占空间且判断会失真")
    }

    /// 坏卡片不许崩。
    func testGarbageCardIsSafe() {
        XCTAssertEqual(WordCard.noteOf("не json"), "")
        let c = WordCard.withNote("не json", note: "x")
        XCTAssertEqual(WordCard.noteOf(c), "x", "🚨 坏卡片上写不进笔记")
    }
}
