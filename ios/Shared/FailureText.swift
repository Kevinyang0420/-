import Foundation

/// 后端失败 → **给用户看的一句话**。纯函数，带坏实现自测。
///
/// 🚨🚨 **绝不把 `err` 原文贴给用户。** `err` 是给我们看的。
///    （2.1《文案》硬规矩①，跟录音屏判据 V5 是同一条。）
///
/// 🚨 **每一句都要能回答「他现在该干什么」** —— 读完他不知道下一步，就是没写好。
///
/// 🚨🚨 **我们自己的 bug 不许说成"你的问题"，更不许推给他的网络。**
///    `请求组装失败` / `地址不对` 那几种是**代码写错了**。
enum FailureText {

    /// 🚨 **这张 `.message` 细分表是【过渡方案】，不是终态。**
    ///
    /// 2.1 自己指出的：**它本质上是"按内容猜原因"，而"关键词表永远补不完"**
    /// —— 那条我们今天已经在别处栽过（判据不该挂在关键词表上）。
    ///
    /// **终态**：后端把「网络错误 / 我们的 bug / 空结果」分成不同的 `Failure` case，
    /// **客户端不猜**。归 1.1/1.2，2.1 会经总协调提。
    /// **在那之前按内容匹配，但要知道它会漏** —— 漏了就落到 `err_other` 兜底。
    /// 🚨 **客户端自己构造的那几条错误文字，只在这里写一次。**
    ///
    ///    构造处（`Backend.swift`）和匹配处（下面那两张表）**引用同一个** ——
    ///    否则各写一遍字符串就是**两个配置点**：改一处漏一处，
    ///    表会静默失配，而**失配的后果正是把「我们自己的 bug」
    ///    说成「你的网络问题」**（2.1 硬规矩③）。
    enum Local {
        static let assembleFailed = "请求组装失败"
        static let badJobURL = "job 地址不对"
        static let badURL = "地址不对"
        static let emptyResult = "返回了空结果"
        // 🚨 H3：这两条原来是裸字面量、匹配表里也没有 →
        //    被 `!raw.isEmpty` 兜底判成「网络连不上」，而正确答案完全不同。
        static let emptyAsr = "没听清，再说一次"
        static let noAudio = "没返回音频"
    }

    /// 我们自己写错了的那几种。**顺序有讲究：先认它，再认网络。**
    static let ourBugMarks = [Local.assembleFailed, Local.badURL,
                              Local.badJobURL]
    // 🚨 `noAudio` 单独一档，**不并进"我们的 bug"** —— 2.1 给了专门文案，
    //    因为它的重点是**「文字还在」**：朗读是次要动作，译文已经在屏上了。
    //    并进通用句会让他以为整件事失败了、结果也没了。
    static let ttsMarks = [Local.noAudio]
    static let emptyMarks = [Local.emptyResult, Local.emptyAsr]

    /// 给用户看的那一句。
    ///
    /// - Parameter raw: `Backend.Failure` 的 `description`（**只在这里读，不外传**）
    /// - Parameter kind: 枚举本身的种类，见 `Kind`
    static func userText(kind: Kind, raw: String) -> String {
        switch kind {
        case .timeout: return L.err_timeout
        case .network: return L.err_network
        case .unauthorized: return L.err_unauthorized
        case .quota: return L.err_quota
        case .http: return L.err_http
        case .message:
            // 🚨 顺序有讲究：**先认我们自己的 bug**。
            //    否则 "请求组装失败" 里若含网络字样会被误报成"你的网络问题"。
            if ourBugMarks.contains(where: { raw.contains($0) }) { return L.err_ourbug }
            if emptyMarks.contains(where: { raw.contains($0) }) { return L.err_empty }
            if ttsMarks.contains(where: { raw.contains($0) }) { return L.err_tts_failed }
            // 🚨🚨 H4：**兜底不许倒向"你的网络问题"。**
            //    后端 `err_kind()` 注释写着「默认落在 internal 那一侧，
            //    **宁可承认是自己的问题**」——
            //    而这里原来是 `!raw.isEmpty → err_network`，**方向正好相反**。
            //    两端对同一个"不知道"给了相反的默认值，而错的那个方向
            //    正好违反硬规矩③（我们的锅不许推给他的网）。
            //    🚨 真网络错**不靠猜** —— 只由 `.network` 那一档产生（见 Backend）。
            return L.err_other
        }
    }

    /// 后端明确给的分类 → 人话。**有它就不猜。**
    ///
    /// 🚨 取值见 `english_coach/server_api.py:283-288`。
    ///    **后端注释本身就写死了两条口径，这里照抄，不自己编**：
    ///    `internal` ＝ 我们自己的 bug，**绝不许说成"你的网络问题"**；
    ///    `bad_request` ＝ **客户端的 bug，不是网络**。
    ///
    /// 🚨 **范围**：后端 11 处 `job_set` 带 `kind`，**还有 9 处不带** ——
    ///    那 9 处仍然落到下面那张关键词表兜底。**表不能删，只是降级。**
    static func byKind(_ kind: String) -> String {
        switch kind {
        case "asr_empty":   return L.err_empty        // 没听清，别做成红色错误
        // 🚨 `no_speech`（2026-09-04 新增）＝**根本没人说话**，跟 `asr_empty`
        //    （听到了但没听清）方向相反：那条 `retry:false`（重转同段没用），
        //    这条 `retry:true` 且**要他重新说**（换输入，不是重转）。
        //    合并两者会抹掉这个区别 —— 见 1.1 规格 §三。
        case "no_speech":   return L.err_no_speech
        case "blocked":     return L.err_kind_blocked
        case "auth":        return L.err_kind_auth
        case "upstream":    return L.err_kind_upstream
        // 🚨 这两个是后端 2026-08-29 上午新加的，客户端一度不认识 → 落兜底
        //    「出了点问题」。**后端加了 kind 客户端必须跟**，
        //    `gate_kind_migration` 就是查这条的（它把我抓出来了）。
        // 额度用完 —— 后端注释写明**不是错误，是正常业务状态，别做成红色**
        case "quota":       return L.err_quota
        // job 过期 —— 给他下一步：再说一次
        case "expired":     return L.err_expired
        // 🚨 这两档都是**我们自己写错了**，措辞不许暗示是他的问题、更不许提网络
        case "bad_request": return L.err_ourbug
        case "internal":    return L.err_ourbug
        default:            return L.err_other        // 认不出的新 kind → 兜底，不猜
        }
    }

    /// 跟 `Backend.Failure` 一一对应。**这里不 import Backend，保持可单测。**
    /// 🚨 `network` 这一档以前【不存在】，所以 `err_network` 全项目零生产者，
    ///    他拔了网线，App 说的是「出了点问题」。判定见 `NetClassify`。
    enum Kind: String { case http, unauthorized, quota, message, timeout, network }

    // MARK: - 自测

    static func selfTest() -> [String] {
        var f: [String] = []
        // ① 五个枚举各自不同（坏实现：全落到同一句兜底）
        let all = [userText(kind: .timeout, raw: ""),
                   userText(kind: .unauthorized, raw: ""),
                   userText(kind: .quota, raw: ""),
                   userText(kind: .http, raw: "HTTP 500")]
        if Set(all).count != all.count { f.append("几个枚举给出了相同的文案") }
        // 🚨 M-B：`network` 这一档必须真的落到「网络连不上」那句。
        //    它以前**零生产者**，他拔了网线看到的是「出了点问题」。
        //    产出方在 `Backend.Failure.network`（由 `NetClassify` 判定）。
        if userText(kind: .network, raw: "") != L.err_network {
            f.append("network 档没落到 err_network —— 断网又会被说成「出了点问题」")
        }
        if userText(kind: .network, raw: "") == userText(kind: .message, raw: "x") {
            f.append("network 跟兜底句一样 —— 等于没分出来")
        }
        // ② 我们自己的 bug **不许**被说成网络问题
        if userText(kind: .message, raw: "请求组装失败") != L.err_ourbug {
            f.append("我们自己的 bug 没有被认出来（会被说成用户的问题）")
        }
        // ③ 空结果 → 没听清
        if userText(kind: .message, raw: "返回了空结果") != L.err_empty {
            f.append("空结果没有映射成「没听清」")
        }
        // ④ 🚨 任何一档都不许把原文漏出去
        let secret = "NSURLErrorDomain Code=-1009 内部堆栈"
        for k in [Kind.timeout, .unauthorized, .quota, .http, .message] {
            if userText(kind: k, raw: secret).contains("NSURLError") {
                f.append("\(k.rawValue) 把后端原文贴给了用户")
            }
        }
        // 🚨 ⑤ H3：这两条客户端自造的错误**不许被判成"你的网络问题"**
        if userText(kind: .message, raw: Local.emptyAsr) != L.err_empty {
            f.append("「没听清」被判成了别的（H3：它曾经落 err_network）")
        }
        if userText(kind: .message, raw: Local.noAudio) != L.err_tts_failed {
            f.append("「没返回音频」没走朗读那档专门文案（重点是【文字还在】）")
        }
        // 🚨 ⑥ H4：**兜底方向**必须跟后端一致（宁可承认是自己的问题），
        //    绝不许一个不认识的错误自动变成"你的网络问题"
        // 🚨 后端在用的每个 kind 都必须给出**不是兜底**的那一句。
        //    漏一个的表现是「出了点问题」，而正确答案完全不同。
        for k in ["asr_empty", "blocked", "auth", "upstream",
                  "bad_request", "internal", "quota", "expired"]
        where byKind(k) == L.err_other {
            f.append("kind=\(k) 落到了兜底句 —— 后端加了 kind 客户端没跟上")
        }
        if userText(kind: .message, raw: "某个我们没登记过的错误") == L.err_network {
            f.append("兜底倒向了「你的网络问题」—— 方向跟后端相反（H4）")
        }
        // ⑦ 全空也要有话说（不许返回空串）
        if userText(kind: .message, raw: "").isEmpty {
            f.append("原因为空时返回了空串 —— 空白界面跟坏掉的界面没区别")
        }
        return f
    }
}
