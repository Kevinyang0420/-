import UIKit

// 探针容器 App。什么都不干，只是键盘扩展的宿主。
// 这个 App 存在的意义：TransProbe 的键盘是**最小可能的键盘扩展**
// （没有录音、没有网络、没有 Secrets，连约束布局都最少）——
// 它要是能弹出来，问题就在 Transless 的代码；它也弹不出来，问题就在签装链。

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ app: UIApplication,
                     didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds)
        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground
        let l = UILabel()
        l.text = "TransProbe\n\n这是探针：去 设置>通用>键盘 添加\n「TransProbe」，能弹出紫色面板就算通过。"
        l.numberOfLines = 0
        l.textAlignment = .center
        l.frame = vc.view.bounds.insetBy(dx: 24, dy: 100)
        vc.view.addSubview(l)
        // 🚨 UI 测试要靠它把键盘弹出来。**自动聚焦**，测试就不用先找位置点一下。
        let tf = UITextField(frame: CGRect(x: 24, y: 200,
                                           width: w.bounds.width - 48, height: 44))
        tf.borderStyle = .roundedRect
        tf.placeholder = "UI 测试用输入框"
        tf.accessibilityIdentifier = "probe.field"
        vc.view.addSubview(tf)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { tf.becomeFirstResponder() }
        w.rootViewController = vc
        w.makeKeyAndVisible()
        window = w
        // 🚨🚨 **我用它当「微信」**：它去开 `transless://rec`，
        //    主 App 退出之后**如果回到这里**，下面那条通知就会打一条痕迹。
        //    这样「退出到底回哪」这个问题我自己就能答，不用 Kevin 去按。
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { _ in
            Probe.note("探针：我回到前台了")
        }
        if ProcessInfo.processInfo.environment["PROBE_OPEN_REC"] == "1" {
            Probe.note("探针：准备去开 transless://rec")
            // 🚨 可延时：我要在这中间把主 App 杀掉（模拟"他很久没用、进程已回收"），
            //    而起录条子只有十来秒有效期，来不及就白跑一轮。
            let d = Double(ProcessInfo.processInfo.environment["PROBE_OPEN_DELAY"] ?? "1.5") ?? 1.5
            DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                if let u = URL(string: "transless://rec") {
                    app.open(u, options: [:]) { ok in
                        Probe.note("探针：开 transless://rec " + (ok ? "成功" : "失败"))
                    }
                }
            }
        }
        return true
    }
}
