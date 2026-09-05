import UIKit

// 🚨🚨 2026-09-03 配色跟宿主外观分叉之后，本文件**必须用 `Theme.kb*`**，
//    不能再用 `Theme.key` / `Theme.text` / `Theme.dim`（那三个是**深色专用**的）。
//    Kevin 当天的原话：「你改完颜色，你要知道这是牵一发动全身的，每个地方都要看一下。
//    你现在键盘的颜色淡成什么样子了？别人能用吗？」
//    —— 我当时只换了 `KeyboardViewController.swift`，本文件漏了，于是
//    半透明白键 + 近白文字压在浅紫面板上，基本看不见。
//    这是「同一规矩散在多个文件，改一处等于没改」那一族。

/// iOS 的打字键盘 —— **照抄安卓 `TypingKeyboard.java` 的布局**，不重新设计。
///
/// 🚨🚨 Kevin 2026-08-25：「这长得跟安卓一样吗？排版结构 completely
///    different，搞的什么垃圾玩意儿，重新做！」
///    他说得对：安卓键盘 1691 行（拼音/字母/符号两页/手写/九宫格/候选栏），
///    iOS 那边只有 267 行 —— 一个麦克风加一行按钮。
///
/// 🚨 这是**第一块**：字母 + 符号两页 + 底排。
///    后面还有拼音候选、九宫格、手写（手写要 TFLite 模型，最后做）。
///    分块做是因为一次搬 1691 行没法验证；每块做完在模拟器上截图核对。
///
/// 🚨 所有布局常量**从安卓那份逐字抄过来**，写在下面 `Layout` 里，
///    抄的时候标了安卓的行号，好核。一个数都不许我自己定 ——
///    他的规矩是「配色版式不许我自己调」。
enum Layout {
    // 安卓 TypingKeyboard.java:31-33
    static let row1 = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
    static let row2 = ["a", "s", "d", "f", "g", "h", "j", "k", "l"]
    static let row3 = ["z", "x", "c", "v", "b", "n", "m"]

    // 🚨🚨 2026-09-03 **照抄 iOS 系统键盘的符号布局**（Typeless 用的也是这一套，
    //    Kevin 发了两张实拍图过来）。原来那两页是自创的：第一页塞 @ # $ % &，
    //    第二页塞 • √ π ÷ × ¶ ∆ ℅ © ® ™ —— 一堆日常打不到的字符占着位置，
    //    而反斜杠、下划线、尖括号这些真正常用的反而被挤到角落或没有。
    //    他找不到左斜杠，就是因为它被排在自创的第二页第三行末尾。
    //
    //    两页现在逐键等于系统键盘：
    //      第一页  1234567890 · - / : ; ( ) $ & @ " · [#+=] . , ? ! ' [退格]
    //      第二页  [ ] { } # % ^ * + = · 下划线 反斜杠 | ~ < > € £ ¥ · · [123] . , ? ! ' [退格]
    //    第三行两页**共用同一组**（. , ? ! '），跟系统一致 —— 翻页时最常用的
    //    那五个标点不会跳位置。
    //
    //    🚨 抄的是**布局**不是**输出**：中文档下这些键仍走 Punct 映射成全角，那一层别动。
    static let sym0 = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'"],
    ]
    static let sym1 = [
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "·"],
        [".", ",", "?", "!", "'"],
    ]

    // 安卓 :455 / :490 —— 行内边距和键盘总高
    static let rowPad: CGFloat = 2
    /// 键面字号。安卓 `TypingKeyboard.java:357` baseKey `setTextSize(17)`。
    static let keyTextSize: CGFloat = 17
    /// 候选栏高。安卓 `suggestBar` 里候选键 34dp + 上下留白。
    /// 🚨🚨 **键盘面板的标准高度 —— 唯一真值**。
    ///    语音面板和打字键盘（除手写外）都必须用它。
    ///    Kevin 反复点名：「只有手写的时候允许调高一些，
    ///    其他的都必须要保持高度一致，又当耳旁风了吗？」
    ///
    ///    2026-08-26 之前这个数在代码里有**三份**：
    ///    键盘初始约束 300、`showVoice()` 250、打字档算出来的 242。
    ///    于是语音面板比打字键盘高 58pt（=174px），
    ///    而且语音面板自己还有两个高度（没切过是 300、切回来是 250）。
    ///    产品经理在真截图上量出 901 vs 727 才发现。
    ///    **收成一个常量之后，改高度只能改这一处。**
    static let panelH: CGFloat = 250

    static let candBarH: CGFloat = 42
    /// 手写板 / 九宫格的高度。安卓 `PAD_H = 216`，两个档位共用它。
    static let padH: CGFloat = 216
    /// 手写区四周留白。安卓 `HAND_PAD_DP = 3`。
    static let handPad: CGFloat = 3
    /// 九宫格键的上下左右留白。安卓 `NUM_KEY_MARGIN = 3`。
    static let numKeyMargin: CGFloat = 3
    /// 九宫格字号。安卓 `setTextSize(22)`——「老人家要看得清」。
    static let numKeyTextSize: CGFloat = 22
    /// 一行按键的高度。安卓键高 `dp(46)` + 行内边距 `ROW_PAD_DP=2` 上下各一份。
    static let keyRowH: CGFloat = 46 + rowPad * 2

    /// 首行字母长按出的数字：q→1 w→2 … o→9 p→0（安卓 `longPressDigit`）。
    /// 🚨 这是 Gboard 的做法：**零占位**，不用切到 ?123 页，
    ///    也不用常驻一行数字把键盘顶高。
    static func longPressDigit(_ k: String) -> String? {
        guard let i = row1.firstIndex(of: k) else { return nil }
        return String((i + 1) % 10)          // q..o → 1..9，p → 0
    }
    /// 安卓 ROW2 那一行左右各缩进 14dp（:270 `keyRow(ROW2, dp(14))`）
    static let row2Indent: CGFloat = 14
    static let keyGap: CGFloat = 3
}

/// 中英标点对照。**跟安卓 `cnPunct()` 同一张表**（TypingKeyboard.java）。
///
/// 🚨 键面和输出必须同源 —— 安卓那边为这个栽过：
///    键面写死中文句号、英文档却输出 `.`，Kevin 说「这摆明了是误导人」。
enum Punct {
    static let half2full: [String: String] = [
        ".": "。", ",": "，", "?": "？", "!": "！", ":": "：", ";": "；",
        "(": "（", ")": "）", "[": "【", "]": "】", "$": "￥", "^": "……",
    ]

    /// 当前档位下这个键**该输出什么**。
    static func out(_ k: String, english: Bool) -> String {
        if english { return k }
        return half2full[k] ?? k
    }

    /// 当前档位下这个键**该显示什么**。跟 `out` 同源，不可能走散。
    static func face(_ k: String, english: Bool) -> String {
        // 成对引号那两个在安卓侧有开合状态，键面用中性写法
        if k == "\"" { return english ? "\"" : "“”" }
        if k == "'" { return english ? "'" : "‘’" }
        return out(k, english: english)
    }
}

/// 打字键盘视图。宿主（KeyboardViewController）通过 `onText` / `onDelete` 收结果。
final class TypingKeyboardView: UIView {

    enum Mode { case letters, symbols }

    var onText: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var onSwitchToVoice: (() -> Void)?
    /// 拿宿主的输入连接。**退格要用**（长按连删、按词删都得读光标前的文字），
    /// 而键盘视图本身拿不到 —— 由 `KeyboardViewController` 注入。
    /// 🚨 为 nil 时退格退化成 `onDelete?()`（单次删除），**不会失灵**。
    var proxyProvider: (() -> UITextDocumentProxy?)?
    var onGlobe: (() -> Void)?

    private var mode: Mode = .letters
    private var symPage = 0
    /// 中/英档。影响标点的**键面和输出**（同源）。
    /// 英文标点档。
    /// 🚨 **不是独立状态** —— 它就是「不是中文档」。原来两个各存一份，
    ///    初值一个 true 一个 true，一开始就自相矛盾：中文档下逗号键
    ///    还写着 `,`。加同步语句只是把两份数据勉强对齐，
    ///    删掉一份才是修好。
    private var english: Bool { !chinese }
    /// 上档状态：0 关 / 1 一次 / 2 锁定。跟安卓三态一致。
    private var capState = 0
    private var lastShiftAt: TimeInterval = 0

    private let stack = UIStackView()
    /// 候选栏。**永远在版面里**（没打字时显示 中/EN 芯片），跟安卓一致。
    let candBar = CandidateBar()
    /// 拼音缓冲。中文档下字母先进这里，不直接上屏。
    private var pinyin = ""
    /// 中文档还是英文档。**候选栏左上角那两个芯片**切（不是左下角的键）。
    private var chinese = true

    // MARK: - 云端整句（他 2026-09-04 拍板「①②一起做」）

    /// 停手多久才去问云端。**不是每敲一个字母就发** —— 那样又卡又烧他的钱。
    private static let cloudDelay: TimeInterval = 0.7
    /// 至少几个音节才值得问。太短的本地词库就够了，问了纯属浪费。
    private static let cloudMinSyllables = 3
    private var cloudTimer: Timer?
    /// 上一次问过的那一串，**同串不重复问**（他反复退格再打回来是常事）。
    private var cloudAsked = ""
    /// 云端给回来的整句，缓存着，重排候选时不用再问一次。
    private var cloudGuess: (py: String, text: String) = ("", "")

    /// 中文下用哪种输入法。左下角那个键在这几档之间循环。
    ///
    /// 🚨🚨 **手写档 2026-09-04 起不上线（Kevin 拍板）**。
    ///
    ///    原因不是它坏了，是 **iOS 从来没有手写识别引擎**：
    ///    `HandwritingRecognizer` 只是个协议，全仓库**没有任何遵从它的类型**，
    ///    `recognizer` 属性**零注入点**，所以恒为 nil、恒空候选。
    ///    安卓那边是真有的（`Handwriting.java` + `model/hccr.tflite` 65MB），
    ///    iOS 键盘扩展内存预算约 60MB **装不下那份模型**，引擎选型一直是
    ///    单独一个待决定（走后端 / 转 Core ML 小模型），至今没定。
    ///
    ///    他报的「写完出不来、识别卡住」就是这个 —— 他在用一个**看起来能用、
    ///    实际永远不出字**的手写板。这是「装饰按钮」那一族：
    ///    UI 上线了，但它做不了它看起来能做的事。
    ///
    /// 🚨 **撤法是把 `.hand` 从 `next` 的循环里摘掉**，不是删掉这个 case：
    ///    ① `label` / `handRow()` / `HandwritePad` 全部原样留着，引擎一落地
    ///       把 `.hand` 加回 `next` 就复活，不用重写；
    ///    ② 删 case 会牵动一堆 `switch`，改动面大、回滚也难。
    ///    **单一配置点就是下面 `next` 那三行** —— 别在别处再加 if 挡一遍。
    enum IMMode {
        case pinyin, wubi, hand
        var label: String {
            switch self {
            case .pinyin: return L.kb_pinyin_s
            case .wubi: return L.kb_wubi_s
            case .hand: return L.kb_hand_s
            }
        }
        var next: IMMode {
            switch self {
            case .pinyin: return .wubi
            // 🚨 引擎落地前**跳过手写**，直接回拼音（见上面的说明）。
            //    引擎做好了就把这行改回 `return .hand`。
            case .wubi: return .pinyin
            case .hand: return .pinyin
            }
        }
    }
    private var imMode: IMMode = .pinyin {
        didSet {
            // 🚨 **九宫格只属于手写档**（安卓 `if (!hand) numMode = false;`）。
            //    挂在 didSet 上而不是散在每个切档的地方 —— 那样漏一处就
            //    会出现"切到拼音了但还显示着九宫格"。
            if imMode != .hand { numMode = false }
        }
    }
    /// 手写档下：true = 九宫格，false = 手写板。
    private var numMode = false
    private var handPad: HandwritePad?

    /// 手写识别引擎。**可以为 nil** —— 见 `HandwritingRecognizer` 上的说明
    /// （安卓那份模型 65MB，iOS 键盘扩展装不下，引擎选型是单独一个决定）。
    var recognizer: HandwritingRecognizer? {
        didSet { handPad?.recognizer = recognizer }
    }

    /// 拼音缓冲变了：安卓走 `setComposingText` 送进输入框，
    /// iOS 对应 `textDocumentProxy.setMarkedText`。
    /// 🚨 **不在候选栏里再显示一遍** —— Kevin 2026-08-23：
    ///    「拼音那一栏显示字母，文本框里也显示字母，就重复了」。
    var onComposing: ((String) -> Void)?
    private var letterButtons: [UIButton] = []
    /// 按钮 → 它长按该出的数字。**不挂在按钮的 tag 上** ——
    /// tag 是个 Int，存不下字符串，而且别处也可能用它。
    private var longPressDigits: [ObjectIdentifier: String] = [:]
    private var punctButtons: [(UIButton, String)] = []
    private var shiftBtn: UIButton?
    private var symBtn: UIButton?
    private var modeBtn: UIButton?
    /// 🚨 空格/完成的键面**跟打字档走**，切中英时要刷新 —— 存引用给 `refreshFaces()`。
    private var spaceBtn: UIButton?
    private var doneBtn: UIButton?

    override init(frame: CGRect) {
        super.init(frame: frame)
        stack.axis = .vertical
        stack.spacing = 0
        // 🚨🚨 **必须 fillEqually**。默认的 .fill 按 hugging 分配高度，
        //    底排那几个键的 hugging 比字母键低 → 底排把富余高度全吃掉，
        //    截图上底排比字母行高一倍多。
        //    Kevin 已经为「键盘各档位高度必须一致」点名过两次
        //    （feedback_keyboard_height_uniform），行与行之间同理。
        //    安卓那边是自己算像素平分的（TypingKeyboard.java 的 rowH），
        //    iOS 用 fillEqually 等价。
        // 🚨 候选栏固高、按键四行等分。
        //    `.fillEqually` 会把候选栏也拉成一样高 —— 那样候选栏跟字母行一样厚，
        //    整个键盘凭空高一截。用 `.fill` + 给每个按键行同一个高度约束
        //    （见 `equalizeRows`）才是"按键行等高、候选栏另算"。
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        candBar.onPick = { [weak self] s in self?.pickCandidate(s) }
        candBar.onMode = { [weak self] zh in self?.setChinese(zh) }
        candBar.onVoice = { [weak self] in
            // 切走之前把没上屏的拼音上掉 —— 绝不静默吞掉他打的东西
            self?.commitPending()
            self?.onSwitchToVoice?()
        }
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 组装

    private func rebuild() {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        letterButtons.removeAll()
        punctButtons.removeAll()
        longPressDigits.removeAll()

        // 🚨 候选栏在最上面，跟安卓 `suggestBar` 同一个位置。
        //    它**不参与等分**（字母行才等分），所以单独固高。
        stack.addArrangedSubview(candBarRow())
        // 手写档：手写板 / 九宫格 二选一，都不走字母那套版面。
        if imMode == .hand {
            stack.addArrangedSubview(numMode ? numPad() : handRow())
            let bottom = bottomRow()
            // 🚨 手写档下**不能跑 `equalizeRows`**：它让"第一行之外的每一行
            //    都等于第一行"，而这里第一行是手写板（固高 216），
            //    底排会被拉平成 216 高。底排单独给标准行高。
            bottom.heightAnchor.constraint(
                equalToConstant: Layout.keyRowH).isActive = true
            stack.addArrangedSubview(bottom)
            refreshCaps()
            notifyHeight()
            return
        }
        switch mode {
        case .letters:
            stack.addArrangedSubview(row(Layout.row1, indent: 0))
            stack.addArrangedSubview(row(Layout.row2,
                                         indent: Layout.row2Indent))
            stack.addArrangedSubview(letterRow3())
        case .symbols:
            let page = symPage == 0 ? Layout.sym0 : Layout.sym1
            stack.addArrangedSubview(row(page[0], indent: 0, punct: true))
            stack.addArrangedSubview(row(page[1],
                                         indent: Layout.row2Indent, punct: true))
            stack.addArrangedSubview(symRow3(page[2]))
        }
        stack.addArrangedSubview(bottomRow())
        equalizeRows()
        refreshCaps()
        notifyHeight()
    }

    /// 手写板那一块。高度 `PAD_H`，跟九宫格一致。
    private func handRow() -> UIView {
        let box = UIView()
        let pad = HandwritePad()
        pad.recognizer = recognizer
        pad.onCandidates = { [weak self] c in self?.candBar.setCandidates(c) }
        pad.layer.cornerRadius = Theme.rKey
        pad.clipsToBounds = true
        pad.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(pad)
        handPad = pad

        // 撤销 / 清空。安卓 handRow 里这两个键在手写板右侧。
        let col = UIStackView()
        col.axis = .vertical
        col.spacing = Layout.rowPad * 2
        col.distribution = .fillEqually
        col.translatesAutoresizingMaskIntoConstraints = false
        for (title, act) in [(L.kb_undo, #selector(tapUndo)),
                             (L.kb_clear, #selector(tapClear))] {
            let b = makeKey(title)
            b.titleLabel?.font = .systemFont(ofSize: 14)   // 安卓 setTextSize(14)
            b.addTarget(self, action: act, for: .touchUpInside)
            col.addArrangedSubview(b)
        }
        box.addSubview(col)

        NSLayoutConstraint.activate([
            pad.leadingAnchor.constraint(equalTo: box.leadingAnchor,
                                         constant: Layout.handPad),
            pad.topAnchor.constraint(equalTo: box.topAnchor,
                                     constant: Layout.handPad),
            pad.bottomAnchor.constraint(equalTo: box.bottomAnchor,
                                        constant: -Layout.handPad),
            col.leadingAnchor.constraint(equalTo: pad.trailingAnchor,
                                         constant: Layout.keyGap),
            col.trailingAnchor.constraint(equalTo: box.trailingAnchor,
                                          constant: -Layout.handPad),
            col.topAnchor.constraint(equalTo: pad.topAnchor),
            col.bottomAnchor.constraint(equalTo: pad.bottomAnchor),
            col.widthAnchor.constraint(equalToConstant: 64),
            box.heightAnchor.constraint(equalToConstant: Layout.padH),
        ])
        return box
    }

    @objc private func tapUndo() { handPad?.undo() }
    @objc private func tapClear() { handPad?.clear() }

    /// 九宫格数字键盘（3 列 × 4 行）。
    ///
    /// 🚨 键位**故意做大**：Kevin 2026-08-23「手写主要是老人家在用，
    ///    不需要打字母，能方便手写并能直接输入数字就好」。
    /// 🚨 `←` 和 `⌫` **不在这里** —— 他说「本来这两个键在这儿也没什么必要嘛，
    ///    放在右上角就好了嘛」。少一行 → 每行更高更宽松，正是他要的效果。
    /// 🚨 总高跟手写板严格相等（都是 `padH`），来回切不忽高忽低。
    private func numPad() -> UIView {
        let rows = [["1", "2", "3"], ["4", "5", "6"],
                    ["7", "8", "9"], ["*", "0", "#"]]
        let v = UIStackView()
        v.axis = .vertical
        v.distribution = .fillEqually
        v.spacing = 0
        for r in rows {
            let h = UIStackView()
            h.axis = .horizontal
            h.distribution = .fillEqually
            h.spacing = Layout.numKeyMargin * 2
            h.isLayoutMarginsRelativeArrangement = true
            h.layoutMargins = UIEdgeInsets(top: Layout.numKeyMargin,
                                           left: Layout.numKeyMargin,
                                           bottom: Layout.numKeyMargin,
                                           right: Layout.numKeyMargin)
            for k in r {
                let b = makeKey(k)
                b.titleLabel?.font = .systemFont(ofSize: Layout.numKeyTextSize)
                b.addAction(UIAction { [weak self] _ in self?.emit(k) },
                            for: .touchUpInside)
                h.addArrangedSubview(b)
            }
            v.addArrangedSubview(h)
        }
        let box = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 2),
            v.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -2),
            v.topAnchor.constraint(equalTo: box.topAnchor,
                                   constant: Layout.handPad),
            v.bottomAnchor.constraint(equalTo: box.bottomAnchor,
                                      constant: -Layout.handPad),
            // 🚨 跟 handRow 用**同一个** padH：两个档位总高严格相等。
            box.heightAnchor.constraint(equalToConstant: Layout.padH),
        ])
        return box
    }

    /// 候选栏那一行。
    /// 🚨 竖向 stack 是 `.fillEqually`（各行等高，Kevin 点名两次的规矩），
    ///    但候选栏比按键行矮 —— 给它一个自己的高度约束，
    ///    并把 `fillEqually` 换成按内容排：见 `rebuild` 里的说明。
    private func candBarRow() -> UIView {
        // 🚨 只在九宫格态显示（安卓 `numTopKeys.setVisibility(hand && numMode)`）。
        candBar.topKeys = (imMode == .hand && numMode)
            ? [("\u{2190}", { [weak self] in
                    self?.numMode = false
                    self?.rebuild()
                }),
               ("\u{232B}", { [weak self] in
                    // 九宫格顶行那个退格。这里是闭包不是按钮，
                    // 拿不到长按事件 —— 走 proxy 的单次删除，跟别处同源。
                    // 🚨 **先问缓冲**（2026-09-04 修）：缓冲里有拼音时这一下
                    //    要删缓冲，不能删文档。见 `backspaceEatsBuffer()`。
                    guard let s = self else { return }
                    if s.backspaceEatsBuffer() { return }
                    if let p = s.proxyProvider?() {
                        p.deleteBackward()
                    } else {
                        s.onDelete?()
                    }
                })]
            : []
        let box = UIView()
        candBar.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(candBar)
        NSLayoutConstraint.activate([
            candBar.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            candBar.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            candBar.topAnchor.constraint(equalTo: box.topAnchor),
            candBar.bottomAnchor.constraint(equalTo: box.bottomAnchor),
            box.heightAnchor.constraint(equalToConstant: Layout.candBarH),
        ])
        return box
    }

    /// 一行键。`punct=true` 时键面走 `Punct.face`（跟输出同源）。
    private func row(_ keys: [String], indent: CGFloat,
                     punct: Bool = false) -> UIView {
        let h = UIStackView()
        h.axis = .horizontal
        h.distribution = .fillEqually
        h.spacing = Layout.keyGap
        for k in keys {
            let b = makeKey(punct ? Punct.face(k, english: english) : k)
            if punct {
                punctButtons.append((b, k))
                b.addAction(UIAction { [weak self] _ in
                    guard let s = self else { return }
                    s.emit(Punct.out(k, english: s.english))
                }, for: .touchUpInside)
            } else {
                letterButtons.append(b)
                attachLongPressDigit(b, k)
                b.addAction(UIAction { [weak self] _ in
                    self?.tapLetter(k)
                }, for: .touchUpInside)
            }
            h.addArrangedSubview(b)
        }
        return pad(h, indent: indent)
    }

    /// 字母第三行：上档 + 7 个字母 + 退格。
    private func letterRow3() -> UIView {
        let h = UIStackView()
        h.axis = .horizontal
        h.spacing = Layout.keyGap
        h.distribution = .fill

        let sh = makeKey("")
        shiftBtn = sh
        sh.addAction(UIAction { [weak self] _ in self?.tapShift() },
                     for: .touchUpInside)
        h.addArrangedSubview(sh)

        let mid = UIStackView()
        mid.axis = .horizontal
        mid.spacing = Layout.keyGap
        mid.distribution = .fillEqually
        for k in Layout.row3 {
            let b = makeKey(k)
            letterButtons.append(b)
            b.addAction(UIAction { [weak self] _ in self?.tapLetter(k) },
                        for: .touchUpInside)
            mid.addArrangedSubview(b)
        }
        h.addArrangedSubview(mid)

        let del = makeKey("⌫")
        attachDelete(del)
        h.addArrangedSubview(del)

        // 两边的功能键各占 1.5 格（跟安卓 wide(1.5f) 一致）
        sh.widthAnchor.constraint(equalTo: mid.widthAnchor,
                                  multiplier: 1.5 / 7).isActive = true
        del.widthAnchor.constraint(equalTo: sh.widthAnchor).isActive = true
        return pad(h, indent: 0)
    }

    /// 符号第三行：翻页 + 符号 + 退格。
    private func symRow3(_ keys: [String]) -> UIView {
        let h = UIStackView()
        h.axis = .horizontal
        h.spacing = Layout.keyGap
        h.distribution = .fill

        // 🚨 翻页键字面照系统：第一页「#+=」，第二页「123」。原来写的「=\<」不是任何主流键盘的写法。
        let more = makeKey(symPage == 0 ? "#+=" : "123")
        more.addAction(UIAction { [weak self] _ in
            guard let s = self else { return }
            s.symPage = 1 - s.symPage
            s.rebuild()
        }, for: .touchUpInside)
        h.addArrangedSubview(more)

        let mid = UIStackView()
        mid.axis = .horizontal
        mid.spacing = Layout.keyGap
        mid.distribution = .fillEqually
        for k in keys {
            let b = makeKey(Punct.face(k, english: english))
            punctButtons.append((b, k))
            b.addAction(UIAction { [weak self] _ in
                guard let s = self else { return }
                s.emit(Punct.out(k, english: s.english))
            }, for: .touchUpInside)
            mid.addArrangedSubview(b)
        }
        h.addArrangedSubview(mid)

        let del = makeKey("⌫")
        attachDelete(del)
        h.addArrangedSubview(del)

        more.widthAnchor.constraint(
            equalTo: mid.widthAnchor,
            multiplier: 1.5 / CGFloat(max(keys.count, 1))).isActive = true
        del.widthAnchor.constraint(equalTo: more.widthAnchor).isActive = true
        return pad(h, indent: 0)
    }

    /// 底排：中英 / ?123 / 逗号 / 空格 / 句号 / 完成。跟安卓一致。
    private func bottomRow() -> UIView {
        let h = UIStackView()
        h.axis = .horizontal
        h.spacing = Layout.keyGap
        h.distribution = .fill

        // 🚨🚨 这个键**只在中文的几种输入法之间循环**（拼音 → 五笔 → 手写），
        //    **不切中英**。中英归候选栏左上角那两个芯片。
        //    Kevin 2026-08-23：「你左上角保留中文和英文这两个选项，
        //    然后中文具体的输入法，你在键盘的左下角设个按钮去切换」。
        //    （手写档还没搬过来，所以现在只在拼音↔五笔之间循环。）
        //
        // 🚨 颜色：常驻 accent + 白字，不随档位变。他要的是"跟旁边的标点键
        //    区分开，不然别人看不懂该按哪个，会 misleading"。
        let m = makeKey(imMode.label)
        modeBtn = m
        m.accessibilityIdentifier = "kb.immode"   // 端到端要验它在英文档下消失
        // 🚨 创建时就定好显隐 —— 不然首屏若本来就是英文档，
        //    这个键会先画出来、等第一次 `refreshFaces()` 才消失（闪一下）。
        m.isHidden = !chinese
        m.backgroundColor = Theme.accent
        m.setTitleColor(.white, for: .normal)
        m.addAction(UIAction { [weak self] _ in
            guard let s = self else { return }
            s.commitPending()          // 换档前先把没上屏的上掉
            s.imMode = s.imMode.next
            s.pinyin = ""
            s.rebuild()
            s.refreshCandidates()
        }, for: .touchUpInside)
        h.addArrangedSubview(m)

        // 🚨 手写档下这个键换职责：切九宫格 / 回手写板（安卓 `symBtn` 同款）。
        // 🚨 九宫格态用 `kb_hand`（「手写」），**不是** `kb_hand_s`（「写」）——
        //    后者是左下角档位键的短标签，两个都用短标签就成了并排两个「写」。
        //    安卓 `symBtn.setText(hand ? (numMode ? kb_hand : "?123") : ...)`。
        let sym = makeKey(imMode == .hand
                          ? (numMode ? L.kb_hand : "?123")
                          : (mode == .letters ? "?123" : "ABC"))
        symBtn = sym
        sym.addAction(UIAction { [weak self] _ in
            // 手写档下这个键切九宫格 / 回手写板（安卓 symBtn 同款）
            if let s = self, s.imMode == .hand {
                s.numMode.toggle()
                s.rebuild()
                return
            }
            guard let s = self else { return }
            s.mode = (s.mode == .letters) ? .symbols : .letters
            s.symPage = 0
            s.rebuild()
        }, for: .touchUpInside)
        h.addArrangedSubview(sym)

        let comma = makeKey(Punct.face(",", english: english))
        punctButtons.append((comma, ","))
        comma.addAction(UIAction { [weak self] _ in
            guard let s = self else { return }
            s.emit(Punct.out(",", english: s.english))
        }, for: .touchUpInside)
        h.addArrangedSubview(comma)

        let space = makeKey(L.kb_space_face(english))
        spaceBtn = space
        space.addAction(UIAction { [weak self] _ in self?.emit(" ") },
                        for: .touchUpInside)
        h.addArrangedSubview(space)

        let period = makeKey(Punct.face(".", english: english))
        punctButtons.append((period, "."))
        period.addAction(UIAction { [weak self] _ in
            guard let s = self else { return }
            s.emit(Punct.out(".", english: s.english))
        }, for: .touchUpInside)
        h.addArrangedSubview(period)

        let done = makeKey(L.kb_done_face(english))
        doneBtn = done
        done.backgroundColor = Theme.accent
        done.setTitleColor(.white, for: .normal)
        done.addAction(UIAction { [weak self] _ in self?.onSwitchToVoice?() },
                       for: .touchUpInside)
        h.addArrangedSubview(done)

        // 空格占大头，其余等宽（安卓那边空格是 wide(3f)）
        for v in [m, sym, comma, period, done] {
            v.widthAnchor.constraint(equalTo: space.widthAnchor,
                                     multiplier: 0.42).isActive = true
        }
        return pad(h, indent: 0)
    }

    private func pad(_ v: UIView, indent: CGFloat) -> UIView {
        let box = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(v)
        NSLayoutConstraint.activate([
            v.leadingAnchor.constraint(equalTo: box.leadingAnchor,
                                       constant: indent),
            v.trailingAnchor.constraint(equalTo: box.trailingAnchor,
                                        constant: -indent),
            v.topAnchor.constraint(equalTo: box.topAnchor,
                                   constant: Layout.rowPad),
            v.bottomAnchor.constraint(equalTo: box.bottomAnchor,
                                      constant: -Layout.rowPad),
        ])
        return box
    }

    /// 当前档位下键盘该多高。
    ///
    /// 🚨 值是**算出来的**，不是写死的常量：
    ///    字母/符号 = 候选栏 + 4 行按键；手写/九宫格 = 候选栏 + 手写幅面 + 底排。
    ///    写死一个数的话，换档时不是被挤扁就是空一块（截图上看到过）。
    var preferredHeight: CGFloat {
        if imMode == .hand {
            // 手写**显式豁免**：Kevin 只允许手写更高。
            return Layout.candBarH + Layout.padH + Layout.keyRowH
        }
        // 🚨 其它档位一律用**唯一常量** `Layout.panelH`，
        //    不再各自算一个数 —— 见 `panelH` 的注释。
        return Layout.panelH
    }

    /// 档位变了要通知宿主改高度约束。
    var onHeightChange: ((CGFloat) -> Void)?

    private func notifyHeight() {
        onHeightChange?(preferredHeight)
    }

    /// 让**按键行**彼此等高（候选栏那一行不参与）。
    ///
    /// 🚨 这是 Kevin 点名两次的「各档位高度必须一致」在 iOS 侧的落点。
    ///    原来靠 `.fillEqually`，但那会把候选栏也算进去。
    private func equalizeRows() {
        let rows = stack.arrangedSubviews.dropFirst()   // 第 0 个是候选栏
        guard let first = rows.first else { return }
        for r in rows.dropFirst() {
            r.heightAnchor.constraint(equalTo: first.heightAnchor).isActive = true
        }
    }

    /// 调试用：直接跳到某个档位。走的是真实切档路径。
    /// 🚨 只给预览页用（`TRANSLESS_KB_MODE`）。正式界面里没有调用点。
    ///
    /// 🚨 **`hand`/`num` 这两档故意留着**（2026-09-04 手写下线之后）：
    ///    手写在正式键盘上已经切不到了（`IMMode.next` 跳过它），
    ///    但这个口子还能进 —— 好让引擎落地时能直接截图核对手写板，
    ///    不用先把档位加回去。**它没有任何正式入口，Kevin 碰不到。**
    func debugMode(_ name: String) {
        switch name {
        case "hand": imMode = .hand; numMode = false
        case "num": imMode = .hand; numMode = true
        case "wubi": imMode = .wubi
        case "sym": mode = .symbols; symPage = 0
        // 🚨 2026-09-03 加这两个，是因为**这两处我一直只能靠代码说「应该对」**：
        //    符号第二页要点两下才到（Kevin 找不到左斜杠就在那儿），
        //    大写锁定要连点两次 shift —— 而模拟器上我点不了键
        //    （CGEvent 要辅助功能授权）。没有这两个入口，
        //    我就只能把「你自己看一眼」推给他，那正是他点名的毛病。
        case "sym2": mode = .symbols; symPage = 1
        case "caps": capState = 2
        default: return
        }
        rebuild()
    }

    /// 调试用：按名字找到某个字母键并**真的点它**。
    /// 🚨 只给预览页用（`TRANSLESS_KB_TYPE`）。正式界面里没有调用点。
    func debugTap(_ letter: String) {
        for b in letterButtons where b.title(for: .normal)?.lowercased() == letter {
            b.sendActions(for: .touchUpInside)
            return
        }
    }

    private func makeKey(_ title: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(Theme.kbKeyText, for: .normal)
        // 安卓 TypingKeyboard.java:357 `baseKey` = setTextSize(17)
        b.titleLabel?.font = .systemFont(ofSize: Layout.keyTextSize)
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.minimumScaleFactor = 0.6
        b.backgroundColor = Theme.kbKey
        // 🚨 安卓 Theme.R_KEY = 12dp。这里原来写的是 6 —— **我自己编的**，
        //    不是照抄。「有标准答案就照抄，别重新设计」。
        b.layer.cornerRadius = Theme.rKey
        return b
    }

    // MARK: - 行为

    /// 给一个键装上完整退格行为（长按连删、1.2 秒后按词删）。
    ///
    /// 🚨 **所有退格键都必须走这里**（安卓那句注释：「退格统一走 Backspace，
    ///    不在这里再写一份」）。散着写的结果就是"这个键的退格跟那个键不一样"，
    ///    而且改的时候必漏一处。
    private func attachDelete(_ b: UIButton) {
        // 🚨🚨 2026-09-03 Kevin：「打字模式的时候，这个删除键没法连删，
        //    只能一个一个删，也很弱」。根因是**顺序**，不是 Backspace 写错了：
        //
        //      let t = TypingKeyboardView()   ← 构造时就把键建好了，attachDelete 在这里跑
        //      t.proxyProvider = { ... }      ← 宿主**之后**才赋值
        //
        //    所以 `if let provider = proxyProvider` 当场读到 nil，
        //    每次都落进下面那条「退化成单次删除」的分支 —— 而它**不报错**，
        //    只是安静地少了连删和按词删。
        //
        //    修法是**别捕获值，捕获查找动作**：闭包每次被调用时才去读
        //    `proxyProvider`，赋值早晚都不影响。
        //    （本文件第 384 行那个九宫格退格一直是对的，正因为它是懒读的。）
        Backspace.attach(b, proxy: { [weak self] in
            if let p = self?.proxyProvider?() { return p }
            return nil
        }, eatsFirst: { [weak self] in
            // 🚨 缓冲里有拼音就先吃缓冲（含长按连删的每一下）。见
            //    `backspaceEatsBuffer()` 上那段根因说明。
            self?.backspaceEatsBuffer() ?? false
        })
        // 宿主没注入（比如 App 里的预览页）时 Backspace 拿不到 proxy，
        // 这里再挂一条单次删除兜底，**不失灵**。
        // 🚨 这条也要先问缓冲 —— 预览页里同样能打拼音。
        b.addAction(UIAction { [weak self] _ in
            guard let s = self, s.proxyProvider?() == nil else { return }
            if s.backspaceEatsBuffer() { return }
            s.onDelete?()
        }, for: .touchUpInside)
    }

    /// 给首行字母装长按出数字。
    private func attachLongPressDigit(_ b: UIButton, _ k: String) {
        guard let digit = Layout.longPressDigit(k) else { return }
        let g = UILongPressGestureRecognizer(target: self,
                                             action: #selector(onLongPressDigit(_:)))
        g.minimumPressDuration = 0.35
        b.addGestureRecognizer(g)
        longPressDigits[ObjectIdentifier(b)] = digit
    }

    @objc private func onLongPressDigit(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let b = g.view as? UIButton,
              let digit = longPressDigits[ObjectIdentifier(b)] else { return }
        // 🚨 先把没上屏的拼音上掉，别让「你好」变成「1你好」——
        //    跟符号键同一个口径（安卓那边写着这条）。
        commitPending()
        emit(digit)
    }

    private func tapLetter(_ k: String) {
        // 中文档：字母先进拼音缓冲，不直接上屏（安卓 `pinyin.append(k)`）
        //
        // 🚨🚨 2026-09-04 修（红队 P2）：判据原来是 `chinese && capState == 0` ——
        //    **shift 一亮，中文档下的字母就绕过缓冲直接上屏**，
        //    而 `pinyin` 那一串还原样留着 → composition 被从中间劈开：
        //    屏幕上是「nih」+「A」，缓冲里还是「nih」，
        //    下一个字母接上去变成「niha」，候选跟屏幕彻底对不上。
        //
        // 🚨 而**拼音输入里 shift 三态本来就没有意义** —— 拼音码全是小写，
        //    大写的 `A` 不是任何音节。所以正确做法不是"大写也进缓冲"
        //    （那等于默认他打错了还替他改），而是**中文档下字母一律进缓冲、
        //    并且把 shift 复位**：他按 shift 多半是想打英文，
        //    那条路应该走「中/EN 芯片」切档，不是靠 shift 硬插一个大写字母。
        if chinese {
            pinyin += k
            // shift 在中文档下不生效 —— 顺手复位，免得它一直亮着让人以为下一个会大写。
            if capState != 0 {
                capState = 0
                refreshCaps()
            }
            refreshCandidates()
            return
        }
        emit(capState == 0 ? k : k.uppercased())
        if capState == 1 {          // 一次性大写用完就掉
            capState = 0
            refreshCaps()
        }
    }

    // MARK: - 拼音

    /// 重算候选。**连拼**：整串切成音节，先拿整串查词，查不到再拿第一个音节查字。
    /// 停手一会儿之后去问一次云端整句。
    ///
    /// 🚨🚨 **三道闸都是为了不烧他的钱**，少一道都会变成"每敲一下发一次"：
    ///    ① 停手 `cloudDelay` 秒才发（他还在打就一直往后推）；
    ///    ② 音节少于 `cloudMinSyllables` 不发（短的本地词库就够）；
    ///    ③ 同一串**问过就不再问**（他退格再打回来是常事）。
    ///
    /// 🚨 回来时**必须核对拼音串有没有变** —— 网络往返期间他可能已经
    ///    打了别的字。不核对就会把上一串的猜测插进这一串的候选里，
    ///    而那种错**看起来像模型很蠢**，其实是我们把结果贴错了地方。
    private func scheduleCloudGuess() {
        cloudTimer?.invalidate(); cloudTimer = nil
        guard chinese, imMode != .wubi, !pinyin.isEmpty else { return }
        let py = pinyin
        guard PinyinSplit.split(py).count >= Self.cloudMinSyllables else { return }
        guard py != cloudAsked else { return }
        cloudTimer = Timer.scheduledTimer(withTimeInterval: Self.cloudDelay,
                                          repeats: false) { [weak self] _ in
            guard let self = self, self.pinyin == py else { return }
            self.cloudAsked = py
            Backend.pinyinGuess(py) { [weak self] text in
                DispatchQueue.main.async {
                    guard let self = self, !text.isEmpty else { return }
                    // 🚨 回来时他可能早打别的了 —— 串对不上就整条丢掉，不硬贴。
                    guard self.pinyin == py else { return }
                    self.cloudGuess = (py, text)
                    self.refreshCandidates()
                }
            }
        }
    }

    private func refreshCandidates() {
        onComposing?(pinyin)
        if pinyin.isEmpty {
            candBar.setCandidates([])
            return
        }
        PinyinSplit.ensureLoaded()

        // 五笔：编码不切音节，直接查表。
        // 🚨 码表里**只有 3 码和 4 码**，纯精确匹配的话打前一两个字母
        //    候选区永远空白，看着就像功能坏了（Kevin 2026-08-21 实测报过）。
        //    所以查不到就退到前缀匹配，边打边缩小范围。
        if imMode == .wubi {
            var wc = PinyinSplit.wubiCandidates(pinyin)
            if wc.isEmpty { wc = PinyinSplit.wubiPrefix(pinyin, limit: 40) }
            candBar.setCandidates(wc.isEmpty ? [pinyin] : wc)
            return
        }

        // 🚨 顺序照安卓 `refreshSuggest` 的五层，别改：
        //    每一层都是 Kevin 报过某个具体毛病之后加的。
        var seen = Set<String>()
        var list: [String] = []
        func add(_ arr: [String]) {
            for s in arr where !s.isEmpty && !seen.contains(s) {
                seen.insert(s)
                list.append(s)
            }
        }

        // ① 整串精确命中的词优先（打 mingtian 出「明天」）
        add(PinyinSplit.candidates(pinyin))
        // ①.2 **云端整句**（他打完停手才问的那一条，见 `scheduleCloudGuess`）。
        //    🚨 排在词库精确命中**之后**：本地命中是确定的，云端是猜的，
        //       确定的东西不该被猜的挤下去。
        //    🚨 只有拼音串跟当初问的那一串**完全一致**才用 —— 见那边的说明。
        if cloudGuess.py == pinyin, !cloudGuess.text.isEmpty {
            add([cloudGuess.text])
        }
        // ①.5 拼音没打完也要能联想出词（mingt → 明天、nih → 你好）
        add(PinyinSplit.prefixWords(pinyin, limit: 20))
        // ② 连拼整句：每个音节取最优拼成一句
        let parts = PinyinSplit.split(pinyin)
        if parts.count > 1 {
            let guess = PinyinSplit.firstGuess(pinyin)
            if !guess.isEmpty { add([guess]) }
        }
        // ③ 每个**完整**音节的候选。
        //    🚨 不能只给第一个音节：打 "woq" 时前面的 wo 是完整的，
        //    要让他能先把「我」上屏，剩下 q 接着打。
        // 2026-09-02 Kevin：「选了一个再接着往下选」。只给【首个】完整音节的候选——
        //    单字候选只能来自首音节，点了才吃得准（吃掉首音节、剩下继续出候选）；
        //    给后面音节的字，点了没法从前面吃，只能整串清，正是他撞的「选了测，后面全没了」。
        if let first = parts.first { add(PinyinSplit.candidates(first)) }

        // ⑤ 查不到就给个"直接上屏拼音"的出口，别让他卡住
        candBar.setCandidates(list.isEmpty ? [pinyin] : list)
        scheduleCloudGuess()
    }

    /// 点了候选：上屏，并从缓冲里吃掉对应的那一段。
    ///
    /// 🚨 **绝不静默吞掉输入**（安卓同款约定）：吃掉多少要算得出来，
    ///    算不出来就整串清掉，不能留一半在缓冲里让人莫名其妙。
    private func pickCandidate(_ s: String) {
        onText?(s)
        // 2026-09-02 Kevin：「选了一个再接着往下选另外一个」——逐字选。**吃掉多少按来源算**：
        //    整串命中 / 前缀联想（mingt→明天）/ 连拼整句 → 整串清（沿用旧约定，避免剩个裸 t）；
        //    首音节的单字候选 → 只吃掉首音节，剩下的拼音留着继续出候选（ceshiyixia 点「测」→ 剩 shiyixia）。
        //    算不出来（或首音节不是缓冲前缀）→ 整串清，**绝不留一半**。
        if imMode != .wubi, !pinyin.isEmpty {
            let parts = PinyinSplit.split(pinyin)
            var whole = PinyinSplit.candidates(pinyin) + PinyinSplit.prefixWords(pinyin, limit: 20)
            if parts.count > 1 { whole.append(PinyinSplit.firstGuess(pinyin)) }
            if !whole.contains(s), let first = parts.first, pinyin.hasPrefix(first),
               PinyinSplit.candidates(first).contains(s) {
                pinyin = String(pinyin.dropFirst(first.count))
                refreshCandidates()
                return
            }
        }
        pinyin = ""
        refreshCandidates()
    }

    private func setChinese(_ v: Bool) {
        chinese = v
        candBar.setChinese(v)
        // 🚨 切走之前把缓冲里的拼音原样上屏 —— **绝不静默吞掉他打的东西**。
        if !v { commitPending() }
        pinyin = ""
        refreshFaces()
        refreshCandidates()
    }

    /// **除候选之外的一切上屏，都走这里** —— 标点、空格、数字、英文字母、句号…
    ///
    /// 🚨🚨 2026-09-04 红队点名：中文档下正在打拼音时，按**标点 / 空格 / 逗号 /
    ///    句号 / 符号行 / `?123`↔`ABC` 切页 / 「完成」键**，这 6 处
    ///    **都没有先 `commitPending()`** 就直接 `onText(...)`。
    ///    后果：打了一半的拼音被那个标点顶掉（屏幕上那段被替换），
    ///    **而 `pinyin` 这个变量还留着旧串**，下个字母接在过期缓冲后面 → 全乱。
    ///
    /// 🚨 **反证就在同一个文件里**：长按出数字和左下角切输入法**是**先
    ///    `commitPending()` 的 —— 同一条规矩散在 10 个调用点、只落地了 2 个。
    ///    **这正是「改一处等于没改」，所以修法是收咽喉，不是再补 6 个 if。**
    ///
    /// - Parameter raw: true = **不要**先定稿拼音（只有候选上屏和 `commitPending`
    ///   自己该传 true —— 它们要么正在替换那段拼音，要么本身就是在定稿）。
    private func emit(_ s: String, raw: Bool = false) {
        if !raw { commitPending() }
        onText?(s)
    }

    /// 宿主那边的位置变了（他点了别处 / 宿主改了文字）→ **丢掉拼音缓冲**。
    ///
    /// 🚨 缓冲和"屏幕上挂着的那段"必须**同进同退**。宿主侧的记账
    ///    （`KeyboardViewController.shownComposing`）作废时这边不跟着清，
    ///    下一个字母就会接在一串**已经不在屏幕上**的旧拼音后面，
    ///    候选全错、再上屏就是一坨乱码。
    /// 🚨 **不 commit、不上屏**：那段拼音已经作为普通文字留在他输入框里了
    ///    （宿主那边只清记账不动文档），这里再 commit 一次就是**重复插入**。
    func dropComposingBuffer() {
        guard !pinyin.isEmpty else { return }
        pinyin = ""
        // 🚨 直接刷候选，**不要走 `refreshCandidates()` 的 `onComposing` 回调** ——
        //    那会再往宿主发一次「显示空串」，而宿主那边记账已经清了，
        //    等于多一次无意义的跨进程调用。这里只需要把候选栏清干净。
        candBar.setCandidates([])
    }

    /// 退格：**缓冲里有拼音就先吃缓冲**，缓冲空了才删文档。
    ///
    /// 🚨🚨 2026-09-04 Kevin 报的「退格删不掉 composing 拼音、必须先『点出拼音』再删」
    ///    根因就在这儿：退格**两条入口**（九宫格顶行那个、主退格键走 `Backspace` 组件）
    ///    **都直接对 `proxy.deleteBackward()`，完全不看 `pinyin` 缓冲**。
    ///    `Backspace.swift` 里 `pinyin`/`composing`/`marked` 三个词零命中 ——
    ///    它根本不知道有缓冲这回事。
    ///
    ///    后果链：打 "nihao" → 缓冲 "nihao"、输入框里是 marked 的 "nihao"
    ///    → 按退格 → 删的是**文档**，我们的缓冲一个字符没少
    ///    → 下一次按键 `refreshCandidates()` 又把整串 `setMarkedText` 写回去
    ///    → 他看到的就是「删不掉」。
    ///    而"先点出拼音再删"能 work，是因为那时拼音已经被 commit 成正式文字了。
    ///
    /// 🚨 **收成一个函数、两条入口都调它** —— 这正是这个文件反复栽的形态：
    ///    同一件事两个出口，改一处等于没改。
    /// - Returns: true = 这次退格已经被缓冲吃掉了，调用方**不要**再删文档。
    private func backspaceEatsBuffer() -> Bool {
        // 🚨 判据是**缓冲非空**，不是「中文档」—— 五笔档也有缓冲（编码），
        //    只判 `chinese` 会让五笔的退格继续走文档，漏掉一半。
        guard !pinyin.isEmpty else { return false }
        pinyin.removeLast()
        refreshCandidates()
        return true
    }

    /// 缓冲里还有拼音就原样上屏 —— **查不到不代表要丢掉他打的东西**。
    private func commitPending() {
        if !pinyin.isEmpty {
            onText?(pinyin)
            pinyin = ""
            refreshCandidates()
        }
    }


    private func tapShift() {
        let now = Date().timeIntervalSince1970
        let dbl = (now - lastShiftAt) < 0.3
        lastShiftAt = now
        if dbl {
            capState = 2                       // 连按两下 = 锁定
        } else if capState == 0 {
            capState = 1
        } else {
            capState = 0
        }
        refreshCaps()
    }

    /// 刷新上档键的样子 + **键面字母跟着变大小写**。
    ///
    /// 🚨 三态只靠**颜色**区分，不靠字形 —— 安卓那边用字形试过三次都不行
    ///    （`⇪`/`⬆` 在真机上跟 `⇧` 长得一样）。
    /// 🚨 箭头**自己画**，不用字体字形：系统字体没有实心上箭头，
    ///    换字符换不出粗细来（安卓 2026-08-25 实测）。
    /// 刷新标点键的**键面**。切中英档后必须调 ——
    /// 键面和输出走同一个来源（`Punct.face` / `Punct.out`），
    /// 否则会出现"键上写 `,`、按下去出 `，`"这种误导人的事。
    private func refreshFaces() {
        for (b, k) in punctButtons {
            b.setTitle(Punct.face(k, english: english), for: .normal)
        }
        modeBtn?.setTitle(imMode.label, for: .normal)
        // 🚨🚨 **英文档下左下角这个键整个消失**（Kevin 2026-09-04）。
        //    他的原话：「如果我选的是英文键盘，为什么左下角还显示拼音？
        //    英文没有拼音。中文才需要在拼音和五笔之间切换，
        //    英文的话这些选项就不该存在。」
        //
        //    它循环的是**中文的几种输入法**（拼音／五笔），
        //    英文档下这几个词一个都不成立 —— 留在那儿不只是没用，是**误导**。
        //
        // 🚨 用 `isHidden` 折叠而不是移除：这一排是 `UIStackView`，
        //    隐藏项会自动让位、旁边的键撑开，不需要重建整个键盘
        //    （`setChinese` 走的是 `refreshFaces()` 这条轻路径，不是 `rebuild()`）。
        // 🚨 挂在这里而不是创建处：切中英**只会**走到这儿，
        //    挂创建处就得靠 `rebuild()` 被调到 —— 那是另一个条件，会漏。
        modeBtn?.isHidden = !chinese
        // 🚨 空格/完成的键面同样跟打字档走（跟上面标点键同一条规矩）。
        //    漏了这两行的话：键面只在**重建**时才对，而切中英走的是这条轻路径，
        //    表现就是"切了英文，空格键上还写着中文" —— 正是他报的那个。
        spaceBtn?.setTitle(L.kb_space_face(english), for: .normal)
        doneBtn?.setTitle(L.kb_done_face(english), for: .normal)
    }

    private func refreshCaps() {
        guard let sh = shiftBtn else { return }
        let up = capState != 0
        for b in letterButtons {
            guard let t = b.title(for: .normal), t.count == 1 else { continue }
            b.setTitle(up ? t.uppercased() : t.lowercased(), for: .normal)
        }
        let color: UIColor
        switch capState {
        // 🚨 锁定态的底不能写死 `.white`：浅色宿主下普通键也是白的。
        case 2: sh.backgroundColor = Theme.kbShiftLock
                color = Theme.kbShiftLockInk
        case 1: sh.backgroundColor = Theme.accent; color = .white
        default: sh.backgroundColor = Theme.kbKey; color = Theme.kbKeyText
        }
        sh.setImage(Self.arrow(color, 20), for: .normal)
        sh.tintColor = color
    }

    /// 画一个实心上箭头（三角头 + 矩形杆），比例照安卓 `Theme.shiftArrow`。
    private static func arrow(_ color: UIColor, _ h: CGFloat) -> UIImage {
        let size = CGSize(width: h * 1.1, height: h)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let c = ctx.cgContext
            let headW = h * 1.0, headH = h * 0.52
            let stemW = h * 0.30, stemH = h - headH
            let cx = size.width / 2
            c.move(to: CGPoint(x: cx, y: 0))
            c.addLine(to: CGPoint(x: cx + headW / 2, y: headH))
            c.addLine(to: CGPoint(x: cx + stemW / 2, y: headH))
            c.addLine(to: CGPoint(x: cx + stemW / 2, y: headH + stemH))
            c.addLine(to: CGPoint(x: cx - stemW / 2, y: headH + stemH))
            c.addLine(to: CGPoint(x: cx - stemW / 2, y: headH))
            c.addLine(to: CGPoint(x: cx - headW / 2, y: headH))
            c.closePath()
            c.setFillColor(color.cgColor)
            c.fillPath()
        }
    }
}
