import XCTest

/// **德/西/阿的历史日期会不会月日对调。**
///
/// 2.1 09-07 提醒：四门旧值是**非定位式** `%d.%d.` —— 没有换位能力，
/// 而德/西/阿的习惯是**日在前**，于是月日对调**且不报错**。
/// 他已把值改成 `de %2$d.%1$d.` / `es %2$d/%1$d` / `ar %2$d/%1$d`。
///
/// 🚨 他明确要我**自己核，别照抄安卓**（iOS 的格式串语法跟安卓不同）。
///    读代码读到的是「先月后日传参 + 定位式反序」，方向应该对 ——
///    **但那是推的**。真正的问题是：`String(format:)` 到底认不认 `%1$d`？
///    这一条就是那次实跑。
///
/// 🚨 **为什么不拿历史页截图来验**：我拍了德语历史页，
///    上面全是「Gestern 20:55」—— 种子里的记录都是最近两天的，
///    `hist_monthday` **一次都没被走到**。
///    那张图看起来很正常，其实**整类对象从没进过检查范围**。
final class MonthDayOrderTests: XCTestCase {

    /// 用一个**月日不对称**的日子：9 月 7 日。
    /// 🚨 别用 7 月 7 日那种 —— 对调了也看不出来，坏样本会静默通过。
    private let month = 9
    private let day = 7

    func testPositionalSpecifiersActuallyWork() {
        // 先把地基验了：Swift 的 `String(format:)` 认不认定位式。
        // 不认的话下面所有语言的判据都建立在沙子上。
        XCTAssertEqual(String(format: "%2$d.%1$d.", month, day), "7.9.",
                       "🚨 String(format:) 不认 %1$d 定位式 —— "
                       + "那么所有靠换位的语言都会月日对调")
    }

    // 🚨 **各语言的值不在这儿查**：`Lang`/`L` 没编进 UITests 目标
    //    （`cannot find 'Lang' in scope`）。为一条检查去改 project.yml
    //    把整套字符串拉进测试包，代价比收益大。
    //    → 值那半交给闸门 `D:/_build/gate_monthday_order.py` 静态查，
    //      它直接读生成物 `Shared/Strings.swift`，
    //      **谁把 `%2$d.%1$d.` 改回 `%d.%d.` 就当场红**。
    //    这一屏只管地基：定位式在真机上到底认不认。
}
