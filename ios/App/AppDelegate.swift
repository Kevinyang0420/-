import UIKit
import AVFoundation

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

    /// 输出模式：译成英文（默认）/ 只转写。跟安卓一致。
    private var mode: Backend.Mode =
        Backend.Mode(rawValue: UserDefaults.standard.string(forKey: "vime.mode") ?? "en") ?? .en
    private let modeEnButton = UIButton(type: .system)
    private let modeZhButton = UIButton(type: .system)
    private let modeRawButton = UIButton(type: .system)

    /// 目标语言（翻译模式用）。跟安卓共用同一套 code。
    private var lang = UserDefaults.standard.string(forKey: "vime.lang") ?? "en"
    private let langButton = UIButton(type: .system)

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
        view.backgroundColor = Theme.bg
        title = "Transless"
        navigationController?.navigationBar.tintColor = Theme.accent
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "权限", style: .plain, target: self, action: #selector(openSetup))

        // 模式切换三档：译成英文（默认）/ 结构化转写 / 逐字转录
        for (b, t, sel) in [(modeEnButton, "译成英文", #selector(pickEn)),
                            (modeZhButton, "结构化", #selector(pickZh)),
                            (modeRawButton, "逐字", #selector(pickRaw))] {
            b.setTitle(t, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            b.layer.cornerRadius = 16
            b.addTarget(self, action: sel, for: .touchUpInside)
        }
        let modeStack = UIStackView(arrangedSubviews: [modeEnButton, modeZhButton, modeRawButton])
        modeStack.axis = .horizontal
        modeStack.spacing = 8
        modeStack.distribution = .fillEqually

        hintLabel.font = .systemFont(ofSize: 15)
        hintLabel.textColor = Theme.dim
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 3

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

        micButton.setTitle("🎤", for: .normal)
        micButton.titleLabel?.font = .systemFont(ofSize: 56)
        micButton.backgroundColor = Theme.accent
        micButton.layer.cornerRadius = 60
        micButton.addTarget(self, action: #selector(tapMic), for: .touchUpInside)

        toneButton.setTitle("语气：" + toneTitle(), for: .normal)
        toneButton.setTitleColor(Theme.dim, for: .normal)
        toneButton.titleLabel?.font = .systemFont(ofSize: 15)
        toneButton.backgroundColor = Theme.key
        toneButton.layer.cornerRadius = 16
        toneButton.addTarget(self, action: #selector(cycleTone), for: .touchUpInside)

        // 语言选择：跟语气并排，不藏进设置
        langButton.titleLabel?.font = .systemFont(ofSize: 15)
        langButton.setTitleColor(Theme.text, for: .normal)
        langButton.backgroundColor = Theme.key
        langButton.layer.cornerRadius = 16
        langButton.addTarget(self, action: #selector(pickLang), for: .touchUpInside)

        [modeStack, hintLabel, heardLabel, resultView, micButton,
         toneButton, langButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            modeStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            modeStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            modeStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            modeStack.heightAnchor.constraint(equalToConstant: 34),

            hintLabel.topAnchor.constraint(equalTo: modeStack.bottomAnchor, constant: 14),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            micButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micButton.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 22),
            micButton.widthAnchor.constraint(equalToConstant: 120),
            micButton.heightAnchor.constraint(equalToConstant: 120),

            toneButton.topAnchor.constraint(equalTo: micButton.bottomAnchor, constant: 16),
            toneButton.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -6),
            toneButton.widthAnchor.constraint(equalToConstant: 130),
            toneButton.heightAnchor.constraint(equalToConstant: 34),

            langButton.topAnchor.constraint(equalTo: micButton.bottomAnchor, constant: 16),
            langButton.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: 6),
            langButton.widthAnchor.constraint(equalToConstant: 110),
            langButton.heightAnchor.constraint(equalToConstant: 34),

            heardLabel.topAnchor.constraint(equalTo: toneButton.bottomAnchor, constant: 14),
            heardLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            heardLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            resultView.topAnchor.constraint(equalTo: heardLabel.bottomAnchor, constant: 14),
            resultView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            resultView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            resultView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
        paintMode()
    }

    // MARK: - 模式

    /// 语言选择：用系统的 action sheet，不自己造轮子
    @objc private func pickLang() {
        let ac = UIAlertController(title: "翻译成", message: nil, preferredStyle: .actionSheet)
        for l in Backend.langs {
            let title = (l.code == lang ? "✓ " : "") + l.label
            ac.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.lang = l.code
                UserDefaults.standard.set(l.code, forKey: "vime.lang")
                self.paintMode()
            })
        }
        ac.addAction(UIAlertAction(title: "取消", style: .cancel))
        ac.popoverPresentationController?.sourceView = langButton
        present(ac, animated: true)
    }

    @objc private func pickEn() { setMode(.en) }
    @objc private func pickZh() { setMode(.zh) }
    @objc private func pickRaw() { setMode(.raw) }

    private func setMode(_ m: Backend.Mode) {
        mode = m
        UserDefaults.standard.set(m.rawValue, forKey: "vime.mode")
        paintMode()
    }

    private func paintMode() {
        for (b, m) in [(modeEnButton, Backend.Mode.en),
                       (modeZhButton, .zh),
                       (modeRawButton, .raw)] {
            let on = (mode == m)
            b.backgroundColor = on ? Theme.accent : Theme.key
            b.setTitleColor(on ? .white : Theme.dim, for: .normal)
        }
        // 语气和语言都只在翻译模式有意义
        toneButton.isHidden = (mode != .en)
        langButton.isHidden = (mode != .en)
        langButton.setTitle(Backend.langLabel(lang) + " ▾", for: .normal)
        switch mode {
        case .en:
            hintLabel.text = "按一下开始说中文\n说完再按一下，英文自动复制好"
        case .zh:
            hintLabel.text = "结构化转写：滤掉口水话、整理成中文，不翻译\n按一下开始说，再按一下停"
        case .raw:
            hintLabel.text = "逐字转录：听到什么写什么，一个字不改\n按一下开始说，再按一下停"
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // 权限没给过就先把设置页推出来要一次。
        // 🚨 转写改到后端后只需要**麦克风**权限（语音识别在服务器做，不用 Speech 授权）。
        if AVAudioSession.sharedInstance().recordPermission != .granted {
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
            micButton.backgroundColor = Theme.accent
            micButton.isEnabled = true
        case .listening:
            micButton.setTitle("■", for: .normal)
            micButton.backgroundColor = Theme.danger
            micButton.isEnabled = true
        case .thinking:
            micButton.setTitle("…", for: .normal)
            micButton.backgroundColor = Theme.keyDown
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
        setPhase(.listening, hint: "听着呢，想到哪说到哪（最长 60 秒）\n说完再按一下红色按钮")
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self, self.phase == .listening else { return }
            let s = Int(self.voice.elapsed)
            self.hintLabel.text = String(format: "听着呢 %d:%02d　·　说完再按一下红色按钮", s / 60, s % 60)
        }

        // 录音 → 停止后拿到 WAV → 传后端转写 → 再润色（跟安卓同一条链）
        voice.start(onPartial: { _ in }, onWav: { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.elapsedTimer?.invalidate(); self.elapsedTimer = nil
                switch result {
                case .failure(let f):
                    self.setPhase(.idle, hint: "\(f)")
                case .success(let wav):
                    self.setPhase(.thinking, hint: "识别中…")
                    Backend.transcribe(wav: wav) { [weak self] r in
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            switch r {
                            case .failure(let f): self.setPhase(.idle, hint: "\(f)")
                            case .success(let zh):
                                self.heardLabel.text = zh
                                self.polish(zh)
                            }
                        }
                    }
                }
            }
        })
    }

    private func polish(_ zh: String) {
        switch mode {
        case .en:  setPhase(.thinking, hint: "整理并译成英文…")
        case .zh:  setPhase(.thinking, hint: "整理中…")
        case .raw: setPhase(.thinking, hint: "上屏…")   // 不过模型，一瞬间
        }
        Backend.polish(text: zh, tone: tone, mode: mode, lang: lang) { [weak self] result in
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
    private let testOut = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "权限与自测"

        let s1 = step("第 1 步 · 允许麦克风", "只用要一次。语音识别在后端做，不用额外授权。")
        micState.font = .systemFont(ofSize: 14)
        micState.numberOfLines = 0
        let askBtn = button("允许麦克风", #selector(askPerms))

        let s2 = step("自测 · 后端通不通", "")
        let testBtn = button("测一次", #selector(selfTest))
        testOut.font = .systemFont(ofSize: 13)
        testOut.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [s1, micState, askBtn, s2, testBtn, testOut])
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
        micState.text = mic ? "麦克风：已允许 ✓" : "麦克风：还没允许"
        micState.textColor = mic ? .systemTeal : .systemOrange
    }

    @objc private func askPerms() {
        AVAudioSession.sharedInstance().requestRecordPermission { _ in
            DispatchQueue.main.async { self.refresh() }
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
