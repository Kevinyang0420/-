import Foundation
import UserNotifications

/// **把认出来的提醒排成一条本地通知。** 只有主 App 用（键盘扩展不排）。
///
/// Kevin 09-07 选了 **A 档：普通提醒** —— 到点弹通知，**静音时不响**。
///
/// 🚨🚨 **我先前跟他说「iOS 不给第三方 App 真闹钟」，那句是错的、已撤回。**
///    市面上的闹钟 App 确实能穿透静音响铃，走的是**后台音频播放**
///    （`UIBackgroundModes: audio` + 播放类别的会话，静音开关管不着它）——
///    而我们**本来就声明了那个后台模式**（`project.yml:167`，为待命引擎加的）。
///    所以 B 档（真闹钟）对我们是便宜的，只是**他选了 A**。
///    → 这里做 A，但别在注释里留下"做不到"的假记录，
///      免得下一个人照着它把一件能做的事记成不能做。
///
/// 🚨 **权限被拒不许功能整个哑掉**（0 的硬要求）：
///    提示照弹（他当场看得见"记下了"），只是到点不通知。
///    **静默失败是最糟的一档** —— 他以为记下了，到点什么都没有。
enum RemindScheduler {

    /// 排一条。**已经排过同一条就替换，不叠加。**
    ///
    /// - Parameter onResult: 回主线程，`granted` 说明到点会不会真的通知。
    ///   界面据此决定提示语措辞 —— **不许两种情况说同一句话**。
    static func schedule(_ r: Remind,
                         onResult: @escaping (_ granted: Bool) -> Void) {
        let c = UNUserNotificationCenter.current()
        // 🚨 `.alert/.sound/.badge`，**不要 `.criticalAlert`** ——
        //    那个要单独向苹果申请授权，没批的话请求会直接失败，
        //    表现是"连普通通知都没弹"。A 档不碰它。
        c.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else {
                KbBridge.note("提醒：通知权限被拒 —— **提示照弹，只是到点不通知**")
                DispatchQueue.main.async { onResult(false) }
                return
            }
            let content = UNMutableNotificationContent()
            // 🚨 标题不写「闹钟」 —— 它不是闹钟，静音时不响。
            //    写成闹钟会让他按闹钟的预期用，然后在最需要的那次落空。
            content.title = L.remind_title
            content.body = r.what
            content.sound = .default
            let secs = max(1, r.at.timeIntervalSinceNow)
            let trig = UNTimeIntervalNotificationTrigger(timeInterval: secs,
                                                         repeats: false)
            // 🚨 id 用「时刻+内容」的哈希：同一条重复认出来时**替换而不是叠加**，
            //    否则他把同一句话说两遍，到点会连响两下。
            let id = "remind." + String(Int(r.at.timeIntervalSince1970))
                + "." + String(NotesCore.stableHash(r.what))
            let req = UNNotificationRequest(identifier: id, content: content,
                                            trigger: trig)
            c.add(req) { err in
                if let e = err {
                    // 🚨 **不静默**：排失败了就得说，否则跟"排上了"分不开。
                    KbBridge.note("提醒：排通知失败 —— " + e.localizedDescription)
                    DispatchQueue.main.async { onResult(false) }
                } else {
                    KbBridge.note("提醒：已排在 " + String(Int(secs)) + " 秒后")
                    DispatchQueue.main.async { onResult(true) }
                }
            }
        }
    }
}
