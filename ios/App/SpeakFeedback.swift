import UIKit

/// **点文字朗读 + loading 期间变色** —— 面对面和随便说点啥**共用这一份**。
///
/// Kevin 2026-09-06：「我看安卓点大字的时候，大字会变颜色（变成紫色），
/// 代表它正在 loading、准备读，但苹果这边还不会」
/// Kevin 2026-09-07：「朗读按钮也不需要了，改成我点一下这个字就自动朗读。
/// **跟那个面对面一样**，它在 loading 的过程中颜色会发生变化」
///
/// 🚨 放在 App/ 不在 Shared/：它要用 ，而那个在 App 层。
/// 🚨 **他说了"跟面对面一样"，所以必须是同一份实现**，不是照着写第二遍。
///    这摊活在"同一规矩两处实现"上栽过很多次；而这一条尤其容易漂 ——
///    紫色、防连点、失败复位，任意一处忘了同步都不会报错。
enum SpeakFeedback {

    /// 正在取音频的那几个对象 —— 防连点用。
    /// 🚨 用对象身份做键，这样两屏各自独立，互不影响。
    private static var busy = Set<ObjectIdentifier>()

    /// 朗读 `text`，期间把 `label` 染成紫色，回来复位。
    ///
    /// 🚨 **两条路都要复位**：只在成功那支复位的话，一次失败就把文字
    ///    永久留在紫色、而且防连点标记卡住 —— 之后再点全被挡掉，
    ///    表现是「朗读彻底坏了」。（面对面那边为这个专门写过注释。）
    /// 🚨 **待机占着音频会话时先让开**，否则 TTS 起不来，
    ///    表现就是"点了没声音"。
    static func speak(_ text: String, on label: UILabel,
                      normal: UIColor, fail: ((String) -> Void)? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let key = ObjectIdentifier(label)
        // 🚨 防连点：**加了反馈之后连点才成为可能** ——
        //    没反馈时他不会连点；两下就是两次请求、两段声音叠着放。
        guard !busy.contains(key) else {
            KbBridge.note("朗读：正在取，这一下忽略")
            return
        }
        busy.insert(key)
        label.textColor = Theme.accent          // 紫 = 正在取
        KbVoiceHost.shared.yieldMic()
        Backend.speak(text: t) { r in
            DispatchQueue.main.async {
                busy.remove(key)
                label.textColor = normal
                switch r {
                case .success(let mp3):
                    KbBridge.note("朗读：拿到音频 \(mp3.count) 字节，开播")
                    Speaker.play(mp3) { _ in }
                case .failure(let f):
                    // 🚨 失败要**说出来**，不能静默 —— 他分不出"没反应"和"失败了"。
                    KbBridge.note("朗读失败：\(f)")
                    fail?(f.userText)
                }
            }
        }
    }
}
