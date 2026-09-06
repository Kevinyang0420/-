import Foundation

/// **单词本卡片** —— 收藏那一刻存下来的那份解释。
///
/// 🚨🚨 Kevin 2026-09-06 连问三次：「我要的单词怎么就这么难呢？单词卡片在哪儿呢？
///    为什么说了你竟然还是没有做呀？」
///    规格、契约、prompt、三端同步链**全做了**，但**没有一端去画那张卡片** ——
///    他点进单词本详情，看到的只有中/英/语气/日期/进度。
///
/// 🚨 **两种形态，字段完全不同**，别硬塞进同一套字段：
///    · **A · 查词**（查词页收藏）：音标 / 词性 / 释义 / 例句 / 搭配
///      —— 这份**查的时候就已经在手上**，收藏时原样存下来即可，
///         **绝不重新查一次**（规格原话：两次结果可能不一样，
///         他会觉得"我收藏的那个解释变了"）。
///    · **B · 句子·词组**（随手翻译/说话记录/面对面收藏）：
///      结构拆解 / 替代表达 / 关键搭配 —— 由后端在收藏那一刻生成。
///
/// 🚨 **存 JSON 原文、解析放这里**。存成结构体的话就得先定死一套字段，
///    后端一改字段就要迁数据；而这两种形态本来就不同构。
enum WordCard {

    /// 一块结构拆解：这一段是什么、在句子里干什么。
    struct Part {
        let part: String
        let role: String
        let note: String
    }

    /// 一条替代说法 + 什么场合用。
    struct Alt {
        let en: String
        let when: String
    }

    /// 解析出来的卡片。两种形态共用这一个容器，**用不上的那些就是空的**。
    struct Parsed {
        // A · 查词
        var phonetic = ""
        var pos = ""
        /// (英文释义, 中文释义, **这一条自己的词性**)
        ///
        /// 🚨 词性是**义项级**的，不是整卡级的。原来只有 (en, zh)、
        ///    整卡靠顶层一个 `pos` —— commute 的三条（v./v./n.）
        ///    在单词本里就全挂在一个词性下，名词那条根本看不出来。
        var senses: [(String, String, String)] = []
        var examples: [(String, String)] = []    // (例句英, 例句中)
        var collocations: [String] = []
        // B · 句子/词组
        var breakdown: [Part] = []
        var alternatives: [Alt] = []
        var keys: [(String, String)] = []        // (英, 中)

        /// 这张卡片有没有内容。**空卡片要如实说"还没有"，不许画个空壳。**
        var isEmpty: Bool {
            senses.isEmpty && examples.isEmpty && collocations.isEmpty
                && breakdown.isEmpty && alternatives.isEmpty && keys.isEmpty
        }
    }

    /// 把 `DictEntry` 存成卡片 JSON（形态 A）。
    ///
    /// 🚨 **在收藏那一刻调**，别等点进去再查 —— 那时那份数据已经不在手上了。
    static func fromDict(_ e: DictEntry) -> String {
        var o: [String: Any] = [
            "kind": "word",
            "phonetic": e.phonetic,
            "pos": e.pos,
            // 🚨 **每条义项的词性也要存下来。** 不存的话卡片一旦落盘
            //    就再分不出哪条是名词 —— 而单词本读的正是这份落盘数据。
            "senses": e.senses.map { ["en": $0.en, "zh": $0.zh, "pos": $0.pos] },
            "collocations": e.collocations,
        ]
        if !e.exampleEn.isEmpty || !e.exampleZh.isEmpty {
            o["examples"] = [["en": e.exampleEn, "zh": e.exampleZh]]
        }
        guard let d = try? JSONSerialization.data(withJSONObject: o),
              let s = String(data: d, encoding: .utf8) else { return "" }
        return s
    }

    /// 解析存下来的 JSON。**解不出就回空卡片，不抛错** ——
    /// 存了半份坏 JSON 也不该让详情页打不开。
    static func parse(_ raw: String) -> Parsed {
        var p = Parsed()
        guard !raw.isEmpty,
              let d = raw.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: d))
                  as? [String: Any] else { return p }

        p.phonetic = (o["phonetic"] as? String) ?? ""
        p.pos = (o["pos"] as? String) ?? ""
        for s in (o["senses"] as? [[String: Any]]) ?? [] {
            p.senses.append(((s["en"] as? String) ?? "",
                             (s["zh"] as? String) ?? "",
                             (s["pos"] as? String) ?? ""))
        }
        for s in (o["examples"] as? [[String: Any]]) ?? [] {
            p.examples.append(((s["en"] as? String) ?? "",
                               (s["zh"] as? String) ?? ""))
        }
        p.collocations = (o["collocations"] as? [String]) ?? []

        for b in (o["breakdown"] as? [[String: Any]]) ?? [] {
            p.breakdown.append(Part(part: (b["part"] as? String) ?? "",
                                    role: (b["role"] as? String) ?? "",
                                    note: (b["note"] as? String) ?? ""))
        }
        for a in (o["alternatives"] as? [[String: Any]]) ?? [] {
            p.alternatives.append(Alt(en: (a["en"] as? String) ?? "",
                                      when: (a["when"] as? String) ?? ""))
        }
        for k in (o["keys"] as? [[String: Any]]) ?? [] {
            p.keys.append(((k["en"] as? String) ?? "",
                           (k["zh"] as? String) ?? ""))
        }
        return p
    }
}
