import XCTest

/// `parseDict` 必须**同时认两种结构**（2026-09-06 换 `engine.LOOKUP_PROMPT` 之后）。
///
/// ```
/// engine ->  "senses":[{pos,en,zh,register}], "examples":[{en,zh}], "phonetic":"/juː/"
/// 旧的   ->  "senses":[{en,zh,register}], "pos":"n.", "example_en", "example_zh"
/// ```
///
/// 🚨 **旧结构不能删**：缓存里存着按旧结构存下来的条目。
///    只认新的话，表现是**「以前查过的词打不开了」** —— 而那不像"换了提示词"
///    引起的问题，会被当成缓存坏了去查错方向。
///
/// 🚨 这一组测的是**解析**，不是"提示词填得对不对"。
///    register 填 `finance` 还是 `formal` 那是提示词的事，1.1 在线上探针里测。
final class ParseDictShapeTests: XCTestCase {

    // MARK: - engine 的新结构

    func testParsesEngineShape() throws {
        let raw = """
        {"word":"quotation","phonetic":"/kwəʊˈteɪʃn/",
         "senses":[{"pos":"n.","en":"a formal statement of price","zh":"报价单",
                    "register":"formal"},
                   {"pos":"n.","en":"a passage quoted","zh":"引文","register":""}],
         "examples":[{"en":"Please send a quotation.","zh":"请发一份报价单。"}],
         "collocations":["request a quotation"]}
        """
        let e = try XCTUnwrap(DictParse.entry(word: "quotation", raw: raw))
        XCTAssertEqual(e.senses.count, 2)
        XCTAssertEqual(e.senses.first?.register, "formal")
        // 🚨 词性在**每条 sense 里**，顶层没有 —— 要取到第一条的
        XCTAssertEqual(e.pos, "n.", "🚨 词性没从 sense 里取，界面会缺词性")
        // 🚨 例句是**数组**，不是两个平铺字段
        XCTAssertEqual(e.exampleEn, "Please send a quotation.",
                       "🚨 examples[] 没解出来，例句会整条不见")
        XCTAssertEqual(e.exampleZh, "请发一份报价单。")
        // 🚨 engine 要求音标带斜杠，而界面自己会补 `/…/` —— 不剥就成 `//juː//`
        XCTAssertEqual(e.phonetic, "kwəʊˈteɪʃn",
                       "🚨 斜杠没剥掉，界面会显示成 //…//")
    }

    // MARK: - 🚨 老缓存的旧结构（不能因为换了提示词就解不出）

    func testStillParsesLegacyShape() throws {
        let raw = """
        {"word":"quote","phonetic":"kwəʊt","pos":"v.",
         "senses":[{"en":"to state a price","zh":"报价","register":""}],
         "example_en":"He quoted 200 dollars.","example_zh":"他报价 200 美元。",
         "collocations":["quote a price"]}
        """
        let e = try XCTUnwrap(DictParse.entry(word: "quote", raw: raw))
        XCTAssertEqual(e.pos, "v.")
        XCTAssertEqual(e.exampleEn, "He quoted 200 dollars.")
        XCTAssertEqual(e.phonetic, "kwəʊt", "旧结构本来就不带斜杠，不该被动过")
    }

    // MARK: - 边角

    /// `phonetic` 是 `null` 时不许崩，也不许把 "null" 当字符串显示。
    func testNullPhoneticBecomesEmpty() throws {
        let raw = """
        {"word":"x","phonetic":null,
         "senses":[{"en":"a","zh":"甲","register":""}]}
        """
        let e = try XCTUnwrap(DictParse.entry(word: "x", raw: raw))
        XCTAssertEqual(e.phonetic, "")
    }

    /// 模型多包一层代码块要能剥掉（原来就有的行为，别改坏）。
    func testStripsCodeFence() throws {
        let raw = "```json\n{\"word\":\"y\",\"senses\":[{\"en\":\"b\",\"zh\":\"乙\"}]}\n```"
        XCTAssertNotNil(DictParse.entry(word: "y", raw: raw))
    }

    /// 🚨 一条 sense 都没有 = 解析失败，**不许返回一个空壳** ——
    /// 空壳会被存进缓存，然后**永远不再重查**。
    func testNoSensesIsFailure() {
        XCTAssertNil(DictParse.entry(word: "z", raw: "{\"word\":\"z\",\"senses\":[]}"))
    }
}

/// 音标斜杠 —— **判据挂在「已存的旧数据」上**（Kevin 2026-09-06 报 `//rɪˈzɪliənt//`）。
///
/// 🚨 1.1 改了契约 + 服务端出口 strip，**那只管新查的词**。
///    他单词本里已存的卡片存的是**带斜杠的老数据** ——
///    只验新查的词，这半漏了也是绿的。
final class PhoneticSlashTests: XCTestCase {

    /// 旧数据：带斜杠存进来的。
    func testLegacySlashesAreStrippedForDisplay() {
        let e = DictEntry(word: "resilient", phonetic: "/rɪˈzɪliənt/", pos: "adj.",
                          senses: [DictSense(en: "a", zh: "甲", register: "")],
                          exampleEn: "", exampleZh: "", collocations: [])
        XCTAssertEqual(e.phoneticForDisplay, "rɪˈzɪliənt",
                       "🚨 旧卡片会显示成 //rɪˈzɪliənt// —— 他报的就是这个")
    }

    /// 🚨 **反向对照**：本来就干净的**一个字都不许动**。
    ///    只测"带斜杠的被剥掉"的话，把首尾字符一律砍掉也全绿，而那会吃掉真音标。
    func testCleanPhoneticIsUntouched() {
        let e = DictEntry(word: "quote", phonetic: "kwəʊt", pos: "n.",
                          senses: [DictSense(en: "a", zh: "甲", register: "")],
                          exampleEn: "", exampleZh: "", collocations: [])
        XCTAssertEqual(e.phoneticForDisplay, "kwəʊt")
    }

    /// 空的仍然是空的（别剥出一个空格来）。
    func testEmptyStaysEmpty() {
        let e = DictEntry(word: "x", phonetic: "", pos: "",
                          senses: [DictSense(en: "a", zh: "甲", register: "")],
                          exampleEn: "", exampleZh: "", collocations: [])
        XCTAssertEqual(e.phoneticForDisplay, "")
    }

    /// 只有斜杠没有内容 → 空，**不是 `/`**（否则界面显示成 `///`）。
    func testSlashesOnlyBecomesEmpty() {
        let e = DictEntry(word: "x", phonetic: "//", pos: "",
                          senses: [DictSense(en: "a", zh: "甲", register: "")],
                          exampleEn: "", exampleZh: "", collocations: [])
        XCTAssertEqual(e.phoneticForDisplay, "", "🚨 会显示成 ///")
    }
}
