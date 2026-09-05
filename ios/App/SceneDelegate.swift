import UIKit

/// **Scene 代理：唯一能拿到「谁把我叫起来的」的地方。**
///
/// 🚨🚨 2026-08-29 Kevin 连按六次都回不到他说话那个页面。真机痕迹坐实了根因：
/// ```
/// 13:55:13  拉起主App：open 回调 true
/// 13:55:14  起录：回到前台时取到键盘的条子     ← 只能靠共享区的条子知道要录
/// 13:55:15  自动切回：来源未知，退回按Home
/// ```
/// **整条痕迹里没有「主App收到URL」** —— App 是活着的、URL 也确实发出去了，
/// 但 `application(_:open:)` **一次都没被调**。
///
/// 原因：工程开了 Scene（`INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES`）。
/// Scene 架构下 URL **只走这两个回调**：
///   · 冷启动 → `scene(_:willConnectTo:options:)` 的 `connectionOptions.urlContexts`
///   · 已在跑 → `scene(_:openURLContexts:)`   ← **他走的是这条**
/// 两个都没人接，所以来源永远是空的 → 不知道开回哪儿 → 只能按 Home → 落桌面。
///
/// 🚨 **不接管界面**：窗口仍旧由 `AppDelegate` 在 `didFinishLaunching` 里建好，
///    这里只把它挂到场景上。**故意不新建窗口** —— 那会变成两套界面代码。
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        // 冷启动那一路的来源在这里
        capture(connectionOptions.urlContexts, how: "冷启动")
        for ua in connectionOptions.userActivities { captureActivity(ua, how: "冷启动·通用链接") }
        guard let ws = scene as? UIWindowScene else { return }
        // 🚨 用 `AppDelegate` 已经建好的那个窗口，别新建。
        //    新建的话首页/深链/闪屏三条路都要再实现一遍，
        //    而那正是「同一件事两处实现」——今天已经踩过好几次。
        if let w = (UIApplication.shared.delegate as? AppDelegate)?.window {
            w.windowScene = ws
            w.makeKeyAndVisible()
            window = w
            KbBridge.note("Scene 接管窗口：沿用主App那个（可见=" + String(w.isKeyWindow) + "）")
        } else {
            KbBridge.note("🚨 Scene 连上时主App还没有窗口 —— 界面可能是黑的，要查")
        }
    }

    /// **App 已经在跑时收到 URL 走这里** —— 他每次按键盘走的正是这条。
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        captureActivity(userActivity, how: "叫醒·通用链接")
    }

    /// **通用链接进来时记下"谁开的我"**（2026-09-02，通用链接理论）。
    /// `referrerURL` / `sourceApplication` 都打出来 —— 这是唯一不需要权限的宿主身份通道（如果成立）。
    private func captureActivity(_ ua: NSUserActivity, how: String) {
        guard ua.activityType == NSUserActivityTypeBrowsingWeb, let url = ua.webpageURL else {
            KbBridge.note("Scene(" + how + ")：活动类型 " + ua.activityType + "，不是通用链接"); return
        }
        let ref = ua.referrerURL?.absoluteString ?? "无"
        // 🚨 不能 value(forKey:) —— 这个 KVC key 不存在，会抛 valueForUndefinedKey 直接崩（2026-09-02 12:35 实撞）。
        //    NSUserActivity 没有公开的"来源 App"属性；能拿的是 referrerURL。用 KVC 探测要用 try? 包 Mirror，别硬取。
        var src = "无"
        KbBridge.note("Scene(" + how + ") 通用链接：" + url.absoluteString + "｜referrer=" + ref + "｜source=" + src)
        if src != "无" && !src.isEmpty { KbBridge.rememberSource(src); KbBridge.rememberHost(src) }
        if url.path.hasPrefix("/kb/arm") { (UIApplication.shared.delegate as? AppDelegate)?.handleArmURL() }
        // 🚨 通用链接拉起后查 systemNavigationAction（返回条对象）是否非 nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { (UIApplication.shared.delegate as? AppDelegate)?.readOpenerProbe() }  // readOpenerProbe（通用链接）
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        capture(URLContexts, how: "叫醒")
        // 🚨 意图仍旧走共享区那张条子（冷启动送不到 URL，两条路只留一个出口）。
        //    这里**只负责把来源记下来**，不重复触发起录 ——
        //    重复触发会变成「两路抢同一个麦克风」，那个坑今天已经写在注释里了。
    }

    private func capture(_ ctxs: Set<UIOpenURLContext>, how: String) {
        guard let c = ctxs.first else {
            KbBridge.note("Scene(" + how + ")：没带 URL")
            return
        }
        let src = c.options.sourceApplication ?? ""
        KbBridge.note("Scene(" + how + ") 收到URL：" + c.url.absoluteString
                      + "｜来自 " + (src.isEmpty ? "未知" : src))
        if !src.isEmpty { KbBridge.rememberSource(src) }
        // 🚨🚨 **直接从这里起录，不再依赖「留条子」。**
        //    工程里一直写着「冷启动 URL 送不到，意图只能挂条子」——
        //    那是基于旧的 `launchOptions[.url]` 得出的，**已经过时**：
        //    2026-08-29 实测 `Scene(冷启动) 收到URL：transless://rec｜来自 com.kevin.tprobe`，
        //    **URL 和来源都送到了**。
        //    条子那条路有 10 秒有效期，过期就整轮白跑（今天连撞两次）。
        // 🚨 `handleRecURL()` 自己有去重，重复进来不会起两路录音。
        // 🚨 **同一规矩必须两个出口都落地** —— 这个文件顶上就写着这条教训。
        if c.url.host == "probehost" || c.url.path == "probehost" {
            (UIApplication.shared.delegate as? AppDelegate)?.probeHostByShowingKeyboard()
            return
        }
        if c.url.host == "arm" || c.url.path == "arm" {
            KbBridge.note("Scene(" + how + ")：收到 arm，只架引擎")
            DispatchQueue.main.async {
                (UIApplication.shared.delegate as? AppDelegate)?.handleArmURL()
            }
            return
        }
        if c.url.host == "rec" || c.url.path == "rec" {
            KbBridge.note("Scene(" + how + ")：这就是起录 URL，直接走起录")
            DispatchQueue.main.async {
                (UIApplication.shared.delegate as? AppDelegate)?.handleRecURLPublic()
            }
        }
    }
}
