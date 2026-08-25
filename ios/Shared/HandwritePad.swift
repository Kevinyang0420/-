import UIKit

/// 手写板：写一个字，停笔约半秒自动识别。**逐行照搬安卓 `HandwritePad.java`。**
///
/// 🚨 渲染口径全部是**从训练集量出来的**，不是凭感觉定的
///    （150 张样本，`D:\_build\_measure.py`）：
///      · 黑底白笔画（四角均值 0、中心 48.6）
///      · 字基本铺满整幅：上边距中位 0、下边界中位 95（共 96）
///      · 墨迹占比中位 14.7% → 96 像素幅面上笔画粗细约 6 px
///    做法：笔迹按**视图坐标**存路径，识别时整体缩放到 96×96 幅面，
///    再以 6 px 笔宽画出来 —— 他写大写小都无所谓，送进模型的始终是同一口径。
///
/// 🚨 **画反了会静默认错，不会报错。** 必须黑底白笔画。
final class HandwritePad: UIView {

    /// 识别结果回调。空数组 = 没有候选。
    var onCandidates: (([String]) -> Void)?
    /// 识别引擎。**可以为 nil** —— 引擎装不上时手写板照常能写能清，
    /// 只是不出候选（跟安卓 `Handwriting.get() == null` 那条降级路径一致）。
    var recognizer: HandwritingRecognizer?

    /// 目标幅面里的笔画宽度，单位 px（幅面 96）。量出来的 14.7% 墨迹占比对应约这个值。
    private static let dstStroke: CGFloat = 6

    /// 送进模型的笔画**亮度**，不是纯白。
    ///
    /// 🚨 这是 2026-08-21 差点交出去的一个哑炮：训练集是铅笔写的，
    ///    笔迹亮度中位只有 144；按纯白 255 画，模型 top-1 从 95.3% 掉到 **28.0%**
    ///    —— 手写档等于是废的，而且不报错、照样出候选，只是十个字认错七个。
    ///    实测（一次只改一个变量）：255 → 28.0% ／ 160 → 92.7% ／ 160+柔化 → 93.3%。
    ///    **只改亮度这一项就够**，主导因素就是它。
    ///    ⚠️ 只改送模型那一份；屏幕上给他看的笔迹仍然是纯白（好看、看得清）。
    private static let modelInk: CGFloat = 160.0 / 255.0
    private static let idle: TimeInterval = 0.5
    /// 模型输入幅面
    static let size = 96

    private var strokes: [UIBezierPath] = []
    private var current: UIBezierPath?
    private var idleWork: DispatchWorkItem?
    /// 识别请求序号：**只认最后一发的结果**。
    /// 写得快时会连着触发几次，后发先至的话候选会闪回上一个字的结果。
    private var recogSeq = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black          // 必须黑底，跟训练集一致
        isMultipleTouchEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    var isEmpty: Bool { strokes.isEmpty && current == nil }

    func clear() {
        idleWork?.cancel()
        strokes.removeAll()
        current = nil
        setNeedsDisplay()
        onCandidates?([])
    }

    /// 撤销最后一笔。写错一笔不用整字重写。
    func undo() {
        idleWork?.cancel()
        if !strokes.isEmpty { strokes.removeLast() }
        setNeedsDisplay()
        if strokes.isEmpty {
            onCandidates?([])
        } else {
            scheduleRecognize()
        }
    }

    override func removeFromSuperview() {
        // 视图没了之后那一发识别还会跑，并把结果回调到已经不在树上的候选区。撤掉。
        idleWork?.cancel()
        super.removeFromSuperview()
    }

    // MARK: - 画

    override func draw(_ rect: CGRect) {
        // 中间十字虚线，帮他把字写在中间
        let w = bounds.width, h = bounds.height
        let g = UIBezierPath()
        g.move(to: CGPoint(x: w / 2, y: 0)); g.addLine(to: CGPoint(x: w / 2, y: h))
        g.move(to: CGPoint(x: 0, y: h / 2)); g.addLine(to: CGPoint(x: w, y: h / 2))
        g.lineWidth = 2
        g.setLineDash([10, 10], count: 2, phase: 0)
        UIColor(red: 0x2A / 255.0, green: 0x31 / 255.0,
                blue: 0x3B / 255.0, alpha: 1).setStroke()
        g.stroke()

        let lw = max(6, min(w, h) * 0.055)
        UIColor.white.setStroke()
        for p in strokes { p.lineWidth = lw; p.stroke() }
        if let c = current { c.lineWidth = lw; c.stroke() }
    }

    // MARK: - 触摸

    private func newPath(at p: CGPoint) -> UIBezierPath {
        let path = UIBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: p)
        // 🚨 点一下也要留下印子，否则「丶」这种一点的笔画会丢
        path.addLine(to: CGPoint(x: p.x + 0.1, y: p.y + 0.1))
        return path
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        idleWork?.cancel()
        current = newPath(at: t.location(in: self))
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let c = current else { return }
        c.addLine(to: t.location(in: self))
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endStroke()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endStroke()
    }

    private func endStroke() {
        if let c = current { strokes.append(c); current = nil; setNeedsDisplay() }
        scheduleRecognize()
    }

    private func scheduleRecognize() {
        idleWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.recognizeNow() }
        idleWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idle, execute: w)
    }

    // MARK: - 渲染成模型输入

    /// 把当前笔迹渲成模型要的 96×96 黑底白字图。没笔迹返回 nil。
    func render() -> UIImage? {
        if strokes.isEmpty { return nil }
        var box = strokes[0].bounds
        for p in strokes.dropFirst() { box = box.union(p.bounds) }

        let S = CGFloat(Self.size)
        // 目标框留出笔宽，否则边缘的笔画会被切掉半条
        let target = S - Self.dstStroke
        let side = max(max(box.width, box.height), 1)
        let scale = target / side

        var m = CGAffineTransform.identity
        m = m.translatedBy(x: S / 2, y: S / 2)
        m = m.scaledBy(x: scale, y: scale)
        m = m.translatedBy(x: -box.midX, y: -box.midY)

        // 🚨 1× 幅面，不是屏幕缩放 —— 模型要的就是 96×96 像素。
        //    用默认 scale 的话 3x 屏上会渲成 288×288，尺寸对不上。
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let r = UIGraphicsImageRenderer(size: CGSize(width: S, height: S),
                                        format: fmt)
        return r.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
            // 🚨 不是纯白 —— 见 `modelInk`。纯白会让准确率从 95% 掉到 28%。
            UIColor(white: Self.modelInk, alpha: 1).setStroke()
            for src in strokes {
                // 🚨 笔宽定在**目标坐标系**里：先把路径变换过去再画，
                //    而不是给画布上矩阵 —— 那样笔宽会跟着缩放，
                //    他写大写小结果就不一样了。
                guard let d = src.copy() as? UIBezierPath else { continue }
                d.apply(m)
                d.lineWidth = Self.dstStroke
                d.lineCapStyle = .round
                d.lineJoinStyle = .round
                d.stroke()
            }
        }
    }

    // MARK: - 识别

    private func recognizeNow() {
        guard let img = render() else { onCandidates?([]); return }
        guard let hw = recognizer else {
            // 引擎装不上：不出候选，但**不报错也不禁用手写板**
            //（跟安卓 `Handwriting.get() == null` 一致）
            onCandidates?([])
            return
        }
        recogSeq += 1
        let mySeq = recogSeq
        // 🚨 推理放**后台线程**。它跑在输入法进程上，慢多少就卡多少，
        //    而"慢多少"取决于机型和模型，不该赌。
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let got = (try? hw.recognize(img, top: 10)) ?? []
            // 🚨 回调必须回主线程：`onCandidates` 直接动 View。
            //    在别的线程碰 View 是未定义行为 —— 多数时候看着正常，
            //    偶尔崩一次，而且堆栈跟这里毫无关系。
            DispatchQueue.main.async {
                guard let s = self, mySeq == s.recogSeq else { return }
                s.onCandidates?(got)
            }
        }
    }
}

/// 手写识别引擎的口子。
///
/// 🚨 故意抽成协议：安卓那份模型是 **65 MB** 的 TFLite，
///    而 iOS 键盘扩展的内存预算只有约 60 MB —— 直接照搬装不下。
///    引擎怎么落地（转 Core ML / 走后端 / 换小模型）是单独一个决定，
///    但手写板 UI、九宫格、候选栏这些都不该等它。
///    引擎为 nil 时手写板照常能写能清，只是不出候选。
protocol HandwritingRecognizer {
    /// 传入 96×96 黑底白字图，返回至多 `top` 个候选字。
    func recognize(_ image: UIImage, top: Int) throws -> [String]
}
