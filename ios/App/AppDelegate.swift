import UIKit
import AVFoundation
import Speech

// Transless 容器 App —— 现在它自己就是主战场。
//
// 🚨 为什么主界面是大按钮而不是设置页（2026-08-21 定的）：
//    iOS 26.6 + 免费证书侧载，键盘扩展一启动就被代码签名校验击杀
//    （CODESIGNING / Invalid Page，探针键盘同样被杀 → 与代码无关）。
//    键盘那条路要换签名通道才能通；在那之前，App 内完成同样的事：
//    按一下说中文 → 再按一下 → 自动转写+整理+译英 → 自动进剪贴板 → 去微信粘贴。

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ app: UIApplication,
                     didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let w = UIWindow(frame: UIScreen.main.bounds)
        w.rootViewController = UINavigationController(rootViewController: MainViewController())
        w.makeKeyAndVisible()
        window = w
        return true
    }
}

// MARK: - 主界面：一个大按钮

final class MainViewController: UIViewController {

    private enum Phase { case idle, listening, thinking }

    private let tones = ["work", "email", "casual", "formal"]
    private let toneLabels = ["工作", "邮件", "随意", "正式"]
    private var tone = UserDefaults.standard.string(forKey: "vime.tone") ?? "work"

    private let hintLabel = UILabel()
    private let heardLabel = UILabel()
    private let resultView = UITextView()
    private let micButton = UIButton(type: .system)
    private let toneButton = UIButton(type: .system)

    private lazy var voice = Voice()
    private var phase: Phase = .idle
    private var elapsedTimer: Timer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1)
        title = "Transless"
        navigationController?.navigationBar.tintColor = .white
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "权限", style: .plain, target: self, action: #selector(openSetup))

        hintLabel.font = .systemFont(ofSize: 15)
        hintLabel.textColor = UIColor(white: 0.6, alpha: 1)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 3
        hintLabel.text = "按一下开始说中文\n说完再按一下，英文自动复制好"

        heardLabel.font = .systemFont(ofSize: 15)
        heardLabel.textColor = UIColor(white: 0.9, alpha: 1)
        heardLabel.textAlignment = .center
        heardLabel.numberOfLines = 4

        resultView.font = .systemFont(ofSize: 17)
        resultView.textColor = .white
        resultView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        resultView.layer.cornerRadius = 12
        resultView.isEditable = false
        resultView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)

        micButton.setTitle("🎤", for: .normal)
        micButton.titleLabel?.font = .systemFont(ofSize: 64)
        micButton.backgroundColor = UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1)
        micButton.layer.cornerRadius = 70
        micButton.addTarget(self, action: #selector(tapMic), for: .touchUpInside)

        toneButton.setTitle("语气：" + toneTitle(), for: .normal)
        toneButton.setTitleColor(UIColor(white: 0.6, alpha: 1), for: .normal)
        toneButton.titleLabel?.font = .systemFont(ofSize: 15)
        toneButton.backgroundColor = UIColor(white: 0.13, alpha: 1)
        toneButton.layer.cornerRadius = 10
        toneButton.addTarget(self, action: #selector(cycleTone), for: .touchUpInside)

        [hintLabel, heardLabel, resultView, micButton, toneButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            hintLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 18),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            micButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micButton.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 26),
            micButton.widthAnchor.constraint(equalToConstant: 140),
            micButton.heightAnchor.constraint(equalToConstant: 140),

            toneButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toneButton.topAnchor.constraint(equalTo: micButton.bottomAnchor, constant: 16),
            toneButton.widthAnchor.constraint(equalToConstant: 130),
            toneButton.heightAnchor.constraint(equalToConstant: 36),

            heardLabel.topAnchor.constraint(equalTo: toneButton.bottomAnchor, constant: 14),
            heardLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            heardLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            resultView.topAnchor.constraint(equalTo: heardLabel.bottomAnchor, constant: 14),
            resultView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            resultView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            resultView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 权限没给过就先把设置页推出来要一次
        let mic = AVAudioSession.sharedInstance().recordPermission == .granted
        let sp = SFSpeechRecognizer.authorizationStatus() == .authorized
        if !(mic && sp) {
            navigationController?.pushViewController(SetupViewController(), animated: true)
        }
    }

    private func toneTitle() -> String { toneLabels[tones.firstIndex(of: tone) ?? 0] }

    @objc private func openSetup() {
        navigationController?.pushViewController(SetupViewController(), animated: true)
    }

    @objc private func cycleTone() {
        let i = tones.firstIndex(of: tone) ?? 0
        tone = tones[(i + 1) % tones.count]
        UserDefaults.standard.set(tone, forKey: "vime.tone")
        toneButton.setTitle("语气：" + toneTitle(), for: .normal)
    }

    private func setPhase(_ p: Phase, hint: String) {
        phase = p
        hintLabel.text = hint
        switch p {
        case .idle:
            micButton.setTitle("🎤", for: .normal)
            micButton.backgroundColor = UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1)
            micButton.isEnabled = true
        case .listening:
            micButton.setTitle("■", for: .normal)
            micButton.backgroundColor = UIColor(red: 0.85, green: 0.25, blue: 0.25, alpha: 1)
            micButton.isEnabled = true
        case .thinking:
            micButton.setTitle("…", for: .normal)
            micButton.backgroundColor = UIColor(white: 0.3, alpha: 1)
            micButton.isEnabled = false
        }
    }

    @objc private func tapMic() {
        if phase == .listening {
            elapsedTimer?.invalidate(); elapsedTimer = nil
            setPhase(.thinking, hint: "识别中…")
            voice.stop()
            return
        }
        if phase == .thinking { return }

        heardLabel.text = ""
        resultView.text = ""
        setPhase(.listening, hint: "听着呢，想到哪说到哪（最长 15 分钟）\n说完再按一下红色按钮")
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, self.phase == .listening else { return }
            let s = Int(self.voice.elapsed)
            self.hintLabel.text = String(format: "听着呢 %d:%02d　·　说完再按一下红色按钮", s / 60, s % 60)
        }

        voice.start(onPartial: { [weak self] partial in
            DispatchQueue.main.async { self?.heardLabel.text = partial }
        }, onDone: { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.elapsedTimer?.invalidate(); self.elapsedTimer = nil
                switch result {
                case .success(let zh):
                    let t = zh.trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.isEmpty { self.setPhase(.idle, hint: "没听清，再说一次"); return }
                    self.heardLabel.text = t
                    self.polish(t)
                case .failure(let f):
                    self.setPhase(.idle, hint: "\(f)")
                }
            }
        })
    }

    private func polish(_ zh: String) {
        setPhase(.thinking, hint: "整理并译成英文…")
        Backend.polish(text: zh, tone: tone) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let en):
                    self.resultView.text = en
                    UIPasteboard.general.string = en   // 自动进剪贴板
                    self.setPhase(.idle, hint: "已复制 ✓　去微信长按输入框 → 粘贴\n再按一下麦克风说下一条")
                case .failure(let err):
                    self.setPhase(.idle, hint: "失败：\(err)")
                }
            }
        }
    }
}

// MARK: - 权限/自测页（原来的首页，降级成二级页）

final class SetupViewController: UIViewController {

    private let micState = UILabel()
    private let speechState = UILabel()
    private let testOut = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "权限与自测"

        let s1 = step("第 1 步 · 允许麦克风和语音识别", "只用要一次。")
        [micState, speechState].forEach {
            $0.font = .systemFont(ofSize: 14)
            $0.numberOfLines = 0
        }
        let askBtn = button("允许麦克风和语音识别", #selector(askPerms))

        let s2 = step("自测 · 后端通不通", "")
        let testBtn = button("测一次", #selector(selfTest))
        testOut.font = .systemFont(ofSize: 13)
        testOut.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [s1, micState, speechState, askBtn, s2, testBtn, testOut])
        stack.axis = .vertical
        stack.spacing = 10

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
                    var s = "输出：\n\(en)\n\n判据：\n"
                    s += name ? "  ✓ 人名 Annie 保住了\n" : "  ✗ 人名 Annie 丢了\n"
                    s += time ? "  ✓ 改口后的时间保住了\n" : "  ✗ 改口后的时间丢了\n"
                    s += dropped ? "  ✓ 说错的「早上」已丢弃\n" : "  ✗ 说错的「早上」还在\n"
                    let all = name && time && dropped
                    s += all ? "\n通过" : "\n有问题 —— 把这一屏发给 Claude"
                    self.testOut.text = s
                    self.testOut.textColor = all ? .systemTeal : .systemOrange
                }
            }
        }
    }
}
