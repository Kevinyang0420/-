import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// **灵动岛（Live Activity）的数据契约** —— 主 App 和灵动岛扩展共用这一份。
///
/// 🚨🚨 为什么做这个（2026-08-29 从 Typeless 身上抓到的）：
///    在 Kevin 手机上列进程，看到 Typeless 同时跑着
///      `Typeless`（主App）/ `keyboard`（键盘扩展）/ `dynamicisland`（灵动岛扩展）
///    —— **它的主 App 常驻后台，所以按键盘时根本不用跳过去，也就不存在"回不来"**。
///    我一整天在找"跳过去怎么回来"，而那个问题在它那儿**根本不存在**。
///
/// 🚨 灵动岛在这里有两个作用，别只记住一个：
///    ① 让主 App 有一个**用户可见的持续存在**，系统更愿意让它活着；
///    ② 录音状态直接显示在灵动岛上（比键盘上那个红圈更明显，他一眼看得见）。
@available(iOS 16.1, *)
struct RecActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// 正在录音还是在出稿
        public var phase: String
        /// 已经录了几秒（给灵动岛显示）
        public var seconds: Int
        public init(phase: String, seconds: Int) {
            self.phase = phase
            self.seconds = seconds
        }
    }
    public init() {}
}
