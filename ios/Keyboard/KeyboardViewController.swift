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
    /// 渐变底。🚨 必须在 viewDidLayoutSubviews 里更新 frame ——
    ///    不更新的话转屏或键盘高度变化时渐变不跟着走，
    ///    表现成「下半截是黑的」，而且只在真机转屏才看得见。
    private var bgLayer: CALayer?


    private enum Phase {
        case idle, listening, thinking
    }

    private let tones = Prompts.all
    private let toneLabels = Prompts.all.map(Prompts.label)
    private var tone = Prompts.normalize(UserDefaults.standard.string(forKey: "vime.tone"))

    private let hintLabel = UILabel()
    private let heardLabel = UILabel()
    private let micButton = UIButton(type: .system)
    private let toneButton = UIButton(type: .system)
    private let fallbackButton = UIButton(type: .system)
    /// 打字键盘（字母/符号）。**懒建**：没点 Type 之前不占内存 ——
    /// 键盘扩展的内存上限很紧（约 60MB），建了不用是浪费。
    private var typingView: TypingKeyboardView?
    private var voiceRoot: UIStackView?
    private var heightC: NSLayoutConstraint?

    // 🚨 懒加载，不在扩展启动瞬间创建。
    //    Voice() 里会 init AVAudioEngine + SFSpeechRecognizer —— 键盘扩展的启动预算
    //    只有几十 MB / 极短的看门狗时限，启动路径上任何重活都可能被系统直接杀掉，
    //    表现就是「选了键盘却弹回上一个」且没有明显报错。录音引擎等第一次按麦克风再建。
    private lazy var voice = Voice()
    private var phase: Phase = .idle

    // MARK: - 界面

    override func viewDidLoad() {
        super.viewDidLoad()
        // 🚨 用户可能只用键盘、从没打开过 App —— 这里也保一次。
        DeviceId.ensure()
        // 🚨 底改成渐变（跟安卓一致）。平涂 Theme.bg 时，
        //    半透明按键透上来的是一片均匀的紫 —— Kevin 说的"太紫了"就是这么来的。
        view.backgroundColor = .clear
        bgLayer = Theme.keyboardBackground(view.bounds)
        view.layer.insertSublayer(bgLayer!, at: 0)

        hintLabel.font = .systemFont(ofSize: 13)
        hintLabel.textColor = Theme.dim
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 1
        hintLabel.text = ""

        heardLabel.font = .systemFont(ofSize: 15)
        heardLabel.textColor = Theme.text
        heardLabel.textAlignment = .center
        heardLabel.numberOfLines = 2

        // 一个大按钮，占绝对主位
        micButton.setTitle("", for: .normal)
        micButton.setImage(Theme.micGlyph(88), for: .normal)
        micButton.tintColor = .white
        micButton.titleLabel?.font = .systemFont(ofSize: 34)
        micButton.backgroundColor = Theme.accent
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
        toneButton.setTitleColor(Theme.dim, for: .normal)
        toneButton.backgroundColor = Theme.key
        toneButton.layer.cornerRadius = 8
        toneButton.addTarget(self, action: #selector(cycleTone), for: .touchUpInside)

        fallbackButton.setTitle(L.kb_tr_before, for: .normal)
        fallbackButton.titleLabel?.font = .systemFont(ofSize: 13)
        fallbackButton.setTitleColor(Theme.dim, for: .normal)
        fallbackButton.backgroundColor = Theme.key
        fallbackButton.layer.cornerRadius = 8
        fallbackButton.addTarget(self, action: #selector(translatePending), for: .touchUpInside)

        let del = smallButton("⌫")
        del.addTarget(self, action: #selector(backspace), for: .touchUpInside)

        // 🚨 进打字键盘的入口。安卓底排有这个键，iOS 一直没有 ——
        //    于是 iOS 用户只能对着一个麦克风，打不了字。
        let typeBtn = smallButton(L.kb_type)
        typeBtn.addTarget(self, action: #selector(showTyping),
                          for: .touchUpInside)

        let bottom = UIStackView(arrangedSubviews:
            [globe, typeBtn, toneButton, fallbackButton, del])
        bottom.axis = .horizontal
        bottom.spacing = 8
        globe.widthAnchor.constraint(equalToConstant: 44).isActive = true
        del.widthAnchor.constraint(equalToConstant: 44).isActive = true
        toneButton.widthAnchor.constraint(equalToConstant: 56).isActive = true
        typeBtn.widthAnchor.constraint(equalToConstant: 52).isActive = true
        bottom.heightAnchor.constraint(equalToConstant: 38).isActive = true

        let root = UIStackView(arrangedSubviews: [hintLabel, heardLabel, micWrap, bottom])
        root.axis = .vertical
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        voiceRoot = root
        // 🚨 高度要能改：打字键盘比语音面板高。存下这个约束，切换时改 constant。
        let hc = view.heightAnchor.constraint(equalToConstant: 250)
        heightC = hc
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            hc,
        ])
    }

    // MARK: - 语音面板 / 打字键盘 切换

    /// 切到打字键盘。**懒建**，第一次点才创建。
    @objc private func showTyping() {
        if typingView == nil {
            let t = TypingKeyboardView()
            t.translatesAutoresizingMaskIntoConstraints = false
            t.onText = { [weak self] s in
                guard let p = self?.textDocumentProxy else { return }
                // 🚨 先撤掉 marked text 再插入。拼音缓冲走的是 marked text，
                //    而 `insertText` 在**有 marked text 时**的行为 UIKit 没承诺
                //    —— 宿主可能替换、也可能让「marked 的 nihao」和
                //    「插入的 你好」叠在一起。安卓那边没这个问题：
                //    `commitText` 的语义就是替换 composing。
                //    ⚠️ 未在真实宿主实测（预览页没有宿主输入框，模拟器切键盘
                //       扩展要点 🌐，脚本点不了）。这是按 UIKit 稳妥写法加的，
                //       代价为零；等能在 Safari 里真跑一次再确认。
                p.unmarkText()
                p.insertText(s)
            }
            t.onDelete = { [weak self] in
                self?.textDocumentProxy.deleteBackward()
            }
            t.onSwitchToVoice = { [weak self] in self?.showVoice() }
            t.onHeightChange = { [weak self] h in
                guard let s = self, s.voiceRoot?.isHidden == true else { return }
                s.heightC?.constant = h
            }
            // 拼音缓冲 -> 输入框的 marked text（安卓的 setComposingText）。
            // 🚨 空串要 `unmarkText()`，直接 setMarkedText("") 在有些宿主 App
            //    里会留下一个空的标记段，光标行为变怪。
            t.onComposing = { [weak self] s in
                guard let p = self?.textDocumentProxy else { return }
                if s.isEmpty {
                    p.unmarkText()
                } else {
                    p.setMarkedText(s, selectedRange: NSRange(location: s.count,
                                                              length: 0))
                }
            }
            view.addSubview(t)
            NSLayoutConstraint.activate([
                t.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                t.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                t.topAnchor.constraint(equalTo: view.topAnchor),
                t.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            typingView = t
        }
        typingView?.isHidden = false
        voiceRoot?.isHidden = true
        // 🚨 高度由键盘自己按当前档位算（手写档比字母档高一截）。
        //    以前这里写死 280，手写档的底排就被挤扁了。
        heightC?.constant = typingView?.preferredHeight ?? 250
    }

    @objc private func showVoice() {
        typingView?.isHidden = true
        voiceRoot?.isHidden = false
        heightC?.constant = 250
    }

    private func smallButton(_ t: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(t, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 17)
        b.backgroundColor = Theme.key
        b.layer.cornerRadius = 8
        return b
    }

    private func toneTitle() -> String {
        toneLabels[tones.firstIndex(of: tone) ?? 0]
    }

    @objc private func cycleTone() {
        let i = tones.firstIndex(of: tone) ?? 0
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
            micButton.setTitle("", for: .normal)
            micButton.setImage(Theme.micGlyph(88), for: .normal)
            micButton.tintColor = .white
            micButton.backgroundColor = Theme.accent
            micButton.isEnabled = true
        case .listening:
            micButton.setTitle("", for: .normal)
            micButton.setImage(Theme.stopGlyph(88), for: .normal)
            micButton.backgroundColor = Theme.danger
            micButton.isEnabled = true
        case .thinking:
            micButton.setImage(nil, for: .normal)
            micButton.setTitle("…", for: .normal)
            micButton.setTitleColor(.white, for: .normal)
            micButton.backgroundColor = Theme.keyDown
            micButton.isEnabled = false
        }
    }

    // MARK: - 录音（说完自动收）

    @objc private func tapMic() {
        if phase == .listening { stopListening(); return }
        if phase == .thinking { return }

        heardLabel.text = ""
        setPhase(.listening, hint: "")

        // 录音 → 停止后拿到 WAV → 后端转写 → 整理翻译上屏（跟安卓、跟 App 同一条链）
        voice.start(onPartial: { _ in }, onWav: { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .failure(let f):
                    self.setPhase(.idle, hint: "\(f)\n可改用系统键盘的 🎤 说完，再点下面「译光标前的中文」")
                case .success(let wav):
                    self.setPhase(.thinking, hint: "")
                    Backend.transcribe(wav: wav) { [weak self] r in
                        DispatchQueue.main.async {
                            guard let self = self else { return }
                            switch r {
                            case .failure(let f):
                                self.setPhase(.idle, hint: "\(f)")
                            case .success(let zh):
                                self.heardLabel.text = zh
                                self.send(zh, replaceChars: 0)   // 自动往下走
                            }
                        }
                    }
                }
            }
        })
    }

    private func stopListening() {
        setPhase(.thinking, hint: "")
        voice.stop()
    }

    // MARK: - 兜底：翻译光标前已有的中文

    @objc private func translatePending() {
        if phase != .idle { return }
        let t = (textDocumentProxy.documentContextBeforeInput ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else {
            hintLabel.text = L.kb_nothing_before
            return
        }
        heardLabel.text = t
        send(t, replaceChars: t.count)
    }

    // MARK: - 统一出口

    private func send(_ zh: String, replaceChars: Int) {
        guard !Secrets.pass.isEmpty else {
            setPhase(.idle, hint: L.kb_no_pass)
            return
        }
        setPhase(.thinking, hint: "")
        // 模式跟 App 共用同一个 UserDefaults 键，两处切换互通
        let mode = Backend.Mode(
            rawValue: UserDefaults.standard.string(forKey: "vime.mode") ?? "en") ?? .en
        let lang = UserDefaults.standard.string(forKey: "vime.lang") ?? "en"
        Backend.polish(text: zh, tone: tone, mode: mode, lang: lang) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let en):
                    for _ in 0..<replaceChars { self.textDocumentProxy.deleteBackward() }
                    self.textDocumentProxy.insertText(en)
                    self.heardLabel.text = ""
                    self.setPhase(.idle, hint: "")
                case .failure(let err):
                    // 失败绝不动输入框，他说的话还在
                    self.setPhase(.idle, hint: "失败：\(err)")
                }
            }
        }
    }

    deinit { voice.stop() }

    /// 🚨 渐变底的 frame 必须跟着 bounds 走。
    ///    不更新的话，转屏或键盘高度变化（切数字层/候选条出现）时
    ///    渐变停在旧尺寸，下半截露出透明底 —— 只在真机上才看得见。
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        bgLayer?.frame = view.bounds
        bgLayer?.sublayers?.forEach { $0.frame = view.bounds }
    }
}
