import XCTest

/// **收藏 → 落盘 → 读回，词性不许丢。**
///
/// 🚨 单词本读的**不是**后端刚返回的数据，而是**收藏那一刻落盘的 JSON**。
///    今天就是只修了查词卡（读后端返回），单词本那份没动 ——
///    Kevin：「你是在查词界面里有了动词和名词，但我是在单词本里看的，
///    单词本那个地方就只有一个动词」。
///    **两个界面读两份数据**，这条判据钉的就是落盘那一份。
final class CardPosRoundTripTests: XCTestCase {

    private func entry(_ poses: [String]) -> DictEntry {
        return DictEntry(
            word: "commute", phonetic: "kəˈmjuːt", pos: "",
            senses: poses.enumerated().map {
                DictSense(en: "sense \($0.offset)", zh: "释义\($0.offset)",
                          register: "", pos: $0.element)
            },
            exampleEn: "", exampleZh: "", collocations: [])
    }

    /// v./v./n. 存下去，读回来还是 v./v./n.
    func testPosSurvivesSaveAndLoad() {
        let json = WordCard.fromDict(entry(["v.", "v.", "n."]))
        let back = WordCard.parse(json)
        let poses = back.senses.map { $0.2 }
        XCTAssertEqual(poses, ["v.", "v.", "n."],
                       "🚨 落盘一轮词性就没了：\(poses) —— "
                       + "单词本读的正是这份数据，他会看到「只有一个动词」")
        XCTAssertTrue(PosGrouping.hasAnyPos(poses))
    }

    /// 🚨 **坏样本 = 他手机上那张老卡片**：存的时候还没有 sense 级 pos。
    ///    必须被认出来需要重取，否则代码改对了他打开还是没有。
    func testLegacyCardIsDetected() {
        let legacy = """
        {"kind":"word","phonetic":"kəˈmjuːt","pos":"v.",
         "senses":[{"en":"a","zh":"甲"},{"en":"b","zh":"乙"}]}
        """
        let back = WordCard.parse(legacy)
        XCTAssertEqual(back.senses.count, 2, "🚨 老卡片解析不出来了 —— 存量数据打不开")
        XCTAssertFalse(PosGrouping.hasAnyPos(back.senses.map { $0.2 }),
                       "🚨 认不出老卡片缺词性 → 不会重取 → 他打开还是没有")
    }

    /// 反向对照：新卡片**不许**被判成要重取（否则每次打开都白跑一次网络）。
    func testFreshCardNotFlagged() {
        let json = WordCard.fromDict(entry(["v.", "n."]))
        let back = WordCard.parse(json)
        XCTAssertTrue(PosGrouping.hasAnyPos(back.senses.map { $0.2 }),
                      "🚨 新卡片被判成缺词性 —— 每次打开都会重取一次")
    }

    /// 分节结果：v. 起一节、n. 起一节，中间那条不起。
    func testSectionsFromSavedCard() {
        let back = WordCard.parse(WordCard.fromDict(entry(["v.", "v.", "n."])))
        let p = back.senses.map { $0.2 }
        XCTAssertEqual(PosGrouping.sectionTitle(at: 0, poses: p), "v.")
        XCTAssertNil(PosGrouping.sectionTitle(at: 1, poses: p))
        XCTAssertEqual(PosGrouping.sectionTitle(at: 2, poses: p), "n.",
                       "🚨 单词本里名词那节起不来 —— 就是他报的那个")
    }
}
