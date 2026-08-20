import UIKit
import AVFoundation
import Speech

// 容器 App。iOS 规定键盘扩展必须挂在一个 App 里。
// 它只干两件事：把两个权限要过一次（键盘扩展里弹不出系统权限框），
// 以及告诉他去哪儿启用键盘。

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ app: UIApplication,
                     didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = SetupViewController()
        w.makeKeyAndVisible()
        window = w
        return true
    }
}

final class SetupViewController: UIViewController {

    private let micState = UILabel()
    private let speechState = UILabel()
    private let testOut = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let title = UILabel()
        title.text = "Transless"
        title.font = .systemFont(ofSize: 30, weight: .bold)

        let sub = UILabel()
        sub.text = "说中文，出结构化英文。什么都不用填，下面两步做完就能用。"
        sub.font = .systemFont(ofSize: 14)
        sub.textColor = .secondaryLabel
        sub.numberOfLines = 0

        let s1 = step("第 1 步 · 允许麦克风和语音识别",
                      "键盘扩展自己弹不出权限框，只能在这里给一次。")
        [micState, speechState].forEach {
            $0.font = .systemFont(ofSize: 14)
            $0.numberOfLines = 0
        }
        let askBtn = button("允许麦克风和语音识别", #selector(askPerms))

        let s2 = step("第 2 步 · 启用 Transless 键盘",
                      "设置 > 通用 > 键盘 > 键盘 > 添加新键盘 > Transless，"
                    + "然后点进它把「允许完全访问」打开（不开就发不出网络请求）。")
        let openBtn = button("打开系统设置", #selector(openSettings))

        let s3 = step("自测 · 先跑一遍再去键盘里用", "")
        let testBtn = button("测一次", #selector(selfTest))
        testOut.font = .systemFont(ofSize: 13)
        testOut.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [
            title, sub,
            s1, micState, speechState, askBtn,
            s2, openBtn,
            s3, testBtn, testOut,
        ])
        stack.axis = .vertical
        stack.spacing = 10
        stack.setCustomSpacing(22, after: sub)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -40),
        ])
        refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refresh()
    }

    private func step(_ t: String, _ why: String) -> UIStackView {
        let a = UILabel()
        a.text = t
        a.font = .systemFont(ofSize: 17, weight: .semibold)
        let b = UILabel()
        b.text = why
        b.font = .systemFont(ofSize: 13)
        b.textColor = .secondaryLabel
        b.numberOfLines = 0
        let s = UIStackView(arrangedSubviews: why.isEmpty ? [a] : [a, b])
        s.axis = .vertical
        s.spacing = 4
        return s
    }

    private func button(_ t: String, _ sel: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(t, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        b.backgroundColor = .secondarySystemBackground
        b.layer.cornerRadius = 10
        b.heightAnchor.constraint(equalToConstant: 46).isActive = true
        b.addTarget(self, action: sel, for: .touchUpInside)
        return b
    }

    private func refresh() {
        let mic = AVAudioSession.sharedInstance().recordPermission == .granted
        let sp = SFSpeechRecognizer.authorizationStatus() == .authorized
        micState.text = mic ? "麦克风：已允许 ✓" : "麦克风：还没允许"
        micState.textColor = mic ? .systemTeal : .systemOrange
        speechState.text = sp ? "语音识别：已允许 ✓" : "语音识别：还没允许"
        speechState.textColor = sp ? .systemTeal : .systemOrange
    }

    @objc private func askPerms() {
        AVAudioSession.sharedInstance().requestRecordPermission { _ in
            SFSpeechRecognizer.requestAuthorization { _ in
                DispatchQueue.main.async { self.refresh() }
            }
        }
    }

    @objc private func openSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(u)
        }
    }

    /// 自测：判据不是"没报错"，是英文里必须保住关键事实。
    @objc private func selfTest() {
        let sample = "哎那个我跟你说一下啊,就是那个报表啊,嗯,我明天早上,"
                   + "不对,是明天下午三点之前给你,然后要抄送给 Annie。"
        testOut.text = "测试中…"
        testOut.textColor = .secondaryLabel
        Backend.polish(text: sample, tone: "work") { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let e):
                    self.testOut.text = "失败：\(e)\n\n把这一屏发给 Claude。"
                    self.testOut.textColor = .systemOrange
                case .success(let en):
                    let name = en.contains("Annie")
                    let time = en.contains("3") || en.lowercased().contains("afternoon")
                    let dropped = !en.lowercased().contains("morning")
                    var s = "输入：\n\(sample)\n\n输出：\n\(en)\n\n判据：\n"
                    s += name ? "  ✓ 人名 Annie 保住了\n" : "  ✗ 人名 Annie 丢了\n"
                    s += time ? "  ✓ 改口后的时间保住了\n" : "  ✗ 改口后的时间丢了\n"
                    s += dropped ? "  ✓ 说错的「早上」已丢弃\n" : "  ✗ 说错的「早上」还在\n"
                    let all = name && time && dropped
                    s += all ? "\n通过 —— 可以去键盘里用了" : "\n有问题 —— 把这一屏发给 Claude"
                    self.testOut.text = s
                    self.testOut.textColor = all ? .systemTeal : .systemOrange
                }
            }
        }
    }
}
