import UIKit

// 说英文 · iOS 键盘扩展
//
// 主路径：点键盘里的麦克风说中文 → 转写 → 整理精简 → 结构化 → 译成英文 → 直接上屏。
// 兜底路径：万一键盘进程里开不了录音（Apple 论坛上是常见故障），
//          用系统键盘的 🎤 把中文说进输入框，再切回来点「译光标前的中文」。
//          这条不依赖任何权限，一定能用。
//
// 🚨 两条路都留着是故意的：我没有 iOS 设备，录音那条只能在他手机上见分晓。
//    失败时界面要**说清卡在哪一步**，他截一张图我就能定位。

final class KeyboardViewController: UIInputViewController {

    private let tones = ["work", "email", "casual", "formal"]
    private let toneLabels = ["工作", "邮件", "随意", "正式"]
    private var tone = UserDefaults.standard.string(forKey: "vime.tone") ?? "work"

    private var toneButtons: [UIButton] = []
    private let statusLabel = UILabel()
    private let previewLabel = UILabel()
    private let micButton = UIButton(type: .system)
    private let fallbackButton = UIButton(type: .system)

    private let voice = Voice()
    private var busy = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.07, green: 0.08, blue: 0.09, alpha: 1)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = UIColor(white: 0.6, alpha: 1)
        statusLabel.numberOfLines = 2
        statusLabel.text = "点麦克风说中文"

        previewLabel.font = .systemFont(ofSize: 14)
        previewLabel.textColor = UIColor(white: 0.9, alpha: 1)
        previewLabel.numberOfLines = 2

        let toneRow = UIStackView()
        toneRow.axis = .horizontal
        toneRow.distribution = .fillEqually
        toneRow.spacing = 6
        for (i, label) in toneLabels.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(label, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 13)
            b.layer.cornerRadius = 8
            b.tag = i
            b.addTarget(self, action: #selector(pickTone(_:)), for: .touchUpInside)
            toneButtons.append(b)
            toneRow.addArrangedSubview(b)
        }

        micButton.setTitle("🎤  点一下开始说", for: .normal)
        micButton.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        micButton.setTitleColor(.white, for: .normal)
        micButton.backgroundColor = UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1)
        micButton.layer.cornerRadius = 12
        micButton.addTarget(self, action: #selector(tapMic), for: .touchUpInside)
        micButton.heightAnchor.constraint(equalToConstant: 56).isActive = true

        fallbackButton.setTitle("译光标前的中文", for: .normal)
        fallbackButton.titleLabel?.font = .systemFont(ofSize: 14)
        fallbackButton.setTitleColor(UIColor(white: 0.75, alpha: 1), for: .normal)
        fallbackButton.backgroundColor = UIColor(white: 0.14, alpha: 1)
        fallbackButton.layer.cornerRadius = 10
        fallbackButton.heightAnchor.constraint(equalToConstant: 38).isActive = true
        fallbackButton.addTarget(self, action: #selector(translatePending), for: .touchUpInside)

        let nextKeyboard = UIButton(type: .system)
        nextKeyboard.setTitle("🌐", for: .normal)
        nextKeyboard.titleLabel?.font = .systemFont(ofSize: 18)
        nextKeyboard.addTarget(self,
                               action: #selector(handleInputModeList(from:with:)),
                               for: .allTouchEvents)

        let del = UIButton(type: .system)
        del.setTitle("⌫", for: .normal)
        del.titleLabel?.font = .systemFont(ofSize: 18)
        del.addTarget(self, action: #selector(backspace), for: .touchUpInside)

        let bottom = UIStackView(arrangedSubviews: [nextKeyboard, fallbackButton, del])
        bottom.axis = .horizontal
        bottom.spacing = 8
        nextKeyboard.widthAnchor.constraint(equalToConstant: 46).isActive = true
        del.widthAnchor.constraint(equalToConstant: 46).isActive = true

        let root = UIStackView(arrangedSubviews: [statusLabel, previewLabel,
                                                  toneRow, micButton, bottom])
        root.axis = .vertical
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            view.heightAnchor.constraint(equalToConstant: 270),
        ])
        paintTones()
    }

    private func paintTones() {
        for (i, b) in toneButtons.enumerated() {
            let on = tones[i] == tone
            b.backgroundColor = on ? UIColor(red: 0.15, green: 0.39, blue: 0.92, alpha: 1)
                                   : UIColor(white: 0.14, alpha: 1)
            b.setTitleColor(on ? .white : UIColor(white: 0.6, alpha: 1), for: .normal)
        }
    }

    @objc private func pickTone(_ sender: UIButton) {
        tone = tones[sender.tag]
        UserDefaults.standard.set(tone, forKey: "vime.tone")
        paintTones()
    }

    @objc private func backspace() { textDocumentProxy.deleteBackward() }

    private func pendingText() -> String {
        (textDocumentProxy.documentContextBeforeInput ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func setBusy(_ b: Bool, _ msg: String) {
        busy = b
        micButton.isEnabled = !b
        fallbackButton.isEnabled = !b
        micButton.alpha = b ? 0.55 : 1
        statusLabel.text = msg
    }

    // MARK: - 语音

    @objc private func tapMic() {
        if voice.running {
            statusLabel.text = "识别中…"
            voice.stop()
            return
        }
        if busy { return }
        previewLabel.text = ""
        micButton.setTitle("⏹  说完点这里", for: .normal)
        statusLabel.text = "听着呢，想到哪说到哪"

        voice.start(onPartial: { [weak self] partial in
            DispatchQueue.main.async { self?.previewLabel.text = partial }
        }, onDone: { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.micButton.setTitle("🎤  点一下开始说", for: .normal)
                switch result {
                case .success(let zh):
                    self.previewLabel.text = zh
                    self.send(zh, replaceChars: 0)
                case .failure(let f):
                    // 说清卡在哪一步，并直接告诉他兜底怎么走
                    self.setBusy(false, "\(f)。可以改用系统键盘的 🎤 说完，再点「译光标前的中文」")
                }
            }
        })
    }

    // MARK: - 兜底：翻译光标前已有的中文

    @objc private func translatePending() {
        if busy { return }
        let t = pendingText()
        guard !t.isEmpty else {
            statusLabel.text = "光标前没有内容"
            return
        }
        previewLabel.text = t
        send(t, replaceChars: t.count)
    }

    // MARK: - 统一出口

    private func send(_ zh: String, replaceChars: Int) {
        guard !Secrets.pass.isEmpty else {
            statusLabel.text = "这份包没配口令，重新构建一次"
            return
        }
        setBusy(true, "整理并译成英文…")
        Backend.polish(text: zh, tone: tone) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let en):
                    // 🚨 只删要替换的那一段，别清空整个输入框
                    for _ in 0..<replaceChars { self.textDocumentProxy.deleteBackward() }
                    self.textDocumentProxy.insertText(en)
                    self.setBusy(false, "已上屏")
                    self.previewLabel.text = ""
                case .failure(let err):
                    // 失败绝不动输入框，他说的话还在
                    self.setBusy(false, "失败：\(err)")
                }
            }
        }
    }
}
