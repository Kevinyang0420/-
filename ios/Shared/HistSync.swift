import Foundation

/// **「这台设备同步说话记录到云端」的开关** —— 只管状态，不管界面。
///
/// 规格 `_规格_历史同步开关UI_20260906.md`（Kevin 09-06 亲口）：
/// > 「历史记录里用户说的话上云**可能会敏感一些**…
/// >  **每个设备都需要有这样一个入口，点击确认后才能把该设备的数据上传到云端**」
///
/// 🚨🚨 **状态是本机的，不跟账号同步。**
///    否则在 A 机点一次，B 机的历史就被"替他同意"上传了 ——
///    **那正好是他要防的那件事**。所以存 `.standard`，
///    **不存 App Group、不上传、不跟着登录走**。
///
/// 🚨 **默认关**。不开就跟现在完全一样（历史只留在本机）。
/// 🚨 **只管说话记录**：单词本和常用词不受它管（他说那两样"问题不大"）。
///    把三样绑在一个开关上会让他为了同步单词本而被迫同意上传说话记录。
enum HistSync {

    /// 🚨 键名带 `.local` 是提醒：**这一条永远不许进 App Group / 不许上传**。
    private static let key = "histsync.on.local"

    static var isOn: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    /// 打开/关掉。**调用方必须先弹确认** —— 这一层不弹，
    /// 因为"确认过没有"是界面的责任，混在这儿会出现"有的入口弹有的不弹"。
    static func set(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: key)
        KbBridge.note("说话记录同步：" + (on ? "打开（本机）" : "关掉（本机）"))
    }

    private static let sinceKey = "histsync.since.local"

    /// **从哪个时刻之后的记录才传。**
    ///
    /// 🚨 关着的时候返回一个**永远到不了的时刻** —— 这样上传那条链
    ///    即使被误调用也传不出去任何东西，而不是靠调用方记得先判 `isOn`。
    ///    （安卓侧 2.3 用的是同一个做法：开关关着返回 `MAX_VALUE`。）
    ///    **让"关着"这件事在数据上也成立**，不只在界面上成立。
    static var since: TimeInterval {
        guard isOn else { return .greatestFiniteMagnitude }
        return UserDefaults.standard.double(forKey: sinceKey)
    }

    /// 打开时选「只同步以后的」→ 传 `Date()`；选「连同已有的一起」→ 传 0。
    static func setSince(_ t: TimeInterval) {
        UserDefaults.standard.set(t, forKey: sinceKey)
        KbBridge.note("说话记录同步分界点：" + (t <= 0 ? "含存量" : String(Int(t))))
    }

    private static let doneKey = "histsync.oneoff.done.local"

    /// **这台设备已经走完过一次开启流程**（one-off 用完就收起来）。
    ///
    /// Kevin 09-07 下午亲口：
    /// > 「它这个应该只是一个 **one-off** 的功能。不点就一直留着；
    /// >   **一旦点完就自动隐藏**。正在同步 → 已同步 → 打个勾 → 隐藏。」
    ///
    /// 🚨 **这一条决定说话记录那屏还画不画那一行** ——
    ///    所以它必须**落盘**，不能只存在内存里：重启后又冒出来，
    ///    在他眼里就是"隐藏没生效"。
    static var oneOffDone: Bool {
        get { UserDefaults.standard.bool(forKey: doneKey) }
        set { UserDefaults.standard.set(newValue, forKey: doneKey) }
    }

    /// 🚨🚨 **关掉同步时要把 one-off 也复位** —— 否则他在设置里关了之后，
    ///    说话记录那屏**再也不会**出现开启入口，等于把功能永久藏死了。
    ///    （这条是我加的：他只说了"点完隐藏"，没说"关掉之后还能不能再开"。
    ///      但"关了就再也开不回来"显然不是他要的。）
    static func turnOff() {
        set(false)
        oneOffDone = false
    }

    /// 这台设备上**已经攒下**多少条历史。
    ///
    /// 🚨 打开时要拿它做二次确认：说清「这台设备上已有的 N 条也会一起传上去」。
    ///    只说"以后会传"而把存量偷偷带上去，是最糟的一种。
    static func backlogCount() -> Int {
        return History.list().count
    }
}
