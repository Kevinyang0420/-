import Foundation

/// 界面文案（中/英）—— **构建时从 `D:\_build\i18n_map.py` 生成，别手改**。
///
/// 🚨 安卓那边同一份表生成 `res/values{,-en}/strings.xml`。
///    两端共用一个配置点，改文案只改 i18n_map.py 再跑一次生成脚本。
///    以前 iOS 的文案是手写的，跟安卓靠注释「一一对应」维持 ——
///    结果「结构化转写/逐字转录」这种被他否掉的措辞在 iOS 留了一整天。
///
/// 🚨 语言由 `Bundle.main.preferredLocalizations` 决定 ——
///    那是**系统给的解析结果**（用户偏好 ∩ App 声明支持的语言），
///    不是我自己解析 Locale。自己解析会跟系统的选择打架。
///    配套：project.yml 里必须声明 CFBundleLocalizations，
///    否则系统不知道这个 App 支持英文，永远返回开发语言。
enum L {
    /// 当前界面是不是英文。
    static let isEn: Bool = {
        let code = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
        return !code.hasPrefix("zh")
    }()

    private static func s(_ zh: String, _ en: String) -> String {
        isEn ? en : zh
    }

    static var ui_lang: String { s("zh", "en") }
    static var home_login: String { s("注册 / 登录", "Sign in") }
    static var home_set_ime: String { s("设为当前输入法", "Set as keyboard") }
    static var login_next_ver: String { s("登录功能下一版做", "Sign-in arrives in the next version") }
    static var step_mic: String { s("允许录音", "Allow microphone") }
    static var step_enable: String { s("启用输入法", "Enable keyboard") }
    static var step_default: String { s("设为默认", "Make it default") }
    static var act_allow: String { s("去允许 ›", "Allow ›") }
    static var act_enable: String { s("去启用 ›", "Enable ›") }
    static var act_settings: String { s("去设置 ›", "Settings ›") }
    static var done_allowed: String { s("已允许", "Allowed") }
    static var done_enabled: String { s("已启用", "Enabled") }
    static var done_default: String { s("已是默认", "Default") }
    static var setup_hint: String { s("三步做完就能在任何输入框里说话", "Three steps, then just talk in any text field") }
    static var ai_notice: String { s("⚠️ 译文由 AI 生成，可能有错，发送前请自行核对。", "⚠️ Translations are AI-generated and may be wrong. Check before you send.") }
    static var check_update: String { s(" · 检查更新", " · Check for updates") }
    static var checking: String { s("检查中…", "Checking…") }
    static var ex_translate: String { s("翻译：说中文（或英文），出目标语言的干净短消息。语气和目标语言在下面那排选。", "Translate: speak Chinese (or English), get a clean short message in the target language. Pick the tone and target language in the row below.") }
    static var ex_transcribe: String { s("转写：不翻译，保留你说的那个语言。下面可选「整理」（去口水话、该分点就分点）或「逐字」（一个字不改）。", "Transcribe: no translation — you get back the language you spoke. Below, pick Clean up (drops filler, splits into points where it helps) or Verbatim (nothing changed).") }
    static var ex_history: String { s("历史：之前上屏过的内容都在这里，删没了可以回来重新复制。", "History: everything you've inserted lives here — if you delete it, come back and copy it again.") }
    static var ex_polish: String { s("整理：滤掉「嗯、那个、就是说」这类口水话，说了几件事就分几条，但**不翻译**，你说什么语言就出什么语言。", "Clean up: drops filler like um and you know, splits several points into separate lines — but does **not** translate. You get back the language you spoke.") }
    static var ex_verbatim: String { s("逐字：听到什么写什么，一个字不改、不整理、不翻译。", "Verbatim: exactly what you said — nothing changed, cleaned up or translated.") }
    static var ex_mic: String { s("点一下开始说，说完再点一下停。中途停顿思考没关系，不会自动截断。单次最长 %1$s 秒，最后 %2$s 秒圆圈里会倒数，到点会自动帮你整理这一段。", "Tap once to start talking, tap again to stop. Pausing to think is fine — it won't cut you off. Up to %1$s seconds per take; the last %2$s seconds count down inside the circle, and it wraps up on its own at the end.") }
    static var ex_type: String { s("打字：内置键盘，拼音/五笔/英文/手写四档，用来改错字。不会把你切到别的输入法。", "Type: the built-in keyboard — Pinyin, Wubi, English and handwriting — for fixing a wrong character. It never switches you to another keyboard.") }
    static var ex_speak: String { s("朗读：把刚上屏的那段念出来。中文用中文女声，英文用 Andrew。", "Read aloud: plays back what was just inserted. A Chinese voice for Chinese, Andrew for English.") }
    static var ex_backspace: String { s("退格：点一下删一个字，长按连删，1.2 秒后按词删。有选中就整段删。", "Backspace: one tap deletes one character; hold to repeat, and after 1.2 seconds it deletes whole words. If something is selected, it goes all at once.") }
    static var ex_send: String { s("发送：相当于按输入框右边那个发送键。个别 App 不支持时，会退回按一下回车。", "Send: same as tapping the send button in the app. Where that isn't supported, it falls back to pressing Enter.") }
    static var ex_tone_casual: String { s("随意：熟人之间的口气，短、放松，可以用缩写。", "Casual: how you'd talk to someone you know — short, relaxed, contractions are fine.") }
    static var ex_tone_work: String { s("工作：发给同事或对接人的直接消息（Slack / 微信 / Teams），专业但不端着。", "Work: a direct message to a colleague or counterpart (Slack, WeChat, Teams) — professional without being stiff.") }
    static var ex_tone_email: String { s("邮件：邮件正文，也用于给客户、监管、审计的正式书面沟通。完整句子、措辞精确，不加称呼和落款（除非你自己说了）。", "Email: the body of an email, and formal written contact with clients, regulators or auditors. Full sentences, precise wording, no greeting or sign-off unless you said one.") }
    static var ex_mic_ios: String { s("点一下开始说，说完再点一下停。中途停顿思考没关系，不会自动截断。", "Tap once to start talking, tap again to stop. Pausing to think is fine — it won't cut you off.") }
    static var ex_tone_cycle: String { s("语气：随意 / 工作 / 邮件三档，点一下轮换。", "Tone: Casual, Work or Email — tap to cycle.") }
    static var ex_lang_pick: String { s("翻译成哪种语言。支持英文、日语、法语、德语、西班牙语、韩语。", "Which language to translate into. English, Japanese, French, German, Spanish and Korean are supported.") }
    static var ex_speak_ios: String { s("朗读：把刚出的那段念出来。中文用中文女声，英文用 Andrew。", "Read aloud: plays back what just came out. A Chinese voice for Chinese, Andrew for English.") }
    static var st_recognizing: String { s("识别中…", "Transcribing…") }
    static var st_polishing: String { s("整理中…", "Cleaning up…") }
    static var st_translating: String { s("整理并译成英文…", "Cleaning up and translating…") }
    static var st_inserting: String { s("上屏…", "Inserting…") }
    static var st_testing: String { s("测试中…", "Testing…") }
    static var btn_got_it: String { s("知道了", "Got it") }
    static var lbl_translate_to: String { s("翻译成", "Translate into") }
    static var mic_allowed: String { s("麦克风：已允许 ✓", "Microphone: allowed ✓") }
    static var mic_not_allowed: String { s("麦克风：还没允许", "Microphone: not allowed yet") }
    static var kb_formal: String { s("正式", "Formal") }
    static var kb_tr_before: String { s("译光标前的中文", "Translate the text before the cursor") }
    static var kb_nothing_before: String { s("光标前没有内容", "Nothing before the cursor") }
    static var kb_no_pass: String { s("这份包没配口令，重新构建一次", "This build has no backend password — rebuild it") }
    static var st_listening_ios: String { s("听着呢 %d:%02d　·　说完再按一下红色按钮", "Listening %d:%02d　·　tap the red button when you're done") }
    static var msg_update_unreachable: String { s("连不上更新服务器：%1$s\n新版安装包现在直接发到你的飞书，不再走 GitHub。\n（在家连着自己网时，这里可以自助更新）", "Can't reach the update server: %1$s\nNew builds are sent to your Feishu now, not GitHub.\n(Self-update works at home, on your own network.)") }
    static var msg_already_latest: String { s("已经是最新版了（%1$s）", "You're already on the latest version (%1$s)") }
    static var msg_new_version: String { s("发现新版 %1$s，下载中…", "Found version %1$s — downloading…") }
    static var msg_downloading: String { s("下载中… %1$s%%", "Downloading… %1$s%%") }
    static var msg_update_failed: String { s("更新失败：%1$s\n（App 内更新只在家里那台机器开着时可用；在外面我会把新版发你飞书）", "Update failed: %1$s\n(In-app update only works at home, with that machine on. When you're out, I send the build to your Feishu.)") }
    static var msg_dl_done: String { s("下载完成 %1$s，正在打开安装界面", "Downloaded %1$s — opening the installer") }
    static var msg_hw_missing: String { s("手写没装上", "Handwriting isn't installed") }
    static var msg_speak_failed: String { s("朗读失败：%1$s", "Couldn't read it aloud: %1$s") }
    static var msg_mic_open_failed: String { s("打不开麦克风：%1$s", "Can't open the microphone: %1$s") }
    static var msg_mic_not_ready: String { s("麦克风没就绪，再点一次", "Microphone isn't ready — tap again") }
    static var msg_max_len: String { s("说满 %1$s 秒，这一段先帮你整理了", "Hit the %1$s-second limit — cleaning up what you said so far") }
    static var msg_mic_lost: String { s("麦克风断了（%1$s），先把已录到的转出来", "Microphone dropped (%1$s) — transcribing what was captured") }
    static var msg_no_audio: String { s("没录到声音：%1$s", "No audio captured: %1$s") }
    static var msg_not_heard: String { s("没听清，再说一次", "Didn't catch that — say it again") }
    static var msg_nothing_recorded: String { s("没录到", "Nothing recorded") }
    static var msg_failed: String { s("失败：%1$s", "Failed: %1$s") }
    static var perm_title: String { s("权限", "Permissions") }
    static var cancel: String { s("取消", "Cancel") }
    static var nothing_to_speak: String { s("还没有可朗读的内容", "Nothing to read aloud yet") }
    static var ios_setup_title: String { s("权限与自测", "Permissions & self-test") }
    static var ios_step1: String { s("第 1 步 · 允许麦克风", "Step 1 · Allow microphone") }
    static var ios_step1_why: String { s("只用要一次。语音识别在后端做，不用额外授权。", "Once only. Speech recognition runs on the server, so no extra permission is needed.") }
    static var ios_allow_mic: String { s("允许麦克风", "Allow microphone") }
    static var ios_step2: String { s("自测 · 后端通不通", "Self-test · Is the backend reachable?") }
    static var ios_test_once: String { s("测一次", "Run test") }
    static var kb_translate: String { s("翻译", "Translate") }
    static var kb_transcribe: String { s("转写", "Transcribe") }
    static var kb_history: String { s("历史", "History") }
    static var kb_type: String { s("⌨  打字", "⌨  Type") }
    static var kb_speak: String { s("朗读", "Speak") }
    static var kb_send: String { s("发送", "Send") }
    static var kb_stop: String { s("■ 停", "■ Stop") }
    static var tone_casual: String { s("随意", "Casual") }
    static var tone_work: String { s("工作", "Work") }
    static var tone_email: String { s("邮件", "Email") }
    static var kb_back: String { s("‹ 返回", "‹ Back") }
    static var kb_pinyin: String { s("拼音", "Pinyin") }
    static var kb_wubi: String { s("五笔", "Wubi") }
    static var kb_hand: String { s("手写", "Handwriting") }
    static var kb_english: String { s("英文", "English") }
    static var kb_pinyin_s: String { s("拼", "PY") }
    static var kb_wubi_s: String { s("五", "WB") }
    static var kb_hand_s: String { s("写", "HW") }
    static var kb_done: String { s("完成", "Done") }
    static var kb_space: String { s("空格", "Space") }
    static var kb_polish: String { s("整理", "Clean up") }
    static var kb_verbatim: String { s("逐字", "Verbatim") }
    static var kb_resend: String { s("重新上屏", "Insert again") }
    static var kb_undo: String { s("撤销", "Undo") }
    static var kb_clear: String { s("清空", "Clear") }
    static var kb_delete: String { s("删除", "Delete") }
    static var hist_title: String { s("  历史记录", "  History") }
    static var hist_empty: String { s("还没有记录 · 说一句就会自动存下来", "Nothing yet · Everything you say gets saved here") }
    static var rec_empty: String { s("还没有录音记录。", "No recordings yet.") }
}
