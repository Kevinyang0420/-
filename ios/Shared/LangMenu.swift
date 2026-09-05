import UIKit

/// **目标语言选择器的共用件** —— 最近用过置顶 + 全量滚动（Kevin 2026-09-05 定的方案乙）。
///
/// 🚨 他的原话：「你选择器不要一下子展示那么多嘛，加个下拉，就可以支持我滑动去选了嘛，
///    所以 32 项又怎么样嘛」。语言表要从 9 门扩到 23+ 门。
///
/// 🚨 为什么做成共用件：目标语言的选择器**有三处**（随手 / 面对面 / 键盘），
///    清单本身已经收在 `Backend.langs` 一处了，但**"怎么排、怎么显示"各写各的** ——
///    9 门时看不出来，23 门时三处会各坏各的。
enum LangRecents {
    private static let key = "vime.lang.recent"
    static let maxKeep = 3

    /// 最近用过的语言码（最新的在前）。
    static var codes: [String] {
        (KbBridge.prefs.array(forKey: key) as? [String]) ?? []
    }

    /// 记一次使用。🚨 **唯一写入口**：三个选择器都调它，
    ///    各写一份的话"最近用过"在三个界面会给出三种顺序。
    static func use(_ code: String) {
        guard !code.isEmpty else { return }
        var v = codes.filter { $0 != code }
        v.insert(code, at: 0)
        if v.count > maxKeep { v = Array(v.prefix(maxKeep)) }
        KbBridge.prefs.set(v, forKey: key)
    }

    /// 排好序的两段：(最近用过, 全部语言)。
    ///
    /// 🚨 「最近用过」**按真实使用记录变**，不是写死三门 —— 这是 2.1 的判据②。
    /// 🚨 一条记录都没有时返回空的第一段，界面**不画那个小标题**，
    ///    不要显示一个空分区。
    /// 分成「最近用过」和「全部语言（含最近用过）」。
    ///
    /// 🚨🚨 **第二个返回值故意包含 recent，这是方案丙定的**
    ///    （Kevin 2026-09-05 13:0x 拍板：「语言列表选丙」）：
    ///    **「全部语言」保持完整不删** —— 所有语言都在，不因使用历史变化。
    ///
    /// 🚨 那为什么他早上会看到「中文」两次？**问题从来不在数据，在渲染**：
    ///    键盘那屏把两段 **拼平** 成一个列表（`recent + all`），
    ///    两段长得一模一样，重复就被读成 bug。
    ///    丙的解法是**把「最近用过」做成横滑 chips**（描边不填充、更扁），
    ///    跟下面的列表行**明显不同类** —— 就像浏览器的"常用站点"和"书签列表"，
    ///    同一个站出现两次没人觉得是错。
    ///
    /// 🚨🚨 **名字改了，因为旧名字骗过人**：原来叫 `rest`（其余）而实际返回全量，
    ///    2026-09-05 有两个人（我和 0）先后照着名字推理、各错一次。
    ///    我一度还"修"成真的去重 —— **那是改对了名字理解、改错了产品意图**。
    ///    现在名字如实：`allIncludingRecent`。
    ///    **只改现象不改名字，下一个人还会踩同一脚。**
    static func sections(all: [String])
        -> (recent: [String], allIncludingRecent: [String]) {
        let r = codes.filter { all.contains($0) }
        return (r, all)
    }

}

enum LangMenu {
    /// 造一份可以直接挂到按钮上的下拉菜单。
    ///
    /// 🚨 用 `UIMenu` 而不是 `UIAlertController`：alert / actionSheet **不是为长列表设计的**，
    ///    9 门就已经很挤，23 门直接不可用（超出屏幕的部分点不到）。
    ///    `UIMenu` 原生可滚，且跟「语气」「方式」那两个下拉是同一个控件 ——
    ///    同一屏上三个参数用三种控件，正是他说过的"一看就是草台班子"。
    ///
    /// 🚨 两段都用 `.displayInline`：内联分段会画分隔线并保留小标题，
    ///    嵌套子菜单则要多点一层 —— 他明确要的是"滑动去选"，不是"再点进去"。
    static func build(current: String,
                      pick: @escaping (String) -> Void) -> UIMenu {
        let all = Backend.langsForUI.map { $0.code }
        let s = LangRecents.sections(all: all)

        // 🚨🚨 **勾只画一次**（Kevin 2026-09-05 报「这里为什么有两个中文」）。
        //
        //    原来是 `state: code == current ? .on : .off` —— **只看"等不等于当前选中"**。
        //    而 `action()` 被两段各调一次，同一个 code 在两段各生成一个 `UIAction`，
        //    **两个都判 `.on`** → 同一门语言两处都打勾。
        //    🚨 这跟"列表重不重复"无关：**只要那门语言同时出现在两段，就必然两个勾。**
        //
        //    修法：让「最近用过」那一段吃掉这个勾，「全部语言」里同一个 code 不再画。
        //    甲（删重复）和乙（保留重复、只在最近用过打勾）**两种改法都要求这一条**，
        //    所以它不用等拍板。
        var checkedOnce = false
        func action(_ code: String) -> UIAction {
            let isCur = (code == current)
            let mark = isCur && !checkedOnce
            if mark { checkedOnce = true }
            return UIAction(title: Backend.langLabel(code),
                     state: mark ? .on : .off) { _ in
                LangRecents.use(code)
                pick(code)
            }
        }

        var children: [UIMenuElement] = []
        if !s.recent.isEmpty {
            children.append(UIMenu(title: L.lang_recent,
                                   options: .displayInline,
                                   children: s.recent.map(action)))
        }
        // 🚨 方案丙：「全部语言」**完整不删**（含最近用过那几门）。
        //    这一屏是**系统菜单**，chips 做不出来 —— 但 `.displayInline`
        //    本来就会画分隔线 + 小标题，两段已经不同类，丙的目的达到了。
        //    🚨 **不要为了"跟另两屏一样"硬把系统菜单改成自绘** ——
        //    丙要的是"两段看上去不是同一种东西"，不是"三屏长得一模一样"。
        children.append(UIMenu(title: L.lang_all,
                               options: .displayInline,
                               children: s.allIncludingRecent.map(action)))
        return UIMenu(title: L.lbl_translate_to, children: children)
    }
}
