import ActivityKit
import UIKit
import ObjectiveC
import AVFoundation

// Transless 容器 App —— **四个界面全部对齐安卓**：开屏 / 首页 / 引导 / 设置。
//
// 🚨🚨 Kevin 2026-08-25：「我是让你所有的 APP 的界面、功能、结构、UI
//    跟安卓的保持一模一样」。
//
// 🚨 我上一版只做了首页就把 App 里那套翻译界面删了，理由是「干活的是键盘」——
//    **那句话在安卓成立，在 iOS 不成立**：iOS 键盘扩展只有 267 行、
//    就一个麦克风，没有拼音/字母/符号/手写/九宫格（安卓那一套 4434 行）。
//    我删之前**没查 iOS 键盘里到底有什么**，直接套用了安卓的结论，
//    结果把 iOS 从"App 里还能用"变成"哪儿都不能用"。
//    他的原话：「搞了一下午就搞出一个废物出来」。
//
// 🚨 配色排版一律从 `Skin.swift` 取（由 `sync_skin_ios.py` 从安卓
//    `Skin.java` 生成）。图标和 logo 由 `sync_ios_icon.py` 从安卓的图生成。
//    这里一个色值、一张图都不许写死。

/// 品牌语。两端一模一样、不随界面语言变（安卓那边也是写死在代码里）。
enum Brand {
    static let sloganZh = "让世界听懂你"
    static let sloganEn = "No Language In Between"
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    /// **被键盘用 `transless://rec` 拉起来时，在前台起录。**
    ///
    /// 🚨 判据分五件事，**别合成一句**（今晚在这一族上栽过五次）：
    /// ① 键盘调了 ② open 回调成没成 ③ **主 App 真到了前台**
    /// ④ **前台起录成功** ⑤ **会不会自己跳回原来那个 App**
    /// 「调了」≠「成功」≠「真到前台」，三件事。
    /// 🚨🚨🚨 **这才是拿到「谁把我叫起来的」的正确入口。**
    ///
    /// Kevin 2026-08-29 按了三次，三次都落桌面。痕迹里 `来源未知（空）`，
    /// 而且**连「主App收到URL」这一行都没有** —— 说明
    /// `application(_:open:)` 根本没被调。
    ///
    /// 根因：工程开了 **Scene**（`project.yml` 里
    /// `INFOPLIST_KEY_UIApplicationSceneManifest_Generation: YES`）。
    /// Scene 架构下 URL **不走 App 代理那个回调**：
    ///   · 冷启动 → `configurationForConnecting` 的 `options.urlContexts`（**就是这里**）
    ///   · 已在跑 → `scene(_:openURLContexts:)`
    /// 我们两个都没接，所以来源永远是空的 → 不知道开回哪儿 → 只能按 Home → 落桌面。
    ///
    /// 🚨 **这个方法本身不改变任何行为**：返回的还是默认配置（不指定
    ///    `delegateClass`），窗口照旧由 App 代理建。**只是顺路把来源读走。**
    ///    —— 故意不引入 SceneDelegate：那会把建窗口的责任接过来，风险大得多。
    /// 🚨 覆盖范围：**只覆盖冷启动那一路**（他现在走的正是这一路）。
    ///    已在跑那一路要 `scene(_:openURLContexts:)`，那个得有 SceneDelegate 才接得到。
    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let ctx = options.urlContexts.first {
            let src = ctx.options.sourceApplication ?? ""
            KbBridge.note("Scene 连上｜URL=" + ctx.url.absoluteString
                          + "｜来自 " + (src.isEmpty ? "未知" : src))
            if !src.isEmpty { KbBridge.rememberSource(src) }
            AppDelegate.launchedByURL = true   // 🚨 开屏据此跳过动画
        } else {
            KbBridge.note("Scene 连上｜没带 URL")
        }
        let cfg = UISceneConfiguration(name: nil, sessionRole: session.role)
        // 🚨 指定 Scene 代理 —— **只有它能收到「已在跑时的 URL」**（`openURLContexts`），
        //    而他每次按键盘走的正是那条。窗口仍由本类建，代理只是挂上去。
        cfg.delegateClass = SceneDelegate.self
        return cfg
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        // 🚨🚨 **拿住「是谁把我叫起来的」** —— 这是能真正回到微信的唯一线索。
        //    Kevin 2026-08-29 连说三次「不能退到桌面，必须回输入框那个窗口」。
        //    `suspend` 等于替他按 Home，**iOS 不知道要回哪儿**，所以必然落桌面。
        //    有了来源 App 的 bundle id，就能用它自己的 scheme 开回去。
        // 🚨 冷启动那一路**不会走这个回调**（工程里早有记录），所以要**存下来下次用**：
        //    键盘绝大多数时候都在同一个 App 里用，上一次的来源就是最好的猜测。
        if let src = options[.sourceApplication] as? String, !src.isEmpty {
            KbVoiceHost.rememberSource(src)
            KbBridge.note("主App收到URL：" + url.absoluteString + "｜来自 " + src)
        } else {
            KbBridge.note("主App收到URL：" + url.absoluteString + "｜来源未知")
        }
        if url.host == "rec" || url.path == "rec" { handleRecURL(); return true }
        if url.host == "arm" || url.path == "arm" { handleArmURL(); return true }
        // 🚨 自测通道：我自己 `devicectl --payload-url transless://probehost` 触发，不用他动手
        if url.host == "probehost" || url.path == "probehost" {
            probeHostByShowingKeyboard(); return true
        }
        return false
    }

    /// 被 `transless://arm` 拉起来时该做的事：**只把引擎架好，然后自己退出去。**
    ///
    /// 🚨🚨 **这是「主 App 被划掉」之后唯一可行的恢复路径。**
    ///    2026-08-30 验死：后台的 App 拿不到麦克风输入路由（`输入源 0 个`，
    ///    连播放引擎都起不来 `-10851`），所以推送把它拉起来也架不上 ——
    ///    架引擎**必须有一个前台的瞬间**。
    ///
    ///    但那个瞬间可以只用来架引擎，不用把他扣在这儿录完一整段：
    ///    架好 → 立刻 `suspend` 自己 → 他落回桌面点一下微信 → 之后永远不用再跳。
    ///    这比原来的 `rec`（跳过来录完、录完还留在这儿）少一大截麻烦。
    /// 🚨 **让我能不靠手点就复现「被划掉之后按录音」这条链。**
    ///    `devicectl device process launch … com.kevin.transless arm` 会把 `arm`
    ///    送进 `CommandLine.arguments`，冷启动看到它就当收到了 `transless://arm`。
    ///    （真机 UI 自动化连试四轮都够不到第三方键盘，这是唯一能自测这条链的办法。）
    static func armFromLaunchArgs() -> Bool {
        return CommandLine.arguments.contains("arm")
    }

    /// **「已就绪，点左上角回去」那一屏。**
    ///
    /// 🚨 这不是"把让他点当方案"（他否过），是**苹果不给回程 API 时的诚实告知**：
    ///    他被拽过来又看不到任何说明，只会觉得又坏了。**沉默比一句说明更糟。**
    /// 🚨 幂等：已经挂着就不再挂第二层（`arm` 可能被触发两次 ——
    ///    冷启动的 launchOptions 和 `application(_:open:)` 都会走到）。
    static func showReadyOverlay() {
        guard let w = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else {
            KbBridge.note("就绪提示：拿不到窗口，没显示")
            return
        }
        let TAG = 90210
        if w.viewWithTag(TAG) != nil { return }

        let v = UIView(frame: w.bounds)
        v.tag = TAG
        v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.backgroundColor = UIColor.black.withAlphaComponent(0.92)

        // 🚨 箭头改指**底部边缘**（Kevin 2026-09-01 发来的 Typeless 引导页就是这么教的：
        //    「向后滑动以继续」+ 配图画在右下角）。原来指左上角那个系统返回键，
        //    目标小得多 —— **有上架产品验证过的答案就照抄，别自己重新设计。**
        let up = UILabel()
        up.text = L.swipe_back_hint
        up.textColor = .systemGreen
        up.font = .systemFont(ofSize: 15, weight: .semibold)
        up.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "✓ " + L.ready_title
        title.textColor = .white
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        title.textAlignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let body = UILabel()
        body.text = L.ready_body
        body.textColor = UIColor.white.withAlphaComponent(0.82)
        body.font = .systemFont(ofSize: 16)
        body.numberOfLines = 0
        body.textAlignment = .center
        body.translatesAutoresizingMaskIntoConstraints = false

        [up, title, body].forEach { v.addSubview($0) }
        w.addSubview(v)
        NSLayoutConstraint.activate([
            up.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            up.bottomAnchor.constraint(equalTo: v.safeAreaLayoutGuide.bottomAnchor,
                                       constant: -10),
            title.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: v.centerYAnchor, constant: -24),
            body.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 32),
            body.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -32),
            body.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
        ])
        // 🚨 点一下就收起来 —— 别把他锁在一屏说明里。
        v.addGestureRecognizer(UITapGestureRecognizer(
            target: v, action: #selector(UIView.kbRemoveSelf)))
        // 🚨🚨 **他多半不会点，而是直接按左上角走人 —— 那这层黑幕就留在那儿了。**
        //    下次他正常打开主 App，看到的是一整屏黑底白字，只会以为坏了。
        //    → 再挂一条：**下次回到前台时自动撤掉**。
        //    （"一次提示变成永久遮挡"是那种看起来没问题、用起来才发现的坏法。）
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main) { [weak v] _ in
            v?.removeFromSuperview()
            if let t = token { NotificationCenter.default.removeObserver(t) }
        }
        KbBridge.note("就绪提示：已显示（告诉他点左上角回去；下次回前台自动撤掉）")
    }

    /// **类级扒表：`NSExtensionContext` / `UIInputViewController` 上有没有宿主身份字段。**
    ///
    /// 🚨 放在主 App 里是因为**类的方法表不需要实例** —— 我自己 `devicectl` 启动一下
    ///    就能拿到答案，不用等他去按键盘。（键盘里那个探针读的是**实例值**，
    ///    那个仍然要等键盘真出现。两个探针问的不是同一个问题：
    ///    这里问"字段存不存在"，那里问"字段里装的是谁"。）
    /// **自己把键盘叫出来** —— 用来在他不在场时验证键盘那条私有方法。
    ///
    /// 🚨 这样验出来的宿主是**我们自己**（`com.kevin.transless`），
    ///    这正是好样本：**能读出正确的宿主 = 通道成立**。
    ///    宿主是不是微信要等他真在微信里按一次，那是第二步。
    func probeHostByShowingKeyboard() {
        DispatchQueue.main.async {
            guard let w = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else {
                KbBridge.note("叫键盘：没有可用窗口")
                return
            }
            let tf = UITextField(frame: CGRect(x: 8, y: 60, width: 200, height: 32))
            tf.tag = 987654
            w.addSubview(tf)
            tf.becomeFirstResponder()
            KbBridge.note("叫键盘：已弹出输入框，等键盘上来")
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                tf.resignFirstResponder()
                tf.removeFromSuperview()
                KbBridge.note("叫键盘：收工")
            }
        }
    }

    /// **注册静默推送**（不弹任何东西，纯粹用来在后台叫醒自己）。
    ///
    /// 🚨 不申请通知权限：`content-available` 的静默推送**不需要用户授权**，
    ///    也不会有横幅/声音/角标。他不会看到任何东西。
    func registerSilentPush() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func application(_ app: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken data: Data) {
        let tok = data.map { String(format: "%02x", $0) }.joined()
        KbBridge.note("静默推送：拿到设备令牌 " + String(tok.prefix(16)) + "…（共 "
                      + String(tok.count) + " 字符）")
        // 🚨 写进 App Group，我用 `devicectl copy from` 取出来发推送 ——
        //    令牌**不打全量到痕迹里**（痕迹是环形缓冲，会被刷掉，而且没必要）。
        if let u = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: KbBridge.group)?
            .appendingPathComponent("Library/Caches/pushtoken.txt") {
            try? tok.write(to: u, atomically: true, encoding: .utf8)
        }
    }

    func application(_ app: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        KbBridge.note("静默推送：注册失败 —— " + error.localizedDescription)
    }

    /// **被静默推送叫醒了 → 在后台把引擎架好。**
    ///
    /// 🚨 系统只给几秒执行窗口，`completionHandler` 必须调，且**别拖**，
    ///    否则 iOS 会降低以后叫醒我们的频率（这是它对"叫醒了不干活"的惩罚）。
    func application(_ app: UIApplication,
                     didReceiveRemoteNotification info: [AnyHashable: Any],
                     fetchCompletionHandler done: @escaping (UIBackgroundFetchResult) -> Void) {
        KbBridge.note("静默推送：被叫醒了（此刻前台="
                      + String(app.applicationState == .active) + "）→ 去架引擎")
        // 🚨🚨🚨 **走「冷启梯子」，不走 `armForBackground()`。**
        //    实测（06:32:42）：`armForBackground` 里我自己写了一道
        //    `guard applicationState == .active`，还把它标成
        //    **「这条是 iOS 的硬限制」** —— 而同一晚 04:27:17 的痕迹是
        //    `冷启架引擎（走梯子）：成了 ✅`，**同样不在前台，架成了**。
        //    我编的限制，被我自己的日志推翻。
        //    🚨 但也别反过来当成"后台一定能架"：06:30:55 那次梯子是**失败**的
        //    （待命档引擎没起来）。真实情况是**时灵时不灵**，
        //    所以这里必须报出成/败，不许静默。
        KbVoiceHost.shared.tryArmOnColdLaunch()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            let ok = KbBridge.hostArmed()
            KbBridge.note("静默推送：叫醒后架引擎 = " + (ok ? "成了 ✅" : "没成 ❌"))
            done(ok ? .newData : .noData)
        }
    }

    /// **扒「回上一个 App」的系统原语**（2026-09-02 08:4x）。
    ///
    /// 🚨 依据：Kevin 实测 Typeless 能回到 **eMPF**（一个没有任何 URL scheme 的 App）
    ///    → 它不是靠 open(URL)，是靠某个系统级"回上一个 App"的原语，iOS 26.6 上可用。
    /// 🚨 台账里以前那些 `_returnToPreviousApp` 之类是**我猜的名字**；
    ///    上次真正的线索（`_hostApplicationBundleIdentifier`）是**扒表**扒出来的。
    ///    这次同样扒表，不猜。只读方法名，不调用，零崩溃风险。
    /// 🚨 由 Darwin 通知 `…debug.dumpret` 触发，不在每次启动跑 —— 痕迹是 200 行环形缓冲。
    func dumpReturnPrimitives() {
        let keys = ["previous", "return", "suspend", "opener", "source", "resign",
                    "dismiss", "deactivat", "frontmost", "switch", "backtoapp",
                    "requestscene", "openurl", "launch"]
        let classes = ["UIApplication", "UIScene", "UIWindowScene", "UISceneSession",
                       "UISceneActivationRequestOptions", "UIWindowSceneActivationRequestOptions",
                       "UIOpenURLContext", "UIApplicationSceneClientSettings",
                       "FBSOpenApplicationService", "FBSOpenApplicationOptions",
                       "FBSSceneManager", "UIScenePresentationManager",
                       "_UISceneOpenURLOptions", "UIApplicationSceneSettings",
                       "RBSProcessHandle", "LSApplicationWorkspace"]
        var total = 0
        for cn in classes {
            guard let c: AnyClass = NSClassFromString(cn) else { continue }
            var hits: [String] = []
            for meta in [false, true] {
                let k: AnyClass = meta ? (object_getClass(c) ?? c) : c
                var n: UInt32 = 0
                guard let ms = class_copyMethodList(k, &n) else { continue }
                for i in 0..<Int(n) {
                    let nm = NSStringFromSelector(method_getName(ms[i]))
                    let low = nm.lowercased()
                    if keys.contains(where: { low.contains($0) }) {
                        hits.append((meta ? "+" : "-") + nm)
                    }
                }
                free(ms)
            }
            if hits.isEmpty { continue }
            total += hits.count
            // 一行塞多个，省环形缓冲
            var line = ""
            for h in hits {
                if line.count + h.count > 300 {
                    KbBridge.note("扒回程原语 " + cn + " ▸ " + line)
                    line = ""
                }
                line += h + " ｜ "
            }
            if !line.isEmpty { KbBridge.note("扒回程原语 " + cn + " ▸ " + line) }
        }
        KbBridge.note("扒回程原语：共 " + String(total) + " 条候选（只列名字，一条都没调）")
    }

    /// **扒 LSApplicationWorkspace 全部方法 + 直接试按 bundle ID 打开 TransProbe。**
    /// 依据：跑器截图证明 Typeless 是按 bundle ID 把没有 scheme 的 TransProbe 开回来的（左上角「◀ Typeless」）。
    /// 台账里「openApplicationWithBundleID 26.4 被封」是论坛说法，没在这台机上实测过 —— 现在实测。
    /// **PID / 审计令牌 → 宿主 bundle ID：把 RunningBoard/LaunchServices 里的口子全试一遍。**
    func pidToBundleProbe() {
        var pid = Int32(KbBridge.hostPid())
        // 自测口子：probepid.txt 指定一个第三方进程的 pid（验 RBS 对非本 team 进程是否也给答案）
        if let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: KbBridge.group)?
            .appendingPathComponent("Library/Caches/probepid.txt"),
           let txt = try? String(contentsOf: u, encoding: .utf8),
           let p = Int32(txt.trimmingCharacters(in: .whitespacesAndNewlines)), p > 0 {
            pid = p; KbBridge.note("P2B：用 probepid.txt 指定的第三方 pid " + String(p))
        }
        let tok = KbBridge.hostToken()
        KbBridge.note("P2B：宿主 pid=" + String(pid) + "｜令牌=" + String(tok?.count ?? 0) + " 字节")
        for cn in ["RBSProcessHandle", "RBSProcessIdentifier", "RBSProcessIdentity", "RBSProcessPredicate",
                   "LSBundleProxy", "LSApplicationProxy", "LSApplicationRecord", "LSApplicationWorkspace",
                   "LSBundleRecord", "FBSSystemService", "UIApplication"] {
            guard let c: AnyClass = NSClassFromString(cn) else { continue }
            var hits: [String] = []
            for meta in [false, true] {
                let k: AnyClass = meta ? (object_getClass(c) ?? c) : c
                var n: UInt32 = 0
                guard let ms = class_copyMethodList(k, &n) else { continue }
                for i in 0..<Int(n) {
                    let nm = NSStringFromSelector(method_getName(ms[i])); let l = nm.lowercased()
                    if l.contains("audittoken") || l.contains("pid") || l.contains("processidentifier")
                        || (l.contains("process") && l.contains("bundle")) {
                        hits.append((meta ? "+" : "-") + nm)
                    }
                }
                free(ms)
            }
            if !hits.isEmpty { KbBridge.note("P2B " + cn + " ▸ " + hits.prefix(14).joined(separator: " ｜ ")) }
        }
        if pid > 0, let idc: AnyClass = NSClassFromString("RBSProcessIdentifier"),
           let hc: AnyClass = NSClassFromString("RBSProcessHandle") {
            let s1 = NSSelectorFromString("identifierWithPid:")
            if let m = class_getClassMethod(idc, s1) {
                typealias F1 = @convention(c) (AnyClass, Selector, Int32) -> AnyObject?
                let f1 = unsafeBitCast(method_getImplementation(m), to: F1.self)
                if let ident = f1(idc, s1, pid) {
                    let s2 = NSSelectorFromString("handleForIdentifier:error:")
                    if let m2 = class_getClassMethod(hc, s2) {
                        typealias F2 = @convention(c) (AnyClass, Selector, AnyObject, UnsafeMutablePointer<NSError?>?) -> AnyObject?
                        let f2 = unsafeBitCast(method_getImplementation(m2), to: F2.self)
                        var err: NSError? = nil
                        if let h = f2(hc, s2, ident, &err) {
                            let bundle = h.value(forKey: "bundle") as AnyObject?
                            let bid = (bundle?.value(forKey: "identifier") as? String) ?? "(nil)"
                            KbBridge.note("P2B ✅ RBSProcessHandle(pid " + String(pid) + ").bundle.identifier = " + bid)
                        } else {
                            KbBridge.note("P2B RBSProcessHandle 失败：" + (err?.localizedDescription ?? "nil") + " code=" + String(err?.code ?? 0))
                        }
                    } else { KbBridge.note("P2B RBSProcessHandle 没有 handleForIdentifier:error:") }
                } else { KbBridge.note("P2B identifierWithPid: 返回 nil") }
            } else { KbBridge.note("P2B RBSProcessIdentifier 没有 identifierWithPid:") }
        }
        if let tok = tok, tok.count == MemoryLayout<audit_token_t>.size {
            var at = audit_token_t()
            withUnsafeMutableBytes(of: &at) { raw in tok.copyBytes(to: raw.bindMemory(to: UInt8.self)) }
            for (cn, sn) in [("LSBundleProxy", "bundleProxyWithAuditToken:error:"),
                             ("LSBundleRecord", "bundleRecordForAuditToken:error:"),
                             ("RBSProcessHandle", "handleForAuditToken:error:")] {
                guard let c: AnyClass = NSClassFromString(cn) else { continue }
                let sel = NSSelectorFromString(sn)
                guard let m = class_getClassMethod(c, sel) else { KbBridge.note("P2B " + cn + " 没有 " + sn); continue }
                typealias F3 = @convention(c) (AnyClass, Selector, audit_token_t, UnsafeMutablePointer<NSError?>?) -> AnyObject?
                let f3 = unsafeBitCast(method_getImplementation(m), to: F3.self)
                var err: NSError? = nil
                if let obj = f3(c, sel, at, &err) {
                    let bid = (obj.value(forKey: "bundleIdentifier") as? String)
                        ?? (obj.value(forKey: "applicationIdentifier") as? String)
                        ?? String(describing: obj).prefix(120).description
                    KbBridge.note("P2B ✅ " + cn + "." + sn + " → " + bid)
                } else {
                    KbBridge.note("P2B " + cn + "." + sn + " 失败：" + (err?.localizedDescription ?? "nil") + " code=" + String(err?.code ?? 0))
                }
            }
        }
        KbBridge.note("P2B：完")
    }

    /// **反查：枚举已装 App，逐个问系统它的 pid，凑出 pid→bundle 表。**
    /// 正向（pid→谁）全被权限挡；反向问的是"我自己能查的清单"，门槛不同。
    func pidMapProbe() {
        var target = Int32(KbBridge.hostPid())
        if let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: KbBridge.group)?
            .appendingPathComponent("Library/Caches/probepid.txt"),
           let txt = try? String(contentsOf: u, encoding: .utf8),
           let p = Int32(txt.trimmingCharacters(in: .whitespacesAndNewlines)), p > 0 { target = p }
        KbBridge.note("PM：目标 pid=" + String(target))
        guard let wsc: AnyClass = NSClassFromString("LSApplicationWorkspace"),
              let ws = (wsc as AnyObject).perform(NSSelectorFromString("defaultWorkspace"))?.takeUnretainedValue() else {
            KbBridge.note("PM：拿不到 workspace"); return
        }
        // ① 已装 App 列表
        var apps: [AnyObject] = []
        for sn in ["allInstalledApplications", "allApplications"] {
            let sel = NSSelectorFromString(sn)
            if ws.responds(to: sel), let arr = ws.perform(sel)?.takeUnretainedValue() as? [AnyObject] { apps = arr; KbBridge.note("PM：" + sn + " → " + String(arr.count) + " 个"); break }
        }
        var bids: [String] = apps.compactMap { $0.value(forKey: "bundleIdentifier") as? String }
        if bids.isEmpty,
           let u = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: KbBridge.group)?
            .appendingPathComponent("Library/Caches/bundles.txt"),
           let txt = try? String(contentsOf: u, encoding: .utf8) {
            bids = txt.split(whereSeparator: { $0.isNewline }).map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            KbBridge.note("PM：LS 列表为空，改用清单 " + String(bids.count) + " 个")
        }
        if bids.isEmpty { KbBridge.note("PM：没有任何 bundle 清单"); return }
        // LSApplicationProxy 上有没有 pid/isRunning 类字段
        if let first = apps.first {
            let c: AnyClass = type(of: first)
            var names: [String] = []; var n: UInt32 = 0
            if let ms = class_copyMethodList(c, &n) {
                for i in 0..<Int(n) { let nm = NSStringFromSelector(method_getName(ms[i])); let l = nm.lowercased()
                    if l.contains("pid") || l.contains("running") || l.contains("process") { names.append(nm) } }
                free(ms)
            }
            KbBridge.note("PM " + String(describing: c) + " ▸ " + names.prefix(20).joined(separator: " ｜ "))
        }
        // ② FBSSystemService.sharedService.pidForApplication:
        var fbs: AnyObject? = nil
        if let fc: AnyClass = NSClassFromString("FBSSystemService") {
            for sn in ["sharedService", "sharedInstance"] {
                let sel = NSSelectorFromString(sn)
                if let m = class_getClassMethod(fc, sel) {
                    typealias F0 = @convention(c) (AnyClass, Selector) -> AnyObject?
                    fbs = unsafeBitCast(method_getImplementation(m), to: F0.self)(fc, sel); if fbs != nil { break }
                }
            }
        }
        KbBridge.note("PM：FBSSystemService 实例=" + (fbs == nil ? "nil" : "有"))
        var hit = "(没对上)"
        var running: [String] = []
        if let fbs = fbs, let m = class_getInstanceMethod(type(of: fbs), NSSelectorFromString("pidForApplication:")) {
            typealias FP = @convention(c) (AnyObject, Selector, NSString) -> Int32
            let f = unsafeBitCast(method_getImplementation(m), to: FP.self)
            let sel = NSSelectorFromString("pidForApplication:")
            for bid in bids {
                let p = f(fbs, sel, bid as NSString)
                if p > 0 { running.append(bid + "=" + String(p)); if p == target { hit = bid } }
            }
            KbBridge.note("PM：FBS 问出在跑的 " + String(running.count) + " 个：" + running.prefix(12).joined(separator: " ｜ "))
        } else { KbBridge.note("PM：FBSSystemService 没有 pidForApplication:") }
        KbBridge.note("PM 🎯 宿主 pid " + String(target) + " = " + hit)
    }

    func dumpLSWorkspaceAndTryOpen() {
        guard let c: AnyClass = NSClassFromString("LSApplicationWorkspace") else {
            KbBridge.note("LSWS：类不存在"); return
        }
        var names: [String] = []
        var n: UInt32 = 0
        if let ms = class_copyMethodList(c, &n) {
            for i in 0..<Int(n) { names.append(NSStringFromSelector(method_getName(ms[i]))) }
            free(ms)
        }
        let hits = names.filter { let l = $0.lowercased(); return l.contains("open") || l.contains("pid") || l.contains("process") || l.contains("bundleid") || l.contains("launch") }
        var line = ""
        for h in hits.sorted() {
            if line.count + h.count > 300 { KbBridge.note("LSWS ▸ " + line); line = "" }
            line += h + " ｜ "
        }
        if !line.isEmpty { KbBridge.note("LSWS ▸ " + line) }
        KbBridge.note("LSWS：共 " + String(names.count) + " 个方法，相关 " + String(hits.count) + " 个")
        // 直接试：+defaultWorkspace → -openApplicationWithBundleID:
        let dsel = NSSelectorFromString("defaultWorkspace")
        guard let meta = object_getClass(c), class_respondsToSelector(meta, dsel),
              let ws = (c as AnyObject).perform(dsel)?.takeUnretainedValue() else {
            KbBridge.note("LSWS：拿不到 defaultWorkspace"); return
        }
        for name in ["openApplicationWithBundleID:", "openApplicationWithBundleIdentifier:"] {
            let sel = NSSelectorFromString(name)
            guard ws.responds(to: sel), let m = class_getInstanceMethod(type(of: ws), sel) else {
                KbBridge.note("LSWS：不响应 " + name); continue
            }
            typealias Fn = @convention(c) (AnyObject, Selector, NSString) -> Bool
            let f = unsafeBitCast(method_getImplementation(m), to: Fn.self)
            let ok = f(ws, sel, "com.kevin.tprobe" as NSString)
            KbBridge.note("LSWS：" + name + " com.kevin.tprobe → " + String(ok))
            if ok { return }
        }
    }

    /// 通用链接也可能走 AppDelegate 这条（不走 Scene）—— 两边都接，打出来源
    func application(_ application: UIApplication, continue userActivity: NSUserActivity,
                     restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        let url = userActivity.webpageURL?.absoluteString ?? "无"
        let ref = userActivity.referrerURL?.absoluteString ?? "无"
        let src = "无"   // 🚨 同 Scene：这个 KVC key 不存在会崩
        KbBridge.note("AppDelegate 通用链接：" + url + "｜referrer=" + ref + "｜source=" + src + "｜type=" + userActivity.activityType)
        if src != "无" && !src.isEmpty { KbBridge.rememberSource(src); KbBridge.rememberHost(src) }
        if userActivity.webpageURL?.path.hasPrefix("/kb/arm") == true { handleArmURL() }
        return true
    }

    /// **读「◀ 打开者」**：主 App 被别的 App 打开时，状态栏左上角显示 opener 名字。
    /// 扒 UIApplication/场景/状态栏里跟 opener/previous/return/back 相关的接口，并试读值。
    func readOpenerProbe() {
        let keys = ["opener", "openedby", "previous", "return", "leftbar", "backbutton",
                    "sourceapp", "sourcebundle", "referring", "launchsource", "invocation"]
        for cn in ["UIApplication", "UIStatusBarManager", "UIWindowScene", "UIScene",
                   "UISceneSession", "_UISceneLifecycleMultiplexer", "FBSSceneImpl",
                   "UIStatusBar", "_UIStatusBarForegroundView", "UISystemNavigationAction"] {
            guard let c: AnyClass = NSClassFromString(cn) else { continue }
            var hits: [String] = []
            for meta in [false, true] {
                let k: AnyClass = meta ? (object_getClass(c) ?? c) : c
                var n: UInt32 = 0
                guard let ms = class_copyMethodList(k, &n) else { continue }
                for i in 0..<Int(n) {
                    let nm = NSStringFromSelector(method_getName(ms[i])); let l = nm.lowercased()
                    if keys.contains(where: { l.contains($0) }) { hits.append((meta ? "+" : "-") + nm) }
                }
                free(ms)
            }
            if !hits.isEmpty { KbBridge.note("OP " + cn + " ▸ " + hits.prefix(16).joined(separator: " ｜ ")) }
        }
        // 试读：UIApplication 上无参、返回对象/字符串的 opener 类方法
        let app = UIApplication.shared
        for name in ["_systemNavigationAction", "systemNavigationAction",
                     "_returnToApplicationSourceBundleID", "returnToApplicationSourceBundleID",
                     "_previousApplicationBundleID", "previousApplicationBundleID",
                     "_openerBundleID", "openerBundleID"] {
            let sel = NSSelectorFromString(name)
            guard app.responds(to: sel) else { continue }
            let v = app.perform(sel)?.takeUnretainedValue()
            KbBridge.note("OP UIApplication." + name + " = " + String(describing: v).prefix(160).description)
        }
        // 场景里的 systemNavigationAction（返回条就是它）
        for scene in UIApplication.shared.connectedScenes {
            for name in ["systemNavigationAction", "_systemNavigationAction"] {
                let sel = NSSelectorFromString(name)
                guard (scene as AnyObject).responds(to: sel) else { continue }
                if let act = (scene as AnyObject).perform(sel)?.takeUnretainedValue() {
                    // UISystemNavigationAction 有 title / responder 等
                    let title = (act.value(forKey: "localizedTitle") as? String) ?? (act.value(forKey: "title") as? String) ?? "?"
                    KbBridge.note("OP 场景.systemNavigationAction 存在！标题=" + title + "｜类=" + String(describing: type(of: act)))
                    // 扒它的字段找 bundle id
                    var names: [String] = []; var n2: UInt32 = 0
                    if let ms = class_copyMethodList(type(of: act), &n2) {
                        for i in 0..<Int(n2) { names.append(NSStringFromSelector(method_getName(ms[i]))) }
                        free(ms)
                    }
                    KbBridge.note("OP systemNavigationAction 字段：" + names.prefix(20).joined(separator: " ｜ "))
                } else {
                    KbBridge.note("OP 场景." + name + " = nil")
                }
            }
        }
        KbBridge.note("OP：完")
    }

    func dumpHostIdentityClasses() {
        for cn in ["NSExtensionContext", "UIInputViewController",
                   "_UIViewServiceViewControllerOperator", "NSExtension"] {
            guard let c: AnyClass = NSClassFromString(cn) else {
                KbBridge.note("类级扒表：" + cn + " —— 这个类不存在")
                continue
            }
            var hits: [String] = []
            var cls: AnyClass? = c
            var d = 0
            while let k = cls, d < 4 {
                d += 1
                var n: UInt32 = 0
                if let ivars = class_copyIvarList(k, &n) {
                    for i in 0..<Int(n) {
                        if let np = ivar_getName(ivars[i]) {
                            let nm = String(cString: np).lowercased()
                            if nm.contains("host") || nm.contains("bundle") || nm.contains("pid") {
                                hits.append("ivar " + String(cString: np))
                            }
                        }
                    }
                    free(ivars)
                }
                var mn: UInt32 = 0
                if let ms = class_copyMethodList(k, &mn) {
                    for i in 0..<Int(mn) {
                        let nm = NSStringFromSelector(method_getName(ms[i]))
                        let low = nm.lowercased()
                        if low.contains("host") || low.contains("bundleid") || low.contains("pid") {
                            hits.append("方法 " + nm)
                        }
                    }
                    free(ms)
                }
                cls = class_getSuperclass(k)
            }
            if hits.isEmpty {
                KbBridge.note("类级扒表：" + cn + " → 没有 host/bundle/pid 字段")
            } else {
                for h in hits.prefix(10) { KbBridge.note("类级扒表：" + cn + " ▸ " + h) }
            }
        }
    }

    func handleArmURL() {
        // 决定性实验（2026-09-02）：多时刻采样 systemNavigationAction（那个「返回条」）。
        for tt in [0.1, 0.5, 1.0, 1.8, 2.6, 3.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + tt) {
                KbBridge.note("OP[采样 t=" + String(tt) + "]")
                self.readOpenerProbe()
            }
        }
        // （probehost 分支在 scene 的 URL 处理里）
        KbBridge.note("收到 arm：只架引擎，架好就退出去")
        // 🚨🚨🚨 **`arm` 是他明确要架，不能被「自动待机的默认值」挡住**（2026-09-02 00:0x）。
        //    `armForBackground()` 第一行是 `guard standby, …` ——
        //    而我今天下午按他要求把 `standby` 改成了**默认关**，
        //    于是键盘跳过来喊 `arm` 时**这个函数直接返回、什么都不做**，
        //    痕迹里就是 `arm：🚨 没架上`（实测 23:59 / 00:00 两次）。
        //    **是那个改动把 `arm` 这条路整个废掉的，不是引擎架不起来。**
        //    （对照：冷启动走的是另一条梯子，23:35 / 23:40 两次都 `成了 ✅`。）
        //    → 「自动待机默认关」管的是**没人要求时别自己开**；
        //      他按了麦克风＝**明确要求**，这时必须架。
        if !KbVoiceHost.shared.standby {
            KbBridge.note("arm：待机是关的，但这是他明确要求 → 本次打开")
            KbVoiceHost.shared.setStandby(true)
        }
        // 2026-09-02 ①：不在前台就等到前台再架（最多 4 秒），别像 21:30 那样直接放弃。
        //            ②：架完轮询 hostArmed（最多 4 秒），真架好才退场；架不好把标记置假再退，
        //               键盘不会拿假标记进录音态。灵动岛仍趁这个前台瞬间建（后台建不了）。
        let t0 = Date()
        func afterArmed() {
            KbBridge.note("arm：趁前台建灵动岛（后台建不了，这是唯一窗口）")
            KbVoiceHost.shared.startLiveActivity()
            KbBridge.note("arm：架好了 ✅（" + String(format: "%.1f", Date().timeIntervalSince(t0)) + " 秒）")
            AppDelegate.showReadyOverlay()
            KbVoiceHost.shared.returnToPreviousApp("arm 架好")
        }
        func pollArmed(_ n: Int) {
            if KbBridge.hostArmed() { afterArmed(); return }
            // 2026-09-02 22:15 实测：跳转路径会顺手把键盘留的「起录条子」取走、**当场开录**——
            //    这时 busySeq != -1，armForBackground 按设计不架（正在录），hostArmed 戳自然不出现，
            //    上一版把它读成「没架上」还 markArmed(false) ——录着的时候告诉键盘失败了。**录着 = 活着**。
            if KbVoiceHost.shared.isRecording {
                KbBridge.note("arm：跳转路径已经在录（" + String(format: "%.1f", Date().timeIntervalSince(t0)) + " 秒）→ 当架好处理，退场")
                KbVoiceHost.shared.returnToPreviousApp("arm 已在录")
                return
            }
            if n >= 20 {
                KbBridge.markArmed(false)
                KbBridge.note("arm：🚨 等了 4 秒既没架上也没在录 → 标记置假后送他回去（键盘照实显示失败，不假装在录）")
                KbVoiceHost.shared.returnToPreviousApp("arm 没架上")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { pollArmed(n + 1) }
        }
        func armWhenActive(_ n: Int) {
            if UIApplication.shared.applicationState == .active {
                if n > 0 { KbBridge.note("arm：等到前台了（" + String(format: "%.1f", Date().timeIntervalSince(t0)) + " 秒），现在架") }
                KbVoiceHost.shared.armForBackground()
                pollArmed(0)
                return
            }
            if n >= 20 {
                KbBridge.markArmed(false)
                KbBridge.note("arm：🚨 4 秒没等到前台（" + AppDelegate.appStateLine() + "）→ 标记置假后送他回去")
                KbVoiceHost.shared.returnToPreviousApp("arm 没等到前台")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { armWhenActive(n + 1) }
        }
        armWhenActive(0)
    }

    /// 被 `transless://rec` 拉起来时该做的事。**三件，缺一都会白测。**
    ///
    /// 🚨 ① **只许跑一次。** 冷启动会**同时**走 `didFinishLaunching` 的 launchOptions
    ///    和 `application(_:open:)` —— 实测两条都触发了，第二次撞见
    ///    `voice.running` 就写下 `SKIP 正在录音中，没跑自检`，
    ///    把第一次的真结果盖掉。**「两个入口同一件事」＝ 同一规矩两个出口。**
    ///
    /// 🚨 ② **等到真正 `前台active` 再起录。** 实测原文：
    ///    `收到起录URL｜此刻 inactive(正在切换)` —— URL 到达时切换动画还没走完。
    ///    我们唯一能录的条件是**前台 active**，在 `inactive` 里 `setActive` +
    ///    `engine.start()` 跟"后台起录"是同一类拒绝。
    ///    **不是能力问题，是时机问题。**
    ///
    /// 🚨 ③ **待机自己打开，绝不让他去点。** Kevin 原话：「键盘语音那里显示没有开启，
    ///    需要我手动点开启」—— **那正是他骂过的那类开关。**
    ///    他被键盘送到这儿，意图已经明确到不能再明确，**没有任何理由再问他一次**。
    /// 已经有一条「等前台 → 起录」的链在跑。
    ///
    /// 🚨 **审查 H2：去重判据从时间改成状态。**
    ///    原来用 2 秒时间窗，而 `startWhenTrulyActive` 最长活 6 秒 ——
    ///    两个窗口不等长，中间留了 4 秒的洞：用户在第 2.5 秒觉得"没反应"
    ///    再按一次，两条链都会在 `.active` 那一刻各起一次录音，
    ///    第二次撞上 `voice.running` 写下 `SKIP`，**把第一次的真结果盖掉**。
    ///    **「毫秒级重复」和「用户又按了一次」用"有没有一条链在跑"来分，才可靠。**
    private var awaitingActive = false

    /// 这一跳**是不是我打开的**待机。审查 H4：放弃起录要把副作用撤回去，
    /// 但**用户自己开的不能被我关掉**，所以要记住是谁开的。
    private var standbyOpenedByJump = false

    /// 取消掉旧的那一条之后，接着走这一次的起录。
    /// 🚨 抽出来是为了**不复制那一大段** —— 复制一份就是第二个出口。
    private func handleRecURLAfterCancel() {
        KbBridge.note("收到起录URL｜此刻 " + Self.appStateLine())
        awaitingActive = true
        startWhenTrulyActive()
    }

    /// 给 `SceneDelegate` 用的入口（Scene 架构下 URL 只走那边）。
    func handleRecURLPublic() { handleRecURL() }

    private func handleRecURL() {
        // 🚨🚨 **他 2026-08-29 10:17 现场撞的就是这里。**
        //    真机面包屑连着两条「已有一条在跑（正在录=true），忽略」——
        //    他按了两次键盘，两次都被**静默丢弃**。
        //
        //    这个「忽略」防的是**同一次意图被投递两遍**（`launchOptions` + `open:`，
        //    毫秒级），那个场景里它是对的。但 `isRecording` 为真**还有第二种来源**：
        //    上一次录音没正常收尾（前台没等到、被挂起、上限定时器没跑到）。
        //    这时按键盘是**明确的「现在开始录」意图**，静默丢弃是最糟的回应。
        //
        //    「毫秒级重投」和「他又按了一次」必须分开 —— 这句话就写在
        //    `awaitingActive` 上面的注释里，而我**只把它落实在了 `awaitingActive` 上**。
        //    又一次「同一条规矩两个出口只落实一个」。
        if awaitingActive {
            KbBridge.note("起录URL：已有一条链在等前台，忽略（同一次意图的重复投递）")
            return
        }
        if KbVoiceHost.shared.isRecording {
            // 🚨🚨 中-1：**「不知道」不许折成「刚起录」**。
            //    `?? 0` 会让 `el < 3` 成立 → 走静默丢弃那一档，
            //    **正是他 10:17 撞的那条，从另一扇门回来。**
            //    方向依据：按键盘是**明确的「现在开始录」意图** ——
            //    宁可多重来一次，不可静默丢弃。
            guard let el = KbVoiceHost.shared.recElapsed else {
                // 🚨🚨 **先分清「没有上一条」和「有上一条但不知道起点」**
                //    （2026-09-02 07:07 他的真机痕迹）。
                //    冷启动时**压根没有上一条录音**，`recElapsed` 为 nil 只是因为
                //    什么都还没录过 —— 却被当成"他又按了一次"，先把自己作废，
                //    紧接着真正那次起录又被判成"已经在录"忽略掉。两步一夹 =
                //    **他切回微信后根本没开始录**。
                //    判据同样是 `busySeq != -1`：没有在录的活儿就没什么可作废的。
                guard KbVoiceHost.shared.isRecording else {
                    KbBridge.note("起录URL：本来就没有在录的活儿（冷启动）→ 直接起录，不作废")
                    return handleRecURLAfterCancel()
                }
                // 2026-09-02 Kevin「点两次」根因之一：这里正是**刚开闸、起点还没记上**的那一瞬
                //    （826/918 处自己写着「正在录=true 而 recStartedAt=nil 可达」），
                //    却被当成「他又按了一次」→ cancelCurrent → 第一下 0.1 秒就被作废、0 字节、
                //    报"没听清"、他只好再点。起点都没记上 = 必然不到 3 秒 = 同一次意图，
                //    跟下面 `el < 3` 那档一样：忽略这条重复投递，**不作废**。
                //    （真正的重按一定有 ≥3 秒的起点可读，走下面那档，判据没放宽。）
                KbBridge.note("起录URL：有一条刚开闸、起点还没记上"
                              + " → 判为同一次意图的重复投递，忽略，不作废")
                return
            }
            if el < 3 {
                KbBridge.note("起录URL：刚起录 "
                              + String(format: "%.1f", el)
                              + " 秒，判为同一次意图的重复投递，忽略")
                return
            }
            // ≥ 3 秒 = 他又按了一次 → **停掉旧的、从头起一次**
            KbBridge.note("起录URL：上一条已经跑了 "
                          + String(format: "%.1f", el)
                          + " 秒，判为他又按了一次 → 停掉旧的重来")
            RecLog.add(sec: 0, bytes: 0, result: "重按重来",
                       detail: "上一条已跑 " + String(format: "%.1f", el) + " 秒")
            KbVoiceHost.shared.cancelCurrent()
        }
        KbBridge.note("收到起录URL｜此刻 " + Self.appStateLine())
        // 🚨🚨 **「录音诊断」以前是个空壳**：`RecLog.add` 全工程 **0 个调用点**，
        //    `dump` 只有 1 个（就是那个设置页）。→ 不管录没录，
        //    那个框**永远**显示「还没有记录」。**它是恒真的，不能当证据。**
        //    （0 总协调据它判「压根没起录」，差点让我们去修一个不存在的问题。）
        //
        //    现在把它做成真的：**起录链第一行就写一条**，
        //    这样他一点就能分清 **没收到 URL** / **收到了没起录** / **起录了但失败**。
        //    🚨 录音发生在**主 App 进程**、诊断也读**主 App 进程** —— **同进程**，
        //    所以 RecLog 那条「不跨进程」的限制在这条路上不成立。
        RecLog.add(sec: 0, bytes: 0, result: "收到起录URL",
                   detail: "此刻 " + Self.appStateLine())
        awaitingActive = true
        startWhenTrulyActive()
        // ⑤ 会不会自己跳回去：**如实记，不预设。**
        for t in [1.0, 3.0, 6.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                KbBridge.note(String(format: "起录URL后 %.0f 秒｜", t) + Self.appStateLine())
            }
        }
    }

    /// 待机策略的**唯一出口**。
    ///
    /// 🚨 **审查 H3：原来这件事有两个配置点，后写的悄悄赢。**
    ///    `handleRecURL` 里决定一次，`didFinishLaunching` 里那条
    ///    `TRANSLESS_STANDBY`/`flag("standby")` 又在 0.5 秒后无条件打开 ——
    ///    于是「录完放手档」在真机上跟不开它**行为完全一样**，
    ///    而日志还老老实实打印着"不开待机保活"。
    ///    **据那种日志下的任何结论都是错的。**
    ///
    /// 🚨 另一半：原来写的是 `else if !standby { setStandby(true) }` ——
    ///    开关为真时**什么都不做**，连"已经开着的"都不关。
    ///    → 现在**显式关**，并且把**执行后读回的真实值**记进面包屑：
    ///    **判据挂在读回的状态上，不是挂在"我走了哪个分支"上。**
    private func applyStandbyPolicy() {
        if Self.coldReturn {
            if KbVoiceHost.shared.standby { KbVoiceHost.shared.setStandby(false) }
            standbyOpenedByJump = false
            KbBridge.note("待机策略：录完放手档，已关闭｜读回="
                          + String(KbVoiceHost.shared.standby))
            return
        }
        if !KbVoiceHost.shared.standby {
            KbVoiceHost.shared.setStandby(true)
            standbyOpenedByJump = true
        }
        KbBridge.note("待机策略：保活档｜读回=" + String(KbVoiceHost.shared.standby))
    }

    /// 等到**真的 `前台active`** 那一刻才起录。
    ///
    /// 🚨 **挂事件，不挂时长。** 0 总协调点的这条是对的：
    ///    轮询"每 0.2 秒看一眼、最多 30 次"本质还是在赌一个时长；
    ///    正确的做法是**订 `didBecomeActiveNotification`，它到了就走**。
    ///    轮询只留作**兜底**（万一通知因为场景生命周期没来），
    ///    而且兜底那条要**明说自己是兜底**，别混进正常路径里。
    ///
    /// 🚨 **两个入口共用这一个闸**：热启动 `application(_:open:)` 和
    ///    冷启动 launchOptions 都只调 `handleRecURL()` → 都走到这里。
    ///    **同一规则两处实现、改一处漏一处**，今晚已经栽过。
    private func startWhenTrulyActive() {
        let t0 = Date()
        if UIApplication.shared.applicationState == .active {
            fire(t0, how: "本来就在前台")
            return
        }
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
            if let token = token { NotificationCenter.default.removeObserver(token) }
            guard let self = self, self.awaitingActive else { return }
            self.fire(t0, how: "等到了 didBecomeActive")
        }
        // 兜底：通知没来也不能永远挂着。**它是兜底，日志里要看得出来。**
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self = self, self.awaitingActive else { return }
            if let token = token { NotificationCenter.default.removeObserver(token) }
            self.awaitingActive = false
            if self.standbyOpenedByJump {
                KbVoiceHost.shared.setStandby(false)
                self.standbyOpenedByJump = false
                KbBridge.note("放弃起录：把本次打开的待机关回去｜读回="
                              + String(KbVoiceHost.shared.standby))
            }
            KbBridge.note("起录闸：6 秒没等到前台（此刻 " + Self.appStateLine() + "），放弃")
            RecLog.add(sec: 0, bytes: 0, result: "起录闸放弃",
                       detail: "6 秒没等到前台，此刻 " + Self.appStateLine())
        }
    }

    /// 真正起录。**耗时和"怎么等到的"都记下来** ——
    /// 这样下次一眼能分清是「等到了」还是「超时硬上」。
    private func fire(_ t0: Date, how: String) {
        awaitingActive = false
        let ms = Int(Date().timeIntervalSince(t0) * 1000)
        applyStandbyPolicy()
        KbBridge.note("起录闸：" + how + "，耗时 " + String(ms) + " ms｜此刻 "
                      + Self.appStateLine())
        RecLog.add(sec: 0, bytes: 0, result: "起录闸通过",
                   detail: how + "，耗时 " + String(ms) + " ms，"
                       + Self.appStateLine())
        // 🚨 **回读条数**，别停在"我调了 add"。
        //    「录音诊断」在他手里必须真的有东西，
        //    而这条数字是我这边唯一能远程看到的凭据。
        KbBridge.note("录音诊断条数=" + String(RecLog.items().count))
        // 🚨🚨 **产品路径走真管线**（录 → 转写 → 润色 → 把稿子留给键盘）。
        //    以前这里默认跑 `runSelfTest()` —— **那是诊断件，根本不出稿**，
        //    所以他按完永远等不到字。自检/长录只在**我显式给环境变量**时才跑。
        // 🚨 只在我显式给环境变量时跑：验「App 能不能自己退回去」。
        //    这是**诊断，不是产品行为** —— 自动切回的方案还没给他看过。
        if ProcessInfo.processInfo.environment["TRANSLESS_SUSPEND"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let sel = NSSelectorFromString("suspend")
                let app = UIApplication.shared
                KbBridge.note("退回实验：响应 suspend = " + String(app.responds(to: sel)))
                if app.responds(to: sel) { app.perform(sel) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    KbBridge.note("退回实验：2 秒后 App 状态 = "
                                  + String(describing: app.applicationState.rawValue)
                                  + "（0=前台 1=将失活 2=后台）")
                }
            }
        }
        // 🚨🚨 **主线程卡死侦测。**
        //    Kevin 2026-08-29 两次撞到「打开 Transless 就卡住」，而我
        //    **至今没定位到卡在哪一行** —— 因为主线程一卡，什么日志都写不出来。
        //    做法：后台线程每 2 秒往主队列丢一个"回声"，5 秒没回来就
        //    **由后台线程**写一条痕迹（后台写不受主线程影响）。
        //    这样卡住的**时刻**和**卡住前最后一条痕迹**就都有了，能定位到那一段。
        // 🚨 覆盖：能抓到"主线程被同步阻塞"。**不覆盖** App 整个被系统挂起
        //    （那种情况后台线程也不跑）—— 两者靠"卡住后还有没有别的痕迹"区分。
        KbVoiceHost.shared.armDebugStop()
        // 调试：远程叫出/收回小窗，用来验「后台能不能临时进画中画」。
        if #available(iOS 15.0, *) {
            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDarwinNotifyCenter(), nil,
                { _, _, _, _, _ in
                    DispatchQueue.main.async { PipVCKeepAlive.shared.showNow() }
                },
                "com.kevin.transless.debug.pipshow" as CFString, nil, .deliverImmediately)
        }
        switch ProcessInfo.processInfo.environment["TRANSLESS_RECURL"] {
        case "long": KbVoiceHost.shared.runLongRec()
        case "1": KbVoiceHost.shared.runSelfTest()
        default: KbVoiceHost.shared.beginJump()
        }
    }

    /// 「录完放手」开关。环境变量给我自己测，`flags.txt` 给真机验。
    /// 自测开关：这一次不取条子（只写不取），好让下一次冷启动去取。
    private static var noTake: Bool {
        ProcessInfo.processInfo.environment["TRANSLESS_NOTAKE"] == "1"
    }

    private static var coldReturn: Bool {
        ProcessInfo.processInfo.environment["TRANSLESS_COLDRETURN"] == "1"
            || KbBridge.flag("coldreturn")
    }

    /// 🚨 **区分「正常终止」和「突然没了」的唯一判据。**
    ///
    /// Kevin 报的「我再回去微信，这会儿就闪退了，整个主程序都闪退了」——
    /// 崩溃日志、JetsamEvent **今晚全是空的**（都做过正对照，不是尺子瞎了），
    /// 而实测顶到后台 50 秒进程还活着（同一个 pid）。
    /// **三种可能里我现在一条都证不了，是因为缺一个"上次是怎么结束的"的记号。**
    ///
    /// iOS 正常回收前会调 `applicationWillTerminate`；
    /// **崩溃和被 jetsam 杀掉都不会调。**
    /// → 下次他再看到"闪退"，面包屑里**有没有这一行**就直接分开了两类原因，
    ///    **不用他描述、也不用再等一次复现。**
    func applicationWillTerminate(_ a: UIApplication) {
        KbBridge.note("主App正常终止（willTerminate）｜此刻 " + Self.appStateLine())
    }

    private static func appStateLine() -> String {
        switch UIApplication.shared.applicationState {
        case .active: return "前台active"
        case .inactive: return "inactive(正在切换)"
        case .background: return "后台"
        @unknown default: return "未知"
        }
    }

    func application(_ app: UIApplication,
                     didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 🚨🚨 **必须挂在启动上，不能挂在 `applyDebugEnv`**（2026-09-05 栽过）。
        //    `applyDebugEnv` 是随手翻译那屏 `viewDidAppear` 里调的 ——
        //    语言用例根本不进那一屏，于是重置**从没执行**：
        //    上一轮跑完停在英文，下一轮的"中文基线"就不成立，
        //    报出来是「基线不是中文」，**看起来像功能坏了**。
        //    启动期的初始化要挂在启动上，不是挂在某一屏上。
        if ProcessInfo.processInfo.environment["TRANSLESS_UILANG_RESET"] == "1" {
            Lang.set(Lang.sys)
        }
        // 🚨🚨 **单词本也要能清回确定起点**（2026-09-05 栽了一次）。
        //    上一轮用例把那条加进单词本**并留在那里**，下一轮跑起来
        //    按钮初始就是「已加入」→ 第一次点变成**移除** →
        //    标签回到「＋ 单词本」→ 断言失败，**看起来像功能坏了**。
        //    实际功能好好的，是**用例没有确定的起点**。
        //    跟界面语言那条同一个形态：**测试之间共享了持久化状态。**
        if ProcessInfo.processInfo.environment["TRANSLESS_CLEAR_WB"] == "1" {
            WordBook.save([])
        }
        KbBridge.note("启动选项键：" + ((o ?? [:]).keys.map { $0.rawValue }.joined(separator: ",")))
        // 🚨 把「此刻在前台还是后台」注给 `Voice` 的录音心跳。
        //    扩展里没有 `UIApplication`，所以这条只能由主 App 给；
        //    没给时心跳打「?」而不是猜一个值。
        //
        //    这是 Kevin 2026-09-04「录音中切走要能继续」那条需求的**量具**：
        //    没有它，日志里「后台第 20 秒还在收帧」这句话根本写不出来，
        //    「断了」和「录了但没上传」就分不开。
        // 🚨 清历史的调试开关放在**启动最开头** —— 我先前把它塞进 Scene 那个
        //    种子块旁边，而 `TRANSLESS_PAGE=speak` 走的是另一条路，**根本没跑到**。
        //    表现是反向控制一直红，而我连着两轮都以为是产品的毛病。
        //    **开关要放在所有路径的必经之处**，不是放在"看起来相关"的那段旁边。
        if ProcessInfo.processInfo.environment["TRANSLESS_CLEAR_HIST"] == "1" {
            History.clear()
        }
        // 🚨 种子也放这儿 —— 跟清空同一个理由：`TRANSLESS_PAGE=speak` 走的是
        //    另一条路，原来那两处（Scene 里）**根本跑不到**，
        //    于是"截图里有历史"全靠模拟器上攒下来的真数据，换台机器就没了。
        // 🚨 **原来那段种子在文件里有两份拷贝**（Scene 的两个分支各一份）——
        //    同一批样本抄两遍，改一处等于没改。现在只有这一份。
        if ProcessInfo.processInfo.environment["TRANSLESS_SEED_HIST"] == "1",
           History.list().isEmpty {
            History.add(mode: "en", tone: "", zh: "我想订一张明天去香港的高铁票",
                        out: "I'd like to book a high-speed rail ticket to Hong Kong for tomorrow.",
                        durMs: 40_000, lang: "en")
            History.add(mode: "zh", tone: "", zh: "这个功能挺好用的，就是有点小问题",
                        out: "这个功能挺好用的，就是有点小问题。", durMs: 12_000)
            History.add(mode: "en", tone: "", zh: "帮我把这段话说得客气一点，我要发给客户",
                        out: "Could you help me phrase this more politely? I need to send it to a client.",
                        durMs: 18_000, lang: "en")
            // 🚨 **种 5 条，不是 3 条** —— 「最近只出 1 条」这条判据，
            //    数据只有 3 条时**看不出**是"截到 1"还是"本来就少"。
            //    坏样本要能让错误实现露馅：`min(1,size)` 写成 `size` 时，
            //    3 条会出 3 行、5 条会出 5 行，而正确实现永远 1 行。
            History.add(mode: "en", tone: "", zh: "下周一开会把时间线再确认一下",
                        out: "Let's confirm the timeline at Monday's meeting.",
                        durMs: 15_000, lang: "en")
            History.add(mode: "raw", tone: "", zh: "这段先照原样记下来别改",
                        out: "这段先照原样记下来别改。", durMs: 9_000)
        }
        Voice.appStateProbe = {
            switch UIApplication.shared.applicationState {
            case .active:     return "前台"
            case .inactive:   return "转场中"
            case .background: return "后台"
            @unknown default: return "未知"
            }
        }
        // 🚨 跟键盘那边**同一句**：把本进程老位置的历史搬进 App Group。
        //    两个进程各有各的老位置，谁也搬不动谁的，所以**两边都要调**。
        //    只在一边落地的话，另一边那些旧记录就永远看不见了。
        History.migrateFromOldContainer()
        // 🚨 常用词：**App 启动拉一次**（SYNC-6 的三个时机之一）。
        //    异步、静默、拉不到就当没这回事 —— 绝不因为它拖慢启动。
        // 🚨 **只有 `PULL_OK` 才覆盖本地**，读不到/未登录一律保留本地那份
        //    （判据在 `VocabCore.canOverwriteLocal`，不在这里）。
        // 🚨 另外两个时机：登录成功（`Auth` 里 merge）、本地变更（常用词屏里 replace）。
        //    **按麦克风之前绝对不拉** —— 不让他为一句话多等一个网络往返。
        VocabSync.pullAsync()
        // 🚨🚨 **老式启动选项里的来源** —— 跟 Scene 那条是**两个不同的通道**。
        //    Scene 的 `sourceApplication` 我验过恒为空（键盘发起时），
        //    但 `LaunchOptionsKey.sourceApplication` **从来没验过**，而且它是**公开的**。
        //    （Wispr Flow 官方文档说 iOS 26.4 自动回程已失效、苹果论坛 DTS 答 "No" ——
        //     但 Typeless 据报仍能做到，所以公开通道里一定还有我没试过的。）
        if let o = o {
            var got: [String] = []
            for (k, v) in o {
                let ks = String(describing: k)
                if ks.lowercased().contains("source") || ks.lowercased().contains("url")
                    || ks.lowercased().contains("annotation") {
                    got.append(ks + "=" + String(String(describing: v).prefix(90)))
                }
            }
            KbBridge.note("启动选项里的来源线索（" + String(o.count) + " 个键）："
                          + (got.isEmpty ? "一条都没有" : got.joined(separator: " ｜ ")))
            if let src = o[.sourceApplication] as? String, !src.isEmpty {
                KbBridge.rememberSource(src)
                KbBridge.note("🎉 启动选项 sourceApplication = " + src + "（回程能用了）")
            }
        } else {
            KbBridge.note("启动选项：nil（不是被 URL 拉起的）")
        }
        if AppDelegate.armFromLaunchArgs() {
            // 🚨 `armwant` = 复现**生产顺序**：键盘在跳走**之前**就写下了"他想录"，
            //    所以等主 App 把他送回微信、键盘重新出现时，标记已经在那儿了。
            //    我第一版测试是在返回**之后**才写标记，键盘早出现了 1 秒 ——
            //    **顺序错了，不是代码错了**（判据挂在一个还没发生的事上）。
            if CommandLine.arguments.contains("armwant") { KbBridge.markWantRec() }
            KbBridge.note("启动参数里有 arm → 走恢复链（只负责架好，回程 iOS 不给 API）")
            // 🚨🚨 **0.8 秒砍掉（2026-09-01）。** Kevin：「还是跳不回原 APP」，
            //    而日志显示到"要退出"那一步时**已经在前台站了 2.15 秒** ——
            //    开屏已经跳过了，那 2.15 秒 = **这里写死的 0.8 秒** + 架引擎约 1 秒。
            //    他要的是「闪一下」，这 0.8 秒纯粹是白等。
            //    🚨 原来加它是怕"太早架引擎会失败"，但那是**开屏还在时**的顾虑；
            //       现在开屏跳过了，`didBecomeActive` 已经到了，可以立刻架。
            DispatchQueue.main.async { self.handleArmURL() }
        }
        // 🚨 导航栏样式要在**任何页面建出来之前**设，而且只设这一次。
        //    上一版我加在首页那条分支里，深链（TRANSLESS_PAGE）走的是另一条 —— 
        //    截图上「设为当前输入法」还是黑字。**一处配置要盖住所有入口**。
        // 🚨🚨 **冷启动这一路 iOS 到底给了我们什么，先原样打出来再说。**
        //    Kevin 2026-08-29：「就剩这一件 —— 主 App 不会自己切回微信。」
        //    根因是每次按都是**冷启动**（App 已被系统回收），
        //    而 `application(_:open:)` 只在 App 还活着时才走，
        //    所以 `sourceApplication` 一直是空的 → 不知道该开回哪儿 → 只能按 Home → 落桌面。
        //    **先看 `launchOptions` 里有没有来源**，有就直接用，没有就换别的办法。
        //    🚨 不许凭记忆断言「冷启动一定拿不到」—— 那正是今天栽过的那类。
        // 🚨 **每次都明确记一行「这次是冷启动」** —— 有没有这一行，
        //    就能分开「冷启动」和「叫醒」，不用靠推。
        //    他那条路到底是哪一种，决定了来源能不能拿到。
        KbBridge.note("=== 本次是【冷启动】（进程刚起）===")
        if let o = o {
            let keys = o.keys.map { $0.rawValue }.sorted().joined(separator: ",")
            KbBridge.note("冷启动参数：" + (keys.isEmpty ? "空" : keys))
            if let src = o[.sourceApplication] as? String, !src.isEmpty {
                KbBridge.rememberSource(src)
                KbBridge.note("冷启动拿到来源 App：" + src)
            }
            if let u = o[.url] as? URL {
                KbBridge.note("冷启动带了URL：" + u.absoluteString)
            }
        } else {
            KbBridge.note("冷启动参数：nil（不是被 URL 拉起来的）")
        }
        // 🚨 自测口子：**让 App 开自己一次**，用来验证「叫醒」这条路
        //    iOS 到底给不给 `sourceApplication`。
        //    他按微信里的键盘我复现不了（没有别的 App 能替我发这个 URL），
        //    但**这条路走的是同一个回调**，来源换成我们自己而已 ——
        //    只要痕迹里出现「来自 com.kevin.transless」，
        //    就说明**叫醒这条路是给来源的**，微信那次自然也给。
        // 🚨 这只证明「机制给不给来源」，**不证明「开回微信一定成功」** ——
        //    后者要他按一次。范围写清楚，别当成全都验过了。
        // 调试口子：预设「来源 App」，用来单独验证**开回去这个动作本身**成不成。
        // 🚨 只影响我自测；他正常用时这个环境变量不存在。
        if let src = ProcessInfo.processInfo.environment["TRANSLESS_FAKESRC"], !src.isEmpty {
            KbBridge.rememberSource(src)
            KbBridge.note("自测：把来源预设成 " + src)
        }
        // 🚨🚨 **「麦克风一直热着」探针**（`TRANSLESS_HOTMIC=1`）。
        //    Typeless V1.9 的发布说明写着「**仅在您说话时开启麦克风，从而节省电量**」
        //    —— 反过来读：**它更早的版本是让麦克风一直开着的**。
        //    如果引擎能在后台**持续**出帧，那按键盘时根本不用起录、也就不用跳过去，
        //    整个"切走再切回"的问题就消失了。
        //    判据：**后台每 30 秒都要有新帧**，光"起录成功"不算。
        if ProcessInfo.processInfo.environment["TRANSLESS_HOTMIC"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                KbVoiceHost.shared.startHotMicProbe()
            }
        }
        if ProcessInfo.processInfo.environment["TRANSLESS_SELFOPEN"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if let u = URL(string: "transless://rec") {
                    UIApplication.shared.open(u, options: [:]) { ok in
                        KbBridge.note("自测：开自己 " + (ok ? "成功" : "失败"))
                    }
                }
            }
        }
        // 🚨🚨 **这三个必须挂在 `didFinishLaunching`，不能挂在 `fire()` 里。**
        //    2026-08-30 查实：它们原来在 `fire(_:how:)` 里 —— 那个函数
        //    **只有触发录音时才跑**，所以「主线程守望」和「远程起岛探针」
        //    从来没被装上过，我却拿它们的沉默当成了「后台没响应」。
        //    **代码在 ≠ 它被跑过** —— 今天第五次栽在这，这次挂到真正的启动路径上。
        // 🚨 **新进程definitionally 不是待命状态** —— 把上一个进程留下的
        //    待命标记先抹掉。不抹的话：① 保活会以为会话已配好而跳过配置；
        //    ② 键盘会以为宿主架着，发命令过来却没人能录。
        // 🚨🚨 **新进程要把上一个进程留下的所有"正在进行中"标记全清掉。**
        //    2026-08-30 09:14 实测：上一轮有个录音没被停下（跑了 122 秒），
        //    进程被杀之后 `kb.rec.since` **还留在共享区**。
        //    新进程起来后键盘一露面就读到"宿主在录=true" →
        //    把他按的**第一下当成了停止** → 什么都没录到，
        //    而且 `kb.res.seq` 永远落后 `kb.cmd.seq` 好几条。
        //    🚨 我上次只清了 `kb.armed.at`，**这个漏了** ——
        //       同一条规矩只落在一个出口上，今天第 N 次。
        //    → 凡是"进行中"的跨进程标记，**冷启动一律清零**。
        KbBridge.markArmed(false)
        KbBridge.markRecording(false)
        KbBridge.markIsland(false)
        KbBridge.markHold(false)
        MainThreadWatch.start()
        KbVoiceHost.shared.armDebugIsland()
        KbVoiceHost.shared.armDebugAltRec()
        KbVoiceHost.shared.armDebugArmRec()
        KbVoiceHost.shared.armAudioWatch()
        KbVoiceHost.shared.armDebugKnownWav()
        KbVoiceHost.shared.armDebugSpeakRec()
        KbVoiceHost.shared.armDebugSpeakOnly()
        // 🚨🚨 **把 Intent 的动作接到宿主上。**
        //    `LiveActivityIntent` 跑在**主 App 自己的进程**里，所以这里接得上。
        //    要验的就一件事：**App 在后台时，由 Intent 触发的起录成不成。**
        //    成了，「不跳出微信」就有了唯一一条活路（苹果 DTS 已明确答复
        //    「跳过去再切回来」没有公开办法，私有路子在 iOS 26.4 后也全死了）。
        // 🚨🚨 **订阅 push-to-start token（2026-08-30）。**
        //    iOS 17.2 起，Live Activity 可以**由推送在后台拉起来**（push-to-start）。
        //    这是我们唯一还能走的路：键盘按麦克风 → 后端发这条推送 →
        //    灵动岛在后台亮 → Intent 在后台起录 → **他全程不离开微信**。
        //    🚨 前提是 App 带 `aps-environment`（今天刚配好，实测已在二进制里）。
        //    🚨 token 会变，所以是个持续的流，不是取一次。
        // 🚨🚨 **启动时先看有没有【别人起的】灵动岛。**
        //    push-to-start 的岛是**系统起的**，我们的 `startLiveActivity()`
        //    根本没跑，所以 `liveActivityOn` 是 false、共享区也没标记 ——
        //    结果我自己的闲置闸把刚被推送拉起来的 App 又杀掉了（实测撞过）。
        //    → 主动查 `Activity.activities`，有就认下来。
        if #available(iOS 16.1, *) {
            let live = Activity<RecActivityAttributes>.activities
            if !live.isEmpty {
                // 2026-09-02 Kevin：「只有正在录音时才显示」。启动时发现的岛都是上一轮/推送
                //    残留（没有在录），**全部收掉**，别再留着当「恢复入口」——那套理论已被实测推翻，
                //    留着的结果就是他头顶一个「0s」常亮。
                KbBridge.note("启动时发现残留灵动岛 " + String(live.count) + " 个 → 全部收掉（平时不显示）")
                for act in live { Task { await act.end(dismissalPolicy: .immediate) } }
                KbBridge.markIsland(false)
            }
            // 岛的状态会变，持续跟着
            Task {
                for await act in Activity<RecActivityAttributes>.activityUpdates {
                    KbBridge.markIsland(true)
                    KbBridge.note("灵动岛：收到一个新活动（id " + act.id.prefix(8) + "）")
                }
            }
        }
        if #available(iOS 17.2, *) {
            Task {
                for await data in Activity<RecActivityAttributes>.pushToStartTokenUpdates {
                    let hex = data.map { String(format: "%02x", $0) }.joined()
                    KbBridge.setPushToStartToken(hex)
                    KbBridge.note("push-to-start token：拿到了 " + String(hex.count)
                                  + " 字符，前 16 位 " + String(hex.prefix(16)))
                }
            }
        } else {
            KbBridge.note("push-to-start：系统版本不够（要 iOS 17.2+）")
        }

        RecIntentBridge.shared.onStart = {
            KbVoiceHost.shared.begin(seq: -1234,
                                     args: ["tone": "", "mode": "en", "lang": "en"])
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                KbVoiceHost.shared.finish()
            }
        }
        // 🚨 **启动时把回程候选打出来** —— 这样"声明 → canOpenURL → 选中"
        //    整条猜的逻辑在真机上跑一遍，只差最后那下 `open`。
        //    没有这一行，我只能说"代码写了"，说不出"它在他机器上真的选得出来"。
        DispatchQueue.main.async {
            let all = KbVoiceHost.guessBackOrder.filter {
                URL(string: $0.scheme).map { UIApplication.shared.canOpenURL($0) } ?? false
            }
            KbBridge.note("回程候选：装着的有 " + String(all.count) + " 个 —— "
                          + all.prefix(6).map { $0.name }.joined(separator: "、")
                          + "｜要回去时会开：" + (all.first?.name ?? "（一个都没有）"))
        }
        KbVoiceHost.shared.armDebugStress()
        KbVoiceHost.shared.armDebugForceArm()
        KbVoiceHost.shared.armDebugMute()
        // 🚨🚨🚨 **冷启动进后台的那一瞬间，立刻试着架引擎（从没测过的一条）。**
        //    Typeless 的形态：三个进程从全无到全有只用了 6 秒
        //    （21:37:35 都不在 → 21:37:41 三个都在），
        //    说明**它的主 App 是被冷启动进后台的**。
        //    而我今天所有「后台架引擎」的测试，App **都是已经跑着的** ——
        //    **「进程刚被冷启动进后台」这个状态一次都没测过。**
        //    iOS 对「代表前台扩展被拉起的新进程」很可能给了不同待遇。
        // 🚨 只留痕、不改产品行为；判据是痕迹里出现「冷启架引擎：成了」。
        if UIApplication.shared.applicationState != .active {
            KbBridge.note("冷启架引擎：试一次（此刻不是前台）")
            KbVoiceHost.shared.tryArmOnColdLaunch()
        }
        // 🚨🚨 **每次回到前台都把引擎架进待命档。**
        //    这是唯一必须在前台做的动作 —— 之后按键盘就不用跳出微信了。
        //    放在 `didBecomeActive` 而不是启动那一次：App 被系统收过、
        //    或者他从别处切回来，都要重新架。**架不上会自己说，不静默。**
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { _ in
            // 🚨 延一下：待机是在启动后 0.5 秒才打开的，
            //    早于它调用会因为 `standby == false` 直接返回（而且不报错）。
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                KbVoiceHost.shared.armForBackground()
            }
        }
        NavStyle.apply()
        // 🚨🚨 **自检通道一启动就挂上**，不等待机被打开。
        //    2026-08-28 实测：我自己 `process launch` + `notification post`，
        //    **偏好里一个字都没变** —— 观察者只在 `setStandby(true)` 里注册，
        //    而待机默认关着。**我唯一能自己触发的那条通道，一直是死的。**
        //    挂上之后，装包 → 触发 → 读结果整条链不需要任何人碰手机，
        //    正是 Kevin 反复要的那件事。
        // 🚨🚨 **每次启动都记「谁启动的」。**
        //    2026-08-28：面包屑里没有这一项，于是「14:51 那次 PiP 失败」
        //    到底是我远程拉的、还是他手点的，**只能靠我记得** ——
        //    而这正是整个排除法的**唯一判据**。总协调差点据此报成
        //    「测试台干扰已排除、PiP 不通」。**又一次判据挂错对象。**
        //    判法：远程拉起时我一定会带 ，
        //    他手点时环境里没有 → manual。**肯定判据，不是靠排除。**
        let how = ProcessInfo.processInfo.environment["TRANSLESS_LAUNCH"] ?? "manual"
        // 🚨 被键盘用 transless://rec 拉起来时，**立刻在前台起录**。
        //    这是三档实测里唯一能录的位置（宿主前台 ✅ 峰值 0.405）。
        //    判据分三层，别合成一句：**到了前台 ≠ 起录成功 ≠ 录到声音**。
        let launchURL = (o?[.url] as? URL)?.absoluteString ?? "无"
        // 🚨🚨 **包戳和启动方式必须写在同一条记录里。**
        //    它们原来是两条独立面包屑，于是「戳取自最新那次启动、
        //    启动方式取自更早那次」能拼出一条**从没存在过的记录**，
        //    而两边各自看都合法 —— 判据没写错，配对的对象错了。
        //    **合成一条就无从配错**，比写个更聪明的解析器可靠。
        // 🚨🚨 **列出系统到底认得哪些「回到上一个 App」的方法。**
        //    Kevin 2026-08-29 反复强调 Typeless 能自动回微信，而我一路在猜
        //    （suspend→桌面、收场景→不支持、开回来源→拿不到来源）。
        //    **别猜了，直接问运行时**：`responds(to:)` 会告诉我们哪个真的存在。
        //    这只是**探测**，不调用任何一个。
        if ProcessInfo.processInfo.environment["TRANSLESS_PROBESEL"] == "1" {
            let names = ["suspend", "_returnToPreviousApp", "returnToPreviousApp",
                         "_suspendAndReturnToPreviousApp", "openPreviousApp",
                         "_openPreviousApplication", "_backToPreviousApp",
                         "terminateWithSuccess", "_terminateWithStatus:",
                         "_switchToPreviousApp", "returnToPreviousApplication",
                         "_performBackToPreviousApp", "backToPreviousApp"]
            let app = UIApplication.shared
            var hit: [String] = []
            for n in names where app.responds(to: NSSelectorFromString(n)) {
                hit.append(n)
            }
            KbBridge.note("回上一个App·系统认得的方法：" + (hit.isEmpty ? "一个都没有" : hit.joined(separator: " / ")))
        }
        KbBridge.note("主App启动：包戳=" + BuildStamp.value
                      + "｜启动方式=" + how + "｜url=" + launchURL)
        // 🚨 三个入口，**一个出口**：launchOptions 的 URL（热路径）、
        //    键盘留的条子（冷启动唯一可靠的那条）、远程环境变量（我自测用）。
        //    `handleRecURL()` 自己有状态去重，重复进来不会起两路。
        if launchURL.hasPrefix("transless://rec") { handleRecURL() }
        // 🚨 `TRANSLESS_NOTAKE=1` **只给我自测用**：这一次不取条子。
        //    上一轮真机自测无效就是因为**写完的条子被【同一次启动】的
        //    didBecomeActive 观察者立刻取走了** —— 于是下一次冷启动啥也没有，
        //    我却读成了"条子机制在真机上不工作"。
        //    **测试动作把被测条件消掉了**，今晚这一族的第八次。
        if Self.noTake {
            KbBridge.note("自测：本次不取条子（NOTAKE）")
        } else if KbBridge.takeRecRequest() {
            KbBridge.note("起录：来自键盘留的条子（URL 没送到也不影响）")
            handleRecURL()
        }
        // 🚨 还要在**每次回到前台**时再取一次：冷启动那一刻 App 可能还没准备好，
        //    而键盘的条子是先写的 —— 这条能兜住"启动那下没取到"的情况。
        // 🚨 **只给我自测用**，而且**必须放在取条子之后**：
        //    上一版放在前面 → 同一次启动里写完立刻被自己取走，**根本没跨过冷启动**。
        //    「测试动作把被测条件毁掉了」—— 今晚这一族的第六次。
        //    外面写不进 App Group（模拟器自带 cfprefsd，宿主机 `defaults write` App 看不见），
        //    所以只能让 App 用**键盘那个同一个函数**留条子。**两端都是产品代码。**
        if ProcessInfo.processInfo.environment["TRANSLESS_WRITEREQ"] == "1" {
            // 🚨 条子里可以带参数（`TRANSLESS_REQ_MODE` / `_TONE` / `_LANG`），
            //    这样我自己就能复现「他选了转写档」那条路 ——
            //    不带参数的话主 App 一律按默认 `en`（翻译），
            //    **那就永远测不出模式相关的毛病**。
            var a: [String: String] = [:]
            let env = ProcessInfo.processInfo.environment
            if let m = env["TRANSLESS_REQ_MODE"] { a["mode"] = m }
            if let t = env["TRANSLESS_REQ_TONE"] { a["tone"] = t }
            if let l = env["TRANSLESS_REQ_LANG"] { a["lang"] = l }
            KbBridge.requestRec(args: a)
            KbBridge.note("自测：已留下条子（参数 " + String(describing: a) + "）")
        }
        // 🚨🚨 **每次回到前台都补挂一次小窗。**
        //    2026-08-29 他实测「小窗没启动出来」，痕迹里**一条 PiP3 都没有** ——
        //    因为挂载只写在 `didFinishLaunching` 里，而他那次 App **本来就活着**
        //    （`Scene(叫醒)` + `起录闸：本来就在前台`），冷启动回调根本没跑。
        //    **「代码在」不等于「它被跑过」** —— 今天第二次栽在这。
        //    🚨 而且原来取不到根视图控制器时是**静默返回**，连痕迹都没有，
        //       所以我一直以为它挂上了。现在取不到会出声。
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { _ in
            guard #available(iOS 15.0, *), PipVCKeepAlive.enabled else { return }
            if let root = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
                .first {
                PipVCKeepAlive.shared.arm(on: root)
            } else {
                KbBridge.note("PiP3：回到前台但取不到根视图，这次没挂上")
            }
        }
        // 🚨 记下「什么时候真正变成前台活跃」—— 自动切回的等待要从这里算起。
        //    **这个观察者必须排在带 guard 的那个之前**，否则它一旦 return，
        //    时刻就记不上了（同一个通知、两个观察者，别让业务 guard 吃掉记账）。
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { _ in
            KbVoiceHost.shared.foregroundAt = Date()
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
            guard let self = self, !Self.noTake, !self.awaitingActive,
                  !KbVoiceHost.shared.isRecording else { return }
            if KbBridge.takeRecRequest() {
                KbBridge.note("起录：回到前台时取到键盘的条子")
                self.handleRecURL()
            }
        }
        // 🚨 **让我自己能测这条路，不用再让他按一次。**
        //    Kevin：「不能每次试完都卡在我这里…你自己就要去点击、去测试」。
        //    键盘那一跳已经验过了（`open 回调 true` + `启动方式=manual`），
        //    这里要验的是**它之后的三件事**：只跑一次 / 等到真前台 / 待机自动开。
        //    `devicectl process launch -e` 带上这个变量就能整条走一遍。
        KbBridge.observeRecURL(Unmanaged.passUnretained(self).toOpaque()) { _, o, _, _, _ in
            guard let o = o else { return }
            let me = Unmanaged<AppDelegate>.fromOpaque(o).takeUnretainedValue()
            DispatchQueue.main.async { me.handleRecURL() }
        }
                if ["1", "long"].contains(ProcessInfo.processInfo.environment["TRANSLESS_RECURL"] ?? "") {
            KbBridge.note("起录URL：由远程环境变量触发（不是他按的）")
            handleRecURL()
        }
        KbVoiceHost.shared.armSelfTest()
        // 🚨 画中画保活（实验开关，只认环境变量 —— 真机用户设不了）。
        //    依据：三档实测显示 iOS **按进程状态**决定给不给输入路由，
        //    而 PiP 改的正是进程状态。**这是唯一改到那一层的手段。**
        //    🚨 但「PiP 能让宿主在后台拿到路由」**没有直接证据**，
        //       所以这一版只做可行性验证，判据仍然是**非静音 PCM**，
        //       **不许拿「PiP 起来了」当成功**（今晚栽过「起录成功≠拿到音频」）。
        if #available(iOS 15.0, *), PipKeepAlive.enabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let w = UIApplication.shared.connectedScenes
                    .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
                    PipKeepAlive.shared.arm(on: w)
                    // 🚨 恢复手动请求，但**闸门改成场景 foregroundActive**（-1001 的真正成因）。
                    //    PiP 必须在前台启动、然后带着它进后台。
                    PipKeepAlive.shared.startIfNeeded()
                }
            }
        }
        // 🚨 第四轮：AVPlayerViewController 路线（TRANSLESS_PIP3=1）——
        //    我们自己的调研里引了苹果社区那句「用 AVPlayerViewController 就没问题」，
        //    **摆了两周，前三轮都没试。**
        if #available(iOS 15.0, *), PipVCKeepAlive.enabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let root = UIApplication.shared.connectedScenes
                    .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
                    .first {
                    PipVCKeepAlive.shared.arm(on: root)
                }
            }
        }
        // 🚨 第三轮：AVPlayerLayer 路线（TRANSLESS_PIP2=1）。
        //    sample-buffer 那条三次全 -1001，其中一次**满足了官方给的成因条件**
        //    仍然被拒 —— 说明我们落在已知但没解释的桶里，继续调是碰运气。
        if #available(iOS 15.0, *), PipPlayerKeepAlive.enabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if let w = UIApplication.shared.connectedScenes
                    .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first {
                    PipPlayerKeepAlive.shared.arm(on: w)
                }
            }
        }
        // 🚨🚨 **让我能自己把待机打开**，不用他去点那个开关。
        //    没有它，我  起来的 App 一进后台就被挂起，
        //    Darwin 通知根本投递不到 —— 2026-08-28 实测：把 App 顶到真后台后
        //    发通知，偏好里的结果**一个字都没变**（还是上一次的）。
        //    而**真实使用时待机是开着的**（靠静音保活留在后台），
        //    所以不开待机测出来的后台根本不是他遇到的那个后台。
        //    🚨 只认环境变量：真机上用户设不了，只有  能注入。
        // 🚨 审查 H3：这条原来会在 0.5 秒后**无条件**打开待机，
        //    把 `applyStandbyPolicy()` 的决定悄悄覆盖掉。
        //    **同一件事两个配置点，后写的赢** —— 加上 coldReturn 优先。
        if Self.coldReturn && (ProcessInfo.processInfo.environment["TRANSLESS_STANDBY"] == "1"
                               || KbBridge.flag("standby")) {
            KbBridge.note("冲突：coldreturn 与 standby 同时为真，按 coldreturn 处理")
        }
        // 🚨🚨 **待机（保活常驻）改成默认开（2026-08-30）。**
        //    Kevin 要的「按麦克风不跳出微信」，前提是**宿主一直活着**，
        //    键盘才能只发一条命令、而不是把他整个人拽走。
        //    Typeless 就是这么做的（他手机上三个进程同时在跑）。
        //    默认关着 = 这条路只在我手工设环境变量时存在，他日常永远走不到。
        //    `TRANSLESS_STANDBY=0` 可显式关掉。
        // 🚨🚨🚨 **默认关掉（2026-09-01 13:0x，他第二次叫停）。**
        //
        //    他的原话：「谁说不耗电？开着麦克风真的很耗电。我现在电量中午
        //    1 点钟就只剩 36%……你给我把它关上吧」
        //    「现在我打开一下 Transless，**它一直录音，又自动开启了**，就很烦啊」
        //    —— 「又自动开启了」指的就是下面这段：启动 0.5 秒后自动开待机，
        //    而待机 = 引擎常驻 = 麦克风被占。
        //
        //    上面那段「默认开」的理由是「他要的不跳转，前提是宿主一直活着」。
        //    **今天三条证据把这个前提推翻了**：
        //      · Apple DTS：没有回程 API（论坛 826851，两问两答都是 No）；
        //      · Typeless 的引导页**自己在教用户滑一下**，它也不自动切回；
        //      · 我们的引擎在他机器上**根本架不起来**（`2003329396 / 输入源 0 个`）
        //        —— 待机开着**只在耗电，没换来任何东西**。
        //
        //    → 默认**关**。要开必须显式：环境变量 `TRANSLESS_STANDBY=1`，
        //      或往共享区 `Library/Caches/flags.txt` 里加一行 `standby`（不用重装包）。
        //      （`KbBridge.flag()` 读的是 flags.txt 的按行匹配，**不是**另一个 standby.txt——第一版注释写错了。）
        //    🚨 两处同一套语义，别再出现 `armidle.txt` 那种两边相反的漂移。
        let wantStandby: Bool = {
            if let v = ProcessInfo.processInfo.environment["TRANSLESS_STANDBY"] {
                return v == "1"
            }
            return KbBridge.flag("standby")
        }()
        if !Self.coldReturn && wantStandby {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                KbVoiceHost.shared.setStandby(true)
                KbBridge.note("显式打开了待机（默认是关的）")
            }
        } else if !Self.coldReturn {
        // 🚨 `dumpHostIdentityClasses()` **已停掉**（2026-09-02 07:3x）。
        //    它每次冷启动吐 40 行，而痕迹是 **200 行的环形缓冲** ——
        //    我刚要查「推送冷启动为什么架不起引擎」，证据已经被自己的调试日志冲没了。
        //    **调试日志不是免费的：它会挤掉真正要看的东西。**
        //    它回答的问题（有没有宿主身份字段）今晚已有定论，全部在
        //    `回程_已验死的路.md`，要复查就临时打开这一行。
        registerSilentPush()        // 🚨 静默推送：后台叫醒自己的唯一入口
            KbBridge.note("待机：默认不开（他 2026-09-01 要求：别一直占麦克风、别耗电）")
        }
        // 调试口子：模拟"他已经体验过了"。**走的是真实的 `Onboard.markTried()`**，
        // 不是伪造一个状态 —— 验的是"标记真写进 Keychain 了 + 首页真会据此显示"。
        // 🚨 没验到的那一半：点麦克风时会不会调 markTried（模拟器点不了，
        //    脚本没有 tap API）。那是 `tapMic` 第一行的一句话，我改的时候盯着写的。
        if ProcessInfo.processInfo.environment["TRANSLESS_MARK_TRIED"] == "1" {
            Onboard.markTried()
        }
        // 调试口子：预设说话页的档位，好并排截"选中翻译"和"选中转写"两张图。
        // 🚨 写的是 `setMode` 读的那个 key，走的是**同一条真实路径**，
        //    不是另建一套状态。
        if let m = ProcessInfo.processInfo.environment["TRANSLESS_MODE"],
           !m.isEmpty {
            KbBridge.prefs.set(m, forKey: "vime.mode")
            // 🚨 设了档位就等于"他点过 Tab" —— 这两件事在真实操作里
            //    本来就是同一下点击带来的（`pickEn`/`pickTranscribe`
            //    先 `touchTabs()` 再 `setMode`）。截图要复刻的正是那个状态。
            KbBridge.prefs.set(true, forKey: "vime.tabTouched")
        }
        DeviceId.ensure()
        let w = UIWindow(frame: UIScreen.main.bounds)
        // 🚨 **调试用的直达入口**：`xcrun simctl launch … --page speak` 之类，
        //    直接跳到某一页，免得在模拟器里手点（脚本点不了，
        //    AppleScript 点击要辅助功能授权）。
        //    这条只认启动参数，正常安装的包收不到，不影响用户。
        //    有了它，我改完 UI 能自己截图核对，不用等 Kevin 装了来告诉我。
        // 🚨 用**环境变量**不用启动参数：`simctl launch` 有自己的参数解析，
        //    `--page speak` 被它吞掉了，App 侧 arguments 里根本收不到
        //    （实测：传了 speak 却进了 setup —— 我一度以为是 switch 写错）。
        //    环境变量走 `SIMCTL_CHILD_` 前缀，simctl 会原样传进来。
        let env = ProcessInfo.processInfo.environment
        // 🚨 只给模拟器验收：让后台起录自测自己开跑，好在几十秒内确认
        //    "它真的会记账、报告真的渲染得出来"。**没验过的诊断件不许发** ——
        //    557 就是发了一版诊断，而那版诊断自己瞎了。
        if BgRecProbe.autoStart {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                BgRecProbe.shared.start()
            }
        }
        // 🚨 验收钩子：走**iOS 真实那条链**跑一句 —— 真的 `Prompts.tone()`、
        //    真的 `langName()`、真的 `Secrets.prompt`、真的 `Backend.submit`。
        //    在 Python 里重拼一遍请求是**测错对象**：那样测的是我抄得对不对，
        //    不是 App 发出去的是什么。
        //    结果落进 UserDefaults，外面读磁盘取 —— 不靠界面。
        if let probe = env["TRANSLESS_POLISH_TEXT"], !probe.isEmpty {
            let lang = env["TRANSLESS_POLISH_LANG"] ?? "en"
            let tone = Prompts.normalize(env["TRANSLESS_POLISH_TONE"])
            let mode = Backend.Mode(
                rawValue: env["TRANSLESS_POLISH_MODE"] ?? "en") ?? .en
            // 🚨🚨 **一次性标记**：外面按 `nonce` 认这一轮的结果。
            //    没有它的话，下一轮启动后、结果还没回来那段时间里，
            //    读到的是**上一轮留在 plist 里的输出** —— 而它看起来完全正常。
            //    2026-08-28 真撞到：Y2 那一栏打出来的是 Y1 的邮件。
            //    跟 `uiautomator dump` 失败时返回上一次的树是同一族。
            let nonce = env["TRANSLESS_POLISH_NONCE"] ?? ""
            UserDefaults.standard.removeObject(forKey: "polishProbe.out")
            UserDefaults.standard.removeObject(forKey: "polishProbe.nonce")
            // 设备令牌要先注册出来，所以延后一点再发
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                Backend.polish(text: probe, tone: tone, mode: mode, lang: lang) { r in
                    let out: String
                    switch r {
                    case .success(let s): out = s
                    case .failure(let f): out = "FAIL: \(f)"
                    }
                    // 🚨 先写正文再写 nonce —— 顺序不许倒。
                    //    倒过来的话外面可能读到"nonce 已更新、正文还是旧的"。
                    UserDefaults.standard.set(out, forKey: "polishProbe.out")
                    UserDefaults.standard.set(nonce, forKey: "polishProbe.nonce")
                }
            }
        }
        // 🚨 **只为我自己截图核对首页 KPI 四格**：给累加器塞一组数。
        //    正式路径永远不会设这个 env（跟 `TRANSLESS_SEED_HIST` 同一套做法）。
        //
        // 🚨🚨 **这种种子证明不了任何"跨进程能不能看见"的事** —— 写的人和读的人
        //    是同一个进程。键盘↔主 App 那类问题（App Group 容器分家）
        //    结构上就不可能被它抓到，只能真机端到端验。这里只用来核**版式**。
        // 🚨 **只为我自己核对常用词屏 / 验同步不会冲掉本地**。
        //
        // 🚨🚨 为什么必须由 **App 自己写**，不能从外面 `defaults write` 塞：
        //    2026-09-04 我就那么干过 —— `xcrun simctl spawn ... defaults write
        //    group.com.kevin.transless kb.vocab.terms ...`，然后 `defaults read`
        //    读回来 2 条，我据此写下「本地的词没被冲掉」。**那是同源自比**：
        //    写和读走的是同一个 cfprefsd 缓存，而 **App 那个进程根本看不见它**
        //    （磁盘上真正的 App Group plist 里 `kb.vocab.terms` 是 0 条，
        //     屏幕上显示的是空态 —— 截图才把这个假结论揭出来）。
        //    种子必须经过 `KbBridge.saveVocab`，也就是**产品代码真正在用的那条路**。
        //
        // 🚨 这个种子**证明不了**跨进程可见性（键盘写、主 App 读）——
        //    写的人和读的人还是同一个进程。它只用来验「拉到空表会不会冲掉本地」。
        if env["TRANSLESS_SEED_VOCAB"] == "1", KbBridge.loadVocab().isEmpty {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            KbBridge.saveVocab([
                VocabCore.Term(id: VocabCore.idOf("PressLogic"), text: "PressLogic",
                               kind: VocabCore.KIND_BOTH, src: VocabCore.SRC_MANUAL,
                               at: now),
                VocabCore.Term(id: VocabCore.idOf("circle back"), text: "circle back",
                               kind: VocabCore.KIND_STYLE, src: VocabCore.SRC_MANUAL,
                               at: now),
                VocabCore.Term(id: VocabCore.idOf("李文彬"), text: "李文彬",
                               kind: VocabCore.KIND_ASR, src: VocabCore.SRC_BOOK,
                               at: now),
                // 候选和否掉各一条 —— 三段都要能截到图
                VocabCore.Term(id: VocabCore.idOf("Transless"), text: "Transless",
                               kind: VocabCore.KIND_BOTH, src: VocabCore.SRC_AUTO,
                               at: now, status: VocabCore.ST_CAND, count: 5),
                VocabCore.Term(id: VocabCore.idOf("那个啥"), text: "那个啥",
                               kind: VocabCore.KIND_BOTH, src: VocabCore.SRC_AUTO,
                               at: now, status: VocabCore.ST_NO, count: 2),
            ])
        }
        if env["TRANSLESS_SEED_KPI"] == "1", KpiWords.total == nil {
            KpiWords.add(1280)                                  // ① 翻译的词
            KpiWords.addSpoken(durMs: 22 * 60_000, zh: "")      // ③ 说了 22 分钟
            KpiWords.addSpoken(durMs: 0, zh: String(repeating: "字", count: 3400))
        }
        if let page = env["TRANSLESS_PAGE"], !page.isEmpty {
            let nav = UINavigationController(rootViewController: HomeViewController())
            nav.setNavigationBarHidden(true, animated: false)
            switch page {
            case "speak": nav.pushViewController(MainViewController(), animated: false)
            // 调试：直达面对面翻译屏，好让我自己截图核对布局（整块居中/上文/空态/横屏）。
            //    正式入口是首页那条长条；这个环境变量只为截图，不影响正式流程。
            case "f2f": nav.pushViewController(FaceToFaceViewController(), animated: false)
            // 调试：直达说话记录屏，好截图核对（列表按档上色/chip/时间/点进详情）。
            case "hist":
                // 🚨 只在**调试注入且历史为空**时塞几条样本给我截图用（照已批图）。
                //    正式路径永远不会设这个 env，用户数据一条不动。
                // 🚨 **反向控制专用**：清空历史，好验「一条都没有时不该出现『最近』」
                //    （2.1 规格第四节第 4 条）。没有它的话，同一台模拟器上
                //    前一个用例种下的历史会留到后一个用例 ——
                //    那样"看见了最近标题"是**测试串味**，不是产品写死，
                //    而这两种原因的修法完全不同。
                // 🚨 跟 `TRANSLESS_SEED_HIST` 同一套：只认调试注入的 env，
                //    真机上用户设不了（只有 Xcode / simctl 能注）。
                if env["TRANSLESS_CLEAR_HIST"] == "1" { History.clear() }
                if env["TRANSLESS_SEED_HIST"] == "1", History.list().isEmpty {
                    History.add(mode: "en", tone: "", zh: "我想订一张明天去香港的高铁票",
                                out: "I'd like to book a high-speed rail ticket to Hong Kong for tomorrow.",
                                durMs: 40_000, lang: "en")
                    History.add(mode: "zh", tone: "", zh: "这个功能挺好用的，就是有点小问题",
                                out: "这个功能挺好用的，就是有点小问题", durMs: 20_000, lang: "")
                    History.add(mode: "en", tone: "", zh: "帮我把这段话说得客气一点，我要发给客户",
                                out: "Could you help me phrase this more politely for a client?",
                                durMs: 30_000, lang: "en")
                    History.add(mode: "en", tone: "",
                                zh: "我们下周一开会把时间线再确认一下，你安排一下会议室",
                                out: "Let's confirm the timeline again at next Monday's meeting. Could you book a meeting room?",
                                durMs: 60_000, lang: "en")
                }
                nav.pushViewController(HistoryListViewController(), animated: false)
            // 调试：直达常用词屏，好截图核对芯片带（候选/已收录/我不要的三段）。
            // 🚨 **不塞任何种子**：这一屏的种子要塞进 App Group 的共享域，
            //    而那正是「写的人和读的人是同一个进程」那类假测试的温床。
            //    要看有词的样子，从外面用
            //    `xcrun simctl spawn <SIM> defaults write group.<bundle> kb.vocab.terms ...`
            //    塞进去 —— 那样读它的是 App 自己的 `loadVocab`，才算真读到了。
            // 🚨🚨 **只为验 H1：把键盘扩展"叫起来"，不需要任何人碰手机。**
            //
            //    H1 要证的是「键盘写的历史，主 App 看得见」，要害是**两个进程
            //    解析到同一个容器**。主 App 那半已经实测（日志里有落点），
            //    键盘那半需要**键盘进程真的跑一次** —— 而我驱动不了它：
            //      · UITest 那条被设备的 `Enable UI Automation` 挡住（04:05 实测
            //        `Timed out while enabling automation mode`）
            //      · 扩展没法用 `devicectl process launch` 直接起
            //    但系统会在**任何输入框获得焦点时**加载当前键盘 —— 包括我们自己
            //    这个 App 里的输入框。而诊断写在键盘的 `viewDidLoad`，
            //    **不用说话、不用点麦克风**，键盘一露面就写下了。
            //
            // 🚨 **前提是 Transless 此刻是选中的那个键盘** —— 不是的话系统会弹
            //    别的键盘，日志里就不会出现 `[键盘扩展]` 那条。
            //    所以「没看到」要读成「这次没叫起来」，**不能读成「键盘写错地方了」**。
            case "kbwake":
                nav.pushViewController(KeyboardWakeController(), animated: false)
            case "vocab":
                nav.pushViewController(VocabViewController(), animated: false)
            // 调试：KPI 四格组件（已落位到首页，这个口子只为单独核对组件本身）。
            case "kpi":
                // 🚨 **反向控制专用**：清空历史，好验「一条都没有时不该出现『最近』」
                //    （2.1 规格第四节第 4 条）。没有它的话，同一台模拟器上
                //    前一个用例种下的历史会留到后一个用例 ——
                //    那样"看见了最近标题"是**测试串味**，不是产品写死，
                //    而这两种原因的修法完全不同。
                // 🚨 跟 `TRANSLESS_SEED_HIST` 同一套：只认调试注入的 env，
                //    真机上用户设不了（只有 Xcode / simctl 能注）。
                if env["TRANSLESS_CLEAR_HIST"] == "1" { History.clear() }
                if env["TRANSLESS_SEED_HIST"] == "1", History.list().isEmpty {
                    History.add(mode: "en", tone: "", zh: "我们下周一开会把时间线再确认一下",
                                out: "Let's confirm the timeline again at next Monday's meeting.",
                                durMs: 45_000, lang: "en")
                    History.add(mode: "en", tone: "", zh: "帮我订一张明天去香港的高铁票",
                                out: "Help me book a high-speed rail ticket to Hong Kong for tomorrow.",
                                durMs: 30_000, lang: "en")
                    History.add(mode: "zh", tone: "", zh: "这个功能挺好用的就是有点小问题",
                                out: "这个功能挺好用的，就是有点小问题。", durMs: 20_000, lang: "")
                }
                nav.pushViewController(KpiDebugController(), animated: false)
            case "setup": nav.pushViewController(SetupViewController(), animated: false)
            case "prefs": nav.pushViewController(PrefsViewController(), animated: false)
            case "login": nav.pushViewController(LoginViewController(), animated: false)
            // 调试：直接落在手机号 tab（好并排截两个 tab 的图）。
            // 🚨 走的是**真实的 tab 切换方法**，不是另建一套状态。
            case "login-phone":
                let lv = LoginViewController()
                lv.startOnPhoneTab = true
                nav.pushViewController(lv, animated: false)
            // 🚨 只为**我自己看键盘长什么样**：键盘扩展要在系统设置里启用、
            //    再点 🌐 切过去，这两步模拟器上脚本点不动。把同一个
            //    `TypingKeyboardView` 直接塞进 App 里截图，看到的是同一份代码。
            //    正式界面里没有任何入口，只有这个环境变量能进。
            case "kb": nav.pushViewController(KeyboardPreviewController(), animated: false)
            // 拼音引擎对拍（期望值来自独立的 Python 参照实现）
            case "pysplit": nav.pushViewController(PinyinSelfTestController(),
                                                   animated: false)
            default: break
            }
            w.rootViewController = nav
            w.makeKeyAndVisible()
            window = w
            return true
        }
        // 🚨 跟安卓一样：先开屏，再进首页。安卓那边 LAUNCHER 指向 SplashActivity。
        w.rootViewController = SplashViewController()
        w.makeKeyAndVisible()
        window = w
        return true
    }
}

// MARK: - 共用的皮肤件（对齐安卓 Skin）

enum UI {
    /// 三段渐变背景。**每个界面都铺**，跟安卓一致。
    /// 主界面的根控制器 —— **全 App 唯一的一处**。
    ///
    /// 🚨🚨 收成一个工厂是因为它原来有**三个**构造点（开屏进首页、换语言重建 UI、
    ///    调试环境变量），而「改成四 Tab」这种事一改就要三处一起改 ——
    ///    漏一处的表现是"平时是 Tab，一换语言就退回老首页"，
    ///    而那种漏只在走到第三级时才现形。记忆 `feedback_rule_lands_at_every_exit`。
    ///
    /// 🚨 调试入口（`TRANSLESS_PAGE`）**故意不走这里**：它要往根上直接 push
    ///    一个调试页，套一层 Tab 只会让截图里多出一条无关的栏。
    static func mainRoot() -> UIViewController {
        MainTabController()
    }

    static func paintBg(_ vc: UIViewController) {
        // 🚨🚨 复审 中-4：**先把旧的那层删掉**。
        //    原来只 `insertSublayer`、从不移除，而首页重建走的是
        //    `view.subviews.forEach { removeFromSuperview() }` ——
        //    渐变是 **sublayer 不是 subview**，一层都删不掉。
        //    登录/加键盘/改昵称/试一段各回来一次 = **5 层全屏渐变常驻**。
        //    收在这里是**单一配置点**，另外 6 个调用它的页面一并受益。
        vc.view.layer.sublayers?
            .filter { $0.name == "skinBg" }
            .forEach { $0.removeFromSuperlayer() }
        let g = Skin.screenBg(vc.view.bounds)
        g.name = "skinBg"
        vc.view.layer.insertSublayer(g, at: 0)
    }

    /// 🚨 渐变层不跟 Auto Layout 走，转屏后要手动同步 frame，
    ///    否则背景只铺一半。
    static func resizeBg(_ vc: UIViewController) {
        vc.view.layer.sublayers?.first(where: { $0.name == "skinBg" })?
            .frame = vc.view.bounds
    }

    static func label(_ text: String, size: CGFloat, kern: CGFloat,
                      color: UIColor, weight: UIFont.Weight) -> UILabel {
        let l = UILabel()
        l.attributedText = NSAttributedString(
            string: text,
            attributes: [.kern: kern,
                         .font: UIFont.systemFont(ofSize: size, weight: weight),
                         .foregroundColor: color])
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }
}

// MARK: - ① 开屏（对齐安卓 SplashActivity）

/// 安卓：Logo 常驻，中文 slogan 260ms 起浮出、英文 1180ms 起，HOLD 2600ms。
/// 🚨 淡入**自己按时间推**，不用系统动画 —— 安卓那边的教训是
///    系统「动画时长缩放」会把它乘一遍（关掉时字啪地跳出来，
///    Kevin 说「像一个青蛙一样跳出来」）。iOS 没有那个全局开关，
///    但按时间推同样稳，而且两端行为一致。
extension AppDelegate {
    /// **这次启动是被 URL 拉起来的吗** —— 开屏据此决定跳不跳过动画。
    /// 🚨 Scene 那条路拿不到启动参数，所以单独立一个标记。
    static var launchedByURL = false
}

final class SplashViewController: UIViewController {

    private let logo = UIImageView(image: UIImage(named: "logo"))
    private let zh = UI.label(Brand.sloganZh, size: Skin.sloganZhSize,
                              kern: Skin.sloganZhKern, color: Skin.sloganZh,
                              weight: .regular)
    private let en = UI.label(Brand.sloganEn, size: Skin.sloganEnSize,
                              kern: Skin.sloganEnKern, color: Skin.dim,
                              weight: .light)
    private let brand = UI.label("Transless", size: Skin.brandSize,
                                 kern: Skin.brandKern, color: Skin.text,
                                 weight: .medium)
    private var went = false

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)

        let stack = UIStackView(arrangedSubviews: [logo, brand, zh, en])
        stack.axis = .vertical
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        logo.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 92),
            logo.heightAnchor.constraint(equalToConstant: 92),
        ])
        stack.setCustomSpacing(21, after: logo)
        stack.setCustomSpacing(9, after: brand)
        stack.setCustomSpacing(5, after: zh)

        zh.alpha = 0
        en.alpha = 0
        fade(zh, delay: 0.26)
        fade(en, delay: 1.18)

        // 🚨🚨🚨 **被键盘拉起来时，开屏一秒都不能等（2026-09-01，Kevin 指出）。**
        //
        //    他的原话：「是不是因为这个主 APP 每次打开，它都要等那个动画
        //    （就那个字浮现出来）播完才会停？」——**他说对了**。
        //    这里写死 HOLD 2.6 秒，而 `arm` 那条路径要的是「闪一下就走」：
        //    我把退出时机调到 0.25 秒，**根本轮不到执行**，因为前面先站了 2.6 秒。
        //    他看到的"停在主 App"，一大半就是这 2.6 秒。
        //
        //    → 只要是被 URL / 启动参数拉起来的（`arm` / `rec`），**直接跳过开屏**。
        //      他自己点图标打开时照旧播，那是品牌门面，不动。
        // 🚨🚨 **`launchedByURL` 在这一刻还是 false —— 判据挂错时机了。**
        //    `didFinishLaunching` 里就把开屏页建好了，而那个标记要等
        //    Scene 连上才置位 —— **开屏那时候还不知道自己是被拉起来的**。
        //    Kevin：「我觉得还是有这个动画…中文字浮现，然后英文字浮现」——
        //    他看到的就是这个。（我用启动参数测时走的是另一条判断，所以"看起来生效了"。）
        //    → 改用**键盘在跳转之前就写好的那个标记**，它一定早于开屏。
        let pulled = CommandLine.arguments.contains("arm")
            || CommandLine.arguments.contains("rec")
            || AppDelegate.launchedByURL
            || KbBridge.peekWantRec(maxAge: 30)
        if pulled {
            KbBridge.note("开屏：被拉起来的，直接跳过 2.6 秒动画")
            DispatchQueue.main.async { [weak self] in self?.go() }
            return
        }
        // 🚨 无条件跳转，绝不能卡死在开屏（安卓同样的兜底）。
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            self?.go()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    /// 620ms 淡入 + 12pt 上浮，自己按时间推。
    private func fade(_ v: UIView, delay: Double) {
        let dur = 0.62
        let rise: CGFloat = 12
        v.transform = CGAffineTransform(translationX: 0, y: rise)
        let t0 = CACurrentMediaTime() + delay
        func step() {
            let dt = CACurrentMediaTime() - t0
            if dt < 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { step() }
                return
            }
            var k = min(1, dt / dur)
            k = k * k * (3 - 2 * k)      // smoothstep，别是生硬的线性
            v.alpha = CGFloat(k)
            v.transform = CGAffineTransform(translationX: 0,
                                            y: rise * CGFloat(1 - k))
            if k < 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { step() }
            }
        }
        step()
        // 🚨 兜底：到点还没亮就直接写死。安卓那边这条被删过一次，
        //    注释还留着而代码没了 —— 开屏可以不好看，但不能少一行字。
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + dur + 0.4) {
            if v.alpha < 1 {
                v.alpha = 1
                v.transform = .identity
            }
        }
    }

    private func go() {
        guard !went else { return }     // 只走一次
        went = true
        // 🚨 2026-09-04：根从「一个导航栈」换成**四 Tab**（`UI.mainRoot()`）。
        //    首页那层导航栈现在由 `MainTabController` 建，隐藏导航栏那一步也在它里面。
        let home = UI.mainRoot()
        // 🚨🚨 **不自动跳转**。新用户看到的是**首页本身**，
        //    只不过那时候首页上只有「说一段试试」一个按钮 ——
        //    "必须让他试"是靠**没别的可点**实现的，不是靠强制跳走。
        //
        //    我上一版做成了"开 App 直接 push 说话页"，Kevin 2026-08-25 纠正：
        //    「应该是先 2（他第一次看到的），然后才是 1，试完之后变成 3。
        //      这个顺序是不是反过来了？」——是反了。
        //    直接跳走的话他连 logo 和 slogan 都没看见就被丢进功能页了。
        home.modalTransitionStyle = .crossDissolve
        home.modalPresentationStyle = .fullScreen
        // 🚨 「只在首页隐藏导航栏、子页要显示」那一条**挪进 `MainTabController`** 了 ——
        //    现在每个 Tab 各有自己的导航栈，只有首页那一栈隐藏。
        //    原来在这里对整个栈调 `setNavigationBarHidden` 是因为当时只有一个栈；
        //    继续留在这里的话，四个 Tab 会被一起藏掉标题栏（交叉审查 H3 那个坑重演）。
        UIApplication.shared.windows.first?.rootViewController = home
    }
}

// MARK: - ② 首页（对齐安卓 SettingsActivity）

final class HomeViewController: UIViewController {

    /// 建首页那几个长条时的状态：体验过没有、登录了没有。
    ///
    /// 🚨 存下来是为了**知道什么时候要重建** —— 从说话页/登录页返回时
    ///    状态可能刚变，不重建的话按钮不会冒出来，看着就像"试了也没用"。
    /// 🚨 **两个状态都要记**：只记 `tried` 的话，登录完回来首页不会变，
    ///    「设为当前输入法」永远出不来 —— 那种漏只在走到第三级时才现形。
    private var builtWithTried = false
    private var builtWithIme = false
    /// 建的时候首页显示的名字。改了昵称回来要刷新 —— 见 viewWillAppear。
    private var builtWithName = ""
    private var builtWithLogin = false
    /// 建的时候 KPI 四格是什么数。
    ///
    /// 🚨🚨 2026-09-04 补：首页换成安卓那套之后**多了 KPI 四格**，
    ///    而这个"变了才重建"的判据当时没跟着加 —— 后果是
    ///    **说完一句话回到首页，四格纹丝不动**，看着像统计根本没在记。
    ///    这正是这个判据被打过两次的同一族毛病：
    ///    **界面上多了一样东西，就要问一句"它会变吗？变了谁来刷？"**
    // 🚨 第 4 个是 ② 的减数 `transMs`（只算翻译档的说话时长）。**它也要盯** ——
    //    漏掉的话，只做了翻译、别的都没变时「省下时间」不会刷新。
    private var builtWithKpi: (Int?, Int?, Int?, Int?) = (nil, nil, nil, nil)

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        // 🚨🚨 **四个**状态都要盯：少盯一个，那一种变化回到首页就不刷新。
        //    这条被同一族的 bug 打过两次：
        //      · 「设完输入法回来那条还在」—— 当时只盯了 tried/login
        //      · 「填完昵称回来首页还是旧名字」—— 当时漏了 displayName
        //    2026-08-26 在安卓上实测抓到第二个（强制重启看得到新名字、
        //    走 viewWillAppear 看到的是旧的），iOS 这边同型，一并修。
        let kpiNow = (KpiWords.total, KpiWords.spokenMs, KpiWords.chars,
                      KpiWords.transMs)
        if builtWithTried != Onboard.tried
            || builtWithLogin != Auth.loggedIn
            || builtWithName != Auth.displayName
            || builtWithIme != SetupViewController.keyboardAdded()
            // 🚨 KPI 也要盯（09-04 加，见 `builtWithKpi` 的说明）：
            //    说完一句话回来，四格必须跟着变。
            || builtWithKpi != kpiNow {
            // 状态变了：整页重搭（首页很轻，重搭比逐个增删可靠）
            view.subviews.forEach { $0.removeFromSuperview() }
            viewDidLoad()
        }
    }

    /// 首页版式 —— **照抄安卓 `SettingsActivity.onCreate()`**（Kevin 2026-09-04：
    /// 「iOS 首页换成安卓那一套」）。安卓的竖向坐标表（393×829dp 画板）：
    ///
    /// ```
    ///  24 状态栏 | 48 顶栏 | 12 间距 | 54 品牌 | 18 间距
    /// 96 格行1 | 10 | 96 格行2 | 16 脚注槽
    /// ─── 弹性留白（把上下顶到两端）───
    /// 88 随手翻译（顶边锁死）| 12 | 52 输入法槽
    /// ```
    ///
    /// 🚨 **没有 ScrollView**：整屏一页不滚，靠中间那块弹性留白撑开。
    ///    安卓那份也是这样 —— 加了滚动条之后"CTA 顶边锁死"这条就没了意义。
    ///
    /// 🚨 底部那条 Tab **不在这里画**：它现在是 `MainTabController` 的系统
    ///    `UITabBar`。安卓那边是自己画的 56dp 文字条，iOS 用原生控件 ——
    ///    **结构照抄，控件用各端原生的**。
    override func viewDidLoad() {
        super.viewDidLoad()
        builtWithTried = Onboard.tried
        builtWithIme = SetupViewController.keyboardAdded()
        builtWithName = Auth.displayName
        builtWithLogin = Auth.loggedIn
        // 🚨 **记的必须是这一次真正画上去的那组数**，所以在建 KPI 之前取一次、
        //    下面建格子时用同一组 —— 分两次取的话，两次之间要是有一次累加，
        //    记下的和画上去的就不是同一组，下次回来判成"没变"而其实变过。
        builtWithKpi = (KpiWords.total, KpiWords.spokenMs, KpiWords.chars,
                        KpiWords.transMs)
        UI.paintBg(self)

        let root = UIStackView()
        root.axis = .vertical
        root.alignment = .fill
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            // 🚨 页边距 **21**（安卓 `root.setPadding(dp(21), 0, dp(21), 0)`）。
            //    原来 iOS 写的是 24 —— 一直跟安卓差 3pt，截图并排看就是内容宽度不一样。
            root.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 21),
            root.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -21),
            root.topAnchor.constraint(equalTo: g.topAnchor),
            root.bottomAnchor.constraint(equalTo: g.bottomAnchor, constant: -16),
        ])

        // ── ① 顶栏 48：账号胶囊 ←→ 设置齿轮 ─────────────────────
        //
        // 🚨 账号从**导航栏左上角挪回页面里**（安卓是页内胶囊）。四 Tab 之后首页
        //    那层导航栏是隐藏的，挂在 `navigationItem` 上的按钮**根本不显示** ——
        //    不挪的话登录入口会整个消失。这不是版式偏好，是会丢功能。
        // 🚨 齿轮**留着**（安卓有，照抄）。它跟「设置」Tab 是同一个去处 ——
        //    我不擅自删，入口去留是产品决定，已列进给 2.1 的问题里。
        // 🚨 右上角这个位置 2026-09-04 换了两次，别按老印象改：
        //    ① 原来是「设置」齿轮 → **删掉**（跟底部「设置」Tab 是同一个去处，
        //       一个页面两个入口）；
        //    ② 空出来的位置改放**输入法状态胶囊**（Kevin 当天点名：
        //       「设为当前输入法那地方，我都已经说了要放到右上角」）。
        //    `gearChip()` 留着不删 —— 它是随时可能被叫回来的产品选项，
        //    不是写漏的死代码。
        let head = UIStackView(arrangedSubviews: [accountChip(), spring(), imeChip()])
        head.axis = .horizontal
        head.alignment = .center
        head.heightAnchor.constraint(equalToConstant: 48).isActive = true
        root.addArrangedSubview(head)

        // ── ② 品牌块 54（顶栏下 12）：Transless + 口号，**左对齐** ──────
        //
        // 🚨 原来 iOS 是 logo + 品牌 + 两行口号**居中**、占满中间一大块。
        //    安卓那套是左对齐的一小块 54pt，因为中间的位置让给了 KPI 四格。
        //    Logo 图在安卓首页上没有 —— 一起去掉（开屏页已经露过一次 logo 了）。
        let brand = UI.label("Transless", size: 26, kern: Skin.brandKern,
                             color: Skin.text, weight: .medium)
        brand.textAlignment = .left
        // 🚨🚨 **首页这一行要跟着界面语言走**（Kevin 2026-09-05：
        //    「切英语，为什么还是『让世界听懂你』？不是应该 no language in between 吗？」）。
        //
        // 🚨 `Brand` 那句注释「两端一模一样、**不随界面语言变**」
        //    对**开屏页**成立 —— 那里中英两行**同时**出现，是品牌演出。
        //    但首页**只显示一行**，那一行就必须是他看得懂的那种语言。
        //    **同一个常量在两个场景里的正确用法不同**，照搬注释就会错。
        let slogan = UI.label(L.isEn ? Brand.sloganEn : Brand.sloganZh,
                              size: 13, kern: Skin.sloganZhKern,
                              color: Skin.sloganZh, weight: .regular)
        slogan.textAlignment = .left
        let brandBox = UIStackView(arrangedSubviews: [brand, slogan])
        brandBox.axis = .vertical
        brandBox.alignment = .leading
        brandBox.distribution = .fillProportionally
        brandBox.heightAnchor.constraint(equalToConstant: 54).isActive = true
        root.setCustomSpacing(12, after: head)
        root.addArrangedSubview(brandBox)

        // ── ③④ KPI 2×2（品牌下 18）+ ⑤ 脚注 ─────────────────────
        //
        // 🚨 安卓那边**多了一次 18**（`gap(18)` 之后 `kpiGrid` 自己又
        //    `setMargins(0, dp(18), 0, 0)`），实际间距是 36。规格要的是 18，
        //    这里按 **18** 做 —— 照抄的是规格不是那个 bug。
        // 🚨 KPI 组件自己管空态（一条数据都没有时整块换成一句引导，不画四个 0）
        //    和脚注槽，所以这里直接挂它。
        root.setCustomSpacing(18, after: brandBox)
        // 🚨 用**上面记下的那一组**算，不再调 `KpiGridView.stats()` 去重读 ——
        //    读两次之间要是刚好有一次累加，`builtWithKpi` 记的和屏幕上画的
        //    就不是同一组数，下次回来会判成"没变"而其实变过（少刷一次）。
        root.addArrangedSubview(KpiGridView(stats: HomeStatsCore.compute(
            words: builtWithKpi.0, spokenMs: builtWithKpi.1,
            chars: builtWithKpi.2, transMs: builtWithKpi.3)))

        // 🚨🚨 **把两份 selfTest 接上闸门。**
        //    `HomeStatsCore.selfTest()` 和 `KpiWords.selfTest()` 写得很细
        //    （好样本 + 一串坏样本），但全项目 grep 下来**零调用点** ——
        //    从建起来那天就没跑过一次。「检查写对了 ≠ 检查在跑」，
        //    没有任何自动链执行它的检查，等于没有。
        //    这里把结果挂到一个隐形标签上，UITest 读它（`KpiSelfTest.swift`）。
        if ProcessInfo.processInfo.environment["TRANSLESS_SELFTEST"] == "1" {
            let r = UILabel()
            r.accessibilityIdentifier = "app.selftest"
            r.isAccessibilityElement = true
            r.text = HomeStatsCore.selfTest() ?? KpiWords.selfTest() ?? "OK"
            r.accessibilityLabel = r.text
            r.font = .systemFont(ofSize: 9)
            r.textColor = .clear
            root.addArrangedSubview(r)
        }

        // ── ⑥ 弹性留白：把上半和下半顶到两端 ──────────────────────
        let waist = UIView()
        waist.setContentHuggingPriority(.init(1), for: .vertical)
        waist.setContentCompressionResistancePriority(.init(1), for: .vertical)
        root.addArrangedSubview(waist)

        // ── ⑦ 主 CTA「随手翻译」88 ──────────────────────────────
        //
        // 🚨 **本屏唯一的实色块**（安卓 `ctaTry` 用 `Skin.ACCENT` 实心）。
        //    iOS 这边用渐变紫 `Theme.purpleGrad` —— Kevin 09-04：
        //    「麦克风底色及翻译、工作等 tab 的紫色不够渐变，需调整为渐变紫色」。
        // 🚨 **永远都在、不被任何门槛挡**（方案 D，他 08-26 逐字拍板：
        //    「随手翻译永久免登录」，看到"拿不到注册转化"这个代价之后仍然选了它）。
        root.addArrangedSubview(cta())

        // ── ⑧⑨ 输入法槽 52（CTA 下 12），三档同槽 ────────────────
        //
        // 🚨🚨 **三档高度必须完全一样**，第三档用"占位不可见"而不是"移除" ——
        //    移除的话 CTA 底下会突然空出 52pt，看着像布局塌了。
        //    安卓那边是 `INVISIBLE` 不是 `GONE`，同一个理由。
        // 🚨 iOS 多一档：**已设好输入法**时这个槽让给「键盘语音待机」开关。
        //    安卓没有这个开关（安卓的键盘能自己录音）；iOS 因为苹果不让扩展进程
        //    录音，真正在录的是主 App 在后台，必须由他显式打开、也随时能关。
        //    放这里而不是新加一条，正是因为这一档下"设为输入法"已经消失、槽是空的。
        root.setCustomSpacing(12, after: root.arrangedSubviews[root.arrangedSubviews.count - 1])
        root.addArrangedSubview(imeSlot())
    }

    /// 顶栏中间那根弹簧。
    private func spring() -> UIView {
        let v = UIView()
        v.setContentHuggingPriority(.init(1), for: .horizontal)
        return v
    }

    /// 账号胶囊：`👤 昵称` / `👤 注册 / 登录`。**一个入口两种状态。**
    ///
    /// 🚨 未登录也显示（Kevin 08-26 拍板 D2）：不显示的话他根本找不到登录入口。
    ///    做成两套控件就是两个配置点，改一处等于没改 —— 所以只有一个函数。
    private func accountChip() -> UIView {
        let signedIn = Auth.loggedIn
        let b = UIButton(type: .system)
        b.setTitle("👤  " + (signedIn ? Auth.displayName : L.home_login),
                   for: .normal)
        b.setTitleColor(signedIn ? Skin.text : Skin.dim, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13)
        b.alpha = signedIn ? 1 : 0.75
        b.backgroundColor = Skin.glassFill
        b.layer.cornerRadius = 18
        b.layer.borderWidth = 0.6
        b.layer.borderColor = Skin.glassStroke.cgColor
        b.contentEdgeInsets = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
        b.addTarget(self, action: signedIn ? #selector(openAccount)
                                           : #selector(openLogin),
                    for: .touchUpInside)
        return b
    }

    /// 右上角**输入法状态胶囊** —— 两态，一个控件。
    ///
    /// | 态 | 长什么样 | 点了 |
    /// |---|---|---|
    /// | 已启用 | 玻璃胶囊 + **紫灯**（实心圆点）+「输入法 · 已启用」 | 进引导页（想改还能改） |
    /// | 未启用 | **accent 紫胶囊** + 空心点 +「设为输入法」 | 进引导页去启用 |
    ///
    /// 🚨🚨 **灯是紫的不是绿的**。Kevin 先说"小绿灯"、**当场自己更正成紫灯** ——
    ///    以最后那次为准（`feedback_latest_instruction_wins`）。
    ///    紫＝品牌色 `Skin.accent`，绿在这套配色里只用于"结构化英文"那一档。
    ///
    /// 🚨 **一个控件两种状态**，不做成两套 —— 两套就是两个配置点，改一处等于没改
    ///    （账号胶囊那条同款理由，那次是产品经理点名的）。
    /// 🚨 文案跟 PC 端同源（`L.home_ime_on` ← `pc/Strings.cs` 的 `main.ime.on`）。
    private func imeChip() -> UIView {
        let on = SetupViewController.keyboardAdded()
        let b = UIButton(type: .system)
        // 灯：已启用=实心，未启用=空心（用 SF Symbols 的两个同族图标，
        // 大小一致所以两态之间不会跳动）。
        let dot = UIImage(systemName: on ? "circle.fill" : "circle",
                          withConfiguration: UIImage.SymbolConfiguration(
                              pointSize: 8, weight: .bold))
        b.setImage(dot, for: .normal)
        b.setTitle("  " + (on ? L.home_ime_on : L.home_ime_off), for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13)
        if on {
            // 已启用：玻璃胶囊 + 紫灯 + 常规文字色 —— 它只是个状态，不抢注意力。
            b.backgroundColor = Skin.glassFill
            b.layer.borderWidth = 0.6
            b.layer.borderColor = Skin.glassStroke.cgColor
            b.tintColor = Skin.accent          // 灯
            b.setTitleColor(Skin.text, for: .normal)
        } else {
            // 未启用：整颗紫胶囊 —— 这是**要他去做的一件事**，该显眼。
            b.backgroundColor = Skin.accent
            b.layer.borderWidth = 0
            b.tintColor = .white
            b.setTitleColor(.white, for: .normal)
        }
        b.layer.cornerRadius = 18
        b.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        // 🚨 **点了干什么，两态不一样**：
        //    · 未启用 → 直接进引导页（他现在该做的就是去启用）
        //    · 已启用 → 弹开关（Kevin 09-04：「都不能放在那个输入法启用的
        //      右上角那个标里面吗？」—— 键盘语音待机原来在首页底部占一条，
        //      他嫌那条多余，收进这里）
        b.addTarget(self,
                    action: on ? #selector(tapImeChip) : #selector(openSetup),
                    for: .touchUpInside)
        imeChipBtn = b
        return b
    }

    /// 右上角那个标本身，留个引用好在待机状态变了时刷新它。
    private var imeChipBtn: UIButton?

    /// 点已启用态的输入法标 → 弹「键盘语音待机」开关。
    ///
    /// 🚨 为什么待机这个开关必须有、不能一删了之：iOS 禁止键盘扩展自己录音，
    ///    按麦克风时真正在录的是**主 App 在后台**，而 iOS 只让"正在录音/播放"
    ///    的 App 留在后台 —— 所以必须由他显式打开、也随时能关掉。
    ///    见 `App/KbVoiceHost.swift`。
    /// 🚨 用 actionSheet 而不是直接 toggle：这个开关**开着会耗电**，
    ///    点一下就静默切换会让他不知道自己开了什么。
    @objc private func tapImeChip() {
        let on = KbVoiceHost.shared.standby
        let a = UIAlertController(title: L.home_ime_on,
                                  message: L.kb_standby_why,
                                  preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(
            title: on ? L.kb_standby_on : L.kb_standby_off,
            style: on ? .destructive : .default) { [weak self] _ in
                self?.toggleStandby()
                self?.paintImeChip()
            })
        a.addAction(UIAlertAction(title: L.home_set_ime, style: .default) {
            [weak self] _ in self?.openSetup()
        })
        a.addAction(UIAlertAction(title: L.cancel, style: .cancel))
        // 🚨 iPad 上 actionSheet 不给 anchor 会直接崩（09-04 已踩过两次）。
        a.popoverPresentationController?.sourceView = imeChipBtn ?? view
        a.popoverPresentationController?.sourceRect =
            (imeChipBtn ?? view).bounds
        present(a, animated: true)
    }

    /// 待机状态变了 → 刷新右上角那个标（原来刷的是底部那条，那条已经撤了）。
    private func paintImeChip() {
        guard let b = imeChipBtn, SetupViewController.keyboardAdded() else { return }
        // 待机开着时给灯换成"正在待机"的样子 —— 他要能一眼看出来它开着。
        let on = KbVoiceHost.shared.standby
        b.setImage(UIImage(systemName: on ? "mic.circle.fill" : "circle.fill",
                           withConfiguration: UIImage.SymbolConfiguration(
                               pointSize: on ? 13 : 8, weight: .bold)),
                   for: .normal)
    }

    /// 右上角「设置」胶囊。
    private func gearChip() -> UIView {
        let b = UIButton(type: .system)
        b.setTitle(L.prefs_entry, for: .normal)
        b.setTitleColor(Skin.dim, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 13)
        b.backgroundColor = Skin.glassFill
        b.layer.cornerRadius = 18
        b.layer.borderWidth = 0.6
        b.layer.borderColor = Skin.glassStroke.cgColor
        b.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        b.addTarget(self, action: #selector(openPrefs), for: .touchUpInside)
        return b
    }

    /// 主 CTA：88 高、圆角 18、渐变紫、17pt 粗体。
    private func cta() -> UIView {
        // 🚨🚨 **方案丙**（Kevin 2026-09-05：「用丙吧，我也觉得丙好一点」）：
        //    圆底图标 + 主副两行 + 右箭头。
        //
        // 🚨 前提是他先说了「还是我们现在的方案最好」—— **整屏结构不动，
        //    只改这个块的内部**：88 的高度、18 的圆角、渐变紫底、在 root 里的位置，
        //    一个像素都不许变。（2.1 先前那三个重构方案已作废，别照着做。）
        //
        // 🚨 **块内不许再套一层按钮**（2.1 判据 4）：图标/文字/箭头全部
        //    不吃触摸，整块还是这一颗 UIButton 在响应。
        //    套第二层按钮会变成"点到图标没反应、点到空白才有反应"。
        let b = UIButton(type: .custom)
        b.setBackgroundImage(Theme.purpleGrad, for: .normal)
        b.layer.cornerRadius = 18
        b.clipsToBounds = true
        b.heightAnchor.constraint(equalToConstant: 88).isActive = true
        // 🚨 给端到端测试一个**按类型的锚点**：按文字找会随文案改动而失效，
        //    而文案是常改的（`L.home_try_speak` 改过好几次）。
        b.accessibilityIdentifier = "app.try"
        b.addTarget(self, action: #selector(openSpeak), for: .touchUpInside)

        // ── 块内三件：圆底图标 · 主副两行 · 右箭头 ───────────────
        let side: CGFloat = 88 * 0.36        // 规格：圆径 ≈ 块高的 36%
        let disc = UIView()
        disc.backgroundColor = UIColor.white.withAlphaComponent(0.18)
        disc.layer.cornerRadius = side / 2
        disc.isUserInteractionEnabled = false
        disc.translatesAutoresizingMaskIntoConstraints = false
        b.addSubview(disc)

        // 🚨 话筒用 Theme.micGlyph 那**唯一一个**比例来源，不自己再乘系数
        //    （今天刚因为"同一个 0.6 乘了两遍"被他点名说话筒太小）。
        let mic = UIImageView(image: Theme.micGlyph(side))
        mic.tintColor = .white
        mic.contentMode = .scaleAspectFit
        mic.isUserInteractionEnabled = false
        mic.translatesAutoresizingMaskIntoConstraints = false
        disc.addSubview(mic)

        let t1 = UILabel()
        t1.text = L.home_try_speak
        t1.font = .systemFont(ofSize: 17, weight: .bold)
        t1.textColor = .white
        t1.translatesAutoresizingMaskIntoConstraints = false

        let t2 = UILabel()
        t2.text = L.home_try_sub
        t2.font = .systemFont(ofSize: 13)
        t2.textColor = UIColor.white.withAlphaComponent(0.88)
        t2.translatesAutoresizingMaskIntoConstraints = false

        let chev = UILabel()
        chev.text = "›"
        chev.font = .systemFont(ofSize: 24, weight: .light)
        chev.textColor = UIColor.white.withAlphaComponent(0.75)
        chev.isUserInteractionEnabled = false
        chev.translatesAutoresizingMaskIntoConstraints = false
        b.addSubview(chev)

        // 🚨 主副两行装进一个 stack **整体**垂直居中（2.1 判据 2：上下留白差 ≤4pt）。
        //    两行各自 centerY 的话，行高一变就不再居中了。
        // 🚨 alignment = .leading 就是判据 1（两行左沿同一个 x）——
        //    靠 stack 保证，而不是给两行各写一条 leading 约束然后祈祷它们一致。
        let col = UIStackView(arrangedSubviews: [t1, t2])
        col.axis = .vertical
        col.spacing = 2
        col.alignment = .leading
        col.isUserInteractionEnabled = false
        col.translatesAutoresizingMaskIntoConstraints = false
        b.addSubview(col)

        NSLayoutConstraint.activate([
            disc.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: 20),
            disc.centerYAnchor.constraint(equalTo: b.centerYAnchor),
            disc.widthAnchor.constraint(equalToConstant: side),
            disc.heightAnchor.constraint(equalToConstant: side),
            mic.centerXAnchor.constraint(equalTo: disc.centerXAnchor),
            mic.centerYAnchor.constraint(equalTo: disc.centerYAnchor),
            mic.widthAnchor.constraint(equalTo: disc.widthAnchor),
            mic.heightAnchor.constraint(equalTo: disc.heightAnchor),

            col.leadingAnchor.constraint(equalTo: disc.trailingAnchor, constant: 14),
            col.centerYAnchor.constraint(equalTo: b.centerYAnchor),
            col.trailingAnchor.constraint(lessThanOrEqualTo: chev.leadingAnchor,
                                          constant: -10),

            chev.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -20),
            chev.centerYAnchor.constraint(equalTo: b.centerYAnchor),
        ])
        // 🚨 面对面翻译**挪成长按**：安卓首页上没有它这一条，而 iOS 这边
        //    不能就这么让它没有入口 —— 安卓的 `FaceToFaceActivity` 已经因为
        //    "建了但没有任何 startActivity 指向它"而点不进去（09-04 查出，已报 2.3）。
        //    长按是临时安置，**入口该放哪由 2.1 定**，已列进给他们的问题里。
        b.addGestureRecognizer(UILongPressGestureRecognizer(
            target: self, action: #selector(onCtaLongPress(_:))))
        return b
    }

    @objc private func onCtaLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        openFaceToFace()
    }

    /// 输入法槽：固定 52，两档同槽。
    ///
    /// | 档 | 条件 | 长什么样 |
    /// |---|---|---|
    /// | A | 键盘还没在系统里启用 | 紫 28% 实块「设为当前输入法」 |
    /// | C（iOS 特有）| 已启用 | 「键盘语音待机」开关 |
    ///
    /// 🚨🚨 **安卓那个档 B（「启用了但不是默认」）在 iOS 上做不出来** ——
    ///    苹果不给容器 App 任何「我是不是当前默认键盘」的 API。
    ///    `keyboardAdded()` 查的是 `UITextInputMode.activeInputModes`，
    ///    答的是"有没有被启用"，**不是**"是不是当前这一个"。
    ///    所以这里只有两档。硬凑第三档就得靠猜，而猜错的表现是
    ///    "明明设好了它还催我去设" —— 那比少一档糟得多。
    /// 底部那条槽 —— **2026-09-04 整条撤掉**（Kevin 拍板）。
    ///
    /// 🚨🚨 **两个分支都撤，不是只撤一个**。我上一版只撤了「设为当前输入法」
    ///    那一半，而**键盘已启用时这条槽显示的是「键盘语音待机」开关**，
    ///    那一半原样留着 —— 于是我跟他说「删了」，他打开一看还在。
    ///    他的原话：「你自己不是说已经删了吗？就没有删，骗我呀」。
    ///    **「删掉一个有分支的东西」要把每个分支都点一遍**，
    ///    只看自己改的那一支就等于没删。
    ///
    ///    两个功能的新去处（都在右上角那个标里，他指定的）：
    ///      · 设为输入法 → `imeChip()` 未启用态，点了进引导页
    ///      · 键盘语音待机 → `imeChip()` 已启用态，点了弹开关
    ///
    /// 🚨 **槽位本身留着、保持 52 高**（`isHidden` 而不是从栈里移除）：
    ///    移除的话「随手翻译」会往下掉 52pt。安卓那边为同一个理由
    ///    用 `INVISIBLE` 不用 `GONE`。
    private func imeSlot() -> UIView {
        let slot = UIView()
        slot.heightAnchor.constraint(equalToConstant: 52).isActive = true
        slot.isHidden = true
        return slot
    }

    private func fill(_ box: UIView, with v: UIView, inset: CGFloat = 0) {
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isUserInteractionEnabled = v is UIControl
        box.addSubview(v)
        NSLayoutConstraint.activate([
            v.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            v.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: inset),
            v.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -inset),
        ])
        if v is UIControl {
            v.topAnchor.constraint(equalTo: box.topAnchor).isActive = true
            v.bottomAnchor.constraint(equalTo: box.bottomAnchor).isActive = true
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    /// 打开注册/登录页。
    ///
    /// 🚨 方法名以前叫 `loginSoon` —— 那是"下个版本再说"时代留下的，
    ///    现在它跳的是真登录页，名字却还在说"soon"，读代码的人会误判。
    @objc private func openLogin() {
        // 🚨 以前这里只弹一句"下个版本"。后端 2026-08-25 已经全链路跑通
        //    （Supabase users 表 + 阿里云短信），Kevin：「注册登录已经 OK 了…
        //    那就把注册登录给做实吧」。
        navigationController?.pushViewController(LoginViewController(),
                                                 animated: true)
    }

    /// 单词本：还没做，但**给真反馈**，不做纯装饰按钮
    /// （`gate_no_dead_feature.py` 会拦装饰按钮）。
    /// 左上角小人 -> 账户页。
    /// 🚨 **不能复用 `PrefsViewController.tapAccount`** —— 那是另一个类的方法，
    ///    `#selector` 只在**当前类**里找。第一版直接写了 `tapAccount`，
    ///    报 `cannot find 'tapAccount' in scope`。
    @objc private func openAccount() {
        // 同一个入口：登录了进账户页，没登录进登录页。
        navigationController?.pushViewController(
            Auth.loggedIn ? AccountViewController() : LoginViewController(),
            animated: true)
    }

    /// 登录引导。**一个函数管所有需要登录的入口**，理由写清楚。
    ///
    /// 产品经理 2026-08-26 的判据：
    ///   · 出引导，**并说明为什么要登录**（只弹登录不说理由 = FAIL）
    ///   · **退得回去**，退回后随手翻译照样能用（N1-e）
    ///
    /// 🚨 文案是他给的，**照抄，不许自己发挥**：
    ///   · 不许出现"还能免费用 N 次" —— 核心翻译**不限次**，那句是假的
    ///   · 不许写"解锁高级功能" —— 要说清解锁的是**哪个具体功能**
    ///
    /// 🚨 返回 true = 已登录、调用方接着做自己的事；
    ///    返回 false = 已经弹了引导，调用方**必须直接返回**。
    // 🚨 实现搬到了下面的 `UIViewController` 扩展（**单一实现**）——
    //    单词本入口 2026-09-04 挪进设置页后，首页和设置都要用同一道门；
    //    两处各写一份就是「同一规矩两处实现」，迟早走散。


    @objc private func openSetup() {
        guard loginGate(L.login_gate_ime) else { return }
        navigationController?.pushViewController(SetupViewController(),
                                                 animated: true)
    }

    // MARK: - 键盘语音待机

    /// 首页那条开关。**只有装了键盘才建**，所以是 optional。
    // 🚨 `standbyBar`（底部那条待机长条）2026-09-04 随整条槽一起撤了。
    //    刷新对象改成右上角那个标 —— 见 `imeChipBtn` / `paintImeChip()`。
    //    **旧名字不留空壳**：留着会让下一个人以为底部还有那条。

    /// 待机状态变了要刷新界面 —— **现在刷的是右上角那个标**。
    /// 🚨 名字沿用 `paintStandby` 是为了不动它的 5 个调用点；
    ///    它现在只是转调 `paintImeChip()`。
    private func paintStandby() { paintImeChip() }

    /// 长按「键盘语音」→ 后台起录自测。
    ///
    /// 🚨 这是**诊断件**，用完要能一键关掉 —— 它开着会让 App 整夜不休眠。
    ///    所以每一屏都写清楚它现在是开是关、收了多少条。
    @objc private func longPressStandby(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let p = BgRecProbe.shared
        let a = UIAlertController(
            title: "后台起录自测",
            message: p.running
                ? "正在跑，已收 \(p.count) 条。把手机放着别管，过几小时回来看。"
                // 🚨🚨 **隐私报告那条必须提前说**（产品经理 2026-08-28 提的，
                //    我没想到）：跑一夜 ≈ 140 次起录，iOS 的「App 隐私报告」里
                //    会出现 140 条麦克风访问记录。他第二天要是自己翻到那一页，
                //    看到的是"Transless 整夜反复开麦克风" ——
                //    **而原因是我们自己设的测试。**
                //    事后解释挽不回信任，只能事前说。
                : "打开后每 5 分钟自动试一次「在后台能不能起录」，"
                  + "每次开麦一秒就关，**录到的声音一个字节都不留**。\n\n"
                  + "⚠️ 跑一夜大约 140 次，所以 iOS 的「设置 → 隐私与安全性 → "
                  + "App 隐私报告」里会看到 140 条 Transless 访问麦克风的记录 —— "
                  + "那是这个自测，不是它在偷听。\n\n"
                  + "它会让 App 一直待机（不再 10 分钟自动关），所以会耗电。\n"
                  + "已收 \(p.count) 条。",
            preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(
            title: p.running ? "停止自测" : "开始自测",
            style: p.running ? .destructive : .default) { [weak self] _ in
                p.running ? p.stop() : p.start()
                self?.paintStandby()
            })
        a.addAction(UIAlertAction(title: "看结果并复制", style: .default) { _ in
            let text = p.report()
            UIPasteboard.general.string = text
            let b = UIAlertController(title: "已复制", message: text,
                                      preferredStyle: .alert)
            b.addAction(UIAlertAction(title: L.btn_got_it, style: .default))
            self.present(b, animated: true)
        })
        a.addAction(UIAlertAction(title: "清空样本", style: .destructive) { _ in
            p.clear()
        })
        a.addAction(UIAlertAction(title: L.login_gate_later, style: .cancel))
        // iPad 上 actionSheet 必须给锚点，否则直接崩
        a.popoverPresentationController?.sourceView = imeChipBtn ?? view
        a.popoverPresentationController?.sourceRect =
            (imeChipBtn ?? view).bounds
        present(a, animated: true)
    }

    @objc private func toggleStandby() {
        if KbVoiceHost.shared.standby {
            KbVoiceHost.shared.setStandby(false)
            paintStandby()
            return
        }
        // 🚨 麦克风没授权就别打开 —— 打开了也只是占着一个起不来的引擎，
        //    而开关亮着，用户会以为好了。
        if Voice.permissionState() != nil {
            navigationController?.pushViewController(SetupViewController(),
                                                     animated: true)
            return
        }
        // 🚨 **代价先说清楚再打开**：麦克风指示灯会一直亮、会耗电。
        //    不说就打开，等于背着他占了麦克风。
        let a = UIAlertController(title: L.kb_standby_off,
                                  message: L.kb_standby_why,
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: L.btn_got_it, style: .default) {
            [weak self] _ in
            KbVoiceHost.shared.setStandby(true)
            self?.paintStandby()
        })
        a.addAction(UIAlertAction(title: L.login_gate_later, style: .cancel))
        present(a, animated: true)
    }

    @objc private func openPrefs() {
        navigationController?.pushViewController(PrefsViewController(),
                                                 animated: true)
    }

    @objc private func openSpeak() {
        navigationController?.pushViewController(MainViewController(),
                                                 animated: true)
    }

    @objc private func openFaceToFace() {
        navigationController?.pushViewController(FaceToFaceViewController(),
                                                 animated: true)
    }
}

// MARK: - ③ 引导页（对齐安卓 SetupActivity）

/// 安卓是三步带**状态检测**：每步显示「去开启」或「已完成」。
///
/// 🚨 **步骤内容按 iOS 的实际要求写，不照抄安卓的字面**
///    （这是 2026-08-22 定的口径：「要对齐的是观感和语言，不是流程」）。
///    安卓第 ③ 步是"设为默认输入法"，iOS 根本没有这个概念 ——
///    照抄会写出一句做不到的指引，比不写还糟。
///    iOS 的三步是：加键盘 → 允许完全访问 → 允许麦克风。
/// 导航栏统一样式。**单一配置点** —— 每个页面各设一遍必然漏一处。
///
/// 🚨 Kevin 2026-08-25：「设置里面的字又是黑色的，根本看不清楚
///    『设置』这两个字。这个 UI 我都说了很多次了」。
///    根因是从来没设过 `UINavigationBar` 的样式：深色背景 +
///    系统默认的黑标题。不是某个页面写错，是整个 App 都没设。
enum NavStyle {
    static func apply() {
        let a = UINavigationBarAppearance()
        a.configureWithTransparentBackground()      // 背景交给页面的渐变
        a.titleTextAttributes = [
            .foregroundColor: Skin.text,
            .font: UIFont.systemFont(ofSize: 17, weight: .medium),
        ]
        a.largeTitleTextAttributes = [.foregroundColor: Skin.text]
        let bar = UINavigationBar.appearance()
        bar.standardAppearance = a
        bar.scrollEdgeAppearance = a
        bar.compactAppearance = a
        // 返回箭头也得是浅色，否则同样看不见
        bar.tintColor = Skin.text
    }
}

final class SetupViewController: UIViewController {

    // 🚨 子页要显示导航栏（首页是隐藏的）—— 不然进来就出不去。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        onAppear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.viewControllers.count == 1 {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }

    /// 子类各自的「回到前台要刷新什么」。默认什么都不做。

    private // 🚨 四元组：(整行, 数字徽章, **标题**, 右侧状态)。
    //    标题是中-4 新加的 —— 原来调用方靠「第一个不是状态的 UILabel」
    //    去猜，猜到的是数字徽章。**身份由构造它的人给出，不靠位置。**
    var rows: [(UIView, UILabel, UILabel, UILabel)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.home_set_ime

        let stack = UIStackView()
        stack.axis = .vertical
        // 行间 15、左右 21，照安卓 SetupActivity
        //（`lp.setMargins(0,0,0,dp(15))` / `root.setPadding(dp(21),0,dp(21),0)`）
        stack.spacing = 15
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 21),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -21),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
        ])

        // 🚨 这里**不再放大标题**。导航栏上已经写着「设为当前输入法」，
        //    正文再来一个一模一样的，白占一屏高度还削弱了真正的步骤层级
        //    （Grok 评审：「用户第一眼看到两个相同标题，信息冗余」）。

        for (n, t) in [("1", L.ios_step_add),
                       ("2", L.ios_step_full),
                       ("3", L.step_mic)] {
            let (row, num, title, state) = makeRow(n, t)
            rows.append((row, num, title, state))
            stack.addArrangedSubview(row)
        }
        // 第 2 项底下补一句说明 —— 那一项永远不会变绿，得说清为什么，
        // 否则他会一直以为没设成功（他 2026-08-25 就是这么卡住的）。
        let fullNote = UILabel()
        fullNote.text = L.full_note
        fullNote.font = .systemFont(ofSize: 12)
        fullNote.textColor = Skin.dim
        fullNote.numberOfLines = 0
        stack.insertArrangedSubview(fullNote,
                                    at: stack.arrangedSubviews.count)

        // 🚨🚨 第 3 步要**可点，而且真的去请求麦克风权限**（交叉审查 H2）。
        //    iOS 只有在 App 请求过一次之后，「设置 → Transless」里才会
        //    出现麦克风开关。我上一版把 requestRecordPermission 删干净了，
        //    于是点「去设置」进去根本没有那个开关，权限永远拿不到 ——
        //    键盘按麦克风必走失败分支。
        //    `project.yml` 自己写着「键盘扩展弹不出系统权限框，
        //    必须由容器 App 先要过一次」，我删的正是那一次。
        let micTap = UITapGestureRecognizer(target: self,
                                            action: #selector(askMic))
        rows[2].0.isUserInteractionEnabled = true
        rows[2].0.addGestureRecognizer(micTap)
        // 🚨🚨🚨 **第 1、2 步一直没有点击目标 —— 它们从来就点不动。**
        //    Kevin 2026-08-31：「我在 Transless 主 App 里面为什么不能够点
        //    『设为当前输入法并启用』呢？你这个功能又给我作废了呀！」
        //    查下来只有 `rows[2]`（麦克风）挂了手势，另外两行**一个都没有**。
        //    状态显示写得再漂亮，点不动就等于没有。
        //    两步都是去系统设置里做（添加键盘 / 允许完全访问），所以都开设置。
        for i in [0, 1] {
            let tap = UITapGestureRecognizer(target: self,
                                             action: #selector(openSystemSettings))
            rows[i].0.isUserInteractionEnabled = true
            rows[i].0.addGestureRecognizer(tap)
        }
        // 🚨 让它**看起来能点** —— 但**不能给整行换底色**。
        //    Kevin 2026-08-25 说「允许录音那个我就是找不到啊」（这一行一直
        //    可点，他是自己撞对的）；我上一版给整行加了底色，
        //    Grok 评审当场指出「三张卡片颜色不一致，会让人误以为步骤 3
        //    是当前高亮/已完成状态」。两条都对。
        //    正解：**三张卡片底色一律相同**，"能点"由右边那个
        //    「去启用 ›」自己表达 —— 把它做成按钮的样子（见 refresh 里
        //    对 `.some(false)` 的处理）。
        // 🚨 复审 中-3：中-4 把元组改成四元组之后，`.2` 的含义
        //    从「状态」变成了「标题」，这几行没跟着改 —— 
        //    引导页第 3 步的**标题**被做成了居中+圆角。
        // 🚨 而中-4 的本意就是**消灭按位置猜身份**，
        //    我却留了一个还在按位置猜的调用点。→ 解构出来用名字。
        let (_, _, _, micState) = rows[2]
        micState.layer.cornerRadius = 9
        micState.clipsToBounds = true
        micState.textAlignment = .center
        // 🚨 状态标签**不许被压缩**。加了内边距之后它变宽了，
        //    横向 stack 默认按 hugging 分配，结果标题把它挤成「去启…」
        //    「请手动…」（截图上看到的）。让标题那边先缩。
        for (_, _, title, lab) in rows {
            lab.setContentCompressionResistancePriority(.required, for: .horizontal)
            lab.setContentHuggingPriority(.required, for: .horizontal)
            // 🚨 中-4：**用 `makeRow` 交出来的真身份**，不再按顺序猜。
            //    原来那句 `first(where: 是 UILabel && !== lab)` 命中的是
            //    数字徽章 —— 这两行一直挂在一个 28×28 的固定尺寸视图上。
            do {
                // 🚨 复审 中-2：**这行 `= 2` 已删**。`makeRow` 里标题本来就是
                //    `numberOfLines = 0`（永不截断）——上一轮它打在数字徽章上
                //    所以没生效；中-4 接到真标题上之后，**0 被 2 覆盖了**，
                //    从"永不截断"变成"超过两行尾部截断"，
                //    跟它自己那句注释正好相反。**修 bug 修出来的新 bug。**
                title.setContentCompressionResistancePriority(.defaultLow,
                                                              for: .horizontal)
            }
        }

        let go = UIButton(type: .system)
        go.setTitle(L.act_settings, for: .normal)
        go.setTitleColor(.white, for: .normal)
        go.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        go.backgroundColor = Skin.accent
        go.layer.cornerRadius = 12
        go.heightAnchor.constraint(equalToConstant: 52).isActive = true
        go.addTarget(self, action: #selector(openSystemSettings),
                     for: .touchUpInside)
        stack.setCustomSpacing(26, after: rows.last!.0)
        stack.addArrangedSubview(go)

        // 🚨 这里**没有** AI 免责声明。
        //    「译文由 AI 生成，发送前请自行核对」原来挂在这一页 ——
        //    而这一页是"怎么把键盘装上"的引导，跟译文毫无关系，
        //    用户看到会想"我现在在翻译什么？"（Grok 评审指出，属实）。
        //    那句话该出现在**真正出译文的地方**，不在这儿。
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    func onAppear() {
        refresh()      // 从系统设置回来要重新查状态
    }

    /// 🚨 每一步的状态**真的去查**，不是写死"未完成"。
    ///    安卓那边就是查出来的（权限 / 已启用输入法 / 是否默认）。
    private func refresh() {
        let added = Self.keyboardAdded()
        // 🚨 权限只从 `Voice.micPermission()` 取（唯一咽喉，见那个函数上的说明）。
        let mic = Voice.micPermission() == .granted
        // 🚨 「完全访问」在容器 App 里**查不到** —— 那是键盘扩展侧的状态，
        //    系统没给容器 App 这个接口。所以这一项如实显示"去设置里开"，
        //    不假装知道。宁可少报一个状态，也不报一个可能是错的。
        // 🚨 第 2 项是 `nil`：**查不到**，不是"未完成"。
        //    见下面 `case .none` 的呈现 —— 不能跟未完成长一个样。
        let states: [Bool?] = [added, nil, mic]
        for (i, s) in states.enumerated() {
            let (_, num, _, lab) = rows[i]   // (行, 徽章, 标题, 状态)
            switch s {
            case .some(true):
                lab.text = L.done_enabled
                lab.textColor = Skin.ok
                // 🚨 每个分支都要**把底色清掉**，不能只在设的那个分支里管。
                //    只在一处设、别处不清，状态一变就留着上一次的底
                //    —— 那种错只在"来回切几次"时才现形。
                lab.backgroundColor = .clear
                num.backgroundColor = Skin.ok
            case .some(false):
                lab.text = "  " + L.act_enable + "  "
                lab.textColor = Skin.text
                // 🚨 「能点」由这个小标签自己表达（浅底 + 亮字），
                //    而不是给整行换底色 —— 后者会破坏三张卡片的一致性。
                lab.backgroundColor = Skin.accent.withAlphaComponent(0.35)
                lab.layer.cornerRadius = 9
                lab.clipsToBounds = true
                num.backgroundColor = Skin.accent2
            case .none:
                // 🚨 **不摆成"待办"的样子**。Kevin 2026-08-25：
                //    「第二个『允许完全访问』，我设置了之后，它还是显示
                //     要我去设置啊，没有设好啊」——
                //    他设好了，是我这一行永远显示「去设置 ›」在误导他。
                // 🚨 但也不能是个光秃秃的「—」：其他两步写着「去启用 ›」，
                //    这里突然一个破折号，"已完成 / 不可点 / 状态未知"分不出来
                //    （Grok 评审指出）。写清楚**它是什么状态**。
                lab.text = L.act_manual
                lab.textColor = Skin.dim
                lab.backgroundColor = .clear
                num.backgroundColor = Skin.accent2
            }
        }
    }

    /// 我们的键盘有没有被添加到系统键盘列表里。
    static func keyboardAdded() -> Bool {
        let mine = (Bundle.main.bundleIdentifier ?? "") + ".keyboard"
        return UITextInputMode.activeInputModes.contains {
            ($0.value(forKey: "identifier") as? String)?.hasPrefix(mine) ?? false
        }
    }

    /// - Returns: `(整行, 数字徽章, 标题, 右侧状态)`
    ///
    /// 🚨🚨 **标题必须由这里交出去，别让调用方去猜。**
    ///    原来只回 `(row, num, state)`，调用方用
    ///    `first(where: { 是 UILabel && !== lab })` 找标题 ——
    ///    **命中的是 `num`**（它也是 UILabel），于是"挤不下就换行"
    ///    挂在了 28×28 的数字徽章上，等于什么都没做，
    ///    窄屏上被截断的仍然是标题。
    ///    **按位置/顺序假设「这是谁」——他为这条骂过我好几次。**
    private func makeRow(_ n: String, _ text: String)
        -> (UIView, UILabel, UILabel, UILabel) {
        let row = UIStackView()
        row.axis = .horizontal
        // 🚨 数字和文字之间 13，照安卓 `nlp.setMargins(0, 0, dp(13), 0)`
        row.spacing = 13
        row.alignment = .center
        // 🚨🚨 每一行是**一张卡片**，`padding(18,20,18,20)` ——
        //    照安卓 `SetupActivity`：`row.setPadding(dp(18), dp(20), dp(18), dp(20))`。
        //    iOS 原来是裸行、只有 12 的 spacing，挤成一坨
        //    （Kevin 2026-08-25：「这个界面太丑了，怎么会这么密呢？
        //     你看一下安卓怎么设计的吧，我不是让你对着安卓来做吗？」）。
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 20, left: 18,
                                         bottom: 20, right: 18)
        row.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        row.layer.cornerRadius = 14

        let num = UILabel()
        num.text = n
        num.textColor = .white
        num.font = .systemFont(ofSize: 14, weight: .medium)
        num.textAlignment = .center
        num.backgroundColor = Skin.accent2
        num.layer.cornerRadius = 14
        num.clipsToBounds = true
        num.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            num.widthAnchor.constraint(equalToConstant: 28),
            num.heightAnchor.constraint(equalToConstant: 28),
        ])
        row.addArrangedSubview(num)

        let t = UILabel()
        t.text = text
        t.textColor = Skin.text
        t.font = .systemFont(ofSize: 15)
        t.numberOfLines = 0
        row.addArrangedSubview(t)

        let state = UILabel()
        state.font = .systemFont(ofSize: 13)
        state.textColor = Skin.dim
        state.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(state)
        return (row, num, t, state)
    }

    @objc private func openSystemSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(u)
        }
    }

    /// 点第 3 步：**真的请求麦克风权限**。
    ///
    /// 🚨 只有 `.denied`（他之前拒过）时才退回打开系统设置 ——
    ///    `.undetermined` 时必须调 request，否则系统设置里
    ///    压根不会出现那个开关。
    @objc private func askMic() {
        let st = Voice.micPermission()
        switch st {
        case .undetermined:
            Voice.requestMic { _ in
                DispatchQueue.main.async { self.refresh() }
            }
        case .denied:
            openSystemSettings()
        default:
            refresh()
        }
    }
}

// MARK: - ④ 设置（对齐安卓 PrefsActivity 的四组）

final class PrefsViewController: UIViewController {

    // 🚨 子页要显示导航栏（首页是隐藏的）—— 不然进来就出不去。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        onAppear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.viewControllers.count == 1 {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }

    /// 子类各自的「回到前台要刷新什么」。默认什么都不做。

    private let list = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        UI.paintBg(self)
        title = L.prefs_title

        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sv)
        list.axis = .vertical
        list.translatesAutoresizingMaskIntoConstraints = false
        sv.addSubview(list)
        NSLayoutConstraint.activate([
            sv.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            sv.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            sv.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            sv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            list.topAnchor.constraint(equalTo: sv.topAnchor),
            list.leadingAnchor.constraint(equalTo: sv.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: sv.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: sv.bottomAnchor),
            list.widthAnchor.constraint(equalTo: sv.widthAnchor),
        ])
        build()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    func onAppear() {
        build()      // 状态可能变了（比如刚去加了键盘）
    }

    private func build() {
        list.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // ① 输入法
        list.addArrangedSubview(group(L.prefs_g_ime))
        let on = SetupViewController.keyboardAdded()
        // 🚨 「账户」放**第一行** —— Kevin：「设置里应该有个账户栏目，
        //    能看到我是用哪个账户登录的」。
        //    这里显示**完整账号**（跟首页那行昵称不同）：
        //    设置页就是查看账户的地方。
        list.addArrangedSubview(row(
            L.account_title,
            Auth.account.isEmpty ? L.account_none : Auth.account,
            #selector(tapAccount)))
        list.addArrangedSubview(row(L.home_set_ime,
                                    on ? L.prefs_ime_on : L.prefs_ime_off,
                                    #selector(openSetup)))
        // 🚨 **单词本从首页挪进设置**（Kevin 2026-09-04 四 Tab 需求变更点 2：
        //    「单词本不是最 key 的，最 key 的是常用词。所以单词本放设置里」）。
        //    首页那条长条已同步去掉 —— **两处只能留一处**，不然又是同一入口两个地方。
        list.addArrangedSubview(row(L.home_wordbook, nil,
                                    #selector(openWordbookFromPrefs)))

        // ② 偏好
        list.addArrangedSubview(group(L.prefs_g_pref))
        list.addArrangedSubview(row(L.lang_title, Lang.label(Lang.current),
                                    #selector(pickLanguage)))

        // ③ 诊断
        list.addArrangedSubview(group(L.prefs_g_diag))
        list.addArrangedSubview(row(L.rec_log_title, L.prefs_diag_sub,
                                    #selector(showRecLog)))

        // ④ 关于
        list.addArrangedSubview(group(L.prefs_g_about))
        let ver = (Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                   as? String) ?? "?"
        // Grok ⑦：「20260825.467」纯日期+build 号，对普通用户毫无意义，
        //         像内部调试信息。变体模式下显示成「版本 467」。
        let build = (Bundle.main.infoDictionary?["CFBundleVersion"]
                     as? String) ?? ver
        list.addArrangedSubview(row(L.prefs_about,
                                    "版本 " + build, nil))
        // 🚨 安卓的「检查更新」是连他局域网那台机下载 APK 的。
        //    **iOS 上不存在这条路** —— 苹果不允许 App 自己装包。
        //    所以这一项如实说明走 TestFlight，不做一个按了没反应的假按钮。
        list.addArrangedSubview(row(L.prefs_check_update, L.ios_update_note,
                                    nil))
        // 🚨 隐私政策入口。**AI 生成披露从产品界面移走之后，这一条是必需的**
        //    —— 条款 8.1 要的是「向终端用户明确披露」，
        //    藏在一个够不着的文档里不叫披露。
        list.addArrangedSubview(row(L.prefs_privacy, nil,
                                    #selector(openPrivacy)))
    }

    /// 分组标题（带上下留白）。
    ///
    /// 🚨🚨 **原来 `return t`（那个 label），留白从来没生效过。**
    ///    它给 `box` 建了 16/8 的约束，然后返回**里面那个 label**；
    ///    label 被 `addArrangedSubview` 加进列表时就脱离了 `box`，
    ///    那三条约束随即作废 —— `_ = w` 是它的墓碑。
    ///    **写了约束 ≠ 约束生效**：约束挂在谁身上、谁被加进视图树，是两件事。
    private func group(_ s: String) -> UIView {
        let t = UILabel()
        t.text = s
        t.font = .systemFont(ofSize: 12)
        // 安卓那边是 argb(0xB0, 0x8B, 0x7F, 0xB0)
        t.textColor = UIColor(red: 0x8B / 255.0, green: 0x7F / 255.0,
                              blue: 0xB0 / 255.0, alpha: 0xB0 / 255.0)
        t.translatesAutoresizingMaskIntoConstraints = false
        let box = UIView()
        box.addSubview(t)
        NSLayoutConstraint.activate([
            t.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 6),
            t.topAnchor.constraint(equalTo: box.topAnchor, constant: 16),
            t.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
        ])
        return box
    }

    private func row(_ title: String, _ sub: String?,
                     _ action: Selector?) -> UIView {
        let b = UIControl()
        b.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        b.layer.cornerRadius = 12
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true

        let t = UILabel()
        t.text = title
        t.textColor = Skin.text
        // 字号照安卓 PrefsActivity：标题 15.5、副标题 11.5
        t.font = .systemFont(ofSize: 15.5)
        let s = UILabel()
        s.text = sub
        // Grok ⑥：副标题在深紫底上对比度偏低。`Skin.sub` 在变体模式下更亮。
        s.textColor = Skin.sub
        s.font = .systemFont(ofSize: 11.5)
        s.numberOfLines = 0
        let col = UIStackView(arrangedSubviews: sub == nil ? [t] : [t, s])
        col.axis = .vertical
        col.spacing = 3
        col.isUserInteractionEnabled = false
        col.translatesAutoresizingMaskIntoConstraints = false
        b.addSubview(col)
        NSLayoutConstraint.activate([
            col.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: 16),
            col.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: -34),
            // 🚨 上下 15，照安卓 `r.setPadding(dp(16), dp(15), dp(16), dp(15))`。
            //    原来写的是 11 —— 每行矮 8pt，一整页看着就"密"
            //    （Kevin 2026-08-25：「里面的排版太密了，不像安卓那样会铺开一些」）。
            col.topAnchor.constraint(equalTo: b.topAnchor, constant: 15),
            col.bottomAnchor.constraint(equalTo: b.bottomAnchor, constant: -15),
        ])
        if let a = action {
            b.addTarget(self, action: a, for: .touchUpInside)
            let chev = UILabel()
            chev.text = "›"
            chev.textColor = Skin.dim
            chev.font = .systemFont(ofSize: 20)
            chev.translatesAutoresizingMaskIntoConstraints = false
            b.addSubview(chev)
            NSLayoutConstraint.activate([
                chev.trailingAnchor.constraint(equalTo: b.trailingAnchor,
                                               constant: -16),
                chev.centerYAnchor.constraint(equalTo: b.centerYAnchor),
            ])
        }
        let pad = UIView()
        pad.translatesAutoresizingMaskIntoConstraints = false
        pad.addSubview(b)
        NSLayoutConstraint.activate([
            b.leadingAnchor.constraint(equalTo: pad.leadingAnchor),
            b.trailingAnchor.constraint(equalTo: pad.trailingAnchor),
            b.topAnchor.constraint(equalTo: pad.topAnchor),
            // 行间距 9，照安卓 `lp.setMargins(0, 0, 0, dp(9))`
            b.bottomAnchor.constraint(equalTo: pad.bottomAnchor, constant: -9),
        ])
        return pad
    }

    /// 隐私政策地址。**只写这一处** —— 域名变了只改这儿。
    /// 🚨 必须定义在 `PrefsViewController` 里 —— 调用点在这个类的设置列表里。
    ///    上一版我按 `openSetup` 这个名字找锚点，结果插进了
    ///    `HomeViewController`（它也有同名方法），编译报
    ///    `cannot find 'openPrivacy' in scope`。
    ///    **「在哪儿定义」跟「定义什么」一样重要**（今天第三次栽在这上面）。
    private static let privacyURL = "https://transless.net/privacy.html"

    /// 账户行：登录了就退出登录，没登录就去登录。
    /// 设置页里的「单词本」入口（Kevin 09-04：单词本从 Tab/首页挪进设置）。
    ///
    /// 🚨 **行为跟首页那条一字不差**：`WordBookFeature.isLive` 为假时只说"还没上线"，
    ///    **一个字都不提登录** —— 门后是空的时候挂登录门＝骗一次注册（产品经理 08-28 定）。
    ///    上线后 `loginGate` 那道门自然生效（`gate_wordbook_copy.py` 要求它留成活代码）。
    @objc private func openWordbookFromPrefs() {
        guard WordBookFeature.isLive else {
            let a = UIAlertController(title: L.home_wordbook,
                                      message: L.home_wordbook_soon,
                                      preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "OK", style: .default))
            present(a, animated: true)
            return
        }
        guard loginGate(L.login_gate_wordbook) else { return }
        navigationController?.pushViewController(
            WordBookViewController(), animated: true)
    }

    @objc private func tapAccount() {
        // 🚨🚨 点这一行是**进账户页**，不是登出。
        //    Kevin 2026-08-26 真机撞到：「我在设置里点了一下『我的账户』，
        //    它居然直接把我退出了。登出应该有专门的『退出登录』按钮，
        //    而不是点一下账户就退出，重新发验证码登录非常繁琐。」
        //    —— 原来这里直接 `Auth.signOut()`，**一点就登出、连确认都没有**。
        //    退出登录现在在账户页底部，单独按钮 + 要确认。
        if Auth.loggedIn {
            navigationController?.pushViewController(AccountViewController(),
                                                     animated: true)
        } else {
            navigationController?.pushViewController(LoginViewController(),
                                                     animated: true)
        }
    }

    @objc private func openPrivacy() {
        guard let u = URL(string: Self.privacyURL) else { return }
        UIApplication.shared.open(u)
    }

    @objc private func openSetup() {
        navigationController?.pushViewController(SetupViewController(),
                                                 animated: true)
    }

    /// 界面语言：跟安卓一样弹窗选。
    @objc private func pickLanguage() {
        // 🚨 用 .alert 不用 .actionSheet：这是 iPad 应用
        //    （project.yml 的 TARGETED_DEVICE_FAMILY = "1,2"），
        //    actionSheet 不设 popover 的 sourceView 会直接闪退（审查 H4）。
        let a = UIAlertController(title: L.lang_title, message: nil,
                                  preferredStyle: .alert)
        for code in Lang.all {
            a.addAction(UIAlertAction(title: Lang.label(code),
                                      style: .default) { _ in
                Lang.set(code)
                // 🚨 选完要**整棵界面重建**，不是只刷这一页（交叉审查 H6）。
                //    只 build() 的话，标题、首页、其它页全还是旧语言，
                //    他会以为这个开关是坏的。
                //    安卓那边是 recreate() 整个 Activity。
                Self.rebuildUI()
            })
        }
        a.addAction(UIAlertAction(title: L.cancel, style: .cancel))
        present(a, animated: true)
    }

    /// 选完语言把整棵界面重建 —— 对齐安卓的 `recreate()`。
    ///
    /// 🚨 回到**首页**而不是停在设置页：所有页都要用新语言重建，
    ///    停在设置页的话上一层还是旧的。
    static func rebuildUI() {
        guard let w = UIApplication.shared.windows.first else { return }
        // 🚨 换语言重建也走**同一个工厂** —— 否则改成四 Tab 之后，
        //    平时是 Tab、一换语言就退回老首页（"规矩要按每个出口落地"）。
        let nav = UI.mainRoot()
        UIView.transition(with: w, duration: 0.25,
                          options: .transitionCrossDissolve,
                          animations: { w.rootViewController = nav })
    }

    /// 录音诊断：跟安卓一样，能看能复制。
    @objc private func showRecLog() {
        let text = RecLog.dump()
        let a = UIAlertController(title: L.rec_log_title,
                                  message: text.isEmpty ? L.rec_log_empty : text,
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: L.prefs_copy, style: .default) { _ in
            UIPasteboard.general.string = text
        })
        a.addAction(UIAlertAction(title: "OK", style: .cancel))
        present(a, animated: true)
    }
}


// ============================================================
// 🚨🚨 下面这一整段是**搬回来的**（交叉审查 H1）。
//
//    我上一版把它删了，理由是「干活的是键盘」——
//    而 iOS 键盘扩展只有 267 行（就一个麦克风 + 语气循环 + 退格），
//    **没有模式选择、没有目标语言、没有朗读**。
//    删掉之后全 App 找不到任何说话入口。
//
//    最难堪的是：文件头那段注释就是我上一次犯这个错时写的教训，
//    我写完又犯了一遍。**写下教训不等于避开它。**
//
//    在 iOS 键盘扩展补齐到跟安卓一样之前，这里是唯一能用的路，
//    别再删。要删先跑 `py ios/contract_test.py` —— 它会红。
// ============================================================

// MARK: - 主界面：一个大按钮

final class MainViewController: UIViewController {
    deinit { teardown() }


    // 🚨 子页要显示导航栏（首页是隐藏的）—— 不然进来就出不去。
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        onAppear()
    }

    /// 🚨 收尾放在这里，不放 `viewWillDisappear` —— 后者在**交互式侧滑一开始**
    ///    就会走到，他划一半松手弹回来，录音已经被掐掉了（复审 中-1）。
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || isBeingDismissed { teardown() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 🚨 收尾**不在这里**（复审 20260829_1056 中-1）：
        //    `isMovingFromParent` 在**交互式侧滑一开始**就为 true，
        //    他划了 1/4 屏松手让它弹回，录音已经被掐掉了。
        //    → 收尾挪到 `viewDidDisappear`（转场真的完成才调）。
        if navigationController?.viewControllers.count == 1 {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }

    /// 🚨 `viewWillAppear` 里调了它，所以**必须有定义**。
    ///    这个页回到前台不用刷新什么，留空即可 —— 但不能不定义，
    ///    CI 上报的就是 "type has no member"。
    func onAppear() { }

    /// 子类各自的「回到前台要刷新什么」。默认什么都不做。

    private enum Phase { case idle, listening, thinking }

    // 🚨 三档，跟 engine.py / 安卓 Gen.TONE_CODES 一致（Kevin 2026-08-21：
    //    「邮件和正式合在一起吧，这两个没什么区别。就是随意、工作和邮件三种」）。
    //    这里是**第三份**副本，暂时只能手工对齐 —— iOS 没走构建期生成那条路。
    //    改档位时三处都要动：engine.py / build_apk.py 生成的 Gen / 这里。
    private let tones = Prompts.all
    private let toneLabels = Prompts.all.map(Prompts.label)
    private var tone = Prompts.normalize(KbBridge.prefs.string(forKey: "vime.tone"))

    /// 输出模式：译成英文（默认）/ 只转写。跟安卓一致。
    private var mode: Backend.Mode =
        Backend.Mode(rawValue: KbBridge.prefs.string(forKey: "vime.mode") ?? "en") ?? .en
    private let logoView = UIImageView()
    /// 长按说明的文案表。用 ObjectIdentifier 当键，免得给每个控件都挂 tag。
    private var tips: [ObjectIdentifier: String] = [:]
    // 第一级 Tab
    private let tabTranslate = UIButton(type: .system)
    private let tabTranscribe = UIButton(type: .system)
    // 第二级：转写下的两个子档
    private let modeZhButton = UIButton(type: .system)
    private let modeRawButton = UIButton(type: .system)
    private var subStack = UIStackView()
    /// 「整理/逐字」那排的高度 —— 翻译档下要收成 0（见建约束处的说明）。
    private var subH = NSLayoutConstraint()
    /// 🚨🚨 **方案 F 的参数行**（Kevin 2026-09-05 看图后定的版式）。
    ///
    ///    原来两档的参数一个在麦克风上（整理/逐字）、一个在下（语气/语言），
    ///    他的原话：「搞得乱七八糟的，一点都不统一，一看就是草台班子做的」。
    ///    根因是**两档参数的数量和种类本来就不同**（翻译两个下拉、转写一个二选一），
    ///    于是各自找地方摆。
    ///
    /// F 的解法：**两档共用同一行，就在结果框的第一行**，下面一条分隔线。
    ///    翻译档放两项、转写档放一项（居中），**行的位置永远不变**。
    private let paramRow = UIStackView()
    /// 转写档的「方式」下拉（整理 / 逐字）—— 取代原来那两个并排胶囊。
    /// 🚨 做成下拉是为了**跟翻译档的语气/语言同一种控件语法**，
    ///    不然一档是"两个互斥胶囊"、一档是"两个下拉"，又是两套。
    private let styleButton = UIButton(type: .system)
    /// 参数行和结果框之间那条分隔线 —— 让它们看起来是同一张卡片的两段。
    private let paramSep = UIView()
    /// 「整理/逐字」那排**上方**的间距 —— 它收成 0 高时这段也要收。
    private var subTop = NSLayoutConstraint()
    /// 状态行上方的间距 —— 它没话说时收成 0（见 `applyHint`）。
    private var hintTop = NSLayoutConstraint()
    /// 状态行**自己的高度** —— 没话说时激活这条 0 高（见 `applyHint`）。
    private var hintH = NSLayoutConstraint()

    /// 未选中的 Tab 收窄到多宽。要放得下完整标签，别截字。
    static let tabNarrow: CGFloat = 88
    /// 收窄约束：**只激活未选中那一个**，选中的没有宽度约束、自然吃满剩余。
    private var narrowTranslate: NSLayoutConstraint?
    private var narrowTranscribe: NSLayoutConstraint?
    /// 两个 Tab 等宽 —— **他还没点过任何一个**时用这个。
    private var equalTabs: NSLayoutConstraint?

    /// 他有没有点过这两个 Tab。
    ///
    /// 🚨 **不能拿 `mode` 判**：mode 有默认值（`.en`），拿它判的话新用户
    ///    一进来就是"翻译被选中"的样子 —— 而 Kevin 2026-08-25 要的是
    ///    「如果用户不点的话，它默认两边都是一样长」。
    ///    **默认档位** 和 **他点过没有** 是两件事。
    private var tabTouched: Bool {
        get { KbBridge.prefs.bool(forKey: "vime.tabTouched") }
        set { KbBridge.prefs.set(newValue, forKey: "vime.tabTouched") }
    }

    /// 目标语言（翻译模式用）。跟安卓共用同一套 code。
    private var lang = KbBridge.prefs.string(forKey: "vime.lang") ?? "en"
    private let langButton = UIButton(type: .system)

    /// 🔊 朗读：把刚出的译文用 Andrew 的声音念出来
    private let speakButton = UIButton(type: .system)
    private var lastOut = ""

    // MARK: - 连续模式（Kevin 2026-08-26 的"随手翻译"同传场景）

    /// 连续模式开关。点一次一直听，说一句出一句。
    private let contButton = UIButton(type: .system)
    private var continuous = false
    /// 结果行。**按序号占位**，不是来一句 append 一句 ——
    /// 🚨 多句会并发在飞（第 2 句说完时第 1 句可能还没回来），
    ///    直接 append 的话顺序由**网络快慢**决定，
    ///    说的顺序和显示的顺序会对不上。
    private var lines: [String] = []
    /// 已经发出去几句（下一句的下标）。
    private var seq = 0
    /// 连续模式的**代次**。每次起录 +1；异步回调回来先比对，不是本代就丢弃。
    /// 🚨 复审 中-5：没有它的话，上一轮在飞的结果会污染新一轮。
    private var epoch = 0
    /// 🔊 正在等 TTS 响应。
    ///
    /// 🚨🚨 复审 高-2：这个状态**必须收进唯一出口**。
    ///    原来 `tapSpeak` 绕过 `paintOutputButtons()` 直接写三个属性，
    ///    而连续模式下上一句的 polish 回来会调一次 `paintOutputButtons()`
    ///    → **飞行中的 🔊 被重新点亮、标题变回「朗读」** →
    ///    他以为没点上，再点一次 → **第二个付费 TTS**，两个响应叠着播。
    /// 🔊 正在等 TTS 响应的**那一代**（nil = 不在等）。
    ///
    /// 🚨 复审 中-1：原来是个裸 `Bool` —— busy 是 gen N 设的，
    ///    他录完新一句（gen N+1）之后旧 TTS 还在飞，busy 仍为 true
    ///    → **新一句的 🔊 是个点不动的「…」**，最长三分钟以上。
    ///    **busy 要属于某一代**：代次一变，它就跟当前这一代无关了。
    private var speakBusyEpoch: Int?
    /// `voice` 这个 lazy 属性**有没有被真正用过**。
    /// 🚨 `teardown()` 会在 `deinit` 路径上跑，那时不该把它构造出来。
    private var voiceUsed = false
    /// 大字展示。旅游时把译文铺满屏幕，手机一转给对方看。
    private let bigButton = UIButton(type: .system)
    /// 收进单词本（Kevin 2026-08-28：「单词本那个功能我是要用的」）。
    private let keepButton = UIButton(type: .system)
    /// 这一句的**中文原话**。收藏要拿它当复习卡正面。
    private var lastZh = ""
    /// 反向翻译：**对方**说外语 → 译成我的语言（界面语言那一档）。
    /// 正向是我说话 → 译成 `lang`（给对方看）。
    private let revButton = UIButton(type: .system)
    private var reversed = false

    private let hintLabel = UILabel()
    private let heardLabel = UILabel()
    private let resultView = UITextView()
    private let aiNoticeLabel = UILabel()
    private let micButton = UIButton(type: .system)
    /// 🚨🚨 **录音时圆钮里放波形，不放停止方块**（Kevin 2026-09-04 第二次说）。
    ///    他的原话：「点一下怎么变成白色正方形方块了？之前不是说用波浪线吗？
    ///    我不是强调了要保持跟输入法的那三块一致吗？」
    ///
    /// 🚨 **直接复用键盘那个 `WaveView`，绝不抄第二份** ——
    ///    这摊活已经在"同一规则两处实现必漂"上栽过两次。
    ///    面对面那屏（`FaceToFaceViewController`）也是复用它，现在三处同源。
    private let waveView = WaveView(frame: .zero)
    /// 处理中数秒 —— 跟面对面共用 `BusyTicker`（Shared/BusyTicker.swift）
    private let busyTicker = BusyTicker()
    private let toneButton = UIButton(type: .system)

    private lazy var voice = Voice()
    private var phase: Phase = .idle
    private var elapsedTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        // 🚨 这是 **App 里的页面**，要用 App 的渐变底（跟首页/设置页一致），
        //    不是 `Theme.bg` —— 那是**键盘扩展**的底色。
        //    刷错的后果：说话页看起来跟 App 其他页不是一套东西。
        //    安卓构建的漂移闸门抓到的（"iOS 主 App 还在刷 Theme.bg"）。
        UI.paintBg(self)
        // 🚨 标题跟安卓的 `try_title` 一致 —— 两端一模一样是硬规矩。
        //    原来写死 "Transless"，而安卓那边是「随手翻译」。
        title = L.home_try_speak
        navigationController?.navigationBar.tintColor = Theme.accent
        // 🚨🚨 **右上角从「权限」改成「查词」**（Kevin 2026-09-05：
        //    「随手翻译右上角那个权限入口不用留了，首页本身已经有权限入口了，
        //     直接改成『查词』」）。
        //
        // 🚨 **删这个入口不丢路径** —— `SetupViewController` 另有两个入口：
        //    首页输入法胶囊（`:2207`）和设置页（`:2979`）。2.1 核过，我也核过。
        // 🚨 **反向控制要单独验**：改完之后**首页那个入口仍在、仍能进去**。
        //    只验"这里变成查词了"的话，把权限入口一起做没了也会全绿。
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: L.dict_title, style: .plain, target: self, action: #selector(openDict))

        // 🚨 两级 Tab（Kevin 2026-08-21：「按你最初的那个方案来」）：
        //    第一级只有 翻译 / 转写；子档位（结构化 / 逐字）放第二级小 chip。
        //    跟安卓 VoiceImeService 的版式一一对应 —— 两端一起改是硬规矩。
        for (b, t, sel) in [(tabTranslate, L.kb_translate, #selector(pickEn)),
                            (tabTranscribe, L.kb_transcribe, #selector(pickTranscribe))] {
            b.setTitle(t, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
            b.layer.cornerRadius = 17
            b.addTarget(self, action: sel, for: .touchUpInside)
        }
        // Kevin 2026-08-21：Tab 右边那块空地放 logo（G3 图标里的整个 T+麦克风，同源）。
        // 压到次要文字色，不抢戏 —— 这一屏的强调色只留给说话长条。
        // 🚨 **不能用 `.alwaysTemplate`** —— logo 是一张带紫色圆角底的方形图标，
        //    template 模式会把所有非透明像素**整块涂成 tintColor**，
        //    渲染出来就是 tab 行右边那个莫名其妙的灰方块（2026-08-26 截图发现）。
        //    template 只适合单色描边图形，不适合有底的图标。
        logoView.image = UIImage(named: "logo")
        logoView.contentMode = .scaleAspectFit

        let modeStack = UIStackView(arrangedSubviews: [tabTranslate, tabTranscribe, logoView])
        modeStack.axis = .horizontal
        modeStack.spacing = Theme.gap * 0.7
        modeStack.distribution = .fill
        tabTranslate.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tabTranscribe.setContentHuggingPriority(.defaultLow, for: .horizontal)
        // 🚨 **未选中的那个**收窄到固定宽，选中的自然吃满剩下的。
        //    Kevin 2026-08-25：「它应该是一个动态的图标，而不是静态的…
        //    我点『转写』的时候，『转写』进一步拉，也是可以拉长到那么长。」
        //    原来两个 hugging 一样低，`.fill` 把富余空间**全给第一个**
        //    （「翻译」）—— 跟谁被选中毫无关系，所以永远长短固定。
        //
        // 🚨 88 是要放得下未选中时的完整标签。太窄会截成「转…」，
        //    那比不做动画更糟。
        narrowTranslate = tabTranslate.widthAnchor.constraint(
            equalToConstant: Self.tabNarrow)
        narrowTranscribe = tabTranscribe.widthAnchor.constraint(
            equalToConstant: Self.tabNarrow)
        equalTabs = tabTranslate.widthAnchor.constraint(
            equalTo: tabTranscribe.widthAnchor)
        tabTranslate.titleLabel?.adjustsFontSizeToFitWidth = true
        tabTranslate.titleLabel?.minimumScaleFactor = 0.75
        tabTranscribe.titleLabel?.adjustsFontSizeToFitWidth = true
        tabTranscribe.titleLabel?.minimumScaleFactor = 0.75
        logoView.setContentHuggingPriority(.required, for: .horizontal)
        logoView.widthAnchor.constraint(equalToConstant: 26).isActive = true

        // 🚨 「整理 / 逐字」，不是「结构化转写 / 逐字转录」——
        //    Kevin 2026-08-21：「这几个表达让人听不懂」。安卓当天改了并加了闸门，
        //    iOS 一直留着旧名字（2026-08-22 才发现）。
        for (b, t, sel) in [(modeZhButton, L.kb_polish, #selector(pickZh)),
                            (modeRawButton, L.kb_verbatim, #selector(pickRaw))] {
            b.setTitle(t, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            b.layer.cornerRadius = 16
            b.addTarget(self, action: sel, for: .touchUpInside)
        }
        contButton.setTitle(L.try_continuous, for: .normal)
        contButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        contButton.titleLabel?.adjustsFontSizeToFitWidth = true
        contButton.titleLabel?.minimumScaleFactor = 0.7
        // 🚨 摘出 subStack 之后要**自己设底色和字色** ——
        //    原来是靠 `paintMode()` 给 stack 里那几个统一刷的。
        contButton.setTitleColor(Theme.text, for: .normal)
        contButton.backgroundColor = Theme.key
        contButton.layer.cornerRadius = 16
        contButton.addTarget(self, action: #selector(toggleContinuous),
                             for: .touchUpInside)
        // 🚨 `contButton` **不能放进 subStack** —— `paintMode()` 里
        //    `subStack.isHidden = isTranslate`，那一行是转写模式的子选项，
        //    翻译模式下整行隐藏。放进去的话「连续」在主模式下就没了。
        //    它现在跟「⇄ 对方说」一样，独立约束在麦克风旁边。
        subStack = UIStackView(arrangedSubviews: [modeZhButton, modeRawButton])
        subStack.axis = .horizontal
        subStack.spacing = Theme.gap * 0.7
        subStack.distribution = .fillEqually

        // 🚨 Kevin 2026-08-21：那几行功能说明「至于要留这么大的位置吗？…
        //    用户自己点着点着自然就明白了。或者长按的时候弹一个 box 来介绍」。
        //    -> 常驻说明清空（下面 paintMode 里也不再写），改成**长按弹**（explain）。
        hintLabel.font = .systemFont(ofSize: 15)
        hintLabel.textColor = Theme.dim
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 1
        applyHint()   // 🚨 初始态也走唯一入口，不给闸门开豁免

        heardLabel.font = .systemFont(ofSize: 15)
        heardLabel.textColor = Theme.text
        heardLabel.textAlignment = .center
        heardLabel.numberOfLines = 4

        resultView.font = .systemFont(ofSize: 17)
        resultView.textColor = Theme.text
        resultView.backgroundColor = Theme.panel
        resultView.layer.cornerRadius = 12
        resultView.isEditable = false
        resultView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)

        // 🚨 AI 生成声明：DeepSeek 开放平台服务协议 8.1「应当向终端用户明确披露
        //    相关输出内容系由人工智能生成」+ 3.7「对生成、合成的文本进行标识」。
        aiNoticeLabel.text = L.ai_notice
        aiNoticeLabel.font = .systemFont(ofSize: 12.5)
        // 🚨 走 Theme，别硬编码 —— 硬编码的话换主题时它不跟着变，
        //    紫色改版之后会剩一块土黄。
        aiNoticeLabel.textColor = Theme.dim
        aiNoticeLabel.numberOfLines = 0
        aiNoticeLabel.textAlignment = .center

        // 🚨🚨 说话键是**圆的**，别再改回长条。
        //    Kevin 2026-08-21 先说「不要搞成圆圈…搞成一个长点的方框」，
        //    当天**又改口**：「不需要留长…还是用回原来那个圆圈的形状，
        //    这样整个输入法都显得干净一点」——以后说的为准。
        //    安卓按后一次改了（build 闸门钉着 circle=3/bar=0），
        //    iOS 停在前一次，2026-08-22 才发现。
        micButton.accessibilityIdentifier = "app.mic"
        micButton.setTitle("", for: .normal)
        micButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        micButton.setTitleColor(.white, for: .normal)
        Theme.setMicGlyph(micButton, side: Theme.micBarHeight)
        micButton.tintColor = .white
        micButton.backgroundColor = Theme.accent
        micButton.layer.cornerRadius = Theme.micBarHeight / 2
        micButton.addTarget(self, action: #selector(tapMic), for: .touchUpInside)
        // 波形贴在圆钮里（照抄面对面那屏的接法，尺寸比例也一样）
        waveView.translatesAutoresizingMaskIntoConstraints = false
        waveView.isUserInteractionEnabled = false      // 别挡住按钮点击
        micButton.addSubview(waveView)
        NSLayoutConstraint.activate([
            waveView.centerXAnchor.constraint(equalTo: micButton.centerXAnchor),
            waveView.centerYAnchor.constraint(equalTo: micButton.centerYAnchor),
            waveView.widthAnchor.constraint(equalTo: micButton.widthAnchor,
                                            multiplier: 0.66),
            waveView.heightAnchor.constraint(equalTo: micButton.heightAnchor,
                                             multiplier: 0.46),
        ])

        toneButton.setTitle(L.p_tone + "：" + toneTitle(), for: .normal)
        toneButton.setTitleColor(Theme.dim, for: .normal)
        toneButton.titleLabel?.font = .systemFont(ofSize: 15)
        toneButton.backgroundColor = Theme.key
        toneButton.layer.cornerRadius = 16
        // 🚨 下拉菜单：`showsMenuAsPrimaryAction = true` 才是**点一下就弹**，
        //    不设的话要长按 —— 那等于没做（他要的正是"少点几下"）。
        toneButton.menu = toneMenu()
        toneButton.showsMenuAsPrimaryAction = true

        // 语言选择：跟语气并排，不藏进设置
        langButton.titleLabel?.font = .systemFont(ofSize: 15)
        langButton.setTitleColor(Theme.text, for: .normal)
        langButton.backgroundColor = Theme.key
        langButton.layer.cornerRadius = 16
        // 🚨 **不再 addTarget** —— 改挂下拉菜单（`refreshLangMenu`）。
        //    留着 addTarget 的话，点一下会既弹菜单又走老路径。
        refreshLangMenu()

        speakButton.setTitle(L.kb_speak, for: .normal)
        // 🚨 单色喇叭贴在文字左边（原来是彩色 emoji，跟主题冲）
        speakButton.setImage(Theme.speakGlyph(17), for: .normal)
        speakButton.tintColor = Theme.text
        speakButton.imageEdgeInsets =
            UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 4)
        speakButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        speakButton.setTitleColor(Theme.text, for: .normal)
        speakButton.backgroundColor = Theme.key
        speakButton.layer.cornerRadius = 16
        paintOutputButtons()
        speakButton.addTarget(self, action: #selector(tapSpeak), for: .touchUpInside)

        bigButton.setTitle(L.try_bigtext, for: .normal)
        bigButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        bigButton.setTitleColor(Theme.text, for: .normal)
        bigButton.backgroundColor = Theme.key
        bigButton.layer.cornerRadius = 16
        paintOutputButtons()
        keepButton.setTitle(L.kb_keep, for: .normal)
        keepButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        keepButton.setTitleColor(Theme.text, for: .normal)
        keepButton.backgroundColor = Theme.key
        keepButton.layer.cornerRadius = 16
        keepButton.addTarget(self, action: #selector(tapKeep),
                             for: .touchUpInside)

        bigButton.addTarget(self, action: #selector(tapBig),
                            for: .touchUpInside)

        // 🚨 按钮文字**就是当前方向**（Kevin 2026-08-26：
        //    「我点一下『对方说』就能变成『我说』」）。
        //    只靠底色区分，用户回头看想不起来现在是哪个方向。
        revButton.accessibilityIdentifier = "app.rev"
        revButton.setTitle(L.try_dir_me, for: .normal)
        revButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        revButton.titleLabel?.adjustsFontSizeToFitWidth = true
        revButton.titleLabel?.minimumScaleFactor = 0.7
        revButton.setTitleColor(Theme.text, for: .normal)
        revButton.backgroundColor = Theme.key
        revButton.layer.cornerRadius = 16
        revButton.addTarget(self, action: #selector(tapReverse),
                            for: .touchUpInside)

        // 🚨🚨 **「我说」和「连续」2026-09-04 从随手翻译屏撤掉**（Kevin 拍板）。
        //
        //    原话：「你那个『随手翻译』里『我说』和『连续说』这两个东西，
        //    我不是说都已经要删掉了吗？它不是已经归到『面对面』去了吗？」
        //
        //    「我说 / 对方说」这个方向切换属于**面对面翻译**那一屏
        //    （那边靠 `Reverse.isMine` 自动判方向，本来就不用手动切）；
        //    随手翻译是「我说一句、出一句」，没有方向这回事。
        //    「连续」同理，是面对面那种来回对话的场景。
        //
        // 🚨 **藏而不删**（`isHidden`）：两个按钮的约束、`paintMode()` 里的
        //    刷新逻辑、`tapReverse()`/`toggleContinuous()` 都还在，
        //    删掉要牵动七八处、回滚也难。他要是想加回来就是这两行的事。
        // 🚨 藏在**加进视图之后**统一设，不散在各自的构造里 ——
        //    散着写下次加第三个又会漏一个。
        revButton.isHidden = true
        contButton.isHidden = true

        [modeStack, subStack, hintLabel, heardLabel, paramRow, paramSep, resultView, micButton,
         toneButton, langButton, speakButton, bigButton, keepButton,
         revButton, contButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        let actionRow = UIStackView(arrangedSubviews:
            [speakButton, bigButton, keepButton])
        actionRow.axis = .horizontal
        actionRow.spacing = 8
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionRow)

        // 🚨🚨 **隐藏 ≠ 不占位**（Kevin 2026-09-04：「麦克风上面那块空档有什么意义呢」）。
        //    翻译档下「整理/逐字」那排是 `isHidden = true`，但它是**用约束定高的
        //    普通视图** —— 隐藏之后那 32pt 高度和上下各 12pt 间距**照样占着**。
        //    麦克风上方那一大片空白就是它，不是谁故意留的白。
        // 🚨 判据是实测：安卓量到 上 210px / 下 54px（3.9 倍），iOS 同一个形状。
        subH = subStack.heightAnchor.constraint(equalToConstant: 32)
        subTop = subStack.topAnchor.constraint(
            equalTo: modeStack.bottomAnchor, constant: Theme.gap)
        hintTop = hintLabel.topAnchor.constraint(
            equalTo: subStack.bottomAnchor, constant: Theme.gap)
        hintH = hintLabel.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            modeStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.gap),
            modeStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.pad * 1.6),
            modeStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.pad * 1.6),
            modeStack.heightAnchor.constraint(equalToConstant: 34),

            subTop,
            subStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.pad * 1.6),
            subStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.pad * 1.6),
            subH,

            hintTop,
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            // 圆形：等宽高 + 居中（跟安卓 MIC_CIRCLE_DP 那套一一对应）
            micButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            // 🚨 反向钮贴在麦克风**左边**，不进那一行选项 ——
            //    那行已经有「整理/逐字/连续」，Kevin 说过「排版太密了」。
            //    麦克风自己的居中约束不动，所以视觉重心不会被推偏。
            revButton.trailingAnchor.constraint(
                equalTo: micButton.leadingAnchor, constant: -16),
            revButton.centerYAnchor.constraint(equalTo: micButton.centerYAnchor),
            revButton.widthAnchor.constraint(equalToConstant: 76),
            revButton.heightAnchor.constraint(equalToConstant: 32),

            // 「连续」在麦克风**右边**，跟左边的「⇄ 对方说」对称。
            contButton.leadingAnchor.constraint(
                equalTo: micButton.trailingAnchor, constant: 16),
            contButton.centerYAnchor.constraint(equalTo: micButton.centerYAnchor),
            contButton.widthAnchor.constraint(equalToConstant: 76),
            contButton.heightAnchor.constraint(equalToConstant: 32),

            // 🚨 上方间距**跟下方用同一个常量**（Kevin 09-04 要「上下等距」）。
            //    原来是 `Theme.gap + 4`，比下面那条多 4 —— 那 4 没有任何理由。
            // 🚨🚨 **麦克风钉在安全区底部**（方案 F 的预览图就是这样）。
            //    Kevin 2026-09-05 当场指出我没按图做：「圆圈怎么都没有？
            //    它那个太靠上了，太顶上面了…你现在这个根本就不是按照方案做的」。
            //
            // 🚨 我上一版**只搬了参数行、没搬麦克风**，然后拿"两档零位移"当验收 ——
            //    量的是**一致性**，不是**跟他批的那张图一不一样**。
            //    两档确实一致，但整体不是那个方案：判据挂错了目标，白验一轮。
            micButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            micButton.widthAnchor.constraint(equalToConstant: Theme.micBarHeight),
            micButton.heightAnchor.constraint(equalToConstant: Theme.micBarHeight),

            // 🚨🚨 **语气/语言、整理/逐字 的位置改由 `paramRow` 统一排**
            //    （方案 F，Kevin 2026-09-05 定）—— 这里不再各自锚一套。
            //    两档共用同一行、同一位置，见 `buildParamRow()`。

            // 🚨 朗读 / 大字 / 收藏三个并排。
            //    原来是**硬坐标**算的（"总宽 140+8+100=248，所以朗读中心
            //    落在 centerX-54"）—— 加第三个就得重算那个 -54，
            //    而且任何一个宽度变了都要再算一遍。
            //    改成 `actionRow` 这个 stack 居中，**加减按钮不用再算坐标**。
            actionRow.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            // 🚨🚨 **锚麦克风，不是语气钮**（2026-09-05 方案 F 改的）。
            //    语气钮搬进结果框顶部的参数行之后，这里再锚它就**成环**：
            //    toneButton → actionRow → heardLabel → paramRow → toneButton。
            //    Auto Layout 不报错，它会挑一组解 —— 表现是整块被推到屏幕底部
            //    （实测参数行落在 y=861，结果框直接量不到）。
            //    **编译一个字都不报，只有量坐标才看得见。**
            actionRow.bottomAnchor.constraint(
                equalTo: micButton.topAnchor, constant: -12),
            actionRow.heightAnchor.constraint(equalToConstant: 36),
            speakButton.widthAnchor.constraint(equalToConstant: 130),
            bigButton.widthAnchor.constraint(equalToConstant: 92),
            keepButton.widthAnchor.constraint(equalToConstant: 92),

            // 「说过的话」挪到**结果框上面**（原来在操作行下面）——
            // 操作行已经跟着麦克风沉到底了，它留在那儿会被压扁。
            heardLabel.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 6),
            heardLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            heardLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            // 🚨🚨 **回到最早的「空框」**（Kevin 2026-09-05 回退 C 方案）。
            //    他的原话：「你还是不要放最近的那些东西了。因为在『说话记录』
            //    隔壁的 tab 已经有了，这里就不要重复放了，还是放一个空置的空框吧。
            //    我们还是按照最早的那个方案来，空就空吧，这个不改了。」
            //
            // 🚨 底边**必须贴到安全区** —— 删了下面的东西却不把框拉到底，
            //    就是他 08-29 骂过的「下面半屏全空」。**删一半比不删更糟。**
            // 参数行贴在结果框上沿，两者共用一张卡片的观感
            paramRow.topAnchor.constraint(equalTo: heardLabel.bottomAnchor, constant: 14),
            paramRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            paramRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            paramRow.heightAnchor.constraint(equalToConstant: 44),

            paramSep.topAnchor.constraint(equalTo: paramRow.bottomAnchor),
            paramSep.leadingAnchor.constraint(equalTo: paramRow.leadingAnchor, constant: 16),
            paramSep.trailingAnchor.constraint(equalTo: paramRow.trailingAnchor, constant: -16),
            paramSep.heightAnchor.constraint(equalToConstant: 1),

            resultView.topAnchor.constraint(equalTo: paramSep.bottomAnchor),
            resultView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            resultView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            // 🚨 底边接**操作行**，不再贴安全区 —— 中间那块空白正是他说的"太空"。
            //    结果框现在从分段条下面一直铺到麦克风上方。
            resultView.bottomAnchor.constraint(
                equalTo: actionRow.topAnchor, constant: -12),
        ])
        // 🚨🚨 **建完约束再走一次状态行的唯一入口。**
        //    `applyHint()` 在上面（建约束之前）已经跑过一次，那时
        //    `hintH` 还是空壳、收不了高度 —— 于是"空状态行收成 0"这条
        //    **写对了却从没生效**（实测一直是 up=24 而不是 12）。
        //    典型的「代码在，但它跑的时机不对」：编译不报、测试也不报，
        //    只有**量一次**才看得见。
        buildParamRow()
        refreshParamRow()
        applyHint()
        // 🚨 立体感统一在这儿走一遍，别在每个控件后面各写一行 —— 漏一个就少一个阴影，
        //    而"少了一个"是看不出来的（跟安卓 Theme.elevateAll 同一套做法）。
        for v in [tabTranslate, tabTranscribe, modeZhButton, modeRawButton,
                  toneButton, langButton, speakButton, bigButton] {
            v.layer.cornerRadius = Theme.rKey
            Theme.elevate(v, 3)
        }
        resultView.layer.cornerRadius = Theme.rCard
        Theme.elevate(resultView, 3)
        Theme.elevate(micButton, 6)     // 主操作，投影重一档，浮在最上层

        // 长按弹说明（跟安卓 explain() 一一对应，文案保持一致）
        explain(tabTranslate, L.ex_translate)
        explain(tabTranscribe, L.ex_transcribe)
        explain(modeZhButton, L.ex_polish)
        explain(modeRawButton, L.ex_verbatim)
        explain(micButton, L.ex_mic_ios)
        explain(toneButton, L.ex_tone_pick)
        explain(langButton, L.ex_lang_pick)
        explain(speakButton, L.ex_speak_ios)

        paintMode()
    }

    // MARK: - 模式

    /// 语言选择：**下拉菜单**（`LangMenu`），跟「语气」「方式」同一个控件。
    ///
    /// 🚨🚨 原来是 `UIAlertController(.actionSheet)`，一门一个 action。
    ///    Kevin 2026-09-05 要把目标语言从 9 门扩到 23+ 门（中东、欧洲小语种），
    ///    **actionSheet 不是为长列表设计的** —— 9 门就已经很挤，
    ///    23 门超出屏幕的部分根本点不到。他的原话：
    ///    「你选择器不要一下子展示那么多嘛，加个下拉，就可以支持我滑动去选了嘛，
    ///     所以 32 项又怎么样嘛」。
    ///
    /// 🚨 排法在 `LangMenu` 一处（最近用过置顶 + 全量），三个选择器共用 ——
    ///    各写各的话 23 门时会各坏各的。
    private func refreshLangMenu() {
        langButton.menu = LangMenu.build(current: lang) { [weak self] code in
            guard let self = self else { return }
            self.lang = code
            KbBridge.prefs.set(code, forKey: "vime.lang")
            self.paintMode()
            self.refreshLangMenu()      // 勾要挪到新选中的那条上
        }
        langButton.showsMenuAsPrimaryAction = true
    }

    /// 朗读最近一次的译文。再点一下 = 停。
    @objc private func tapSpeak() {
        if Speaker.isPlaying {
            Speaker.stop()
            paintOutputButtons()     // 标题由唯一出口按 isPlaying 决定
            bigButton.setTitle(L.try_bigtext, for: .normal)
            revButton.setTitle(
                reversed ? L.try_dir_them : L.try_dir_me,
                for: .normal)
            return
        }
        let text = lastOut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { setOneOff(L.nothing_to_speak); return }
        // 🚨 中-4：**请求飞行期间禁用**。网络慢 2~5 秒时他会以为没反应再点一下，
        //    于是发出第二个 `/api/tts`（付费翻倍）；两个响应先后回来，
        //    后一个的 completion 把标题改回「朗读」而音频还在响 ——
        //    **按钮说没在播，耳朵里在播**。
        // 🚨 高-2：只置位，**画法交给唯一出口** —— 绕过它直接写的话，
        //    别的回调调一次 `paintOutputButtons()` 就把飞行态抹掉了。
        speakBusyEpoch = epoch
        paintOutputButtons()
        // 🚨 中-5：**捕获本代**。`guard phase == .idle` 挡不住这一类 ——
        //    他录完新一句、结果也出来了之后，`.idle` **同样成立**，
        //    于是 A 的 TTS 回来时播的是 A，而屏上是 B。
        //    重试把这个窗口从 30 秒拉到了 ~132 秒，撞上的概率不再是小数。
        let ep = epoch
        Backend.speak(text: text) { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // 🚨 高-2：**非 idle 一律丢弃这次结果**。
                //    请求飞行期间他可能已经开录了；这时既不能播（会录进去），
                //    也不能改标题（那会跟当前状态打架）。
                //    诊断照落，别静默。
                // 🚨 高-2：**每一条出口都要复位 busy**，包括被丢弃这条 ——
                //    漏一条就是一个永远转不回来的「…」。
                //    🚨 中-5：复位**必须排在代次闸之前**，理由同上。
                // 🚨 中-1：**只清自己那一代的**。无条件清的话，
                //    上一代的回调会把**当前这一代**的 busy 清掉 → 🔊 复活 →
                //    他再点一次 = **第二个付费 TTS**。
                if self.speakBusyEpoch == ep { self.speakBusyEpoch = nil }
                guard ep == self.epoch else {
                    self.logFailure("朗读结果属于上一代（他已经录了新的），丢弃",
                                    step: "朗读")
                    self.paintOutputButtons()
                    return
                }
                guard self.phase == .idle else {
                    self.logFailure("朗读结果到达时已不在待命（阶段=\(self.phase)），丢弃",
                                    step: "朗读")
                    self.paintOutputButtons()
                    return
                }
                self.paintOutputButtons()
                switch r {
                case .failure(let e):
                    self.paintOutputButtons()
                    // 🚨 M2：**原文不上屏**，进诊断；屏上给 2.1 那句
                    //    （重点是"文字还在" —— 朗读是次要动作，译文还在屏上）
                    // 🚨 H-B：**不动阶段** —— 录音中改成 idle 会让停止键变回开始键。
                    self.logFailure("\(e)", step: "朗读")
                    // 🚨 M-D：额度/口令/断网要原样告诉他 —— 那几种
                    //    **下一次翻译也会失败**，说成「读不出来」会误导。
                    self.setOneOff(e.ttsText)
                case .success(let mp3):
                    // 🚨 **先 play 再刷**：`Speaker.isPlaying` 读的是
                    //    `player?.isPlaying`，在 `play()` 返回前恒为 false。
                    //    上一版这里先写死 `L.kb_stop`，而紧挨着上面那行
                    //    `paintOutputButtons()` 按 isPlaying 写的是「朗读」——
                    //    **两行打架，全靠顺序碰巧对**。
                    Speaker.play(mp3) { [weak self] err in
                        DispatchQueue.main.async {
                            self?.paintOutputButtons()
                            if let err = err {
                                self?.logFailure("\(err)", step: "朗读播放")
                                // 播放失败是本机的事，跟额度/口令无关 → 保持通用句
                                self?.setOneOff(L.err_tts_failed)
                            }
                        }
                    }
                    self.paintOutputButtons()   // play 已返回，isPlaying 才是真的
                }
            }
        }
    }

    /// 长按弹一条说明（跟安卓 VoiceImeService.explain 同一套文案）。
    /// 说明不占版面，只在长按时出现。
    private func explain(_ v: UIView, _ text: String) {
        let g = UILongPressGestureRecognizer(target: self, action: #selector(showTip(_:)))
        v.addGestureRecognizer(g)
        tips[ObjectIdentifier(v)] = text
    }

    @objc private func showTip(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let v = g.view,
              let text = tips[ObjectIdentifier(v)] else { return }
        let ac = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: L.btn_got_it, style: .cancel))
        present(ac, animated: true)
    }

    /// 🚨 只有**点这两个一级 Tab** 才算"点过"。
    ///    二级的「整理 / 逐字」不算 —— 那是转写档里面的子选择，
    ///    跟"他有没有在翻译/转写之间做过选择"是两回事。
    private func touchTabs() { tabTouched = true }

    @objc private func pickEn() { touchTabs(); setMode(.en) }
    @objc private func pickZh() { setMode(.zh) }
    @objc private func pickRaw() { setMode(.raw) }
    /// 点第一级「转写」：默认落在结构化转写；已经在转写档就保持原子档。
    @objc private func pickTranscribe() {
        touchTabs()
        setMode(mode == .raw ? .raw : .zh)
    }

    private func setMode(_ m: Backend.Mode) {
        mode = m
        KbBridge.prefs.set(m.rawValue, forKey: "vime.mode")
        paintMode()
    }

    private func paintMode() {
        // 第一级
        let isTranslate = (mode == .en)
        tabTranslate.backgroundColor = isTranslate ? Theme.accent : Theme.key
        tabTranslate.setTitleColor(isTranslate ? .white : Theme.dim, for: .normal)
        tabTranscribe.backgroundColor = isTranslate ? Theme.key : Theme.accent
        tabTranscribe.setTitleColor(isTranslate ? Theme.dim : .white, for: .normal)

        // 🚨 三态：**没点过 → 两边等长**；点了谁谁吃满、另一个收窄。
        //    只动**约束的启用状态**，不重建约束：重建的话动画没有起点，
        //    会直接跳过去而不是拉伸。
        // 🚨🚨 **永远等宽**（Kevin 2026-09-05 看图后改口径，方案 F）。
        //
        //    原来是三态：没点过两边等长、点了谁谁吃满。那是他 2026-08-25 亲口要的
        //    （「我点『转写』的时候，『转写』进一步拉」），我一直守着没动。
        //
        //    2026-09-05 他自己骂这一页「一看就是草台班子做的」；Grok 独立评审
        //    **也把这个拉伸判为「这次版式最伤的一点」** ——
        //    「更像两个会抢宽度的 Tab，用户建立不起『左翻译、右转写』的位置记忆，
        //     眼睛每次要重新找字」。他看完图接受了等宽。
        //
        // 🚨 **选中只换填充和字色，宽度一格不动**（上面那两行已经在做）。
        //    `narrow*` 两条约束留着但永不启用 —— 删掉的话以后想回滚要重写；
        //    留着并写清楚为什么不用，比删了干净。
        narrowTranslate?.isActive = false
        narrowTranscribe?.isActive = false
        equalTabs?.isActive = true
        // 🚨 **标题跟档位走**（方案 F）：转写档下还写着「随手翻译」是信息错误，
        //    Grok 也点了这条。改在这一处 —— 切档的唯一出口。
        title = isTranslate ? L.home_try_speak : L.try_title_zh
        refreshParamRow()
        // 首帧不做动画（还没上屏，animate 会闪一下）
        if view.window != nil {
            UIView.animate(withDuration: 0.22,
                           delay: 0,
                           usingSpringWithDamping: 0.9,
                           initialSpringVelocity: 0.2,
                           options: [.curveEaseOut]) {
                self.view.layoutIfNeeded()
            }
        }

        // 第二级：翻译下是语气+语言，转写下是 结构化/逐字。永远只出现一排。
        // 🚨🚨 **这一排整个退役了**（2026-09-05 方案 F）：「整理/逐字」的职责
        //    搬进了结果框顶部参数行里的「方式 ▾」下拉。
        //    原来这里是 `isHidden = isTranslate`，于是切到转写档它又冒出来
        //    ——**同一个开关两处写，我在参数行里设的被这行覆盖**（实测：
        //    转写档下 整理/逐字 仍在 y=174，结果框被顶到 411）。
        //    这里改成恒藏，参数行那边就不用再管它。
        subStack.isHidden = true
        // 🚨 **高度也要跟着收**：只改 `isHidden` 是改了一半，
        //    隐藏了还占 32pt + 两段间距，表现就是"麦克风上面空一大块"。
        // 🚨🚨 **恒 0** —— 这一排已退役（方案 F），两档都不该占位。
        //    原来是 `isTranslate ? 0 : 32`，那是 09-04「隐藏≠不占位」那轮加的；
        //    退役之后它就成了**第三个还在改这个值的地方**，
        //    实测表现是转写档麦克风比翻译档低 44pt（174 vs 218）。
        //    **同一个量三处写，改两处等于没改。**
        subH.constant = 0
        // 🚨 **高度收了，它上面那段间距也要收** —— 否则剩下的是
        //    「12 + 0高的行 + 12」＝ 24，还是不等距。
        //    实测走过一遍才发现：收行高之后 up 从 36 降到 24，
        //    **停在 24 不动**，就是这两段间距叠出来的。
        subTop.constant = 0    // 同上：退役了，两档都不占位
        for (b, m) in [(modeZhButton, Backend.Mode.zh), (modeRawButton, .raw)] {
            b.accessibilityIdentifier = (m == .zh) ? "app.mode.zh" : "app.mode.raw"   // UITest 坏样本用
            let on = (mode == m)
            b.backgroundColor = on ? Theme.accent : Theme.key
            b.setTitleColor(on ? .white : Theme.dim, for: .normal)
        }
        toneButton.isHidden = !isTranslate
        langButton.isHidden = !isTranslate
        // 🚨🚨 **文案只有 `refreshParamTitles()` 一个出口**。
        //    这里原来自己也写一遍 `langLabel(lang) + " ▾"`，而它跑在后面，
        //    把方案 F 的「译成 英文 ▾」盖回成「英文 ▾」——
        //    真机上跟他批的预览图不一样，就差在这一行。
        //    **同一条规矩两处实现，必漂。**
        refreshParamTitles()
        // 🚨 改了设定 ＝ 一次性提示该退场（2.1：靠状态变化清，不靠计时器）
        setOneOff("")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        UI.resizeBg(self)
    }

    /// 调试口子：把新功能的状态摆出来好截图。
    ///
    /// 🚨 **每一条都调真实方法**，不是另设一个布尔。
    ///    伪造状态截出来的图只能证明"我画得出来"，
    ///    证明不了那个按钮点下去真会这样。
    private func applyDebugEnv() {
        // 🚨 只为**出图**：把「最近用过」那一段种上，否则它是空的、
        //    截图里根本看不到分段。种的是**输入数据**，不是选择器本身。
        if let seed = ProcessInfo.processInfo.environment["TRANSLESS_SEED_RECENT"],
           !seed.isEmpty {
            for code in seed.split(separator: ",").reversed() {
                LangRecents.use(String(code))
            }
            // 🚨 **种完必须重建菜单**：菜单在初始化时就建好了，
            //    而这里是 `viewDidAppear` —— 不重建的话菜单里still是空的"最近用过"。
            //    第一版就是这么红的：种子写进去了、菜单没跟着变，
            //    **"改了数据"跟"界面用上了"是两件事。**
            refreshLangMenu()
        }
        // 🚨 **只为把界面推进「处理中」那一档**，好让闸门量到秒数在不在走。
        //    被测的是 `BusyTicker`（没被这个开关碰过）——
        //    这里只负责**进入状态**，不是"跑测试时改了被测对象"。
        if ProcessInfo.processInfo.environment["TRANSLESS_FAKE_PHASE"] == "thinking" {
            setPhase(.thinking, hint: "")
            return
        }
        let env = ProcessInfo.processInfo.environment
        if let t = env["TRANSLESS_RESULT"], !t.isEmpty {
            // 走 setLine 那条真实回填路径的等价物：写结果区 + 按真实规则点亮
            resultView.text = t
            lastOut = t
            paintOutputButtons()
        }
        // 🚨🚨 **能直接切到转写档**（2026-09-04 加）。加它的原因是 Kevin 当天骂的：
        //    「你那个转写也是啊，不要就改了翻译没改转写。又是我给你提醒」——
        //    我改完随手翻译只截了**翻译档**一张图就说改好了，
        //    而转写档（整理/逐字）是同一屏的另一半，**我根本没看过**。
        //    没有这个口子，我每次都只能验一个档、另一半靠猜 ——
        //    「只验了自己改的那一支」正是今天反复栽的那个形态。
        if let m = env["TRANSLESS_MODE"], !m.isEmpty {
            // 🚨 调**真实的切档方法**（跟点那几个按钮走同一条路），
            //    不是自己设一个变量 —— 伪造状态截出来的图只能证明"我画得出来"。
            switch m {
            case "zh": pickZh()              // 转写 · 整理
            case "raw": pickRaw()            // 转写 · 逐字
            default: pickEn()                // 翻译
            }
        }
        if env["TRANSLESS_CONT"] == "1" { toggleContinuous() }
        if env["TRANSLESS_REV"] == "1" { tapReverse() }
        if env["TRANSLESS_BIG"] == "1" {
            // 🚨 延后一拍：`present` 要等这一层真的上了屏，
            //    在 viewDidAppear 同步调会被系统忽略（而且不报错）。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                [weak self] in self?.tapBig()
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyDebugEnv()
        // 🚨🚨 **一上来就弹系统麦克风授权框**，别 push 引导页。
        //    Kevin 2026-08-25：「Typeless 现在就是这样子，它就是让你先给权限，
        //    然后去试一下…用户下载你这个软件的时候，他就有预期这是需要录音的…
        //    iPhone 的话，肯定还是要用户确认嘛。」
        //
        //    🚨 区分两件事：弹**系统权限框**是对的（一次点允许就完事）；
        //       这里原本干的是 push **引导页**（"设为当前输入法"三步），
        //       那跟录音毫无关系 —— 刚装的人一进来就被弹去那一屏，
        //       答非所问，而且他要的体验一秒都没发生。
        let perm = Voice.micPermission()
        if perm == .undetermined {
            Voice.requestMic { _ in }
            return
        }
        // 被拒过：系统不会再弹了，这时候引导页才有意义（教他去设置里开）
        if perm == .denied, Onboard.tried {
            navigationController?.pushViewController(SetupViewController(), animated: true)
        }
    }

    // 🚨🚨 **这里原来是 `buildScrollColumn()` + `refreshRecent()`（C 方案），
    //    2026-09-05 按 Kevin 的话整块删掉** —— 「说话记录」那个 Tab 已经有历史，
    //    这一屏不重复放。结果框回到最早的空框、底边贴安全区。
    //
    // 🚨 删的时候**连引导句一起删**：那句是跟 C 方案一起加的，
    //    留着它就不是他要的"空置的空框"了。
    //    顺带避开安卓踩过的坑：**按钮显隐不许读框里的文字** ——
    //    引导句一写进去，"大字"按钮就会把它当成"有内容"而在空态冒出来。
    //    判据要挂**真状态**（有没有结果），不是"框里有没有字"。

    /// 搭方案 F 的参数行：**两档共用同一行**，就在结果框第一行。
    ///
    /// 🚨 翻译档放「语气 工作 ▾」「译成 英文 ▾」两项；转写档只放「方式 整理 ▾」一项，
    ///    **居中**。行的位置、结果框、麦克风全不动 —— 切档只是这一行里少一个词。
    ///    这正是原来两档一上一下的根：**两档参数数量不同**，于是各自找地方摆。
    private func buildParamRow() {
        // 🚨 给参数行一个 identifier：闸门要量的就是**这一行**的位置。
        //    没有它时闸门只能去找「语气」「整理」这些按钮 —— 转写档没有「语气」、
        //    「整理」的标题又是「方式 …」，两个都找不到就退回去量结果框顶，
        //    于是**两档量的是不同的对象**，读出 65 vs 20 的假差异（实际两档一样）。
        //    典型的「判据没写错、量得也准，但量的对象跟结论说的对象不是一个」。
        paramRow.accessibilityIdentifier = "app.paramRow"
        paramRow.axis = .horizontal
        paramRow.distribution = .fillEqually
        paramRow.alignment = .fill
        paramRow.translatesAutoresizingMaskIntoConstraints = false
        // 参数行 + 分隔线 + 结果框 = 视觉上一张卡片：圆角只在最上面两个角
        paramRow.backgroundColor = Theme.panel
        paramRow.layer.cornerRadius = Theme.rCard
        paramRow.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        paramSep.translatesAutoresizingMaskIntoConstraints = false
        paramSep.backgroundColor = UIColor.white.withAlphaComponent(0.13)
        // 结果框接在下面，所以它的圆角只留下面两个
        resultView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]

        // 参数行里三个钮：**没有底色、没有描边**，就是可点的文字 ——
        // 他嫌"密"，而胶囊底色正是密的主要来源。
        for b in [toneButton, langButton, styleButton] {
            b.backgroundColor = .clear
            b.layer.borderWidth = 0
            b.layer.cornerRadius = 0
            b.setTitleColor(Theme.text, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 15)
        }
        toneButton.menu = toneMenu()
        toneButton.showsMenuAsPrimaryAction = true
        styleButton.menu = styleMenu()
        styleButton.showsMenuAsPrimaryAction = true
    }

    /// 转写档「方式」的下拉：整理 / 逐字。
    /// 🚨 走 `pickZh` / `pickRaw` 这两个**已有的唯一入口**，不另写一套切档逻辑。
    private func styleMenu() -> UIMenu {
        UIMenu(title: L.ex_style_menu_title, children: [
            UIAction(title: L.kb_polish, state: mode == .zh ? .on : .off) {
                [weak self] _ in self?.pickZh() },
            UIAction(title: L.kb_verbatim, state: mode == .raw ? .on : .off) {
                [weak self] _ in self?.pickRaw() },
        ])
    }

    /// 参数行按当前档换内容。**唯一出口** —— 切档、改语气、改语言都走它。
    ///
    /// 🚨 写法统一成「**小标签 + 当前值 ▾**」。原来「语气：工作」是"标签+冒号+值"、
    ///    「英文 ▾」是"值+下拉"，**同一行两种语法**，看着像一个只读、一个可选
    ///    （Grok 点名的问题）。
    private func refreshParamRow() {
        paramRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let isTranslate = (mode == .en)
        if isTranslate {
            paramRow.addArrangedSubview(toneButton)
            paramRow.addArrangedSubview(langButton)
        } else {
            // 🚨 转写档只有一项 —— 用两侧的空占位把它挤到**正中**，
            //    而不是让 `fillEqually` 把它拉成整行宽。
            paramRow.addArrangedSubview(UIView())
            paramRow.addArrangedSubview(styleButton)
            paramRow.addArrangedSubview(UIView())
        }
        // 🚨 **顺带把旧的「整理/逐字」那一排整个收掉** —— 它的职责搬进了
        //    参数行里的那个下拉。留着不藏的话，同一件事屏幕上会有两个入口。
        // 高度与上方间距收成 0（隐藏≠不占位，这一课今天上过三次）
        subH.constant = 0
        subTop.constant = 0
        refreshParamTitles()
    }

    /// 参数行三个钮的文案 —— **统一成「小标签 + 当前值 ▾」**。
    ///
    /// 🚨 原来「语气：工作」是"标签+冒号+值"、「英文 ▾」是"值+下拉"，
    ///    同一行两种语法，看着像一个只读、一个可选（Grok 点名）。
    @objc private func openDict() {
        navigationController?.pushViewController(DictViewController(), animated: true)
    }

    private func refreshParamTitles() {
        toneButton.setTitle(L.p_tone + " " + toneTitle() + " ▾", for: .normal)
        langButton.setTitle(L.p_lang + " " + Backend.langLabel(langNow) + " ▾",
                            for: .normal)
        styleButton.setTitle(L.p_style + " " + (mode == .raw ? L.kb_verbatim : L.kb_polish)
                             + " ▾", for: .normal)
    }

    private func toneTitle() -> String { toneLabels[tones.firstIndex(of: tone) ?? 0] }

    @objc private func openSetup() {
        navigationController?.pushViewController(SetupViewController(), animated: true)
    }

    /// 语气改成**下拉菜单**（Kevin 2026-09-04 第二次说：
    /// 「为什么现在还要点一下才能换？之前不是说做成下拉菜单吗？」）。
    ///
    /// 🚨 **一次点开就能看到全部并直接挑**，不用连点 N 下轮一圈 ——
    ///    轮换的毛病是"想要的那个在第 4 个"时他得点 4 次，
    ///    而且**中途每一下都真的改了语气**（点过头就得再转一圈回来）。
    ///
    /// 🚨 选项列表**用 `Prompts.all`**，跟安卓同一份来源，不在这里另列一遍。
    private func toneMenu() -> UIMenu {
        let items = tones.enumerated().map { (i, t) -> UIAction in
            let a = UIAction(title: toneLabels[i],
                             state: t == tone ? .on : .off) { [weak self] _ in
                self?.pickTone(t)
            }
            return a
        }
        return UIMenu(title: L.ex_tone_menu_title, children: items)
    }

    /// 选中某个语气。**唯一写入口** —— 存偏好、刷标题、刷菜单勾选三件事
    /// 必须一起做，散开写就会出现"标题变了但勾还在旧的那条上"。
    private func pickTone(_ t: String) {
        tone = t
        KbBridge.prefs.set(tone, forKey: "vime.tone")
        toneButton.setTitle(L.p_tone + "：" + toneTitle(), for: .normal)
        // 🚨 菜单要**重新生成**才会更新那个勾 —— `UIMenu` 是值类型快照，
        //    改了 `tone` 不会自动反映到已经挂上去的那份。
        toneButton.menu = toneMenu()
    }

    // MARK: - 状态行（唯一写入口）
    //
    // 🚨🚨 **这一行原来有 11 个地方在写，互相覆盖。**（2.1 裁定，判据 S6/S7）
    //    开连续模式冲掉反向提示、切反向冲掉连续提示，
    //    **一开始录音，每秒刷的计时把两条全盖掉。**
    //    安卓那边同一个病：`post(showDir)` 后面紧跟 `post(setText)`，
    //    同一个 Handler、FIFO，**用户从来没看见过那句方向提示**。
    //
    //    → **收两层**（只收一层不够）：
    //      很多地方 → `setOneOff(_:)`  ← 一次性提示那个【槽】的唯一写入口
    //                      ↓
    //                 `applyHint()`    ← `hintLabel.text` 的【唯一】写入口
    //
    // **优先级**（2.1 定）：
    //   ① 一次性提示 ② 录音中的计时 ③ 连续模式 ④ 自动判出的方向 ⑤ 空
    //
    // 🚨 **反向不在表里** —— 它的家是 `revButton`（常驻可见、高亮、可点回去）。
    //    **一个状态必须有且只有一个常驻的家。**
    //    哪天 `revButton` 被撤，反向就**立刻**必须进这一行 ——
    //    **撤按钮和改这一行必须同一次改完**（判据 S8）。

    /// 一次性提示：**只有 `setPhase(.idle, hint:)` 传来的非空 hint** 才进这里。
    ///
    /// 🚨🚨 **判据是 `phase`，不是文案内容**（2.1 2026-08-29 更正了她自己的上一版）：
    ///    她第一版给的是**按内容列举**（"朗读失败 / nothing_to_speak / 其它错误"），
    ///    而我落地时只能**按调用点**归类 —— 于是把「识别中/翻译中/润色中」这类
    ///    **阶段描述**也归进了一次性提示，**等于让「识别中」去压「录音计时」，
    ///    而它俩本来就该同级。**
    ///    **内容清单永远列不全 —— 跟"关键词表补不完"是同一族。**
    ///
    ///    **可执行的归类规则**：
    ///      `.idle` ＝ 没有正在进行的事 → 这时还传一句话，必然是**刚发生完的事**
    ///      `.thinking` / `.listening` ＝ 有事正在进行 → 这时传的话，是**在描述那件事**
    ///    **`phase` 已经把两者分开了，不需要加参数。**
    private var oneOff = ""

    /// 当前阶段自己的描述（`.thinking` 的"识别中/翻译中…"、`.listening` 的计时）。
    private var phaseText = ""

    /// 录音中那行计时。
    private var listeningText = ""

    /// 一次性提示的唯一写入口。
    ///
    /// 🚨 **清它靠状态变化，不靠计时器**：计时器会制造两个问题 ——
    ///    消息在他读到之前就没了，以及"计时器没到就被新状态盖掉"的竞态。
    ///    **状态变化是确定的、可测的；时钟不是。**
    private func setOneOff(_ msg: String) {
        // 🚨🚨 M2：**一次性提示只在 `.idle` 收**。
        //    这原来只是注释里的约定，而 `tapSpeak` 的异步回调可以落在
        //    他**已经开始下一次录音之后** —— `oneOff` 非空会把计时行压住
        //    （`HintPolicy` 里一次性提示优先级高于计时），
        //    `elapsedTimer` 每秒刷也翻不了身，整段录音（最长 60 秒）
        //    提示行卡在「读不出来」。**约定要变成代码强制。**
        guard phase == .idle else { return }
        oneOff = msg
        applyHint()
    }

    /// `hintLabel.text` 的**唯一**写入口。谁都不许绕过它。
    ///
    /// 优先级（2.1 裁定）：
    /// ```
    /// ① 一次性提示（只来自 .idle 的非空 hint）
    /// ② 当前 phase 的描述
    ///      .listening → 录音计时 > 连续模式提示
    ///      .thinking  → 识别中 / 翻译中 / 润色中 / 上屏中
    ///      .idle      → （iOS 暂无自动判方向，留空）
    /// ③ 空
    /// ```
    /// 🚨 **反向不在表里** —— 它的家是 `revButton`（常驻可见、高亮、可点回去）。
    ///    **一个状态必须有且只有一个常驻的家。**
    ///    哪天 `revButton` 被撤，反向就**立刻**必须进这一行 ——
    ///    **撤按钮和改这一行必须同一次改完**（判据 S8）。
    /// 失败时：**给他看人话，同时把原文落进诊断**。
    ///
    /// 🚨🚨 **这两件事必须是同一个动作**（2.1 判据 ERR1/ERR2）。
    ///    上一版我只做了前半 —— 界面对了，**原因丢了**，
    ///    而那正是安卓 2026-08-23 那个 bug 的形状：
    ///    中间层把具体错误吞成泛化消息，Kevin 看到完全静默，我们也查不出原因。
    ///
    /// 🚨 **映射只许发生在这最后一步** —— 上游一路原样传，中间不许改写（ERR3）。
    /// 只落诊断，**不动阶段**。
    ///
    /// 🚨 拆出来是因为：朗读失败可能发生在**录音进行中**，
    ///    而 `showFailure` 会 `setPhase(.idle)` —— **停止键会变回开始键**，
    ///    他按下去是开第二段录音，第一段的回调被顶掉。（复审 H-B）
    private func logFailure(_ raw: String, step: String) {
        RecLog.add(sec: 0, bytes: 0, result: "失败·" + step,
                   detail: String(raw.prefix(200)))
        KbBridge.note("失败·" + step + "：" + String(raw.prefix(120)))
    }

    /// 落诊断 + 回到 idle。**只用于那些确实结束了的失败。**
    private func showFailure(_ raw: String, human: String, step: String) {
        logFailure(raw, step: step)
        setPhase(.idle, hint: human)
    }

    private func applyHint() {
        // 🚨 **判断不在这儿** —— 在 `HintPolicy.pick`（纯函数、带坏实现自测）。
        //    工程里已有教训（`KbBridge.hostAlive` 注释）：
        //    **判断写两遍，等于"测的那份"和"跑的那份"是两码事。**
        //    这里只负责取数。
        let ph: HintPolicy.Phase
        switch phase {
        case .idle: ph = .idle
        case .listening: ph = .listening
        case .thinking: ph = .thinking
        }
        hintLabel.text = HintPolicy.pick(
            oneOff: oneOff, phase: ph, listening: listeningText,
            phaseText: phaseText, continuousText: continuous ? L.try_cont_on : "")
        // 🚨🚨 **状态行没话说的时候，连它上面那段间距一起收掉。**
        //    跟「整理/逐字」那排同一个形状：**空 ≠ 不占位**。
        //    Kevin 09-04 要「麦克风上下等距」——实测（读控件坐标，不数像素）
        //    上 36pt / 下 12pt，多出来的 24 就是这条空状态行的上下两段间距。
        //    收掉之后上下都是 12。
        // 🚨 挂在 `applyHint` 里是因为**它是状态行文字的唯一写入口** ——
        //    挂别处就得靠调用方记得同步，而这一行全项目有十几个触发点。
        let hintEmpty = (hintLabel.text ?? "").isEmpty
        hintTop.constant = hintEmpty ? 0 : Theme.gap
        // 🚨 **连它自己的高度也要收**：空 UILabel 在这个字号下仍占 12pt，
        //    只收间距的话上方还剩 24（实测 up=24 down=12）。
        //    收完两者：上 12 / 下 12，跟他要的「上下等距」对上。
        // 🚨 用 `isActive` 开关一条 0 高约束，不去改 `isHidden` ——
        //    `isHidden` 不会让约束链让位（「整理/逐字」那排就是这么栽的）。
        // 🚨🚨 **约束还没建好时别碰它**。`applyHint()` 在 `viewDidLoad`
        //    建约束**之前**就会被调到，那时 `hintH` 还是个默认构造的空壳
        //    `NSLayoutConstraint()` —— 对它设 `isActive = true` **当场崩**
        //    （改 `.constant` 无害，所以上面两条没事，只有这条会炸）。
        //    端到端测试报的「App 没起来」就是它，**编译一个字都不报**。
        if hintH.firstItem != nil { hintH.isActive = hintEmpty }
    }

    private func setPhase(_ p: Phase, hint: String) {
        phase = p
        // 🚨 H-B：**录音/处理中禁用 🔊**。
        //    不禁的话他点了会【完全没反应】——
        //    M1 之后一次性提示只在 `.idle` 露面，而这时不是 idle。
        //    **让他点不到，比点了没反应好**（每个状态都要跟"没反应"分得开）。
        // 🚨🚨 H4（本轮我自己造的）：**只禁不恢复 = 又一个"点了没反应"**。
        //    `paintOutputButtons()` 是 `isEnabled` 的唯一恢复点，
        //    而失败回到 `.idle` 这条路上原来一个地方都没调它 ——
        //    成功一次 → 再录 → 失败 → 🔊 看得见、永远点不动。
        //    **修 H-B 的手造出了 H-B 要消灭的那个状态。**
        // 🚨 还要连 `alpha` 一起变：**"禁用但长得一样"跟"点了没反应"
        //    在他眼里是同一件事**（跟 `keepButton` 一致）。
        if p == .idle {
            paintOutputButtons()
        } else {
            speakButton.isEnabled = false
            speakButton.alpha = 0.45
        }
        // 🚨 **按 phase 分流**（2.1 裁定）：
        //    `.idle` 的非空 hint ＝ 刚发生完的事 → 一次性提示；
        //    `.thinking` / `.listening` 的 hint ＝ 在描述正在进行的事 → 阶段描述。
        //    **不加新参数，`phase` 本身就是那个参数。**
        if p == .idle {
            phaseText = ""
            listeningText = ""
            setOneOff(hint)          // 空串也要走：状态回 idle 时把上一条清掉
        } else {
            phaseText = hint
            oneOff = ""              // 有事正在进行 → 上一条一次性提示退场
            if p != .listening { listeningText = "" }
            applyHint()
        }
        switch p {
        case .idle:
            micButton.setTitle("", for: .normal)
            Theme.setMicGlyph(micButton, side: Theme.micBarHeight)
            micButton.tintColor = .white
            micButton.backgroundColor = Theme.accent
            micButton.isEnabled = true
        case .listening:
            micButton.setTitle("", for: .normal)
            // 🚨 **`setImage(nil,)` 而不是把图标调透明** ——
            //    UIButton 在自己重绘时会把 `imageView` 的属性复原，
            //    透明那招藏不掉，波形和图标会叠成一团（09-04 面对面栽过一次）。
            micButton.setImage(nil, for: .normal)
            micButton.backgroundColor = Theme.danger
            micButton.isEnabled = true
        case .thinking:
            micButton.setImage(nil, for: .normal)
            // 秒数由 `busyTicker` 每 0.12 秒刷（跟面对面、键盘同一个节奏）。
            // 🚨 原来这里只有一个**静态**的「…」—— 看上去跟卡死没区别，
            //    正是 Kevin 09-05 说的「第三个阶段它没有那个数数」。
            micButton.backgroundColor = Theme.keyDown
            micButton.isEnabled = false
        }
        // 🚨 挂在这个**唯一的渲染出口**上，三态自动都对；
        //    散到起录/停录/失败各处的话，漏一处就会出现
        //    「已经出结果了、秒数还在涨」。
        busyTicker.sync(busy: p == .thinking, on: micButton)
        // 🚨 **波形只在「在听」时出现**，挂在这个唯一的渲染出口上，
        //    不散在起录/停录/失败各处 —— 漏一处就会出现
        //    「已经不录了、波形还在动」，比没有反馈更误导。
        waveView.setActive(p == .listening)
    }

    /// 出了结果才算"体验过"。**跟安卓 `TryActivity` 同一个判据**：
    /// `if (fo.length() > 0) Onboard.markTried(...)`。
    ///
    /// 🚨 判据故意放在这一个函数里，两处调用点都走它 ——
    ///    散成两行 `if ... { Onboard.markTried() }` 就是下一次走散的起点。
    private func markTriedIfProduced(_ out: String) {
        if !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Onboard.markTried()
        }
    }

    @objc private func tapMic() {
        // 🚨🚨 **这里不再 `markTried()`**（2026-08-26 修）。
        //    原来是函数第一行就置位 —— 权限都还没请求。
        //    后果：Kevin 只是点了一下麦克风（弹窗都没点完），
        //    就被记成"体验过了"，下次进来只剩注册登录页。
        //    他的原话：**「没用过，一进去就是登录页」**。
        //
        //    而**安卓那边是拿到非空结果才置位**的
        //    （`TryActivity`：`if (fo.length() > 0) markTried(...)`）。
        //    同一个标志两端两套判据，两边注释还各自说自己那套才对
        //    —— 典型的「同一规则两处实现，悄悄走散」。
        //    现在统一成安卓那套：**真出了结果才算体验过**。
        //    见 `markTriedIfProduced(_:)`。
        // 🚨 权限还没决定就**先请求**，别直接走失败分支 ——
        //    第一次体验的人就是靠这一下拿到麦克风的。
        //    只在 `.undetermined` 时请求：已经被拒过的话系统不会再弹，
        //    那种情况要给去设置的出口，不能装作在等他点（见下面的 else）。
        let perm = Voice.micPermission()
        if perm == .undetermined {
            Voice.requestMic { ok in
                DispatchQueue.main.async {
                    if ok { self.tapMic() }        // 给了就接着走这一次
                }
            }
            return
        }
        if perm == .denied {
            // 被拒过：系统不会再弹，只能去设置里开
            navigationController?.pushViewController(SetupViewController(),
                                                     animated: true)
            return
        }
        if phase == .listening {
            elapsedTimer?.invalidate(); elapsedTimer = nil
            setPhase(.thinking, hint: L.st_recognizing)
            stopVoiceAndMark()
            return
        }
        if phase == .thinking {
            // 🚨🚨 复审 高-2：**这里原来是静默 `return`**，而键盘那条一模一样的路
            //    上一轮已经改成"点一下＝取消"了 —— **同一条规矩两个出口，
            //    只落实一个**（今天第 N 次）。
            //    接上重试之后这个窗口最坏是**三到五分钟**：他盯着灰掉的「…」，
            //    按几次都没反应，而界面上没有任何东西告诉他还能怎么办。
            // 🚨 推代次**必须跟取消同一次做**：单句链原来没有代次闸
            //    （`epoch` 只在连续模式那条查），靠 `phase == .thinking`
            //    挡住重入所以是潜伏的 —— 取消一加上去它立刻变成活的。
            epoch += 1
            // 🚨 高-1：**加 `if voice.running`** —— 全工程其它 5 个调用点都有，
            //    只有这里没有。此刻引擎已经停过一次，对已停引擎再 stop 一次，
            //    只要它不是严格幂等就会二次投递 `onWav`。
            stopVoiceAndMark()
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            KbVoiceHost.shared.reclaimMic()
            logFailure("这一轮被他取消了（处理中点了麦克风）", step: "取消")
            setPhase(.idle, hint: L.kb_cancelled)
            return
        }

        heardLabel.text = ""
        // 🚨 高-2：**起录前先停播放**。全工程原来没有任何一处这么做，
        //    于是"正在播 TTS 时开录"会把我们自己的声音录进去。
        Speaker.stop()
        // 🚨 中-5：**代次 +1**。`idx` 只是数组下标，没有代次的话，
        //    上一轮未回的响应会写进新一轮的同下标行，还覆盖 `lastOut` ——
        //    此时点「收藏」存进单词本的是**上一轮的句子**。
        epoch += 1
        // 🚨🚨 高-1：**在这里捕获，不是在回调里读**。
        //    上一版在 `onWav` 到达之后才 `let ep = self.epoch` —— 那是
        //    **重新取当前值，不是闸**：取消若发生在 `voice.stop()` 与
        //    `onWav` 送达之间，读到的就是取消后的新代次，
        //    下游三道闸全部自我对齐、逐条放行。
        //    键盘 `finishLocal` 那条教训我自己写过，**这个出口没改**。
        let recEpoch = epoch
        resultView.text = ""
        lines.removeAll()
        // 🚨 中-5：`lastOut`/`lastZh` 也要清 —— 不清的话新一轮结果区是空的，
        //    而 🔊 和「收藏」还挂着上一句（回到 `.idle` 就会露出来）。
        lastOut = ""
        lastZh = ""
        // 🚨 M7：清空之后必须刷新按钮 —— 否则「大字」还显示着，
        //    点下去 `tapBig` 的 `guard !text.isEmpty` 静默 return，
        //    又是一个"点了没反应"。
        paintOutputButtons()
        seq = 0
        setPhase(.listening, hint: continuous
                 ? L.try_cont_on
                 : "听着呢，想到哪说到哪（最长 60 秒）\n说完再按一下红色按钮")
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] tm in
            // 🚨 复审 中-4 的后一半：**self 没了就把自己停掉**。
            //    `[weak self]` 只是不持有，**定时器本身仍被 runloop 持有** ——
            //    页面销毁后它会每秒空转到进程结束。
            //    键盘那边的 `retickUI`/`startPendingWatch` 早就这么写了，
            //    主 App 这条一直漏着（**同一条规矩两处实现，只落实了一处**）。
            guard let self = self else { tm.invalidate(); return }
            guard self.phase == .listening else { return }
            let s = Int(self.voice.elapsed)
            self.listeningText = String(format: L.st_listening_ios, s / 60, s % 60)
            self.applyHint()
        }

        // 录音 → 停止后拿到 WAV → 传后端转写 → 再润色（跟安卓同一条链）
        // 🚨 连续模式才传 `onUtterance`。不传 = 老的单句行为，
        //    一个字节的行为差别都没有（同一段 tap，只是不切）。
        // 🚨 待机（替键盘代录）占着麦克风，先让开 —— 两个 AVAudioEngine
        //    抢同一个输入节点会打架，表现是「待机开着时随手翻译录不了音」，
        //    等于新功能把 iOS 上唯一能用的那个录音入口弄坏了。
        KbVoiceHost.shared.yieldMic()

        voiceUsed = true
        // 🚨 **波形要真的跟着他的声音跳**，不能只是个动画 ——
        //    动画在麦克风哑掉时照样在动，那正是"看起来在工作"的假信号。
        //    数据源跟键盘、跟面对面那屏完全一样：`Voice.onLevel`。
        voice.onLevel = { [weak self] v in
            DispatchQueue.main.async { self?.waveView.push(v) }
        }
        voice.start(onPartial: { _ in },
                    onUtterance: continuous ? { [weak self] wav in
                        // 🚨 中-新：**这一层也要闸**。`cut()` 在音频线程里先捕获
                        //    闭包再 `main.async` 排队 —— 对**已经排队**的那一发，
                        //    把 `onUtterance = nil` 是无效的。
                        //    代次推进之后那一发仍会跑 `sendUtterance` 的同步前半段
                        //    （`seq += 1` / `lines.append("")` / `paintLines()`），
                        //    **结果区就永久多一行「…」**。
                        guard let self = self, recEpoch == self.epoch else { return }
                        self.sendUtterance(wav, ep: recEpoch)
                    } : nil,
                    onWav: { [weak self] result in
            DispatchQueue.main.async {
                // 🚨🚨 中-4：**`reclaimMic()` 必须排在 `guard let self` 之前。**
                //    `KbVoiceHost.shared` 是单例，不需要 self；
                //    而页面被销毁（录音中左滑返回）时 self 已经没了，
                //    排在 guard 之后就**永远执行不到** ——
                //    键盘语音待机静默死掉，而首页那个开关还亮着。
                //    （这条注释的下一句自己预言过这件事，然后还是栽了：
                //     规则写对了，位置错了。）
                KbVoiceHost.shared.reclaimMic()
                guard let self = self else { return }
                // 🚨🚨 高-1：**闸在这一层**。下面那三道都以它为基线。
                guard recEpoch == self.epoch else {
                    self.logFailure("录音结果属于上一代（已取消），丢弃", step: "取消")
                    return
                }
                self.elapsedTimer?.invalidate(); self.elapsedTimer = nil
                switch result {
                case .failure(let f):
                    self.showFailure("\(f)", human: f.userText, step: "录音")
                case .success(let wav):
                    // 🚨 连续模式下空 WAV 是**正常收尾**（刚切完一句才按的停止，
                    //    `Voice.stop()` 查过 `hasVoice` 才交空的），不是错。
                    if self.continuous {
                        self.setPhase(.idle, hint: "")
                        if wav.count > 44 { self.sendUtterance(wav, ep: recEpoch) }
                        return
                    }
                    self.setPhase(.thinking, hint: L.st_recognizing)
                    // 🚨 高-2 的后一半：**单句链也要代次闸**。
                    //    🚨 用**起录时**捕获的那一代，**不再重新取值**（高-1）。
                    let ep = recEpoch
                    Backend.transcribe(wav: wav) { [weak self] r in
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            guard ep == self.epoch else {
                                self.logFailure("转写结果属于上一代（已取消），丢弃",
                                                step: "取消")
                                return
                            }
                            switch r {
                            case .failure(let f): self.showFailure("\(f)", human: f.userText, step: "录音")
                            case .success(let zh):
                                self.heardLabel.text = zh
                                self.polish(zh, ep: ep)
                            }
                        }
                    }
                }
            }
        })
    }

    /// 切连续模式。**录音中不许切** —— 切了之后录音器还在老模式跑，
    /// 界面显示的却是新模式，两份状态会对不上。
    @objc private func toggleContinuous() {
        if phase != .idle { return }
        continuous.toggle()
        paintContinuous()
        // 🚨 连续是【设定】，排在计时后面；切设定同时清掉一次性提示
        setOneOff("")
    }

    private func paintContinuous() {
        contButton.backgroundColor = continuous ? Theme.accent : Theme.panel
        contButton.setTitleColor(continuous ? .white : Theme.text,
                                 for: .normal)
    }

    /// 把 `lines` 拼成结果文本。还没回来的那行显示成省略号占位。
    private func paintLines() {
        resultView.text = lines
            .map { $0.isEmpty ? "\u{2026}" : $0 }
            .joined(separator: "\n")
    }

    /// 连续模式：一句走完 transcribe → polish 两步，回填到 `lines[idx]`。
    ///
    /// 🚨 idx **必须贯穿两步**。只在 polish 那步取 `lines.count` 的话，
    ///    第 2 句先回来时会写到第 1 句的位置上。
    /// - Parameter ep: **起录时**捕获的那一代（高-1：别在函数体里重新取）。
    /// **停掉这一轮的一切**（录音、计时、麦克风占位、播放）。
    ///
    /// 🚨🚨 复审 中-2：`onWav` 里那次 `reclaimMic()` 的前提是
    ///    「`onWav` 一定会被送达」—— 而 VC 被 pop 之后 `voice`（lazy、VC 持有）
    ///    随之释放、引擎析构，**`onWav` 大概率根本不回调**。
    ///    于是待机的占位没人还回去：键盘显示「宿主离线」，
    ///    **而首页那条开关仍然高亮「待机中」** —— 他会报
    ///    「待机开着但键盘用不了」，而诊断里什么都没有。
    ///
    /// 🚨 **两个出口走同一个函数**（`viewWillDisappear` / `deinit`）——
    ///    键盘那边为「各写一遍、而且写得不一样」已经栽过一次。
    private func teardown() {
        epoch += 1
        // 🚨 低：`voice` 是 **lazy** —— 在 `deinit` 路径上无条件碰它
        //    会把它**实例化出来**。键盘那边早有一条一模一样的注释
        //    （「别无条件碰 `localVoice`」）——**同一条规矩的第二个出口又漏了**。
        stopVoiceAndMark(lazySafe: true)
        // 🚨 中-1(b)：**busy 也要清**。原来只有 TTS 回调会清，
        //    teardown 之后它是悬空的，而 `paintOutputButtons` 的
        //    `speakBusyEpoch != epoch` 会让 🔊 复活 → 他再点一次 =
        //    **第二个付费 TTS**。
        speakBusyEpoch = nil
        elapsedTimer?.invalidate()
        elapsedTimer = nil
        KbVoiceHost.shared.reclaimMic()
        Speaker.stop()
        // 🚨🚨 高-1：**必须把 `phase` 复位**（跟键盘 `teardown(uiSafe:)` 一致）。
        //    不复位的话 `phase` 停在 `.listening`，回到页面点麦克风走
        //    `stopListening()` → `.thinking` → `voice.stop()` 被 guard 挡回
        //    → `onWav` 永远不来 → **卡死在处理中，而取消入口挂在禁用的按钮上**。
        if phase != .idle { setPhase(.idle, hint: "") }
    }

    private func sendUtterance(_ wav: Data, ep: Int) {
        // 🚨 在**发出去之前**把目标语言定死。等结果时用户点了反向的话，
        //    这一句会用错的语言回来。
        let fLang = langNow
        // 🚨 低-3：**`mode`/`tone` 也要冻结**。原来只冻了 `lang`，
        //    这两个是在回调里现读的 —— 连续模式下他说完第 1 句马上点「转写」，
        //    第 1 句在飞的结果会用**新档位**去润色，而屏上第 1 行显示的是它。
        //    （单句模式 `.thinking` 期间点 Tab 同理，Tab 没禁用。）
        let fMode: Backend.Mode = (reversed && mode == .raw) ? .en : mode   // 同主流程：反向时逐字临时提升，不写偏好
        let fTone = tone
        let idx = seq
        seq += 1
        lines.append("")            // 先占位，保住说话的顺序
        paintLines()
        Backend.transcribe(wav: wav) { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // 🚨 中-5：**外层这一道当初漏了**。上一版只在内层 polish 回调
                //    插了代次闸，而 transcribe 失败这条路直接写 `setLine` ——
                //    上一轮在飞的转写失败照样能写进新一轮的同下标行。
                //    **一个函数里有两层异步，闸就要两道**（覆盖面又一次比以为的小）。
                guard ep == self.epoch else { return }
                switch r {
                case .failure(let f):
                    // 错误落在**那一行**上，别把整块已经出来的结果冲掉
                    // 🚨 H3：**原文不上屏**（`"\(f)"` 是 description，
                    //    形如 `HTTP 500` / `[internal] 后端原文`），
                    //    而且原来**一个字诊断都没落**。
                    self.logFailure("\(f)", step: "连续")
                    self.setLine(idx, f.userText)
                case .success(let zh):
                    self.heardLabel.text = zh
                    // 🚨 反向时目标语言换成**我的语言**。
                    //    用 `self.lang` 的话反向按钮点了等于没点，
                    //    而界面还亮着 —— 那种"看起来生效了"的错最难查。
                    Backend.polish(text: zh, tone: fTone,
                                   mode: fMode, lang: fLang) {
                        [weak self] r2 in
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            // 🚨 中-5：不是本代就整条丢弃（上一轮在飞的结果）。
                            //    🚨 **必须排在 `guard let self` 之后** ——
                            //    在它之前 `self` 还是 optional，编译不过。
                            guard ep == self.epoch else { return }
                            switch r2 {
                            case .success(let en):
                                // 🚨 高-1：两条链都走**同一个出口**
                                self.commitResult(zh: zh, out: en)
                                self.paintOutputButtons()
                                self.setLine(idx, en)
                                // 🚨 连续模式也要算 —— 少接一处的话，
                                //    只用连续模式的人永远解锁不了。
                                self.markTriedIfProduced(en)
                            case .failure(let e):
                                self.logFailure("\(e)", step: "连续")
                                self.setLine(idx, e.userText)
                            }
                        }
                    }
                }
            }
        }
    }

    /// 切正向/反向。**录音中不许切** —— 这一次录的是谁的话，
    /// 中途改了的话发出去的目标语言跟界面显示的对不上。
    @objc private func tapReverse() {
        if phase != .idle { return }
        reversed.toggle()
        revButton.setTitle(reversed ? L.try_dir_them : L.try_dir_me,
                           for: .normal)
        revButton.backgroundColor = reversed ? Theme.accent : Theme.key
        revButton.setTitleColor(reversed ? .white : Theme.text, for: .normal)
        // 🚨 **反向不进这一行** —— 它的家是 `revButton`（常驻可见、高亮、可点回去）。
        //    2.1 裁定：一个状态必须有且只有一个常驻的家。
        //    🚨 哪天 `revButton` 被撤，反向就【立刻】必须进这一行，
        //       **撤按钮和改这一行必须同一次改完**（判据 S8）。
        setOneOff("")
        // 🚨 反向必须是**翻译**模式。停在「逐字」上的话，
        //    对方说的英文会被原样吐回来 —— 一个字都没翻，
        //    而用户以为反向没生效。
        // 2026-09-03（2.1 裁定）：反向那一次用 .en 出稿是对的，但**不许写偏好**——
        //    原来这里 pickEn() → setMode(.en) 持久改了他的默认档，反向关掉也不改回，
        //    他会在下次按麦克风时拿到英文、以为「又坏了」。改成在发送处临时覆盖（fMode）。
        //    判据：逐字 → 反向 → 回正向，档位仍是逐字。
    }

    /// 这一次要译成什么语言。
    ///
    /// 🚨 反向时走 `Reverse`（两端同一份口径、有自测），
    ///    **不要在这里现写 if-else**。
    private var langNow: String {
        return reversed ? Reverse.target(for: Lang.current) : lang
    }

    /// 「朗读 / 大字」的显隐。**只由这里决定**，别在别处再写一遍。
    ///
    /// 🚨 跟安卓一致：没内容时**隐藏**（不是置灰）。
    ///    `speakBtn.setVisibility(lastText.length() > 0 ? VISIBLE : GONE)`
    ///
    /// 🚨 两个判据不同，别合并：
    ///    朗读看 `lastOut`（念最后那一句），
    ///    大字看 `resultView`（展示整段 —— 连续模式下有好几句）。
    private func paintOutputButtons() {
        // 🚨🚨 这两行**曾经被我自己的批量正则替换成了 `paintOutputButtons()`**，
        //    于是方法调用自己 → 无限递归 → EXC_BAD_ACCESS/SIGSEGV，
        //    App 一启动就崩。**编译完全通过**，只有真跑才看得见。
        //    根因是顺序错了：我先插入这个方法、再跑全局替换，
        //    方法体自然也在替换范围里。
        //    → 批量替换一律**先换、后插新代码**；插完再 grep 一遍新方法体。
        // 🚨🚨 **`phase` 必须收进这个唯一出口**（复审 高-2）。
        //    H4 让 `.idle` 分支调这个函数，等于把「能不能点 🔊」的判据
        //    从 `phase` 换成了 `lastOut.isEmpty` —— 而这个函数**不知道 phase**，
        //    它的三个异步调用点（tapSpeak 回调 / setLine / sendUtterance）
        //    会在 `.listening`、`.thinking` 时把 🔊 **重新点亮**。
        //    最坏那条：录音中点 🔊 → TTS **播进热麦克风**、录进这一句，
        //    他以为"识别乱了"。连续模式下这是主路径，必然发生。
        // 🚨 `isHidden` 仍只看 `lastOut` —— 录音时把按钮藏掉会跳版。
        //    **不可点** 和 **不存在** 是两回事，这里要的是前者。
        let hasText = !lastOut.isEmpty
        // 🚨 高-2：busy 也收进来，跟键盘的 `paintSpeakButton(busy:)` 对称。
        let canSpeak = hasText && phase == .idle && speakBusyEpoch != epoch
        let canBig = !bigTextNow().isEmpty
        speakButton.isHidden = !hasText
        speakButton.isEnabled = canSpeak
        // 🚨 **alpha 必须跟着 isEnabled 一起恢复**。
        //    `setPhase` 非 idle 时把它压到 0.45，而这里是唯一的恢复点 ——
        //    不写这一行，按钮**永远灰着**（能点，但看着像坏的）。
        //    禁用状态要看得出来，恢复也要看得出来，**两边对称**。
        speakButton.alpha = canSpeak ? 1.0 : 0.45
        // 🚨 中-2：**title 也要收进来**。原来是「三个属性走唯一出口、
        //    第四个散在三处」—— 点 🔊 → 飞行中开录 → 结果被丢弃，
        //    录完出了新译文之后按钮可点可用、**脸上还写着「…」**。
        speakButton.setTitle(speakBusyEpoch == epoch ? "…"
                             : (Speaker.isPlaying ? L.kb_stop : L.kb_speak),
                             for: .normal)
        // 🚨 收藏跟朗读同一个判据（**有这一句**才出现），
        //    不跟大字（那个看的是整段）。收过的置灰写「已收」。
        keepButton.isHidden = !hasText
        paintKeepButton()
        bigButton.isHidden = !canBig
        bigButton.isEnabled = canBig
    }

    /// 现在该拿去大字展示的内容：连续模式给整段，单句模式给那一句。
    private func bigTextNow() -> String {
        return (resultView.text ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines)
    }

    /// 大字展示：译文铺满屏幕，点一下关掉。
    /// 这一句收过没有。用**同一个 id 算法**，不另写判断。
    private func inBook() -> Bool {
        if lastOut.isEmpty { return false }
        let id = WordBookCore.idOf(lastZh, lastOut)
        return WordBook.list().contains { $0.id == id }
    }

    private func paintKeepButton() {
        let got = inBook()
        keepButton.setTitle(got ? L.kb_kept : L.kb_keep, for: .normal)
        keepButton.isEnabled = !got
        keepButton.alpha = got ? 0.45 : 1
    }

    /// 收进单词本。
    ///
    /// 🚨 **按真实结果显示**，不是先宣布成功 —— 安卓键盘那边我犯过这个错：
    ///    无条件把按钮改成「已收」，而 `add` 可能返回 error/empty/nogroup，
    ///    用户以为收了、本子里没有。
    @objc private func tapKeep() {
        guard !lastOut.isEmpty else { return }
        let r = WordBook.add(zh: lastZh, en: lastOut, span: "full",
                             tone: tone, today: Srs.todayString())
        let ok = (r == "added" || r == "added_evicted" || r == "same")
        paintKeepButton()
        let msg = (r == "same") ? L.wb_dupe : (ok ? L.wb_saved : L.wb_save_failed)
        let a = UIAlertController(title: nil, message: msg,
                                  preferredStyle: .alert)
        present(a, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            a.dismiss(animated: true)
        }
    }

    /// 大字页要朗读时调这里 —— **复用主页面那条朗读链**，
    /// 不在大字页里再写一份（同一件事两份实现必漂，今天已经栽过一次）。
    private func speakForBig(_ t: String, _ done: @escaping () -> Void) {
        // 🚨 `Speaker` 只有 `play(mp3:)`，没有 `speak(text:)` ——
        //    先取 TTS 再播，跟 `tapSpeak()` 同一条链（`Backend.speak` → `Speaker.play`）。
        // 🚨 这里**不带 epoch 守卫**，跟 `tapSpeak()` 不同，理由写清楚：
        //    大字页是模态盖在主页面上的，presented 期间录不了音、也不会有新一代结果，
        //    那几个 `guard ep == self.epoch` 在这条路上恒真 ——
        //    抄进来就是一处永远不会失败的假判断。
        Backend.speak(text: t) { r in
            DispatchQueue.main.async {
                if case .success(let mp3) = r {
                    Speaker.play(mp3) { _ in DispatchQueue.main.async { done() } }
                } else {
                    done()
                }
            }
        }
    }

    @objc private func tapBig() {
        // 🚨 2026-09-03 拉齐安卓：**空也要弹**，弹出来显示 `try_big_empty`。
        //    原来 `guard !text.isEmpty else { return }` —— 点了没反应，
        //    他不知道是没内容还是按钮坏了。安卓 `paintBig()` 是给空态留了文案的。
        let t = bigTextNow()
        let vc = BigTextViewController(text: t)
        // 朗读接回主页面那套（这一页不自己碰播放器）。
        vc.onSpeak = { [weak self] s, done in self?.speakForBig(s, done) }
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }

    private func setLine(_ idx: Int, _ text: String) {
        guard idx < lines.count else { return }
        lines[idx] = text
        paintLines()
        // 🚨 大字按钮的判据是**结果区有没有东西**，不是 `lastOut` ——
        //    连续模式下 lastOut 只是最后一句，而结果区是整段对话。
        paintOutputButtons()
    }

    /// - Parameter ep: 起录时那一代。**取消之后旧结果不许上屏**
    ///   （复审 高-2：取消一加上去，这条潜伏的路立刻变成活的）。
    /// 🚨 低：`tone`/`mode`/`langNow` **在这里冻结**。
    ///    `sendUtterance` 已经冻结了而这里没有 —— 同一条规矩两个出口。
    ///    后果：`.thinking` 期间他点了 Tab，在飞的那一句会用**新档位**润色。
    /// 一句结果落地的**唯一出口**。
    ///
    /// 🚨🚨 复审 高-1：原来 `polish`（单句）只写 `lastOut`、`sendUtterance`（连续）
    ///    才写 `lastZh` —— **单句那条链一次都没写过 `lastZh`，而单句是他日常走的**。
    ///    后果：收藏进单词本的**中文原话是空串**，而且 `idOf("", out)` 算出来的 id
    ///    跟另一端用真 zh 算的**对不上** → 同一句在两端被当成两条，
    ///    「已收」判重跨端失效。**按钮照样变「已收」，界面上完全看不出来。**
    ///    → 收成一个出口，两条链都调它。
    /// 这一段说了多久（毫秒）。**在按停的那一刻记下来** ——
    /// `voice.elapsed` 在引擎停掉之后就归零了，等结果回来再问它永远是 0。
    private var lastSpokeMs = 0

    /// 停引擎，**并记下这一段说了多久**。三条停止路径都走这里。
    ///
    /// 🚨 收成一个方法而不是三处各写一遍：这正是这个文件里反复栽过的形态 ——
    ///    「全工程其它 5 个调用点都有 `if voice.running`，只有这里没有」
    ///    （见下面 3846 那条注释）。同一件事三个出口，漏一个就是那条路
    ///    **静默不计时长**，而 KPI③ 少算是看不出来的。
    /// 🚨 `lazySafe`：`voice` 是 lazy 的，`deinit` 路径上无条件碰它会把它
    ///    实例化出来。那条路要传 `true`。
    private func stopVoiceAndMark(lazySafe: Bool = false) {
        if lazySafe && !voiceUsed { return }
        guard voice.running else { return }
        lastSpokeMs = Int(voice.elapsed * 1000)
        voice.stop()
    }

    private func commitResult(zh: String, out: String) {
        lastZh = zh
        lastOut = out
        // 🚨🚨 2026-09-04 补：**随手翻译说的话原来一条都没进说话记录**。
        //    iOS 上 `History.add` 只有键盘在调 —— 而安卓 `TryActivity` 和
        //    `FaceToFaceActivity` 都调了。后果有两层：
        //      ① 在随手翻译里说的话，「说话记录」Tab 里**看不见**；
        //      ② KPI ③④（累计说话 / 说了多少字）**少算**这一整条入口。
        //    挂在 `commitResult` 是因为它是**出结果的唯一咽喉**（单句和连续
        //    两条成功路径都经它）—— 挂在每条成功分支上就是三处实现。
        //
        // 🚨 `mode` 要转成 History 认的字符串。**逐字档也记**：它也是他说的话。
        // 🚨 `lang` 只有翻译档才有目标语言，整理/逐字传空 —— 跟键盘那两处一致。
        let m: String
        switch mode {
        case .en:  m = "en"
        case .zh:  m = "zh"
        case .raw: m = "raw"
        }
        History.add(mode: m, tone: tone, zh: zh, out: out,
                    durMs: lastSpokeMs,
                    lang: m == "en" ? langNow : "")
        // 🚨 用完清零：不清的话下一句要是没经过 `stopVoiceAndMark`
        //    （比如从别的路径来的结果），会把**上一句的时长**记到这一句头上。
        //    KPI③ 多算比少算更难发现。
        lastSpokeMs = 0
    }

    private func polish(_ zh: String, ep: Int) {
        let fTone = tone
        let fMode: Backend.Mode = (reversed && mode == .raw) ? .en : mode   // 反向时逐字临时提升为翻译，不写偏好
        switch fMode {
        case .en:  setPhase(.thinking, hint: L.st_translating)
        case .zh:  setPhase(.thinking, hint: L.st_polishing)
        case .raw: setPhase(.thinking, hint: L.st_inserting)   // 不过模型，一瞬间
        }
        let fLang = langNow
        Backend.polish(text: zh, tone: fTone, mode: fMode, lang: fLang) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard ep == self.epoch else {
                    self.logFailure("润色结果属于上一代（已取消），丢弃", step: "取消")
                    return
                }
                switch result {
                case .success(let en):
                    self.resultView.text = en
                    self.paintOutputButtons()
                    UIPasteboard.general.string = en   // 自动进剪贴板
                    // 🚨🚨 高-1：**这里原来只写 `lastOut`，没写 `lastZh`** ——
                    //    单句是他日常走的那条，于是收藏进单词本的中文原话是空串，
                    //    且 `idOf("", out)` 跟另一端算出来的 id 对不上。
                    self.commitResult(zh: zh, out: en)
                    // 🚨 **真出了结果才算体验过** —— 跟安卓 `TryActivity`
                    //    的 `if (fo.length() > 0) markTried(...)` 同一个判据。
                    self.markTriedIfProduced(en)
                    self.paintOutputButtons()
                    self.setPhase(.idle, hint: L.ok_copied)
                case .failure(let err):
                    self.showFailure("\(err)", human: err.userText, step: "上屏")
                }
            }
        }
    }
}



// MARK: - 键盘预览（只给 TRANSLESS_PAGE=kb 用）

/// 把打字键盘按**它在键盘扩展里的真实高度**摆出来，贴在屏幕底部。
/// 上面留一个假的输入框，好看清键盘和输入区的相对关系（跟安卓截图对齐用）。
/// 键盘预览：**把真的 `KeyboardViewController` 嵌进来跑**。
///
/// 🚨🚨 上一版是我自己摆的一个假页面（直接 new 一个 `TypingKeyboardView`），
///    于是截图永远显示"打字键盘、跟安卓一致"，
///    而用户打开键盘看到的是语音面板、比安卓少两整行 ——
///    我"验过"的每一次都是白验。**判据挂在了错的对象上。**
///    （Kevin 2026-08-26 真机截图打脸后重写。）
///
/// 🚨 仍有两处跟真扩展不同，**写清楚，别当等价**：
///    ① 没有宿主输入框，`textDocumentProxy` 是空的 → 能验版面，不能验上屏
///    ② `hasFullAccess` 在容器 App 里恒 false → 预览里会看到那行红字，
///       那是预览环境的限制，不代表真机也这样
final class KeyboardPreviewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // 🚨🚨 2026-09-03：配色改成跟宿主外观分叉之后，这里**必须先设
        //    `Theme.hostIsLight`**，否则预览页永远按深色画 ——
        //    我截出来的图就代表不了他手机上那份（宿主是浅色的微信）。
        //    这正是「量的对象跟结论说的对象不是一个」那一族：
        //    图截得再清楚，画的不是同一套配色就说明不了任何事。
        //    默认跟模拟器外观走，也可以用 TRANSLESS_KB_LIGHT=0/1 显式指定。
        if let f = ProcessInfo.processInfo.environment["TRANSLESS_KB_LIGHT"] {
            Theme.hostIsLight = (f == "1")
        } else {
            Theme.hostIsLight = (traitCollection.userInterfaceStyle == .light)
        }
        // 🚨🚨 预览壳的底**故意用一个跟键盘完全不同的纯色**（2026-08-26 改）。
        //    原来这里铺的是 `Theme.keyboardBackground` —— **跟键盘自己的底
        //    一模一样**，于是截图上"键盘从哪儿开始"根本看不出边界，
        //    量高度的脚本只能退而求其次去找"第一行有结构的内容"，
        //    量到的是**内容顶边**而不是键盘视图的高度：
        //    语音面板和打字键盘的内边距不同，就会量出假的高度差。
        //    换成纯色之后，"不是这个色的那一块"就是键盘，边界是硬的。
        //    🚨 只影响预览页（`TRANSLESS_PAGE=kb`），正式界面没有入口。
        view.backgroundColor = UIColor(red: 0.10, green: 0.42, blue: 0.16,
                                       alpha: 1)   // 深绿，键盘配色里没有

        let fake = UILabel()
        // 调试页：正式界面没有入口（TRANSLESS_PAGE=kb 才进得来）
        fake.text = "  预览：真实键盘扩展（KeyboardViewController）"
        fake.font = .systemFont(ofSize: 13)
        fake.textColor = Theme.dim
        fake.backgroundColor = UIColor.white.withAlphaComponent(0.08)
        fake.layer.cornerRadius = 8
        fake.layer.masksToBounds = true
        fake.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fake)

        // 🚨 **真的那个类**，不是复刻。改了键盘，这里跟着变；
        //    改漏了，这里也一眼看得出来。
        let kb = KeyboardViewController()
        kb.previewMode = true
        addChild(kb)
        kb.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(kb.view)
        kb.didMove(toParent: self)

        NSLayoutConstraint.activate([
            fake.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            fake.leadingAnchor.constraint(equalTo: view.leadingAnchor,
                                          constant: 12),
            fake.trailingAnchor.constraint(equalTo: view.trailingAnchor,
                                           constant: -12),
            fake.heightAnchor.constraint(equalToConstant: 40),

            kb.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            kb.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            kb.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 🚨 预览页切到打字键盘并跳到指定档位（**只给截图/量高度用**，
        //    正式界面没有入口 —— 走的是环境变量 `TRANSLESS_KB_MODE`）。
        //
        // 🚨 这个环境变量原来挂在 `_OldFakeKeyboardPreview` 上，而那个类
        //    **已经没有任何入口引用**（它自己的注释就这么写着）——
        //    也就是说它是**死的**。我第一次截各档位的图时被它骗了：
        //    设了 mode、截出来三张一模一样的语音面板，还差点交出去。
        //    现在接到**真的那个键盘**上。
        if let m = ProcessInfo.processInfo.environment["TRANSLESS_KB_MODE"],
           !m.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                kb.showTyping()
                if m != "pinyin" { kb.typingView?.debugMode(m) }
            }
        }
    }
}

// 下面这个是**旧的假预览**，留着只为对照，不再被任何入口引用。
private final class _OldFakeKeyboardPreview: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // 🚨🚨 预览页**必须复刻键盘扩展里的环境**，否则截出来的图不代表真相。
        //    第一版我在这里刷了个灰底，截图一片灰 —— 我差点以为是键盘配色错了，
        //    去改 TypingKeyboard 的颜色。实际扩展里
        //    `KeyboardViewController` 铺的是 `Theme.keyboardBackground`，
        //    键是 `#16FFFFFF` 半透明白，**透的是什么底就是什么色**。
        view.backgroundColor = .clear
        let bg = Theme.keyboardBackground(UIScreen.main.bounds)
        bg.frame = UIScreen.main.bounds
        bg.sublayers?.forEach { $0.frame = UIScreen.main.bounds }
        view.layer.insertSublayer(bg, at: 0)

        let fakeField = UILabel()
        // 调试页：正式界面没有入口（TRANSLESS_PAGE=kb 才进得来）
        fakeField.text = "  预览：打字键盘"
        fakeField.textColor = UIColor(white: 0.6, alpha: 1)
        fakeField.font = .systemFont(ofSize: 15)
        fakeField.backgroundColor = UIColor(white: 0.16, alpha: 1)
        fakeField.layer.cornerRadius = 8
        fakeField.clipsToBounds = true
        fakeField.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fakeField)

        let kb = TypingKeyboardView()
        // 预览页也要跟着档位改高，否则截出来的图跟真实键盘不是一回事
        let kbH = kb.heightAnchor.constraint(equalToConstant: kb.preferredHeight)
        kb.onHeightChange = { h in kbH.constant = h }
        // 🚨 预览页把 composing 显示在上面那个假输入框里 ——
        //    键盘扩展里它进的是宿主 App 的输入框，这里没有宿主。
        kb.onComposing = { [weak fakeField] s in
            // 调试页：正式界面没有入口（TRANSLESS_PAGE=kb 才进得来）
            fakeField?.text = s.isEmpty ? "  预览：打字键盘" : "  " + s
        }
        kb.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(kb)

        NSLayoutConstraint.activate([
            fakeField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            fakeField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            fakeField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            fakeField.heightAnchor.constraint(equalToConstant: 40),

            kb.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            kb.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            kb.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            // 键盘扩展里给的是 280（见 KeyboardViewController.showTyping）
            kbH,
        ])

        if let m = ProcessInfo.processInfo.environment["TRANSLESS_KB_MODE"],
           !m.isEmpty {
            kb.debugMode(m)
        }

        // 自动按键：让候选栏在截图里有东西，且走的是真实按键路径。
        if let seq = ProcessInfo.processInfo.environment["TRANSLESS_KB_TYPE"],
           !seq.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                for ch in seq { kb.debugTap(String(ch)) }
            }
        }
    }
}


// MARK: - 大字展示

/// 译文铺满屏幕，点一下关掉。旅游时手机一转给对方看。
///
/// 🚨 字号走 `BigText`（跟安卓同一张表、有自测），**不在这里现算**。
/// 🚨 展示期间不让屏幕灭掉 —— 给对方看的时候没人在碰手机，
///    十几秒就黑屏了。`isIdleTimerDisabled` 在 `viewWillDisappear` 里**必须
///    还原**，否则整个 App 从此不再自动锁屏（用户会当成耗电 bug）。
final class BigTextViewController: UIViewController {
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // 🚨 中-4：转屏后要跟着改 frame（这一页就是给人转屏看的）。
        UI.resizeBg(self)
    }


    private let text: String
    private let hint = UILabel()

    /// 朗读交给调用方做 —— 这一页不自己碰网络/播放器。
    /// 参数：要念的文字、念完/失败后回调（用来把提示行刷回去）。
    var onSpeak: ((String, @escaping () -> Void) -> Void)?

    init(text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) 用不到") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // 🚨 用**主界面那个渐变底**（`Skin.screenBg`），不是 `Theme.bg` ——
        //    后者是**键盘扩展**的底色。这两个搞混过一次，被漂移闸门抓出来。
        //    也别自己挑颜色：Kevin 说过「你不要自己设计了」。
        // 🚨 **不设 backgroundColor** —— 主 App 的页面一律只插渐变层。
        //    我第一版写了 `Theme.bg`，那是**键盘扩展**的底色，
        //    当场被漂移闸门拦下来（`iOS 跟安卓没有漂移` 那一项）。
        //    页面别处（AppDelegate:108）就是只 insertSublayer、不设色。
        // 🚨 复审 中-4：**改走单一配置点**。原来自己插层、层没起名 `skinBg`，
        //    所以 `UI.resizeBg` 够不着它 —— 而这个页面的用途**就是转屏给对方看**
        //    （注释自己写着「旅游时手机一转给对方看」）。
        //    横屏后 `view.bounds` 变成 844×390 而层还是 390×844，
        //    右侧约一半没有任何背景（`backgroundColor` 是 nil）。
        UI.paintBg(self)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        // 🚨 空态照安卓 `paintBig()`：文字换成 `try_big_empty`、字号固定 28
        //    （不走 `BigText.size` —— 那张表是给正文长度分档的，
        //     拿去算一句提示语没有意义）。
        let empty = text.isEmpty
        let label = UILabel()
        label.text = empty ? L.try_big_empty : text
        label.textColor = .white
        label.font = .systemFont(ofSize: empty ? 28 : BigText.size(text),
                                 weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(label)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            label.topAnchor.constraint(greaterThanOrEqualTo: scroll.topAnchor, constant: 20),
            label.bottomAnchor.constraint(lessThanOrEqualTo: scroll.bottomAnchor, constant: -20),
            label.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -20),
            label.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -40),
            // 🚨 文字少时要**垂直居中**，不能贴在顶上。
            //    `centerY` 用低优先级，文字长到撑破一屏时让它让位给上面
            //    那两条 greaterThan/lessThan，否则约束会冲突。
            {
                let c = label.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
                c.priority = .defaultHigh
                return c
            }(),
        ])

        // ── 以下是 2026-09-03 拉齐安卓补的（队列②）────────────────────
        // 🚨 **点大字＝切换朗读，不是关闭**（安卓 `showBig()` 里挂的是 `toggle()`）。
        //    iOS 原来点任意处直接 dismiss —— 两端点同一个地方结果相反，
        //    这是功能差异不是样式差异。关闭改成右上角那个 ×，跟安卓一致。
        let tap = UITapGestureRecognizer(target: self,
                                         action: #selector(toggleSpeak))
        view.addGestureRecognizer(tap)

        // 提示行：告诉他点一下会发生什么。安卓 `bigHint`，14sp、白 55%。
        hint.textColor = UIColor(white: 1, alpha: 0.55)
        hint.font = .systemFont(ofSize: 14)
        hint.textAlignment = .center
        hint.numberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)

        // 右上角 ×。安卓 30sp、白 75%、四周 10dp 内边距。
        // 🚨 **可点区域给到 44×44**（苹果最小可点尺寸）——
        //    安卓靠 padding 撑，iOS 这边用约束写死，别只把字号调大。
        let close = UIButton(type: .system)
        close.setTitle("×", for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 30)
        close.setTitleColor(UIColor(white: 1, alpha: 0.75), for: .normal)
        close.accessibilityLabel = L.try_big_close
        close.addTarget(self, action: #selector(close_), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(close)

        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            hint.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),

            close.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            close.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -8),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
        ])
        paintHint()
    }

    /// 提示行的文案。安卓 `paintBig()` 的优先级：朗读中 > 点一下。
    /// 🚨 iOS 这一页是**模态盖在主页面上**的，presented 期间不会在录音/识别，
    ///    所以安卓那两档（`try_listening` / `try_working`）在这里够不着，
    ///    不照抄进来 —— 抄一个永远为假的分支，就是又一处假代码。
    private func paintHint() {
        hint.text = Speaker.isPlaying ? L.try_big_speaking : L.try_big_tap
    }

    /// 点正文：切换朗读。跟安卓 `toggle()` 同义。
    @objc private func toggleSpeak() {
        if Speaker.isPlaying {
            Speaker.stop()
            paintHint()
            return
        }
        guard !text.isEmpty else { return }
        onSpeak?(text) { [weak self] in self?.paintHint() }
        paintHint()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 🚨 一定要还原 —— 忘了的话整个 App 从此不自动锁屏。
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// 只有右上角那个 × 会走到这里 —— 点正文是朗读，不是关闭。
    @objc private func close_() {
        Speaker.stop()          // 🚨 关页面必须停朗读，否则声音会在他看不见的地方继续念
        dismiss(animated: true)
    }
}


extension UIView {
    /// 给「就绪提示」那一屏用的：点一下自己消失。
    @objc func kbRemoveSelf() { removeFromSuperview() }
}

/// 登录门 —— **全 App 单一实现**（首页和设置页共用）。
///
/// 2026-09-04 单词本入口从首页挪进设置后，两个页面都要弹同一道门。
/// 🚨 抽成扩展而不是各写一份：「同一规矩两处实现」是这个项目栽过多次的坑
///    （同一决定散在两处，改一处等于没改）。
///
/// 🚨 文案是 Kevin 给的，**照抄，不许自己发挥**：
///   · 不许出现"还能免费用 N 次" —— 核心翻译**不限次**，那句是假的
///   · 不许写"解锁高级功能" —— 要说清解锁的是**哪个具体功能**
///
/// 🚨 返回 true = 已登录、调用方接着做自己的事；
///    返回 false = 已经弹了引导，调用方**必须直接返回**。
extension UIViewController {
    func loginGate(_ why: String) -> Bool {
        if Auth.loggedIn { return true }
        let a = UIAlertController(title: nil, message: why,
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: L.login_gate_go,
                                  style: .default) { [weak self] _ in
            self?.navigationController?.pushViewController(
                LoginViewController(), animated: true)
        })
        // 🚨 「以后再说」= N1-e 的退路。点了什么都不做，
        //    首页原样留着，随手翻译照常能用。
        a.addAction(UIAlertAction(title: L.login_gate_later, style: .cancel))
        present(a, animated: true)
        return false
    }
}
