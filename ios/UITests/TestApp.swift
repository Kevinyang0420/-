import XCTest

/// **UI 测试统一的启动入口 —— 默认把音频关掉。**
///
/// 🚨🚨 起因（2026-09-05 又栽一次）：模拟器上 `AVAudioEngine` 会撞
///    `AudioToolbox _ReportRPCTimeout` 直接 `abort`，报出来长得像
///    **「App 没起来」/「Application is not running」** ——
///    我因此差点去查那一轮真正改的六处代码，而它们一个字都没错。
///
/// 🚨 **为什么做成默认而不是逐个补**：扫全部用例发现 **7 个都漏了**。
///    逐个补只能修好今天这七个，**下次新写的照样漏** ——
///    规矩要挂在唯一入口上，不是挂在每个调用点上（这条今天已经犯过三次）。
///
/// 真要测音频的用例，显式传 `audio: true`。
enum TestApp {
    static func launch(_ page: String? = nil,
                       audio: Bool = false,
                       env: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.kevin.transless")
        if let p = page { app.launchEnvironment["TRANSLESS_PAGE"] = p }
        if !audio { app.launchEnvironment["TRANSLESS_NO_ARM"] = "1" }
        for (k, v) in env { app.launchEnvironment[k] = v }
        app.launch()
        return app
    }
}
