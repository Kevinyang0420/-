import Foundation

/// 说过的话的历史记录。**照搬安卓 `History.java`**。
///
/// 🚨 存在的理由（Kevin 2026-08-21）：「我说话说了一次，然后不小心删没了，
///    想再去复制一遍的时候，发现之前说的那段话已经找不到了」。
///    所以**上屏成功的那一刻就落盘**，不是等他主动保存 ——
///    他不会去按保存，等他发现丢了的时候就已经晚了。
///
/// 🚨 只存本机，**绝不上传**：他说的内容里有工作信息。
///    存最近 `maxItems` 条，超了丢最旧的（键盘扩展内存有限）。
///
/// 🚨 存在**键盘扩展自己的** UserDefaults 里。
///    本来该走 App Group（主 App 也能看），但这个工程**还没配** ——
///    `Lang.swift` / `RecLog.swift` 的注释写着：配 App Group 要动签名和
///    描述文件，那是单独一件事。安卓那边历史也是在键盘里看的，
///    所以这个限制现在不影响功能。**别假装配了**：
///    写 `UserDefaults(suiteName:)` 而实际没有那个 group 时会**静默回落**
///    到 standard，看起来一切正常，等哪天真配了才发现历史对不上。
enum History {

    private static let key = "history_json"
    private static let maxItems = 50

    struct Item {
        let ts: Double          // 毫秒时间戳，跟安卓同口径
        let mode: String        // en / zh / raw
        let tone: String
        let zh: String          // 识别到的原话
        let out: String         // 最终上屏的结果
    }

    private static var store: UserDefaults { .standard }

    /// 上屏成功后立刻调。**任何异常都不许影响主流程** ——
    /// 记不上不是塌天的事，但崩了是。
    static func add(mode: String, tone: String, zh: String, out: String) {
        guard !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        var arr = raw()
        // 🚨 键名写死 `"zh"`。安卓那份写成了
        //    `o.put(c.getString(R.string.ui_lang), zh)` ——
        //    用**界面语言的值**（"zh"/"en"/"hant"）当 JSON 键名，
        //    于是换一次界面语言，之前的历史就读不出来了。那是笔误，别照抄。
        let item: [String: Any] = [
            "ts": Date().timeIntervalSince1970 * 1000,
            "mode": mode.isEmpty ? "en" : mode,
            "tone": tone,
            "zh": zh,
            "out": out,
        ]
        arr.insert(item, at: 0)            // 最新的放最前
        if arr.count > maxItems { arr = Array(arr.prefix(maxItems)) }
        write(arr)
    }

    static func list() -> [Item] {
        raw().map {
            Item(ts: ($0["ts"] as? Double) ?? 0,
                 mode: ($0["mode"] as? String) ?? "",
                 tone: ($0["tone"] as? String) ?? "",
                 zh: ($0["zh"] as? String) ?? "",
                 out: ($0["out"] as? String) ?? "")
        }
    }

    /// 删单条（按时间戳定位）。
    static func remove(ts: Double) {
        write(raw().filter { (($0["ts"] as? Double) ?? 0) != ts })
    }

    static func clear() {
        store.removeObject(forKey: key)
    }

    /// 给界面用的一行摘要：时间 + 模式。跟安卓 `label()` 同口径。
    static func label(_ it: Item) -> String {
        let m: String
        switch it.mode {
        case "zh":  m = L.kb_transcribe + " " + L.kb_polish
        case "raw": m = L.kb_transcribe + " " + L.kb_verbatim
        default:    m = L.kb_translate
        }
        let d = Date(timeIntervalSince1970: it.ts / 1000)
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d · %@", c.hour ?? 0, c.minute ?? 0, m)
    }

    // MARK: - 存取

    private static func raw() -> [[String: Any]] {
        guard let s = store.string(forKey: key),
              let d = s.data(using: .utf8),
              let a = try? JSONSerialization.jsonObject(with: d)
                as? [[String: Any]] else { return [] }
        return a
    }

    private static func write(_ arr: [[String: Any]]) {
        guard let d = try? JSONSerialization.data(withJSONObject: arr),
              let s = String(data: d, encoding: .utf8) else { return }
        store.set(s, forKey: key)
    }
}
