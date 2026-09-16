import UIKit

/// **被 push 进来的子页共用基类** —— 09-16 Kevin 亲口点名：从首页点账户小人进去
/// 「没有返回按钮，直接就进到账户页面了。至少要跟我从『设置』里面点进去一样，
/// 头顶上要有标题，还要有一个返回按钮」。
///
/// 🚨 根因：`SetupViewController`（`AppDelegate.swift:3179`）里早就写了恢复
/// 导航栏那两行，但它是 `final class`——**规矩焊死在一个具体页面上，
/// 没有任何页面能真的继承它**。首页 `MainViewController` 隐藏了导航栏，
/// 14 个从首页直接 push 出去的子页各自 `: UIViewController`，谁都没恢复，
/// 进去就没有标题、没有返回按钮、出不去。
/// 📖 `feedback_rule_lands_at_every_exit`：写在一个出口，等于只在那个出口生效。
///
/// 🚨 **改法是把恢复逻辑收成一个可继承的基类，不是逐页手动补一份一样的代码**——
/// 14 个页面全部改成继承这个类，"恢复导航栏"这条规矩只实现这一处。
/// 子类如果自己也要重写 `viewWillAppear`/`viewWillDisappear`，
/// **必须调用 `super`**（已核过现有三个重写了的页面——Account/DeleteAccount/Notes——
/// 全部本来就调了 `super`，不用额外改）。
///
/// 🚨 反向控制：`MainViewController`（首页）不继承这个类，它要保持隐藏，
/// 闸门 `verify_nav_bar_restored.py` 专门查这一条，别为了修子页把首页弄丑。
class PushedViewController: UIViewController {
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if navigationController?.viewControllers.count == 1 {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }
}
