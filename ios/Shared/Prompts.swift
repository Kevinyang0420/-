import Foundation

/// 跟 engine.py / worker 那两份保持同一套逻辑。
/// 🚨 提示词本身**不在这里**，它由构建时生成的 Secrets.swift 提供，
///    源头永远是 engine.py。别在这个文件里手抄一份。
enum Prompts {

    static func tone(_ t: String) -> String {
        switch t {
        case "email":
            return "a business email body. Slightly more formal, complete sentences, "
                 + "no greeting line and no sign-off unless the speaker said one."
        case "casual":
            return "a casual message to someone you know well. Relaxed, short, contractions."
        case "formal":
            return "a formal written communication to a client, regulator or auditor. "
                 + "Precise, hedged where the speaker hedged, no slang."
        default:
            return "a direct work message to a colleague or counterpart (Slack / WhatsApp / Teams). "
                 + "Professional but not stiff. Contractions are fine."
        }
    }

    /// 🚨 模型偶尔把 ZH 块吐两遍（实测）：<<<OUT>>>…<<<ZH>>>中文<<<ZH>>>中文
    ///    键盘只要英文那半截。
    static func splitEn(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let a = s.range(of: "<<<OUT>>>"), let b = s.range(of: "<<<ZH>>>"),
              a.upperBound <= b.lowerBound else { return s }
        return String(s[a.upperBound..<b.lowerBound])
            .replacingOccurrences(of: "<<<OUT>>>", with: "")
            .replacingOccurrences(of: "<<<ZH>>>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 🚨 提示词里禁了破折号，但模型照样吐（实测），所以代码里兜死。
    static func postprocess(_ input: String) -> String {
        var s = input
        s = s.replacingOccurrences(of: " — ", with: "; ")
        s = s.replacingOccurrences(of: "—", with: "; ")
        s = s.replacingOccurrences(of: " – ", with: "; ")

        var out = ""
        let chars = Array(s)
        for (i, ch) in chars.enumerated() {
            if ch == "–" {
                let p = i > 0 ? chars[i - 1] : " "
                let n = i + 1 < chars.count ? chars[i + 1] : " "
                out += (p.isNumber && n.isNumber) ? "-" : ", "
            } else {
                out.append(ch)
            }
        }
        while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
        return out.replacingOccurrences(of: " ;", with: ";")
                  .replacingOccurrences(of: " ,", with: ",")
                  .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
