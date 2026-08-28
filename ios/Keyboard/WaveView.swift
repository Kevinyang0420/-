import UIKit

/// 录音时的实时声波条 —— **逐条对着安卓 `WaveView.java` 抄的**，不是我自己设计的。
///
/// 🚨 Kevin 2026-08-28 看 iOS 那版：「停止符号怎么这么大，像个肚脐眼一样…
///    **你抄一下安卓的，不要自己弄**。」
///    安卓早就把「录音中画个大停止方块」换成了这条波形，理由写在
///    `WaveView.java` 里：他 2026-08-22 说「我都不知道它到底有没有听到我说话」。
///
/// 🚨 **这不只是好看**：他撞的"录完没转出来"，最可能的原因就是**根本没录到音**。
///    以前那些情况下界面长得一模一样。有了波形，没声音时它是平的 ——
///    一眼分得清"没听到"和"听到了但后面挂了"。
///
/// 数值全部照抄安卓，别自己调（`android/.../WaveView.java`）：
///
/// | 项 | 值 | 安卓出处 |
/// |---|---|---|
/// | 竖条个数 | 13 | `BARS = 13` |
/// | 间隙占槽宽 | 22% | `gap = w/BARS*0.22f` |
/// | 最大高度 | 92% | `maxH = h*0.92f` |
/// | 最低高度 | 26% | `Math.max(h*0.26f, …)` |
/// | 颜色 | 纯白 | `bar.setColor(0xFFFFFFFF)` |
/// | 透明度 | 0.45 → 1.00 从左到右 | `a = 0.45f + 0.55f*(i/(BARS-1))` |
/// | 控件尺寸 | 圆的 66% × 46% | `ws = MIC_CIRCLE_DP*0.66f`, 高 `*0.46f` |
///
/// 🚨 **不录音时什么都不画**（安卓那边同样）：他明确说过没点录音前不该有波形。
final class WaveView: UIView {

    static let bars = 13

    private var level = [Float](repeating: 0, count: WaveView.bars)
    private var head = 0
    private var active = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false   // 点它要能穿透到麦克风按钮
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 开始/停止。停止时清空 —— 下次录音不会闪一下上次的波形。
    func setActive(_ on: Bool) {
        active = on
        if !on {
            level = [Float](repeating: 0, count: WaveView.bars)
            head = 0
        }
        isHidden = !on
        setNeedsDisplay()
    }

    /// 推一个音量值（0…1）。
    ///
    /// 🚨 iOS 这边跟安卓有一处**结构性不同**：安卓的波形和录音在同一个进程，
    ///    `push()` 直接从录音线程调；iOS 的录音在**主 App**里，
    ///    键盘只能隔着 App Group 拿。所以这里是**整批灌**（`replace`），
    ///    不是一个一个 push —— 见 `replace(_:)`。
    func push(_ rms: Float) {
        level[head] = min(1, max(0, rms))
        head = (head + 1) % WaveView.bars
        setNeedsDisplay()
    }

    /// 一次把宿主那边的整条环形缓冲灌进来（最旧在前，最新在后）。
    func replace(_ vs: [Float]) {
        guard !vs.isEmpty else { return }
        var a = [Float](repeating: 0, count: WaveView.bars)
        let n = min(vs.count, WaveView.bars)
        // 右对齐：最新的落在最右边，跟安卓「越新的越亮、右边是刚说的」一致
        for i in 0..<n { a[WaveView.bars - n + i] = min(1, max(0, vs[vs.count - n + i])) }
        level = a
        head = 0
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard active else { return }          // 安卓 onDraw 里也再挡一道
        let w = bounds.width, h = bounds.height
        guard w > 0, h > 0 else { return }
        guard let cx = UIGraphicsGetCurrentContext() else { return }

        let n = CGFloat(WaveView.bars)
        let gap = w / n * 0.22
        let bw = w / n - gap
        let cy = h / 2
        let maxH = h * 0.92

        for i in 0..<WaveView.bars {
            let v = CGFloat(level[(head + i) % WaveView.bars])
            let bh = max(h * 0.26, v * maxH)
            let x = CGFloat(i) * (bw + gap) + gap / 2
            let a = 0.45 + 0.55 * (CGFloat(i) / (n - 1))
            cx.setFillColor(UIColor.white.withAlphaComponent(a).cgColor)
            let r = CGRect(x: x, y: cy - bh / 2, width: bw, height: bh)
            cx.addPath(UIBezierPath(roundedRect: r, cornerRadius: bw / 2).cgPath)
            cx.fillPath()
        }
    }
}
