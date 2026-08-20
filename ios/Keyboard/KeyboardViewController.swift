import UIKit

// Transless 同传输入法 · iOS 键盘扩展
//
// 交互目标（Kevin 2026-08-20 明确的）：**按一下开始说，再按一下停**，然后自动出英文。
// 参照 Typeless 的单按钮形态：界面上只有一个大按钮是主角。
//
// 🚨 上一版做错的地方：
//   1. 界面塞了四个语气标签 + 麦克风 + 三个底部按钮，他不知道该按哪个
//   2. 停下来之后什么反应都没有，他不知道发生了什么
// 现在：一个大按钮独占中间；按一下开始、再按一下停；停了之后**自动**转写→整理→
// 翻译→上屏，全程不用他再点第二个按钮。每一步界面上都写着现在在干嘛。
//
// 🚨 别再加「静音自动收音」：他说口水话时中间会停顿思考，1.8 秒的自动截断会把他打断。
//    下面那个 8 秒只是防呆（忘了关就别一直录着），不是交互主路径。

final class KeyboardViewController: UIInputViewController {

    private enum Phase {
        case idle, listening, thinking
    }

    private let tones = ["work", "email", "casual", "formal"]
    private let toneLabels = ["工作", "邮件", "随意", "正式"]
    private var tone = UserDefaults.standard.string(forKey: "vime.tone") ?? "work"

    private let hintLabel = UILabel()
    private let heardLabel = UILabel()
    private let micButton = UIButton(type: .system)
    private let toneButton = UIButton(type: .system)
    private let fallbackButton = UIButton(type: .system)

    // 🚨 懒加载，不在扩展启动瞬间创建。
    //    Voice() 里会 init AVAudioEngine + SFSpeechRecognizer —— 键盘扩展的启动预算
    //    只有几十 MB / 极短的看门狗时限，启动路径上任何重活都可能被系统直接杀掉，
    //    表现就是「选了键盘却弹回上一个」且没有明显报错。录音引擎等第一次按麦克风再建。
    private lazy var voice = Voice()
    private var phase: Phase = .idle
    private var silenceTimer: Timer?
    private var lastPartialAt = Date()

    // MARK: - 界面

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1)

        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = UIColor(white: 0.55, alpha: 1)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 2
        hintLabel.text = "按一下开始说中文　·　说完再按一下，自动出英文"

        heardLabel.font = .systemFont(ofSize: 15)
        heardLabel.textColor = UIColor(white: 0.92, alpha: 1)
        heardLabel.textAlignment = .center
        heardLabel.numberOfLines = 2

        // 一个大按钮，占绝对主位
        micButton.setTitle("🎤", for: .normal)
        micButton.titleLabel?.font = .systemFont(ofSize: 40)
        micButton.backgroundColor = UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1)
        micButton.layer.cornerRadius = 44
        micButton.addTarget(self, action: #selector(tapMic), for: .touchUpInside)
        micButton.translatesAutoresizingMaskIntoConstraints = false
        micButton.widthAnchor.constraint(equalToConstant: 88).isActive = true
        micButton.heightAnchor.constraint(equalToConstant: 88).isActive = true

        let micWrap = UIView()
        micWrap.addSubview(micButton)
        micButton.centerXAnchor.constraint(equalTo: micWrap.centerXAnchor).isActive = true
        micButton.topAnchor.constraint(equalTo: micWrap.topAnchor).isActive = true
        micButton.bottomAnchor.constraint(equalTo: micWrap.bottomAnchor).isActive = true

        // 底部一排都做小，别跟主按钮抢注意力
        let globe = smallButton("🌐")
        globe.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        toneButton.setTitle(toneTitle(), for: .normal)
        toneButton.titleLabel?.font = .systemFont(ofSize: 13)
        toneButton.setTitleColor(UIColor(white: 0.6, alpha: 1), for: .normal)
        toneButton.backgroundColor = UIColor(white: 0.13, alpha: 1)
        toneButton.layer.cornerRadius = 8
        toneButton.addTarget(self, action: #selector(cycleTone), for: .touchUpInside)

        fallbackButton.setTitle("译光标前的中文", for: .normal)
        fallbackButton.titleLabel?.font = .systemFont(ofSize: 13)
        fallbackButton.setTitleColor(UIColor(white: 0.6, alpha: 1), for: .normal)
        fallbackButton.backgroundColor = UIColor(white: 0.13, alpha: 1)
        fallbackButton.layer.cornerRadius = 8
        fallbackButton.addTarget(self, action: #selector(translatePending), for: .touchUpInside)

        let del = smallButton("⌫")
        del.addTarget(self, action: #selector(backspace), for: .touchUpInside)

        let bottom = UIStackView(arrangedSubviews: [globe, toneButton, fallbackButton, del])
        bottom.axis = .horizontal
        bottom.spacing = 8
        globe.widthAnchor.constraint(equalToConstant: 44).isActive = true
        del.widthAnchor.constraint(equalToConstant: 44).isActive = true
        toneButton.widthAnchor.constraint(equalToConstant: 56).isActive = true
        bottom.heightAnchor.constraint(equalToConstant: 38).isActive = true

        let root = UIStackView(arrangedSubviews: [hintLabel, heardLabel, micWrap, bottom])
        root.axis = .vertical
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            view.heightAnchor.constraint(equalToConstant: 250),
        ])
    }

    private func smallButton(_ t: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(t, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 17)
        b.backgroundColor = UIColor(white: 0.13, alpha: 1)
        b.layer.cornerRadius = 8
        return b
    }

    private func toneTitle() -> String {
        toneLabels[tones.firstIndex(of: tone) ?? 0]
    }

    @objc private func cycleTone() {
        let i = (tones.firstIndex(of: tone) ?? 0 + 0)
        tone = tones[(i + 1) % tones.count]
        UserDefaults.standard.set(tone, forKey: "vime.tone")
        toneButton.setTitle(toneTitle(), for: .normal)
    }

    @objc private func backspace() { textDocumentProxy.deleteBackward() }

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

    // MARK: - 录音（说完自动收）

    @objc private func tapMic() {
        if phase == .listening { stopListening(); return }
        if phase == .thinking { return }

        heardLabel.text = ""
        setPhase(.listening, hint: "听着呢，想到哪说到哪　·　说完再按一下红色按钮")
        lastPartialAt = Date()
        startSilenceWatch()

        voice.start(onPartial: { [weak self] partial in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.heardLabel.text = partial
                self.lastPartialAt = Date()          // 还在说话，把静音计时推后
            }
        }, onDone: { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.stopSilenceWatch()
                switch result {
                case .success(let zh):
                    let t = zh.trimmingCharacters(in: .whitespacesAndNewlines)
                    if t.isEmpty {
                        self.setPhase(.idle, hint: "没听清，再说一次")
                        return
                    }
                    self.heardLabel.text = t
                    self.send(t, replaceChars: 0)     // 自动往下走，不用他再点
                case .failure(let f):
                    // 说清卡在哪一步，并指出兜底怎么走
                    self.setPhase(.idle, hint: "\(f)\n可改用系统键盘的 🎤 说完，再点下面「译光标前的中文」")
                }
            }
        })
    }

    /// 只是防呆：万一他忘了关，别一直录下去。**不是交互主路径** ——
    /// 主路径是他自己再按一下。8 秒足够长，中途思考停顿不会被误截。
    private func startSilenceWatch() {
        stopSilenceWatch()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.phase == .listening else { return }
            if Date().timeIntervalSince(self.lastPartialAt) > 8.0 {
                self.stopListening()
            }
        }
    }

    private func stopSilenceWatch() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    private func stopListening() {
        stopSilenceWatch()
        setPhase(.thinking, hint: "识别中…")
        voice.stop()
    }

    // MARK: - 兜底：翻译光标前已有的中文

    @objc private func translatePending() {
        if phase != .idle { return }
        let t = (textDocumentProxy.documentContextBeforeInput ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            hintLabel.text = "光标前没有内容"
            return
        }
        heardLabel.text = t
        send(t, replaceChars: t.count)
    }

    // MARK: - 统一出口

    private func send(_ zh: String, replaceChars: Int) {
        guard !Secrets.pass.isEmpty else {
            setPhase(.idle, hint: "这份包没配口令，重新构建一次")
            return
        }
        setPhase(.thinking, hint: "整理并译成英文…")
        Backend.polish(text: zh, tone: tone) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let en):
                    for _ in 0..<replaceChars { self.textDocumentProxy.deleteBackward() }
                    self.textDocumentProxy.insertText(en)
                    self.heardLabel.text = ""
                    self.setPhase(.idle, hint: "已上屏 ✓　点麦克风继续说")
                case .failure(let err):
                    // 失败绝不动输入框，他说的话还在
                    self.setPhase(.idle, hint: "失败：\(err)")
                }
            }
        }
    }

    deinit { silenceTimer?.invalidate() }
}
