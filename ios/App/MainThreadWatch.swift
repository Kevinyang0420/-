import Foundation

/// **主线程卡死侦测**（2026-08-29 加）。
///
/// 🚨 为什么需要它：Kevin 两次撞到「打开 Transless 就卡住、界面出不来」，
///    而我**一次都没定位到卡在哪** —— 主线程一卡，所有日志都写不出来，
///    痕迹停在卡住前的最后一条，看起来像"什么都没发生"。
///
/// 做法：后台线程每 2 秒往主队列丢一个回声；5 秒没回来就**由后台线程**
/// 写一条痕迹（后台写不受主线程影响）。卡住的时刻 + 卡住前最后一条痕迹 = 定位区间。
///
/// 🚨 **覆盖 / 不覆盖**（按今天的规矩，判据必须写清范围）：
///   · 覆盖：主线程被同步阻塞（死锁、忙等、长时间同步 IO）
///   · **不覆盖**：整个 App 被系统挂起 —— 那时后台线程也不跑，什么都不会写。
///     两者靠「卡住之后还有没有别的痕迹」区分。
enum MainThreadWatch {

    private static var started = false
    private static let lock = NSLock()
    private static var lastPong = Date()
    private static var reported = false

    static func start() {
        lock.lock(); defer { lock.unlock() }
        if started { return }
        started = true
        lastPong = Date()
        Thread.detachNewThread {
            while true {
                Thread.sleep(forTimeInterval: 2)
                DispatchQueue.main.async {
                    lock.lock(); lastPong = Date(); reported = false; lock.unlock()
                }
                Thread.sleep(forTimeInterval: 0.3)
                lock.lock()
                let gap = Date().timeIntervalSince(lastPong)
                let already = reported
                if gap > 5 && !already { reported = true }
                lock.unlock()
                if gap > 5 && !already {
                    KbBridge.note("🚨 主线程卡住已 "
                                  + String(format: "%.0f", gap)
                                  + " 秒（上面最后一条痕迹就是卡住前的最后一步）")
                }
            }
        }
    }
}
