import XCTest

/// `PosGrouping` —— 查词卡和单词本卡共用的分节逻辑。
final class PosGroupingTests: XCTestCase {

    /// commute：v. v. n. → 第 0 条起「v.」节，第 2 条起「n.」节，第 1 条不起。
    func testTwoSections() {
        let p = ["v.", "v.", "n."]
        XCTAssertEqual(PosGrouping.sectionTitle(at: 0, poses: p), "v.")
        XCTAssertNil(PosGrouping.sectionTitle(at: 1, poses: p),
                     "🚨 同词性又起了一节 —— `v.` 会重复出现两次")
        XCTAssertEqual(PosGrouping.sectionTitle(at: 2, poses: p), "n.",
                       "🚨 名词那节没起来 —— 他看到的就是「只给了动词」")
    }

    /// 🚨 单词性的词不许硬造出第二节。
    func testSinglePosOneSection() {
        let p = ["v."]
        XCTAssertEqual(PosGrouping.sectionTitle(at: 0, poses: p), "v.")
        XCTAssertNil(PosGrouping.sectionTitle(at: 1, poses: p))
    }

    /// 🚨 **存量卡片**：一个 pos 都没有 → 不画任何节，且 `hasAnyPos` 为假
    ///    （调用方据此重新取一次卡片）。
    func testLegacyCardWithoutPos() {
        let p = ["", "", ""]
        for i in 0..<3 {
            XCTAssertNil(PosGrouping.sectionTitle(at: i, poses: p),
                         "🚨 老卡片没有词性，却画出了空标题")
        }
        XCTAssertFalse(PosGrouping.hasAnyPos(p),
                       "🚨 认不出老卡片缺词性 —— 就不会去重取，"
                       + "他打开还是没有，会说「又没修好」")
    }

    /// 反向对照：有词性的卡片**不许**被判成需要重取（否则每次打开都白跑一次网络）。
    func testFreshCardNotRefetched() {
        XCTAssertTrue(PosGrouping.hasAnyPos(["v.", "n."]))
        XCTAssertTrue(PosGrouping.hasAnyPos(["", "n."]),
                      "🚨 部分有词性也算有 —— 不该整张卡重取")
    }

    /// 不相邻时宁可多一节，也不许把不同词性塞进同一节。
    func testNonAdjacentStillSeparates() {
        let p = ["v.", "n.", "v."]
        XCTAssertEqual(PosGrouping.sectionTitle(at: 1, poses: p), "n.")
        XCTAssertEqual(PosGrouping.sectionTitle(at: 2, poses: p), "v.",
                       "🚨 第三条被并进了名词节 —— 那正是他报的那个 bug")
    }
}
