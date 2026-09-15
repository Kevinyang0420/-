import XCTest

/// `BuildKind.classify` 的判据测试——**不开模拟器就能跑**（纯逻辑）。
///
/// 🚨 Kevin 2026-09-14 晚原话「那个录音诊断 也不要放在正式版里 测试版可以留着」，
///    规格 `_spec_reclog_release_hidden.md`。
///
/// 🚨🚨 **为什么这里没有"打真实 IPA 扫二进制"的判据**（三端里独 iOS 缺这一层，
///    是平台差异，不是漏做）：PC/安卓能靠 `--release`/`BuildConfig.DEBUG`
///    在**编译期**产出内容不同的两份二进制，所以能扫包验证字符串在不在。
///    iOS 的 TestFlight 包和最终提审通过的 App Store 包是**同一份二进制**
///    ——苹果的发布流程是"选一个已上传的构建提交审核"，不是重新编译一次。
///    所以 iOS 唯一能做的是**运行时**按收据类型分流（`BuildKind`），
///    字符串本身一直在二进制里，只是不显示。这不满足"包里搜不到"这条字面判据，
///    但满足它背后的真实要求："正式版用户看不到这个入口"。
final class BuildKindTests: XCTestCase {

    func testAppStoreReceiptIsNotTestBuild() {
        XCTAssertFalse(BuildKind.classify(receiptFilename: "receipt"),
                       "真正的 App Store 收据文件名，必须判成不是测试版")
    }

    func testSandboxReceiptIsTestBuild() {
        XCTAssertTrue(BuildKind.classify(receiptFilename: "sandboxReceipt"),
                      "TestFlight/沙盒收据，必须判成是测试版")
    }

    /// 🚨 真机 `xcodebuild install`（dev 签名，这一整晚给 Kevin 装的都是这种）
    ///    根本没有收据文件，这条必须也判成测试版——不然这一晚装的每一个包
    ///    诊断入口全被藏掉了，而那正是这一晚一直在用的排障工具。
    func testNoReceiptAtAllIsTestBuild() {
        XCTAssertTrue(BuildKind.classify(receiptFilename: nil),
                      "没有收据文件（真机开发直装）必须判成测试版")
    }

    /// 🚨🚨 09-15 补的坏样本：一个从没见过的收据文件名（不是 "receipt" 也不是
    ///    "sandboxReceipt"）。这条是在证明**判据真的从 `!= "receipt"` 改成了
    ///    显式枚举**——旧写法下这条会判成"是测试版"（因为它不等于 "receipt"），
    ///    新写法下必须判成"不是测试版"（因为它既不是 sandboxReceipt 也不是 nil）。
    ///    "不确定时往藏起来那边倒"——这条正是在验证那个方向。
    func testUnknownReceiptFilenameIsNotTestBuild() {
        XCTAssertFalse(BuildKind.classify(receiptFilename: "weirdReceipt"),
                       "没见过的收据文件名，判据应该保守地当成正式版（藏起来），"
                       + "不是当成测试版（露出来）——这条在旧的 != \"receipt\" 写法下会红")
    }
}
