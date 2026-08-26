import Foundation

/// 单词本一条记录的 **id 算法**。纯逻辑，两端必须算出**一模一样**的值
/// （安卓那份在 `android/java/com/kevin/shuoyingwen/WordId.java`）。
///
/// 🚨 为什么单独抽出来：`WordBook` 依赖平台存储，在两端一致性闸门那个
///    裸编译环境里跑不了。而**真正必须两端一致的只有这个算法**。
///
/// 🚨 **两个字段一起算**，不是只算英文：同一句英文可能是从不同中文说出来的，
///    那是两张不同的卡（正面不一样）。
///
/// 🚨 分隔符 `U+001F` **必须写成转义**，不许写不可见字符字面量 ——
///    第一版两端都写字面量，Java 被写成 U+0001、iOS 是 U+001F，
///    **两端 id 根本不一样，而两边自测都通过**。只有跨端比对才看得见。
enum WordId {

    static func make(_ zh: String, _ en: String) -> String {
        let s = norm(zh) + "\u{001F}" + norm(en)
        var h: Int64 = 1_125_899_906_842_597
        for ch in s.unicodeScalars {
            h = 31 &* h &+ Int64(ch.value)
        }
        return String(UInt64(bitPattern: h), radix: 16)
    }

    /// 去掉首尾空白、把中间连续空白压成一个空格。
    ///
    /// 🚨🚨 **手写字符集，不用 `.whitespacesAndNewlines`**。
    ///    Java 的 `\s` 只有 6 个 ASCII 字符，而 Swift 那个集合还包含
    ///    全角空格、不换行空格等一大票 Unicode 空白 —— **两端不是同一个集合**。
    ///    用各自的定义时，一句带全角空格的中文在两端会归一成不同的串，
    ///    于是**同一条记录算出两个 id**，而两边自测都通过。
    static func norm(_ s: String) -> String {
        var out = ""
        var pendingSpace = false
        for ch in s.unicodeScalars {
            if isWs(ch) {
                if !out.isEmpty { pendingSpace = true }
            } else {
                if pendingSpace { out.append(" "); pendingSpace = false }
                out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    /// Java `\s` 的那 6 个字符，**按码点写死**：
    /// 32(空格) 9(TAB) 10(LF) 11(VT) 12(FF) 13(CR)。
    ///
    /// 🚨 写码点而不是写 "	" 这种转义：这个工程里今天已经被
    ///    "转义在写文件时被解释掉"坑了三次。码点没有这个风险。
    private static func isWs(_ c: Unicode.Scalar) -> Bool {
        let v = c.value
        return v == 32 || v == 9 || v == 10 || v == 11 || v == 12 || v == 13
    }

    /// 跟安卓 `selfTest()` 一一对应。返回 nil = 全过。
    static func selfTest() -> String? {
        if norm("  a   b  ") != "a b" { return "norm 该压掉多余空白" }
        // 🚨 **制表符也要测**。原来只测空格，"从空白字符集里删掉 TAB"
        //    这个坏样本根本碰不到任何断言 —— 覆盖缺口。
        let tab = String(UnicodeScalar(9))
        if norm("a" + tab + tab + "b") != "a b" { return "norm 该把制表符也算空白" }
        let vt = String(UnicodeScalar(11))
        if norm("a" + vt + "b") != "a b" { return "norm 该把垂直制表符也算空白" }
        if make("我们要推迟", "push it back")
            == make("往后挪一下", "push it back") {
            return "中文不同就该是两条"
        }
        if make("ab", "c") == make("a", "bc") {
            return "id 没加分隔符，边界处会撞"
        }
        if make(" 我们 ", " push  it back ") != make("我们", "push it back") {
            return "id 该对空白不敏感"
        }
        // 🚨🚨 期望值写死，来自一段**等价的 Python 实现**，
        //    不是从 Java 或 Swift 任何一端跑出来的 —— 两端各自
        //    "不撞就算过"是同源自比，分隔符走散时两边照样全绿。
        let got1 = make("我们要推迟", "push it back")
        if got1 != "ac5871db3f06c37d" {
            // 🚨 **把实际值带上**：不带的话"改哈希种子"和"改分隔符"
            //    报的是同一句话，闸门会判成"两个坏样本同因"。
            return "id 跟约定不一致：中英样本算出 " + got1
        }
        let got2 = make("ab", "c")
        if got2 != "5e03fffffeb1116a" {
            return "id 跟约定不一致：分隔符边界样本算出 " + got2
        }
        return nil
    }
}
