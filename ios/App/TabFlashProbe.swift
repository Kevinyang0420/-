import UIKit

/// **Tab 栏逐帧取色探针** —— 用来查「点设置时 Tab 面板闪一下白」。
///
/// 🚨🚨 立它是因为**截图抓不到这个现象**：一张截图 100–300ms，
///    而闪白只有一两帧（约 30ms）。「没抓到」不等于「没有」——
///    拿抓不到当证据下结论，是把观测窗口比事件还短的仪器当成了判据。
///
/// 做法：`CADisplayLink` 每帧（约 16ms）把 tab 栏**真正画出来的像素**
///    渲染一小块出来读中心色，记成一条序列。捕获率 100%，不会漏帧。
///
/// 🚨 读的是 `drawHierarchy` 的**渲染结果**，不是 `backgroundColor` 属性 ——
///    背景由私有的 `_UIBarBackground` 画，属性上读到的可能跟屏幕上不是一回事
///    （"字节对≠显示对"）。
final class TabFlashProbe {
    private var link: CADisplayLink?
    private weak var bar: UITabBar?
    private(set) var samples: [(t: Double, lum: CGFloat)] = []
    private var t0 = CACurrentMediaTime()
    /// 把「这一次切换里最亮的那一帧」写到这里，UITest 读它下判据。
    /// 🚨 只有数在测试进程里读得到，闸门才拦得住 —— 光打 NSLog
    ///    等于"人去看日志"，那不是闸门。
    weak var readout: UILabel?
    private var lastColors = ""

    func start(on bar: UITabBar, seconds: Double = 1.2) {
        self.bar = bar
        samples.removeAll()
        t0 = CACurrentMediaTime()
        link?.invalidate()
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.add(to: .main, forMode: .common)
        link = l
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.stop()
        }
    }

    func stop() {
        link?.invalidate(); link = nil
        guard !samples.isEmpty else { NSLog("TABPROBE 没采到样"); return }
        let lums = samples.map { $0.lum }
        let mn = lums.min() ?? 0, mx = lums.max() ?? 0
        // 🚨🚨 **正向自检：先证明这台仪器活着，再谈读数。**
        //    tab 栏底色是深紫（约 0.10–0.18）。要是所有帧都读到纯黑，
        //    那是**画不出来**，不是"没有闪白" —— 第一版就栽在这儿：
        //    64 帧全 0.000，而 `最亮=0.000` 看上去恰恰像"一切正常"。
        //    坏仪器给出的恰恰是最让人安心的那个读数。
        let median = lums.sorted()[lums.count / 2]
        if median < 0.02 {
            NSLog("TABPROBE_DEAD 中位亮度 %.3f —— 画不出来，这一轮读数作废", median)
            return
        }
        // 🚨 判据是**最亮的那一帧**，不是平均 —— 平均会把一两帧闪白抹平，
        //    那正是这个现象最容易被"测过了"掩盖的方式。
        NSLog("TABPROBE 帧数=%d 最暗=%.3f 最亮=%.3f 序列=%@",
              samples.count, mn, mx,
              lums.map { String(format: "%.2f", $0) }.joined(separator: ","))
        NSLog("TABPROBE_SEQ %@", lums.map { String(format: "%.3f", $0) }
                                     .joined(separator: ","))
        NSLog("TABPROBE_MAX %.3f", mx)
        // 🚨 累计**历次切换的最大值**：他抱怨的是"点设置那一下"，
        //    只留最后一次的话，前面几次切换闪了也看不见。
        let prev = Double(readout?.text ?? "") ?? 0
        readout?.text = String(format: "%.3f", max(prev, Double(mx)))
    }

    /// 逐帧把 tab 栏底衬那几层**真正生效的颜色**读出来（走 `presentation()`）。
    ///
    /// 🚨🚨 这是**第四种仪器**，前三种各有各的盲区，都不能下结论：
    ///    ① 离屏渲染取像素 —— 读到的是假象（第一版全 0.000，后来又读到图标的紫）；
    ///    ② 真截图取像素 —— 100~300ms 一张，抓不到 30ms 的闪；
    ///    ③ 录屏逐帧 —— 实测只有 14.73fps（68ms/帧），时间分辨率不够。
    ///
    /// 这一种不碰像素，直接读图层树：`presentation()` 拿的是**动画进行中
    /// 那一刻真正生效的值**（模型层读不到转场中间态）。
    /// 瞬时变浅的话，这里会看见 backgroundColor 变了。
    ///
    /// 🚨 仍然要说清它的盲区：**毛玻璃材质的实际呈色不在 backgroundColor 上**，
    ///    所以「这里没变」只能说明"不是有人把底色改浅了"，
    ///    不能说明"屏幕上没变浅"。分不开的那部分，如实写着。
    private func layerColors(of bar: UITabBar) -> String {
        var out: [String] = []
        func hex(_ c: CGColor?) -> String {
            guard let c = c, let comp = c.components, comp.count >= 3 else { return "-" }
            let lum = comp[0] * 0.299 + comp[1] * 0.587 + comp[2] * 0.114
            return String(format: "%.2f", lum)
        }
        // 🚨 **不按类名过滤了。** 第一版只收类名含 `BarBackground`/`Visual` 的，
        //    结果一条都没匹配上，只打出个 `bar=-` —— 我又一次在**猜类名**。
        //    正确做法是先把真实的视图树打出来看（"猜不到就打出来"），
        //    所以这里**全收**，让日志自己告诉我里面有什么。
        for v in bar.subviews {
            let n = String(describing: type(of: v))
            let l = v.layer.presentation() ?? v.layer
            out.append(n.prefix(18) + "=" + hex(l.backgroundColor)
                       + "/a" + String(format: "%.2f", l.opacity))
            for sub in v.subviews {
                let sl = sub.layer.presentation() ?? sub.layer
                out.append("  " + String(describing: type(of: sub)).prefix(14)
                           + "=" + hex(sl.backgroundColor)
                           + "/a" + String(format: "%.2f", sl.opacity))
            }
        }
        let bl = bar.layer.presentation() ?? bar.layer
        out.append("bar=" + hex(bl.backgroundColor))

        // 🚨🚨 **portal 那一条要测两样才算数**：
        //    ① 它**盖没盖住** tab 栏（面积占比）；② 它**是不是浅的**（中心取色）。
        //    只知道"切换时有个 portal 在淡出"是**机制信号**，不是结论 ——
        //    不覆盖、或者是深色的，它就跟"闪白"无关。
        for v in bar.subviews where String(describing: type(of: v)).contains("Portal") {
            let f = v.frame
            let cover = (f.width * f.height) / max(1, bar.bounds.width * bar.bounds.height)
            let lum = luminance(of: bar, at: CGPoint(x: f.midX, y: f.midY)) ?? -1
            out.append(String(format: "PORTAL a=%.2f 盖住%.0f%% 中心亮度=%.3f",
                              v.layer.presentation()?.opacity ?? v.layer.opacity,
                              cover * 100, Double(lum)))
        }
        return out.joined(separator: " | ")
    }

    @objc private func tick() {
        guard let bar = bar, bar.bounds.width > 0, bar.bounds.height > 0 else { return }
        // 🚨🚨 **采样点必须落在"底衬"上，不能落在图标／文字上。**
        //    第一版取 `midX, midY` —— 那正是**中间那格的图标**所在，
        //    而那个图标是恒定紫的（亮度约 0.36）。
        //    于是"0.19 跳到 0.36 并保持"读起来像闪白，
        //    实际很可能是**图标布局完成后被画进来**。
        //    我拿这个读数去检验了两个假设、两个都"没变化" ——
        //    真相是**两个假设都动不到我量的那个东西**。
        //    量错对象时，改什么都不动，看上去就像"假设全错"。
        //
        //    现在取三个**空白处**：左右两侧格与格之间、以及贴近底边
        //    （标签下方）。取**中位数**，任何一点被图标盖到也不至于带偏。
        let h = bar.bounds.height, w = bar.bounds.width
        let pts = [CGPoint(x: w * 0.30, y: bar.bounds.maxY - 5),
                   CGPoint(x: w * 0.70, y: bar.bounds.maxY - 5),
                   CGPoint(x: w * 0.03, y: bar.bounds.minY + h * 0.5)]
        var vals: [CGFloat] = []
        for pt in pts {
            if let v = luminance(of: bar, at: pt) { vals.append(v) }
        }
        guard !vals.isEmpty else { return }
        vals.sort()
        samples.append((CACurrentMediaTime() - t0, vals[vals.count / 2]))
        // 🚨 **只在变化时打**：每帧一条会把日志刷爆，
        //    而真正要看的那一两帧就被冲走了（"观测窗口比事件短"的另一种形态）。
        if let bar = self.bar {
            let c = layerColors(of: bar)
            if c != lastColors {
                lastColors = c
                NSLog("TABLAYER %.3fs %@", CACurrentMediaTime() - t0, c)
            }
        }
    }

    /// 把 `bar` 在 `pt` 处**真正画出来的**那个像素读出来。
    ///
    /// 🚨 用 `layer.render(in:)` 而不是 `drawHierarchy(afterScreenUpdates:false)`：
    ///    后者实测 64 帧全读到 0.000（纯黑）—— 那不是"没有闪白"，
    ///    是它压根什么都没画出来。**坏仪器给出的恰恰是最让人安心的读数。**
    private func luminance(of bar: UITabBar, at pt: CGPoint) -> CGFloat? {
        // 🚨🚨 **渲染整个 window，不是只渲染 tab 栏。**
        //    毛玻璃（`UIVisualEffectView`）要**背后的画面**才能合成出真实颜色；
        //    只把 bar 自己画出来，它背后什么都没有 —— 读到的必然是假象。
        //    今晚在这上面栽了两次：先是全读 0.000，后来读到中间那格图标的紫 0.36，
        //    还拿这个假读数去"证伪"了两个假设。
        //    坐标要换算到 window 里，因为现在画的是 window。
        guard let win = bar.window else { return nil }
        let wp = bar.convert(pt, to: win)
        let r = CGRect(x: wp.x - 1, y: wp.y - 1, width: 3, height: 3)
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.opaque = true
        fmt.scale = 1
        let img = UIGraphicsImageRenderer(size: r.size, format: fmt).image { ctx in
            ctx.cgContext.translateBy(x: -r.minX, y: -r.minY)
            win.layer.render(in: ctx.cgContext)
        }
        guard let cg = img.cgImage, let dp = cg.dataProvider,
              let data = dp.data, let p = CFDataGetBytePtr(data) else { return nil }
        let bpp = cg.bitsPerPixel / 8
        let idx = (cg.height / 2) * cg.bytesPerRow + (cg.width / 2) * bpp
        guard CFDataGetLength(data) > idx + 2 else { return nil }
        return (CGFloat(p[idx]) * 0.299 + CGFloat(p[idx + 1]) * 0.587
                + CGFloat(p[idx + 2]) * 0.114) / 255.0
    }
}
