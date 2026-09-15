import Foundation

/// **这份包是不是测试版**——单一来源，别在别处各判一次。
///
/// 来源：Kevin 2026-09-14 晚原话「那个录音诊断 也不要放在正式版里 测试版可以留着」，
/// 规格 `_spec_reclog_release_hidden.md`。
///
/// 🚨🚨 **不能用 `#if DEBUG`**——TestFlight 包是 **Release 配置**编的，`DEBUG` 是假，
///    用它会把测试版（TestFlight）的入口一起干掉，那正是最需要它的地方
///    （规格原话：「`#if DEBUG` 不行——TestFlight 包是 Release 配置编的」）。
/// 🚨🚨 09-15：判据从 `!= "receipt"` 改成**显式枚举** `== "sandboxReceipt" || == nil`。
///    起因：0 让我确认"正式 App Store 收据文件名确实是 receipt"这条地基，
///    我查了但只找到社区多年一致的结论，没找到苹果逐字写明的一手来源——
///    `!= "receipt"` 这个写法要是这条地基不成立，**后果是正式版也被误判成
///    测试版，App Store 用户看得到诊断入口**，正是 Kevin 明确禁止的那件事。
///    显式枚举的失败方向反过来：**只在"生产版文件名不是 receipt"这个假设
///    不成立时，才会把某种没见过的收据类型误判成正式版**——不确定时
///    往"藏起来"倒，不往"露出来"倒，这跟 Kevin 的硬要求方向一致。
///    只认两种已知的**测试**信号（TestFlight 收据 `sandboxReceipt` /
///    真机开发直装没有收据文件 `nil`），其余一律当正式版。
enum BuildKind {
    static var isTestBuild: Bool {
        classify(receiptFilename: Bundle.main.appStoreReceiptURL?.lastPathComponent)
    }

    /// 纯函数版本，供 UI 测试打三种坏/好样本（真机没法伪造一份真正的
    /// App Store 收据文件去测，所以只能测"给定文件名，判断对不对"这一层）。
    static func classify(receiptFilename: String?) -> Bool {
        receiptFilename == "sandboxReceipt" || receiptFilename == nil
    }
}
