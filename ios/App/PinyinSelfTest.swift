import UIKit

/// 拼音引擎自检页（`TRANSLESS_PAGE=pysplit`）。
///
/// 🚨 **期望值是独立算出来的**：`D:\_build\_py_expected.json` 由一份
///    Python 参照实现跑**安卓的码表**得出，那份 Python 照着
///    `PinyinSplit.java` 的算法写。所以这里是"Swift 实现 vs Java 算法"
///    两条独立路径对拍 —— 不是拿 Swift 的输出当自己的期望值（同源自比）。
///
/// 🚨 坏样本：`TRANSLESS_PYTEST_BAD=1` 会把第一条的期望值改掉。
///    跑一次看它变红，才证明这一屏绿是真的绿。
final class PinyinSelfTestController: UIViewController {

    /// 切分用例。左＝输入，右＝期望（`/` 分隔）。
    private static let splitCases: [(String, String)] = [
        ("mingtianxiawu", "ming/tian/xia/wu"),
        ("nihao", "ni/hao"),
        ("xian", "xian"),
        // 🚨 这条守的是"切不动就把剩下全塞一段"那个 bug：
        //    a 是合法音节先切走，bc 切不动攒成一段，后面 ni/hao 照切。
        ("abcnihao", "a/bc/ni/hao"),
        ("women", "wo/men"),
        ("zhuang", "zhuang"),
        ("wo", "wo"),
        ("qqq", "qqq"),
        ("shenmeshihou", "shen/me/shi/hou"),
        ("xiexie", "xie/xie"),
    ]

    /// 退格按词删的用例。第三列是**为什么是这个数**——
    /// 期望值靠推的话就是假断言，得说得出理由。
    private static let wordCases: [(String, Int, String)] = [
        ("hello world", 5, "删 world 五个字母"),
        ("hello world ", 6, "先吃掉尾部那个空格，再删 world"),
        ("hello   ", 3, "只有空白就把空白吃掉"),
        ("a", 1, "只剩一个字符"),
        ("", 1, "空串也要删一下，不能一动不动"),
        ("你好", 1, "🚨 汉字按单字删 —— 中文没空格分词，"
                    + "一路吃到空白会把整句删光"),
        ("hello 你好", 1, "同上，汉字只删一个"),
        ("ab12", 4, "字母数字混在一起算一个词"),
    ]

    /// 候选用例。右＝期望的**前 5 个**（空格分隔）。
    private static let candCases: [(String, String)] = [
        ("ni", "你 泥 尼 拟 逆"),
        ("hao", "好 号 灏 豪 浩"),
        ("ming", "名 明 命 鸣 洺"),
        ("tian", "天 田 甜 添 填"),
        ("women", "我们"),
        ("xiexie", "谢谢"),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.bg

        PinyinSplit.ensureLoaded()

        var lines: [String] = []
        var fail = 0

        lines.append(PinyinSplit.ready
            ? "码表装载：OK（syllables 非空）"
            : "码表装载：🚨 空表 —— Resources 没进 bundle")
        if !PinyinSplit.ready { fail += 1 }
        lines.append(PinyinSplit.diag())
        lines.append("")

        var cases = Self.splitCases
        // 坏样本注入：证明这一屏绿是真绿，不是恒真
        if ProcessInfo.processInfo.environment["TRANSLESS_PYTEST_BAD"] == "1" {
            cases[0].1 = "ming/tian/xia/WRONG"
            lines.append("⚠️ 坏样本模式：第 1 条期望值已被改错，它必须变红")
            lines.append("")
        }

        lines.append("— 切分 —")
        for (input, want) in cases {
            let got = PinyinSplit.split(input).joined(separator: "/")
            let ok = got == want
            if !ok { fail += 1 }
            lines.append(String(format: "%@ %-14@ %@%@",
                                ok ? "PASS" : "FAIL", input as NSString, got,
                                ok ? "" : "   期望 " + want))
        }

        lines.append("")
        lines.append("— 候选（前 5）—")
        for (key, want) in Self.candCases {
            let got = PinyinSplit.candidates(key).prefix(5)
                .joined(separator: " ")
            let ok = got == want
            if !ok { fail += 1 }
            lines.append(String(format: "%@ %-8@ %@%@",
                                ok ? "PASS" : "FAIL", key as NSString, got,
                                ok ? "" : "   期望 " + want))
        }

        lines.append("")
        lines.append("— 五笔前缀（打 j，取 8）—")
        let w = PinyinSplit.wubiPrefix("j", limit: 8)
        // 🚨 这里不比字面结果 —— 排序规则是"常用优先"，
        //    期望值该是「不该出现明显生僻字」而不是某个固定串。
        lines.append(w.isEmpty ? "FAIL 打 j 一个候选都没有" : "PASS " + w.joined(separator: " "))
        if w.isEmpty { fail += 1 }

        lines.append("")
        lines.append("— 退格按词删（光标前是什么 → 删几个）—")
        // 期望值是**手推的**，每条都写清为什么：
        for (before, want, why) in Self.wordCases {
            let got = Backspace.wordDeleteCount(before)
            let ok = got == want
            if !ok { fail += 1 }
            lines.append(String(format: "%@ %-16@ %d  %@",
                                ok ? "PASS" : "FAIL", before as NSString,
                                got, ok ? why : "🚨期望 \(want)  " + why))
        }

        lines.append("")
        lines.append("— 长按字母出数字 —")
        for (k, want) in [("q", "1"), ("w", "2"), ("o", "9"), ("p", "0")] {
            let got = Layout.longPressDigit(k) ?? "nil"
            let ok = got == want
            if !ok { fail += 1 }
            lines.append("\(ok ? "PASS" : "FAIL") \(k) → \(got)"
                         + (ok ? "" : "  期望 \(want)"))
        }
        // 非首行不该有数字 —— 这条守的是"别给所有字母都装上"
        for k in ["a", "z", "m"] {
            let got = Layout.longPressDigit(k)
            let ok = got == nil
            if !ok { fail += 1 }
            lines.append("\(ok ? "PASS" : "FAIL") \(k) → "
                         + (got ?? "nil（非首行，正确）"))
        }

        lines.append("")
        lines.append(fail == 0 ? "=== 全过 ===" : "=== FAIL：\(fail) 项 ===")

        let tv = UITextView()
        tv.isEditable = false
        tv.backgroundColor = .clear
        tv.textColor = fail == 0 ? Theme.text : UIColor(red: 1, green: 0.45,
                                                        blue: 0.45, alpha: 1)
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.text = lines.joined(separator: "\n")
        tv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tv)
        NSLayoutConstraint.activate([
            tv.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            tv.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            tv.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}
