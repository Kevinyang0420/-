import XCTest

/// **「最常用」的排序** —— Kevin 2026-09-06 01:40：
/// 「最近的语言要支持左右滑动，**永远前面放最常用的前三个**，用过的都可以左右滑取出来」
///
/// 🚨🚨 **「最常用」≠「最近用」。** 这条测试存在的唯一理由就是守住这个区别 ——
///    做成"最近用"的话下面第一条会红。
final class LangRankTests: XCTestCase {

    /// 🚨 测的是**规则**（纯函数），不经存储 —— 所以没有 setUp 清偏好这回事，
    ///    也不会被上一个用例留下的数据串味。
    private func use(_ seq: [String]) -> ([String], [String: Int]) {
        var used: [String] = []
        var counts: [String: Int] = [:]
        for c in seq {                       // 照 `LangRecents.use` 的写法
            used.removeAll { $0 == c }
            used.insert(c, at: 0)
            counts[c] = (counts[c] ?? 0) + 1
        }
        return (used, counts)
    }

    /// 🚨 **2.1 点名的坏样本**：A 用 5 次但很久以前，B 用 1 次刚刚。
    ///    **A 必须排在 B 前面。** 做成"最近用"这条会红。
    func testMostUsedBeatsMostRecent() {
        let (u, c) = use(["ja", "ja", "ja", "ja", "ja", "fr"])
        let r = LangRank.rank(used: u, counts: c, all: ["ja", "fr", "en"])
        XCTAssertEqual(r.first, "ja",
            "🚨 排在最前的是 \(r.first ?? "空") —— 他要的是「最常用」（次数最多），"
            + "不是「最近用」。fr 刚用过但只有 1 次，ja 用了 5 次。")
        XCTAssertEqual(r, ["ja", "fr"], "顺序应为次数降序")
    }

    /// 次数相同才看最近 —— 否则两门都用过 1 次时顺序会随字典遍历乱跳。
    func testTieBreaksByRecency() {
        let (u, c) = use(["de", "es"])          // es 更近，次数都是 1
        let r = LangRank.rank(used: u, counts: c, all: ["de", "es"])
        XCTAssertEqual(r, ["es", "de"], "🚨 次数相同时该按最近用的在前")
    }

    /// 🚨 **用过的都要能滑出来** —— 不许截断到 3 条。
    ///    旧实现 `maxKeep = 3` 会把第 4 门之后的直接丢掉，
    ///    那样"左右滑取出来"就无从谈起。**前三个靠排序，不靠截断。**
    func testKeepsMoreThanThree() {
        let (u, c) = use(["ja", "fr", "de", "es", "ko"])
        let r = LangRank.rank(used: u, counts: c, all: ["ja", "fr", "de", "es", "ko"])
        XCTAssertEqual(r.count, 5,
            "🚨 只留下 \(r.count) 门 —— 用过的都该留着能滑出来，前三个靠排序保证")
    }

    /// 一条记录都没有时返回空 —— 界面据此不画那个小标题（不显示空分区）。
    func testEmptyWhenNeverUsed() {
        XCTAssertTrue(LangRank.rank(used: [], counts: [:], all: ["ja", "fr"]).isEmpty)
    }

    /// 🚨 反向控制：**没在 `all` 里的语言不许出现**。
    ///    引擎支持的语言表变了之后，历史里那些下架的语言不该还挂在最前面。
    func testFiltersUnsupported() {
        let (u, c) = use(["xx", "ja"])          // xx 不在支持表里
        XCTAssertEqual(LangRank.rank(used: u, counts: c, all: ["ja", "fr"]), ["ja"],
                       "🚨 不在支持表里的语言漏出来了")
    }

    // MARK: - 🚨 老用户升级迁移（2.1 点名：不迁移他打开就是乱的）

    /// 有最近记录、没有计数 → **补一份，每门 1 次**。
    func testSeedsCountsOnUpgrade() {
        let seeded = LangRank.seedCounts(used: ["ja", "fr", "de"], existing: [:])
        XCTAssertEqual(seeded, ["ja": 1, "fr": 1, "de": 1],
                       "🚨 升级迁移没补上 —— 老语言全是 0 次，随手用一门新的就把它们顶下去")
    }

    /// 🚨 **已经有计数就不许再补** —— 补第二次会把真实次数抹成 1。
    func testDoesNotReseedWhenCountsExist() {
        XCTAssertNil(LangRank.seedCounts(used: ["ja"], existing: ["ja": 7]),
                     "🚨 又补了一次，真实的 7 次会被抹成 1")
    }

    /// 全新用户（没有最近记录）不用迁移，也不该凭空造出一份计数。
    func testNoSeedForFreshInstall() {
        XCTAssertNil(LangRank.seedCounts(used: [], existing: [:]))
    }

    /// 🚨 迁移之后**老顺序要保住**：三门都是 1 次 → 平局 → 按最近顺序。
    func testOrderSurvivesMigration() throws {
        let used = ["ja", "fr", "de"]                 // ja 最近
        // 🚨 用 `XCTUnwrap` 不用 `!` —— 强解包失败是**崩溃**，
        //    崩溃和"判定不通过"长得不一样，会被读成「测试框架坏了」。
        //    坏样本跑的时候这里就崩过一次。
        let c = try XCTUnwrap(LangRank.seedCounts(used: used, existing: [:]),
                              "🚨 迁移没发生，下面的顺序判定无从谈起")
        XCTAssertEqual(LangRank.rank(used: used, counts: c,
                                     all: ["ja", "fr", "de"]), used,
                       "🚨 迁移把他原来的顺序打乱了")
    }
}
