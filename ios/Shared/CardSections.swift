import Foundation

/// **一张卡片该分成哪几段、每段几行** —— 纯逻辑，不碰 UIKit。
///
/// ## 为什么单独抽出来
/// 「查词结果页」和「单词本详情页」要画**同一张卡**：
/// 单词卡（音标/释义/例句/搭配）和句子卡（意思/结构拆解/换个说法/关键搭配）。
/// 单词本那边已经有一套，查词页再写一套 ——
/// **同一规矩两处实现，这摊活今晚已经栽过三次**
/// （话筒比例三处、语言表手抄、`apply_overrides` 写了没接）。
///
/// 所以段落**内容**收在这里（可单测、不需要模拟器），
/// 每一屏只保留自己的**行样式**。
///
/// ## 🚨 `kind` 由模型给，客户端不许自己猜
/// 规格 `_规格_查句子_20260907.md` 写死：
/// > 不许客户端按空格或字数猜。英文短语有空格（`take issue with`），
/// > 中文句子没有空格 —— 任何本地规则都会在某一门语言上错，**而且错了不报错**。
///
/// 所以这里只认返回值里的 `kind`，**缺省当词卡**（老后端不带这个字段，
/// 老行为必须不变）。
enum CardSections {

    /// 一段：标题 + 若干行。行已经拼好（多行用换行分隔）。
    struct Section {
        let title: String
        let rows: [String]
    }

    /// 这份 JSON 是不是句子卡。
    ///
    /// 🚨 **只看 `kind`**。`kind` 缺失 = 词卡 —— 后端还没上线分流时，
    ///    老返回不带这个字段，这条保证老客户端行为一个字不变。
    static func isSentence(_ o: [String: Any]) -> Bool {
        return (o["kind"] as? String) == "sentence"
    }

    /// 句子卡的四段。标题由调用方给（各屏的 i18n 键不同，别在这儿写死）。
    ///
    /// 🚨 **空段不出现**。先摆标题再填内容的话，没数据时会留一排孤零零的标题
    ///    —— 单词本那边为这个专门写过判据。
    static func sentence(_ o: [String: Any],
                         titles: (meaning: String, breakdown: String,
                                  alternatives: String, keys: String)) -> [Section] {
        var out: [Section] = []

        // ① 整句什么意思。🚨 规格：**不是第二份译文**，是一句话说清意思。
        if let m = (o["meaning"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty {
            out.append(Section(title: titles.meaning, rows: [m]))
        }

        // ② 结构拆解 —— 「可参考的句式」他专门提了，落在 note 里。
        let bd = (o["breakdown"] as? [[String: Any]]) ?? []
        let bdRows = bd.compactMap { p -> String? in
            let part = (p["part"] as? String) ?? ""
            guard !part.isEmpty else { return nil }
            let role = (p["role"] as? String) ?? ""
            let note = (p["note"] as? String) ?? ""
            let head = part + (role.isEmpty ? "" : "  ·  " + role)
            return head + (note.isEmpty ? "" : "\n" + note)
        }
        if !bdRows.isEmpty {
            out.append(Section(title: titles.breakdown, rows: bdRows))
        }

        // ③ 换个说法 + 什么场合用
        let alt = (o["alternatives"] as? [[String: Any]]) ?? []
        let altRows = alt.compactMap { a -> String? in
            let en = (a["en"] as? String) ?? ""
            guard !en.isEmpty else { return nil }
            let when = (a["when"] as? String) ?? ""
            return en + (when.isEmpty ? "" : "\n" + when)
        }
        if !altRows.isEmpty {
            out.append(Section(title: titles.alternatives, rows: altRows))
        }

        // ④ 可以拆下来复用的搭配
        let keys = (o["keys"] as? [[String: Any]]) ?? []
        let keyRows = keys.compactMap { k -> String? in
            let en = (k["en"] as? String) ?? ""
            guard !en.isEmpty else { return nil }
            let zh = (k["zh"] as? String) ?? ""
            return en + (zh.isEmpty ? "" : "  " + zh)
        }
        if !keyRows.isEmpty {
            out.append(Section(title: titles.keys, rows: keyRows))
        }
        return out
    }

    /// 存进单词本时那几个字段（规格第三节）。
    ///
    /// 🚨 `zh` 用模型给的 `meaning`，`en` 用他查的**那句原文**，
    ///    `span` 是 `"full"`（这个字段本来就是给整句用的）。
    ///    id 由三端已有的 `WordId` 出，**不另造**。
    static func wordbookFields(_ o: [String: Any], query: String)
        -> (zh: String, en: String, span: String) {
        let meaning = ((o["meaning"] as? String) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (zh: meaning,
                en: query.trimmingCharacters(in: .whitespacesAndNewlines),
                span: "full")
    }
}
