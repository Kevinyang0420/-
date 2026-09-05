import UIKit

/// 退格键的行为，**单一配置点**。照搬安卓 `Backspace.java`。
///
/// 🚨 Kevin 2026-08-21：「只能够一个一个单词、一个一个字母删吗？
///    不能全选之后一整个删吗？」安卓原来三处各写一遍 `deleteSurroundingText(1,0)`
///    —— 点一下删一个、长按没反应。三处分别修一定会漏，所以抽成一个类。
///    iOS 这边一开始就只留这一处。
///
/// 行为：
///   · 点一下       → 删一个字符
///   · 按住不放     → 400ms 后开始连删，先按字符、1.2 秒后**按词**加速
///   · 松手         → 停
///
/// 🚨 iOS 和安卓的差别：`UIKeyInput.deleteBackward()` 已经正确处理了
///    选中文字和 emoji 代理对（安卓那边要自己判 `isSurrogatePair`，
///    否则会把 emoji 劈成半个乱码）。所以这里不重复实现那两条，
///    但**按词删**系统没给，得自己数。
enum Backspace {
    /// 按住多久开始连删
    static let firstDelay: TimeInterval = 0.4
    /// 连删间隔
    static let repeatInterval: TimeInterval = 0.055
    /// 连删多久之后升级成按词删
    static let wordAfter: TimeInterval = 1.2

    /// 给一个按钮装上完整的退格行为。
    /// - Parameter eatsFirst: **前置钩子**，每一下删除之前问一次。
    ///   返回 true = 这一下已经被上层（拼音缓冲）吃掉，不要碰文档。
    ///   传 nil 就是老行为（一律删文档）。
    static func attach(_ button: UIButton,
                       proxy: @escaping () -> UITextDocumentProxy?,
                       eatsFirst: (() -> Bool)? = nil) {
        let h = Holder(proxy: proxy)
        h.eatsFirst = eatsFirst
        button.addTarget(h, action: #selector(Holder.down),
                         for: [.touchDown])
        button.addTarget(h, action: #selector(Holder.up),
                         for: [.touchUpInside, .touchUpOutside, .touchCancel])
        // 🚨 target-action 只持弱引用，Holder 会当场被释放、长按就没反应了。
        //    挂到按钮上保命 —— 按钮活多久它活多久。
        objc_setAssociatedObject(button, &holderKey, h,
                                 .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private final class Holder: NSObject {
        let proxy: () -> UITextDocumentProxy?
        /// **前置钩子**：返回 true 表示这一下已经被上层（拼音缓冲）吃掉了，
        /// 不要再删文档。
        ///
        /// 🚨🚨 为什么做成钩子、而不是在外面套一个 `if` 再决定要不要 attach：
        ///    退格在这个组件里有**三条出口** —— `down()` 那一下、长按连删、
        ///    以及超过 `wordAfter` 之后的按词删。外面套 if 只挡得住第一下，
        ///    **长按连删照样一路删到文档里**（他一按住就会把已经上屏的字也删掉）。
        ///    钩子放在这一层，三条出口自动都过它。
        ///    这正是本项目反复栽的那个形态：同一条规矩多个出口，只落地一个。
        var eatsFirst: (() -> Bool)?
        private var timer: Timer?
        private var downAt = Date()

        init(proxy: @escaping () -> UITextDocumentProxy?) {
            self.proxy = proxy
        }

        /// 删一下：**先问钩子**，钩子吃掉了就不碰文档。
        private func deleteOne() {
            if eatsFirst?() == true { return }
            proxy()?.deleteBackward()
        }

        @objc func down() {
            downAt = Date()
            deleteOne()                    // 先删一下，手感跟系统键盘一致
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: firstDelay,
                                          repeats: false) { [weak self] _ in
                self?.startRepeat()
            }
        }

        @objc func up() {
            timer?.invalidate()
            timer = nil
        }

        private func startRepeat() {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: repeatInterval,
                                          repeats: true) { [weak self] _ in
                guard let s = self else { return }
                // 🚨 长按连删**每一下都要问钩子**：缓冲里还剩拼音时，
                //    连删应该一个一个吃缓冲，而不是越过它去删已经上屏的字。
                if s.eatsFirst?() == true { return }
                guard let p = s.proxy() else { return }
                if Date().timeIntervalSince(s.downAt) > wordAfter {
                    Backspace.deleteWord(p)
                } else {
                    p.deleteBackward()
                }
            }
        }
    }

    /// 删掉光标前的一个「词」：先吃掉尾部空白，再吃掉连续的非空白。
    ///
    /// 🚨 中文没有空格分词，一路吃到空白会把整句删光。所以**汉字按单字删**
    ///    —— 安卓那边同理（它按 `Character.isLetterOrDigit` 判，
    ///    而汉字是 letter，所以中文其实也会连着吃；这里做得更保守一点，
    ///    宁可少删也别把他一整句吞了）。
    static func deleteWord(_ p: UITextDocumentProxy) {
        guard let before = p.documentContextBeforeInput, !before.isEmpty else {
            p.deleteBackward()
            return
        }
        for _ in 0..<wordDeleteCount(before) { p.deleteBackward() }
    }

    /// 光标前是 `before` 时，按词删该删掉几个字符。
    ///
    /// 🚨 **纯函数**，不碰 `UITextDocumentProxy` —— 抽出来就是为了能真的验。
    ///    塞在 `deleteWord` 里的话，要测就得有一个真的输入连接，
    ///    结果只能退化成"在源码里搜函数名"，那种检查任何输入都通过。
    static func wordDeleteCount(_ before: String) -> Int {
        if before.isEmpty { return 1 }
        var n = 0
        var idx = before.endIndex
        // 先吃尾部空白
        while idx > before.startIndex {
            let prev = before.index(before: idx)
            if before[prev].isWhitespace { n += 1; idx = prev } else { break }
        }
        // 再吃一串非空白；遇到汉字就只删一个（见上面的说明）
        var ate = 0
        while idx > before.startIndex {
            let prev = before.index(before: idx)
            let c = before[prev]
            if c.isWhitespace { break }
            if c.unicodeScalars.first.map({ $0.value >= 0x4E00 }) == true {
                if ate == 0 { n += 1; ate += 1 }
                break
            }
            n += 1
            ate += 1
            idx = prev
        }
        return max(1, n)
    }
}

private var holderKey: UInt8 = 0
