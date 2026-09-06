import Foundation

/// 「处理中… 已等 N 秒」这个秒表的**纯判断部分**。
///
/// 🚨 抽出来是因为里面最危险的一条是**「别人写了就交出去」** ——
///    `hintLabel` 有 9 个写入点，其中几个在 thinking 期间写**错误提示**。
///    这条要是坏了，用户刚看到的报错会被「处理中…」盖掉，
///    **而且不报任何错**：屏幕上有字、看着正常，只是把一个有用的信息
///    换成了一个没用的。这种坏法必须有判据挡着。
enum ThinkHint {

    /// 前几秒不打扰：让 `setPhase` 传进来的那句（如「重发中…」）先被看见。
    static let quietSec = 3

    /// 秒表该不该**交出控制权**。
    ///
    /// - owned: 上一次由秒表自己写进去的那句（空 = 还没接管过）
    /// - current: `hintLabel` 现在显示的内容
    ///
    /// 判据：**接管过、而当前文本已经不是自己写的那句** → 交出去。
    /// 🚨 还没接管过时不许交（`owned` 为空时任何 current 都不算"别人改的"），
    ///    否则秒表永远起不来 —— 那就是「永远不会通过的检查」的反面：
    ///    一个永远会退出的功能。
    static func shouldYield(owned: String, current: String?) -> Bool {
        if owned.isEmpty { return false }
        return current != owned
    }

    /// 这一秒该显示什么。返回 nil = **别动**（还在安静期）。
    static func line(elapsed: Int, template: String) -> String? {
        guard elapsed >= quietSec else { return nil }
        return template.replacingOccurrences(of: "%1$@", with: String(elapsed))
    }
}
