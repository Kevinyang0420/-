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
        w.rootViewController = vc
        w.makeKeyAndVisible()
        window = w
        return true
    }
}
