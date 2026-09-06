import XCTest

/// `NotesCore` 的纯逻辑自测 —— 不需要模拟器、不需要后端。
///
/// 🚨 每条都写清「什么输入会让它失败」，答不上来的判据不写。
final class NotesCoreTests: XCTestCase {

    private func item(_ id: String, _ body: String, _ mtime: TimeInterval,
                      tags: [String] = []) -> NotesCore.Item {
        return NotesCore.Item(id: id, title: NotesCore.titleOf(body),
                              body: body, tags: tags, at: mtime, mtime: mtime)
    }

    /// 🚨 **同一条历史点两次「留下来」不该长出两条。**
    ///    失败输入：id 里掺了时间 —— 那样每点一次都是新 id。
    func testSameHistoryGivesSameId() {
        let a = NotesCore.idFromHistory("hist-42")
        let b = NotesCore.idFromHistory("hist-42")
        XCTAssertEqual(a, b, "🚨 同一条历史算出两个 id —— 会长出重复笔记")
        XCTAssertNotEqual(a, NotesCore.idFromHistory("hist-43"))
        XCTAssertEqual(NotesCore.idFromHistory("  "), "", "🚨 空历史 id 该返回空")
    }

    /// 🚨🚨 **哈希必须跨进程稳定。**
    ///    Swift 自带的 `hashValue` 每次启动都换种子 —— 存下来的 id
    ///    **重启后就对不上**，「不长第二条」那条保证会静默失效。
    ///    这里钉死具体数值：跟 Java `String.hashCode` 同一套（31 进制）。
    func testStableHashMatchesJava() {
        // "a" = 97；"ab" = 97*31+98 = 3105；"abc" = 96354（Java 已知值）
        XCTAssertEqual(NotesCore.stableHash("a"), 97)
        XCTAssertEqual(NotesCore.stableHash("ab"), 3105)
        XCTAssertEqual(NotesCore.stableHash("abc"), 96354,
                       "🚨 跟安卓算不出同一个数 —— 两端 id 会对不上")
    }

    /// 标题取第一句、最多 24 字。
    func testTitleTakesFirstSentence() {
        XCTAssertEqual(NotesCore.titleOf("明天开会。记得带资料"), "明天开会")
        XCTAssertEqual(NotesCore.titleOf("  "), "", "🚨 空正文该返回空串")
        let long = String(repeating: "字", count: 40)
        XCTAssertEqual(NotesCore.titleOf(long).count, 24, "🚨 没截到 24 字")
        // 换行要当空格，否则标题里会带一个折行
        XCTAssertFalse(NotesCore.titleOf("第一行\n第二行").contains("\n"))
    }

    /// 🚨 **按 id 去重 + 按 mtime 倒序**。
    ///    失败输入：同一个 id 加两次 —— 不去重就会有两条。
    func testUpsertDedupesAndSorts() {
        var list: [NotesCore.Item] = []
        list = NotesCore.upsert(list, item("a", "旧的", 100))
        list = NotesCore.upsert(list, item("b", "新的", 200))
        list = NotesCore.upsert(list, item("a", "改过的", 300))
        XCTAssertEqual(list.count, 2, "🚨 同一个 id 长出了两条")
        XCTAssertEqual(list.first?.id, "a", "🚨 最新改的没排在最前")
        XCTAssertEqual(list.first?.body, "改过的", "🚨 没有就地更新")
    }

    /// 🚨 封顶砍**最旧的**，最新那条必须还在第一位。
    func testCapDropsOldest() {
        var list: [NotesCore.Item] = []
        for i in 0..<(NotesCore.max + 5) {
            list = NotesCore.upsert(list, item("id\(i)", "第\(i)条",
                                               TimeInterval(i)))
        }
        XCTAssertEqual(list.count, NotesCore.max, "🚨 没有封顶")
        XCTAssertEqual(list.first?.id, "id\(NotesCore.max + 4)",
                       "🚨 砍错了方向 —— 把最新的砍掉了")
    }

    /// 🚨🚨 **搜索必须搜得到原话**（规格判据：只搜标题 = FAIL）。
    ///    这条的坏样本很具体：关键词只出现在正文第 30 个字之后，
    ///    而标题只截前 24 字 —— **只搜标题的实现在这里必红**。
    func testSearchFindsBodyNotJustTitle() {
        let body = String(repeating: "前面的废话", count: 6) + "关键线索在这里"
        let list = [item("a", body, 1)]
        XCTAssertEqual(NotesCore.search(list, "关键线索").count, 1,
                       "🚨 搜不到正文里的词 —— 只搜标题了")
        XCTAssertEqual(NotesCore.search(list, "不存在的词").count, 0)
    }

    func testSearchIsCaseInsensitiveAndEmptyReturnsAll() {
        let list = [item("a", "Hello World", 1), item("b", "别的", 2)]
        XCTAssertEqual(NotesCore.search(list, "hello").count, 1,
                       "🚨 大小写敏感了")
        XCTAssertEqual(NotesCore.search(list, "  ").count, 2,
                       "🚨 空关键词该返回全部，不是返回空")
    }

    func testSearchMatchesTags() {
        let list = [item("a", "正文", 1, tags: ["工作", "周五"])]
        XCTAssertEqual(NotesCore.search(list, "周五").count, 1, "🚨 搜不到标签")
    }

    /// 标签去重，大小写不敏感，保留先出现的写法。
    func testNormTags() {
        let t = NotesCore.normTags([" 工作 ", "工作", "Work", "work", "  "])
        XCTAssertEqual(t, ["工作", "Work"], "🚨 标签没去重或改了写法")
    }
}
