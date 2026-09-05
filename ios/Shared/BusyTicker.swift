import UIKit

/// **处理中那一档在圆钮里数秒** —— 随手翻译 / 面对面共用这一个实现。
///
/// 🚨🚨 Kevin 2026-09-05：「它没有倒数。不是有三个阶段嘛，在第三个阶段
///    它没有那个数数，就还是很不统一。」
///    面对面写了一份、键盘写了一份，**随手那一屏干脆没写** ——
///    第三阶段只有一个静态的「…」，看上去跟卡死没区别。
///
/// 🚨 为什么抽出来：这是同一条规矩的第三份实现。前两份已经漂了
///    （一份数秒、一份不数），再抄一遍只会有第四份。
///
/// 用法：**只在相位渲染的唯一出口调 `sync`**，不要散在起录/停录/失败各处 ——
///    那是三个出口，漏一个就会出现「已经出结果了、秒数还在涨」。
final class BusyTicker {
    private var timer: Timer?
    private var since = Date()

    /// - Parameters:
    ///   - busy: 当前是不是"处理中"那一档
    ///   - button: 要往里写秒数的圆钮
    func sync(busy: Bool, on button: UIButton) {
        guard busy else { stop(); return }
        // 🚨🚨 **已经在数就别重来。** 渲染出口在处理中会被反复调到
        //    （版式刷新、状态刷新都会走它）。每次都重置起点的话，
        //    秒数**永远停在 0s** —— 而"停住"恰恰是他用来判断
        //    "是不是挂了"的信号，等于把指示器做成了恒定的假信号，比没有更糟。
        if timer != nil { return }
        since = Date()
        button.setTitle("…", for: .normal)          // 兜住第 0 秒，别闪一格空白
        button.setTitleColor(.white, for: .normal)
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) {
            [weak self, weak button] t in
            guard let self = self, let b = button else {
                t.invalidate(); self?.timer = nil; return
            }
            let sec = Int(Date().timeIntervalSince(self.since))
            b.setTitle(sec <= 0 ? "…" : "\(sec)s", for: .normal)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }
}
