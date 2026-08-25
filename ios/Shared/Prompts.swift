import Foundation

/// 跟 engine.py / worker 那两份保持同一套逻辑。
/// 🚨 提示词本身**不在这里**，它由构建时生成的 Secrets.swift 提供，
///    源头永远是 engine.py。别在这个文件里手抄一份。
enum Prompts {

    /// 🚨 语气档位的**唯一一份**（iOS 侧）。顺序也要跟 engine.TONES 一致。
    ///    2026-08-25 之前 App 和键盘各抄一份，结果键盘一直留着已经删掉的
    ///    第四档「正式」——而闸门只查 App 那份，整整漏了过去。
    ///    要加/删档位就只改这里，别再在界面文件里写字面量数组。
    static let all = ["casual", "work", "email"]

    /// 界面上显示的名字。跟 all 是同一套 key，别各排各的顺序。
    static func label(_ t: String) -> String {
        switch t {
        case "casual": return L.tone_casual
        case "email":  return L.tone_email
        default:       return L.tone_work
        }
    }

    /// 存过的旧值可能已经被删掉（比如「正式」），落回 work 而不是崩或者发个后端不认的档位。
    static func normalize(_ t: String?) -> String {
        guard let t = t, all.contains(t) else { return "work" }
        return t
    }


    static func tone(_ t: String) -> String {
        switch t {
        case "email":
            return "a business email body. Slightly more formal, complete sentences, "
                 + "no greeting line and no sign-off unless the speaker said one."
        case "casual":
            return "a casual message to someone you know well. Relaxed, short, contractions."
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
