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
        // 🚨 首启就去后端换设备令牌：留存统计 / 按人计额度 / 推送触达都靠它。
        //    异步、失败自动回落共享口令，不阻塞启动。
        DeviceId.ensure()
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

    // 🚨 三档，跟 engine.py / 安卓 Gen.TONE_CODES 一致（Kevin 2026-08-21：
    //    「邮件和正式合在一起吧，这两个没什么区别。就是随意、工作和邮件三种」）。
    //    这里是**第三份**副本，暂时只能手工对齐 —— iOS 没走构建期生成那条路。
    //    改档位时三处都要动：engine.py / build_apk.py 生成的 Gen / 这里。
    private let tones = ["casual", "work", "email"]
    private let toneLabels = [L.tone_casual, L.tone_work, L.tone_email]
    private var tone = UserDefaults.standard.string(forKey: "vime.tone") ?? "work"

    /// 输出模式：译成英文（默认）/ 只转写。跟安卓一致。
    private var mode: Backend.Mode =
        Backend.Mode(rawValue: UserDefaults.standard.string(forKey: "vime.mode") ?? "en") ?? .en
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

    /// 目标语言（翻译模式用）。跟安卓共用同一套 code。
    private var lang = UserDefaults.standard.string(forKey: "vime.lang") ?? "en"
    private let langButton = UIButton(type: .system)

    /// 🔊 朗读：把刚出的译文用 Andrew 的声音念出来
    private let speakButton = UIButton(type: .system)
    private var lastOut = ""

    private let hintLabel = UILabel()
    private let heardLabel = UILabel()
    private let resultView = UITextView()
    private let aiNoticeLabel = UILabel()   // DeepSeek 条款 8.1/3.7 要求的 AI 生成披露
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
            title: L.perm_title, style: .plain, target: self, action: #selector(openSetup))

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
        logoView.image = UIImage(named: "logo")?.withRenderingMode(.alwaysTemplate)
        logoView.tintColor = Theme.dim
        logoView.contentMode = .scaleAspectFit

        let modeStack = UIStackView(arrangedSubviews: [tabTranslate, tabTranscribe, logoView])
        modeStack.axis = .horizontal
        modeStack.spacing = Theme.gap * 0.7
        modeStack.distribution = .fill
        tabTranslate.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tabTranscribe.setContentHuggingPriority(.defaultLow, for: .horizontal)
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
        hintLabel.text = ""

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
        micButton.setTitle("", for: .normal)
        micButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .medium)
        micButton.setTitleColor(.white, for: .normal)
        micButton.setImage(Theme.micGlyph(Theme.micBarHeight * 0.6), for: .normal)
        micButton.tintColor = .white
        micButton.backgroundColor = Theme.accent
        micButton.layer.cornerRadius = Theme.micBarHeight / 2
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
        speakButton.isEnabled = false          // 没东西可念时不给点
        speakButton.addTarget(self, action: #selector(tapSpeak), for: .touchUpInside)

        [modeStack, subStack, hintLabel, heardLabel, resultView, aiNoticeLabel, micButton,
         toneButton, langButton, speakButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        NSLayoutConstraint.activate([
            modeStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.gap),
            modeStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.pad * 1.6),
            modeStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.pad * 1.6),
            modeStack.heightAnchor.constraint(equalToConstant: 34),

            subStack.topAnchor.constraint(equalTo: modeStack.bottomAnchor, constant: Theme.gap),
            subStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.pad * 1.6),
            subStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.pad * 1.6),
            subStack.heightAnchor.constraint(equalToConstant: 32),

            hintLabel.topAnchor.constraint(equalTo: subStack.bottomAnchor, constant: Theme.gap),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            // 圆形：等宽高 + 居中（跟安卓 MIC_CIRCLE_DP 那套一一对应）
            micButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            micButton.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: Theme.gap + 4),
            micButton.widthAnchor.constraint(equalToConstant: Theme.micBarHeight),
            micButton.heightAnchor.constraint(equalToConstant: Theme.micBarHeight),

            toneButton.topAnchor.constraint(equalTo: micButton.bottomAnchor, constant: Theme.gap),
            toneButton.trailingAnchor.constraint(equalTo: view.centerXAnchor, constant: -6),
            toneButton.widthAnchor.constraint(equalToConstant: 130),
            toneButton.heightAnchor.constraint(equalToConstant: 34),

            langButton.topAnchor.constraint(equalTo: micButton.bottomAnchor, constant: Theme.gap),
            langButton.leadingAnchor.constraint(equalTo: view.centerXAnchor, constant: 6),
            langButton.widthAnchor.constraint(equalToConstant: 110),
            langButton.heightAnchor.constraint(equalToConstant: 34),

            speakButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            speakButton.topAnchor.constraint(equalTo: toneButton.bottomAnchor, constant: 10),
            speakButton.widthAnchor.constraint(equalToConstant: 140),
            speakButton.heightAnchor.constraint(equalToConstant: 36),

            heardLabel.topAnchor.constraint(equalTo: speakButton.bottomAnchor, constant: Theme.gap),
            heardLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            heardLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            resultView.topAnchor.constraint(equalTo: heardLabel.bottomAnchor, constant: 14),
            resultView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            resultView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            resultView.bottomAnchor.constraint(equalTo: aiNoticeLabel.topAnchor, constant: -8),
            aiNoticeLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            aiNoticeLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            aiNoticeLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
        // 🚨 立体感统一在这儿走一遍，别在每个控件后面各写一行 —— 漏一个就少一个阴影，
        //    而"少了一个"是看不出来的（跟安卓 Theme.elevateAll 同一套做法）。
        for v in [tabTranslate, tabTranscribe, modeZhButton, modeRawButton,
                  toneButton, langButton, speakButton] {
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
        explain(toneButton, L.ex_tone_cycle)
        explain(langButton, L.ex_lang_pick)
        explain(speakButton, L.ex_speak_ios)

        paintMode()
    }

    // MARK: - 模式

    /// 语言选择：用系统的 action sheet，不自己造轮子
    @objc private func pickLang() {
        let ac = UIAlertController(title: L.lbl_translate_to, message: nil, preferredStyle: .actionSheet)
        for l in Backend.langs {
            let title = (l.code == lang ? "✓ " : "") + l.label
            ac.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self = self else { return }
                self.lang = l.code
                UserDefaults.standard.set(l.code, forKey: "vime.lang")
                self.paintMode()
            })
        }
        ac.addAction(UIAlertAction(title: L.cancel, style: .cancel))
        ac.popoverPresentationController?.sourceView = langButton
        present(ac, animated: true)
    }

    /// 朗读最近一次的译文。再点一下 = 停。
    @objc private func tapSpeak() {
        if Speaker.isPlaying {
            Speaker.stop()
            speakButton.setTitle(L.kb_speak, for: .normal)
            return
        }
        let text = lastOut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { hintLabel.text = L.nothing_to_speak; return }
        speakButton.isEnabled = false
        speakButton.setTitle("…", for: .normal)
        Backend.speak(text: text) { [weak self] r in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.speakButton.isEnabled = true
                switch r {
                case .failure(let e):
                    self.speakButton.setTitle(L.kb_speak, for: .normal)
                    self.hintLabel.text = "朗读失败：\(e)"
                case .success(let mp3):
                    self.speakButton.setTitle(L.kb_stop, for: .normal)
                    Speaker.play(mp3) { [weak self] err in
                        DispatchQueue.main.async {
                            self?.speakButton.setTitle(L.kb_speak, for: .normal)
                            if let err = err { self?.hintLabel.text = "朗读失败：\(err)" }
                        }
                    }
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

    @objc private func pickEn() { setMode(.en) }
    @objc private func pickZh() { setMode(.zh) }
    @objc private func pickRaw() { setMode(.raw) }
    /// 点第一级「转写」：默认落在结构化转写；已经在转写档就保持原子档。
    @objc private func pickTranscribe() { setMode(mode == .raw ? .raw : .zh) }

    private func setMode(_ m: Backend.Mode) {
        mode = m
        UserDefaults.standard.set(m.rawValue, forKey: "vime.mode")
        paintMode()
    }

    private func paintMode() {
        // 第一级
        let isTranslate = (mode == .en)
        tabTranslate.backgroundColor = isTranslate ? Theme.accent : Theme.key
        tabTranslate.setTitleColor(isTranslate ? .white : Theme.dim, for: .normal)
        tabTranscribe.backgroundColor = isTranslate ? Theme.key : Theme.accent
        tabTranscribe.setTitleColor(isTranslate ? Theme.dim : .white, for: .normal)

        // 第二级：翻译下是语气+语言，转写下是 结构化/逐字。永远只出现一排。
        subStack.isHidden = isTranslate
        for (b, m) in [(modeZhButton, Backend.Mode.zh), (modeRawButton, .raw)] {
            let on = (mode == m)
            b.backgroundColor = on ? Theme.accent : Theme.key
            b.setTitleColor(on ? .white : Theme.dim, for: .normal)
        }
        toneButton.isHidden = !isTranslate
        langButton.isHidden = !isTranslate
        langButton.setTitle(Backend.langLabel(lang) + " ▾", for: .normal)
        switch mode {
        case .en:
            hintLabel.text = ""
        case .zh:
            hintLabel.text = ""
        case .raw:
            hintLabel.text = ""
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
            micButton.setTitle("", for: .normal)
            micButton.setImage(Theme.micGlyph(Theme.micBarHeight * 0.6), for: .normal)
            micButton.tintColor = .white
            micButton.backgroundColor = Theme.accent
            micButton.isEnabled = true
        case .listening:
            micButton.setTitle("", for: .normal)
            micButton.setImage(Theme.stopGlyph(Theme.micBarHeight * 0.6), for: .normal)
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

    @objc private func tapMic() {
        if phase == .listening {
            elapsedTimer?.invalidate(); elapsedTimer = nil
            setPhase(.thinking, hint: L.st_recognizing)
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
            self.hintLabel.text = String(format: L.st_listening_ios, s / 60, s % 60)
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
                    self.setPhase(.thinking, hint: L.st_recognizing)
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
        case .en:  setPhase(.thinking, hint: L.st_translating)
        case .zh:  setPhase(.thinking, hint: L.st_polishing)
        case .raw: setPhase(.thinking, hint: L.st_inserting)   // 不过模型，一瞬间
        }
        Backend.polish(text: zh, tone: tone, mode: mode, lang: lang) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let en):
                    self.resultView.text = en
                    UIPasteboard.general.string = en   // 自动进剪贴板
                    self.lastOut = en                  // 给「🔊 朗读」用
                    self.speakButton.isEnabled = true
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
        // 🚨 原来是 `.systemBackground`（浅色）—— 从深紫主界面点进来会闪一下白。
        //    这种不一致只有真机点进去才看得见，代码里看着毫无问题。
        view.backgroundColor = Theme.bg
        title = L.ios_setup_title

        let s1 = step(L.ios_step1, L.ios_step1_why)
        micState.font = .systemFont(ofSize: 14)
        micState.textColor = Theme.text
        micState.numberOfLines = 0
        let askBtn = button(L.ios_allow_mic, #selector(askPerms))

        let s2 = step(L.ios_step2, "")
        let testBtn = button(L.ios_test_once, #selector(selfTest))
        testOut.font = .systemFont(ofSize: 13)
        testOut.textColor = Theme.dim
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
        a.textColor = Theme.text
        let b = UILabel()
        b.text = why
        b.font = .systemFont(ofSize: 13)
        b.textColor = Theme.dim
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
        micState.text = mic ? L.mic_allowed : L.mic_not_allowed
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
        testOut.text = L.st_testing
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
