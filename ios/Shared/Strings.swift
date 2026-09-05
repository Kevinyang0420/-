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
    /// 当前界面语言代码。
    ///
    /// 🚨🚨 **必须读 `Lang.effective`，不能读 `preferredLocalizations`**
    ///    （2026-09-05 修，Kevin 实机报「选 English 后整个界面还是中文」）：
    ///    读系统语言的话，App 内那个「界面语言」设置项**根本没人读**。
    /// 🚨🚨 **必须是计算属性，不能是 `static let`** ——
    ///    `static let` 每进程只算一次，切完语言要等重启才变。
    ///    🚨 这两条**曾经被生成器打回去过**：模板里写死成 `static let`，
    ///       一跑生成就把修复覆盖掉。现在模板里就是对的，别再改回去。
    private static var code: String {
        switch Lang.effective {
        case Lang.en: return "en"
        case Lang.hant: return "zh-Hant"
        default: return "zh-Hans"
        }
    }

    /// 当前界面是不是英文。
    static var isEn: Bool { !code.hasPrefix("zh") }

    /// 当前界面是不是繁体中文。
    /// 🚨 判据用 `zh-Hant` 前缀，**不要枚举 zh-TW/zh-HK/zh-MO** ——
    ///    系统在 App 声明支持 zh-Hant 时返回的就是 zh-Hant，
    ///    枚举地区码会漏掉它，然后静默掉回简体。
    static var isHant: Bool { code.hasPrefix("zh-Hant") }

    private static func s(_ zh: String, _ en: String,
                          _ hant: String) -> String {
        isEn ? en : (isHant ? hant : zh)
    }

    static var ui_lang: String { s("zh", "en", "zh") }
    static var home_login: String { s("注册 / 登录", "Sign in", "註冊 / 登錄") }
    static var home_set_ime: String { s("设为当前输入法", "Set as keyboard", "設為當前輸入法") }
    static var login_next_ver: String { s("登录功能下一版做", "Sign-in arrives in the next version", "登錄功能下一版做") }
    static var step_mic: String { s("允许录音", "Allow microphone", "允許錄音") }
    static var step_enable: String { s("启用输入法", "Enable keyboard", "啟用輸入法") }
    static var step_default: String { s("设为默认", "Make it default", "設為預設") }
    static var act_allow: String { s("去允许 ›", "Allow ›", "去允許 ›") }
    static var act_enable: String { s("去启用 ›", "Enable ›", "去啟用 ›") }
    static var act_settings: String { s("去设置 ›", "Settings ›", "去設定 ›") }
    static var done_allowed: String { s("已允许", "Allowed", "已允許") }
    static var done_enabled: String { s("已启用", "Enabled", "已啟用") }
    static var done_default: String { s("已是默认", "Default", "已是預設") }
    static var setup_hint: String { s("三步做完就能在任何输入框里说话", "Three steps, then just talk in any text field", "三步做完就能在任何輸入框裡說話") }
    static var ai_notice: String { s("⚠️ 译文由 AI 生成，可能有错，发送前请自行核对。", "⚠️ Translations are AI-generated and may be wrong. Check before you send.", "⚠️ 譯文由 AI 生成，可能有錯，發送前請自行核對。") }
    static var check_update: String { s(" · 检查更新", " · Check for updates", " · 檢查更新") }
    static var checking: String { s("检查中…", "Checking…", "檢查中…") }
    static var ex_translate: String { s("翻译：说中文（或英文），出目标语言的干净短消息。语气和目标语言在下面那排选。", "Translate: speak Chinese (or English), get a clean short message in the target language. Pick the tone and target language in the row below.", "翻譯：說中文（或英文），出目標語言的乾淨短消息。語氣和目標語言在下面那排選。") }
    static var ex_transcribe: String { s("转写：不翻译，保留你说的那个语言。下面可选「整理」（去口水话、该分点就分点）或「逐字」（一个字不改）。", "Transcribe: no translation — you get back the language you spoke. Below, pick Clean up (drops filler, splits into points where it helps) or Verbatim (nothing changed).", "轉寫：不翻譯，保留你說的那個語言。下面可選「整理」（去口水話、該分點就分點）或「逐字」（一個字不改）。") }
    static var ex_history: String { s("历史：之前上屏过的内容都在这里，删没了可以回来重新复制。", "History: everything you've inserted lives here — if you delete it, come back and copy it again.", "歷史：之前上屏過的內容都在這裡，刪沒了可以回來重新複製。") }
    static var ex_polish: String { s("整理：滤掉「嗯、那个、就是说」这类口水话，说了几件事就分几条，但**不翻译**，你说什么语言就出什么语言。", "Clean up: drops filler like um and you know, splits several points into separate lines — but does **not** translate. You get back the language you spoke.", "整理：濾掉「嗯、那個、就是說」這類口水話，說了幾件事就分幾條，但**不翻譯**，你說什麼語言就出什麼語言。") }
    static var ex_verbatim: String { s("逐字：听到什么写什么，一个字不改、不整理、不翻译。", "Verbatim: exactly what you said — nothing changed, cleaned up or translated.", "逐字：聽到什麼寫什麼，一個字不改、不整理、不翻譯。") }
    static var ex_mic: String { s("点一下开始说，说完再点一下停。中途停顿思考没关系，不会自动截断。单次最长 %1$s 秒，最后 %2$s 秒圆圈里会倒数，到点会自动帮你整理这一段。", "Tap once to start talking, tap again to stop. Pausing to think is fine — it won't cut you off. Up to %1$s seconds per take; the last %2$s seconds count down inside the circle, and it wraps up on its own at the end.", "點一下開始說，說完再點一下停。中途停頓思考沒關係，不會自動截斷。單次最長 %1$s 秒，最後 %2$s 秒圓圈裡會倒數，到點會自動幫你整理這一段。") }
    static var ex_type: String { s("打字：内置键盘，拼音/五笔/英文/手写四档，用来改错字。不会把你切到别的输入法。", "Type: the built-in keyboard — Pinyin, Wubi, English and handwriting — for fixing a wrong character. It never switches you to another keyboard.", "打字：內置鍵盤，拼音/五筆/英文/手寫四檔，用來改錯字。不會把你切到別的輸入法。") }
    static var ex_speak: String { s("朗读：把刚上屏的那段念出来。中文用中文女声，英文用 Andrew。", "Read aloud: plays back what was just inserted. A Chinese voice for Chinese, Andrew for English.", "朗讀：把剛上屏的那段念出來。中文用中文女聲，英文用 Andrew。") }
    static var ex_backspace: String { s("退格：点一下删一个字，长按连删，1.2 秒后按词删。有选中就整段删。", "Backspace: one tap deletes one character; hold to repeat, and after 1.2 seconds it deletes whole words. If something is selected, it goes all at once.", "退格：點一下刪一個字，長按連刪，1.2 秒後按詞刪。有選中就整段刪。") }
    static var ex_send: String { s("发送：相当于按输入框右边那个发送键。个别 App 不支持时，会退回按一下回车。", "Send: same as tapping the send button in the app. Where that isn't supported, it falls back to pressing Enter.", "發送：相當於按輸入框右邊那個發送鍵。個別 App 不支持時，會退回按一下回車。") }
    static var ex_tone_casual: String { s("随意：熟人之间的口气，短、放松，可以用缩写。", "Casual: how you'd talk to someone you know — short, relaxed, contractions are fine.", "隨意：熟人之間的口氣，短、放鬆，可以用縮寫。") }
    static var ex_tone_work: String { s("工作：发给同事或对接人的直接消息（Slack / 微信 / Teams），专业但不端着。", "Work: a direct message to a colleague or counterpart (Slack, WeChat, Teams) — professional without being stiff.", "工作：發給同事或對接人的直接消息（Slack / 微信 / Teams），專業但不端著。") }
    static var ex_tone_email: String { s("邮件：邮件正文，也用于给客户、监管、审计的正式书面沟通。完整句子、措辞精确，不加称呼和落款（除非你自己说了）。", "Email: the body of an email, and formal written contact with clients, regulators or auditors. Full sentences, precise wording, no greeting or sign-off unless you said one.", "郵件：郵件正文，也用於給客戶、監管、審計的正式書面溝通。完整句子、措辭精確，不加稱呼和落款（除非你自己說了）。") }
    static var ex_mic_ios: String { s("点一下开始说，说完再点一下停。中途停顿思考没关系，不会自动截断。", "Tap once to start talking, tap again to stop. Pausing to think is fine — it won't cut you off.", "點一下開始說，說完再點一下停。中途停頓思考沒關係，不會自動截斷。") }
    static var ex_tone_cycle: String { s("语气：随意 / 工作 / 邮件三档，点一下轮换。", "Tone: Casual, Work or Email — tap to cycle.", "語氣：隨意 / 工作 / 郵件三檔，點一下輪換。") }
    static var ex_lang_pick: String { s("翻译成哪种语言。", "Which language to translate into.", "翻譯成哪種語言。") }
    static var ex_speak_ios: String { s("朗读：把刚出的那段念出来。中文用中文女声，英文用 Andrew。", "Read aloud: plays back what just came out. A Chinese voice for Chinese, Andrew for English.", "朗讀：把剛出的那段念出來。中文用中文女聲，英文用 Andrew。") }
    static var st_recognizing: String { s("识别中…", "Transcribing…", "識別中…") }
    static var st_polishing: String { s("整理中…", "Cleaning up…", "整理中…") }
    static var st_translating: String { s("整理并译成英文…", "Cleaning up and translating…", "整理並譯成英文…") }
    static var st_inserting: String { s("上屏…", "Inserting…", "上屏…") }
    static var st_testing: String { s("测试中…", "Testing…", "測試中…") }
    static var btn_got_it: String { s("知道了", "Got it", "知道了") }
    static var lbl_translate_to: String { s("翻译成", "Translate into", "翻譯成") }
    static var mic_allowed: String { s("麦克风：已允许 ✓", "Microphone: allowed ✓", "麥克風：已允許 ✓") }
    static var mic_not_allowed: String { s("麦克风：还没允许", "Microphone: not allowed yet", "麥克風：還沒允許") }
    static var kb_tr_before: String { s("译光标前的中文", "Translate the text before the cursor", "譯光標前的中文") }
    static var kb_nothing_before: String { s("光标前没有内容", "Nothing before the cursor", "光標前沒有內容") }
    static var kb_no_pass: String { s("这份包没配口令，重新构建一次", "This build has no backend password — rebuild it", "這份包沒配口令，重新構建一次") }
    static var kb_type_plain: String { s("打字", "Type", "打字") }
    static var kb_rec_failed_tap: String { s("录音失败 · 上面是现场，可长按复制；点一下收起", "Recording failed — details above, tap to dismiss", "錄音失敗 · 上面是現場，可長按複製；點一下收起") }
    static var kb_rec_failed_retry: String { s("录音失败 · 上次的音频还在，点一下重试", "Recording failed — last audio kept, tap to retry", "錄音失敗 · 上次的音頻還在，點一下重試") }
    static var kb_rec_failed_plain: String { s("录音失败，点一下收起", "Recording failed, tap to dismiss", "錄音失敗，點一下收起") }
    static var kb_lang_pick: String { s("选语言", "Language", "選語言") }
    static var kb_preparing: String { s("准备中…", "Preparing…", "準備中…") }
    static var kb_rearming: String { s("重新架引擎…", "Re-arming…", "重新架引擎…") }
    static var kb_resending: String { s("重发中…", "Resending…", "重發中…") }
    static var ready_title: String { s("准备好了", "You're all set", "準備好了") }
    static var ready_body: String { s("到任何 App 里切到 Transless 键盘，按麦克风开始说", "Switch to the Transless keyboard in any app and tap the mic", "到任何 App 裡切到 Transless 鍵盤，按麥克風開始說") }
    static var err_polish_timeout: String { s("润色超时，先给你逐字稿", "Polishing timed out — showing the raw transcript", "潤色超時，先給你逐字稿") }
    static var kb_need_full_short: String { s("设置 › 通用 › 键盘 › Transless 开启「允许完全访问」", "Settings › General › Keyboard › Transless › Allow Full Access", "設定 › 通用 › 鍵盤 › Transless 開啟「允許完全訪問」") }
    static var kb_history_none: String { s("还没有记录", "Nothing yet", "還沒有記錄") }
    static var kb_jumped_hint: String { s("已跳到 Transless 录音，说完点左上角返回", "Recording in Transless - tap the back arrow when done", "已跳到 Transless 錄音，說完點左上角返回") }
    static var kb_jump_failed: String { s("这次没出稿，点这里看原因", "No text this time - tap for details", "這次沒出稿，點這裡看原因") }
    static var rec_r0_title: String { s("正在准备…", "Getting ready...", "正在準備…") }
    static var rec_r0_cancel: String { s("取消", "Cancel", "取消") }
    static var rec_r1_title: String { s("正在为键盘录音", "Recording for the keyboard", "正在為鍵盤錄音") }
    static var rec_r1_hint: String { s("说完点停止", "Tap stop when you're done", "說完點停止") }
    static var rec_r1_stop: String { s("停止", "Stop", "停止") }
    static var rec_r2_title: String { s("正在出稿…", "Working on it...", "正在出稿…") }
    static var rec_r3_title: String { s("好了，点左上角回去", "Done - tap the back arrow to return", "好了，點左上角回去") }
    static var rec_r3_hint: String { s("英文已经准备好，回到刚才那个输入框就会填进去", "Your English is ready - go back and it will be inserted", "英文已經準備好，回到剛才那個輸入框就會填進去") }
    static var rec_r4_title: String { s("这次没成", "That didn't work", "這次沒成") }
    static var rec_r4_detail: String { s("坏在这一步：%@", "Where it broke: %@", "壞在這一步：%@") }
    static var rec_r4_retry: String { s("再试一次", "Try again", "再試一次") }
    static var rec_tail_warn: String { s("还剩 %@ 秒", "%@s left", "還剩 %@ 秒") }
    static var err_expired: String { s("这次等太久过期了，再说一次", "That request expired - say it again", "這次等太久過期了，再說一次") }
    static var err_open_app_failed: String { s("打不开 Transless，去设置里给键盘开「完全访问」", "Can't open Transless - enable Full Access for the keyboard", "打不開 Transless，去設定裡給鍵盤開「完全訪問」") }
    static var kb_cancelled: String { s("已取消，可以重新说", "Cancelled - say it again", "已取消，可以重新說") }
    static var ok_copied: String { s("已复制，可以去任何地方粘贴", "Copied - paste it anywhere", "已複製，可以去任何地方粘貼") }
    static var err_timeout: String { s("等太久了，再说一次试试", "Took too long - try again", "等太久了，再說一次試試") }
    static var err_unauthorized: String { s("登录过期了，重新登录一下", "Session expired - please sign in again", "登錄過期了，重新登錄一下") }
    static var err_quota: String { s("今天的次数用完了", "You've used up today's quota", "今天的次數用完了") }
    static var err_http: String { s("服务器没响应，等一下再试", "Server didn't respond - try again in a moment", "伺服器沒響應，等一下再試") }
    static var err_network: String { s("网络连不上，检查一下网络", "Can't reach the network - check your connection", "網絡連不上，檢查一下網絡") }
    static var err_ourbug: String { s("出了点问题，这条没发出去", "Something went wrong - it wasn't sent", "出了點問題，這條沒發出去") }
    static var err_empty: String { s("没听清，再说一次", "Didn't catch that - say it again", "沒聽清，再說一次") }
    static var err_other: String { s("出了点问题，再试一次", "Something went wrong - try again", "出了點問題，再試一次") }
    static var err_zh_unreadable: String { s("这次没整理好 —— 再说一次试试", "Could not format that - try saying it again", "這次沒整理好 —— 再說一次試試") }
    static var err_speak_failed: String { s("没能念出来，文字还在 —— 再点一次试试", "Couldn't play that - your text is still there, tap again", "沒能念出來，文字還在 —— 再點一次試試") }
    static var retry_badge: String { s("没传上去 · 再点一下", "Not sent · tap again", "沒傳上去 · 再點一下") }
    static var mode_switched: String { s("已切到：%1$s", "Switched to: %1$s", "已切到：%1$s") }
    static var tone_switched: String { s("语气：%1$s", "Tone: %1$s", "語氣：%1$s") }
    static var ime_enabled_not_default: String { s("Transless 已经装好了，还不是默认输入法 —— 点这里切换", "Transless is installed but not your default keyboard - tap to switch", "Transless 已經裝好了，還不是預設輸入法 —— 點這裡切換") }
    static var home_stats_empty: String { s("说几句试试，这里会记下你说了多少", "Say a few things - your numbers will show up here", "說幾句試試，這裡會記下你說了多少") }
    static var home_stats_footnote: String { s("按平均打字 %1$s 词/分钟算", "Based on average typing speed of %1$s words per minute", "按平均打字 %1$s 詞/分鐘算") }
    static var tab_home: String { s("首页", "Home", "首頁") }
    static var tab_history: String { s("历史", "History", "歷史") }
    static var tab_wordbook: String { s("单词本", "Words", "單詞本") }
    static var tab_me: String { s("我的", "Me", "我的") }
    static var tab_history_soon: String { s("历史现在在键盘里看，这一屏还在做", "History lives in the keyboard for now - this screen is on the way", "歷史現在在鍵盤裡看，這一屏還在做") }
    static var ime_switch_here: String { s("点这里切换", "Tap to switch", "點這裡切換") }
    static var ime_not_default_line1: String { s("Transless 已经装好了，还不是默认输入法", "Transless is installed but not your default keyboard", "Transless 已經裝好了，還不是預設輸入法") }
    static var kb_retry_a11y: String { s("麦克风。上一句还在，没传上去。轻点重试。要说新的一句，用底部 Speak。", "Microphone. Your last sentence is kept but was not sent. Tap to retry. To say something new, use Speak below.", "麥克風。上一句還在，沒傳上去。輕點重試。要說新的一句，用底部 Speak。") }
    static var kb_retrying: String { s("正在再试…", "Retrying…", "正在再試…") }
    static var kb_retry_gone: String { s("那段音频已经不在了，只能再说一次", "That audio is gone - please say it again", "那段音訊已經不在了，只能再說一次") }
    static var f2f_back: String { s("‹ 返回", "‹ Back", "‹ 返回") }
    static var f2f_hint_1: String { s("把手机放在两人中间", "Put the phone between you", "把手機放在兩人中間") }
    static var f2f_hint_2: String { s("轮流对着它说", "Take turns speaking to it", "輪流對著它說") }
    static var f2f_speak: String { s("按一下说话", "Tap to speak", "按一下說話") }
    static var f2f_zh: String { s("中文", "Chinese", "中文") }
    static var hist_clear_ask: String { s("清空之后就找不回来了，确定吗？", "This cannot be undone. Clear everything?", "清空之後就找不回來了，確定嗎？") }
    static var hist_copy: String { s("复制译文", "Copy translation", "複製譯文") }
    static var hist_resend: String { s("重新翻译", "Translate again", "重新翻譯") }
    static var hist_d_orig: String { s("你说的", "What you said", "你說的") }
    static var hist_d_out: String { s("译文", "Translation", "譯文") }
    static var hist_resent: String { s("重新翻译好了", "Re-translated", "重新翻譯好了") }
    static var kpi_words: String { s("翻译的词", "Words", "翻譯的詞") }
    static var kpi_saved: String { s("省下时间", "Time saved", "省下時間") }
    static var kpi_spoken: String { s("累计说话", "Time spoken", "累計說話") }
    static var kpi_chars: String { s("说了多少字", "Characters", "說了多少字") }
    static var cand_head: String { s("新发现的（%1$s）· 点一下收录，长按不要", "New words (%1$s) · tap to keep, long-press to skip", "新發現的（%1$s）· 點一下收錄，長按不要") }
    static var cand_added: String { s("已收录：%1$s", "Kept: %1$s", "已收錄：%1$s") }
    static var cand_rej_closed: String { s("› 我不要的（%1$s）", "› Skipped (%1$s)", "› 我不要的（%1$s）") }
    static var cand_rej_open: String { s("⌄ 我不要的（%1$s）", "⌄ Skipped (%1$s)", "⌄ 我不要的（%1$s）") }
    static var cand_recall: String { s("收回候选", "Bring back", "收回候選") }
    static var vocab_kept_head: String { s("我的常用词（%1$s）· 长按删除", "My words (%1$s) · long-press to delete", "我的常用詞（%1$s）· 長按刪除") }
    static var vocab_del_confirm: String { s("删掉「%1$s」？", "Delete “%1$s”?", "刪掉「%1$s」？") }
    static var hist_mode_en: String { s("结构化英文", "Polished English", "結構化英文") }
    static var hist_mode_zh: String { s("整理中文", "Tidied Chinese", "整理中文") }
    static var hist_mode_raw: String { s("逐字", "Verbatim", "逐字") }
    static var tab_vocab: String { s("常用词", "Words", "常用詞") }
    static var tab_settings: String { s("设置", "Settings", "設定") }
    static var vocab_sub: String { s("你常说的人名、公司名、口头禅", "Names and phrases you use often", "你常說的人名、公司名、口頭禪") }
    static var vocab_full: String { s("常用词最多 500 个，先删掉几个不用的再加", "Up to 500 terms - remove a few you don't use first", "常用詞最多 500 個，先刪掉幾個不用的再加") }
    static var vocab_too_long: String { s("这个词太长了 —— 常用词是名字或短语，不是整句话", "Too long - terms are names or phrases, not whole sentences", "這個詞太長了 —— 常用詞是名字或短語，不是整句話") }
    static var vocab_empty: String { s("还没有常用词。把你常说的人名、公司名、口头禅加进来，Transless 就会记住怎么听、怎么说。", "No personal terms yet. Add the names, companies and phrases you say often, and Transless will remember how to hear them and how to say them.", "還沒有常用詞。把你常說的人名、公司名、口頭禪加進來，Transless 就會記住怎麼聽、怎麼說。") }
    static var home_vocab: String { s("常用词", "Personal terms", "常用詞") }
    static var vocab_add: String { s("＋ 添加", "+ Add", "＋ 新增") }
    static var vocab_add_hint: String { s("人名、公司名，或你常说的话", "A name, a company, or a phrase you use often", "人名、公司名，或你常說的話") }
    static var vocab_kind_both: String { s("听和说都用", "Both", "聽和說都用") }
    static var vocab_kind_asr: String { s("只帮我听对", "Recognition only", "只幫我聽對") }
    static var vocab_kind_style: String { s("只帮我说得像", "Wording only", "只幫我說得像") }
    static var vocab_delete: String { s("删除", "Delete", "刪除") }
    static var vocab_from_book: String { s("来自单词本", "From word book", "來自單詞本") }
    static var err_mic_ask: String { s("还没给录音权限 —— 点一下允许就能用", "Microphone permission not granted yet - allow it to continue", "還沒給錄音權限 —— 點一下允許就能用") }
    static var err_mic_denied: String { s("麦克风被关着了：去「设置 → Transless → 麦克风」打开", "Microphone is off: go to Settings > Transless > Microphone", "麥克風被關著了：去「設定 → Transless → 麥克風」打開") }
    static var err_audio_session: String { s("录音没能开始 —— 如果正在通话、或有别的 App 在录音，先关掉再试", "Couldn't start recording - if you're on a call or another app is recording, close it and try again", "錄音沒能開始 —— 如果正在通話、或有別的 App 在錄音，先關掉再試") }
    static var err_kind_blocked: String { s("这句没法处理，换个说法试试", "Can't process that - try rephrasing", "這句沒法處理，換個說法試試") }
    static var err_kind_auth: String { s("登录过期了，重新登录一下", "Session expired - please sign in again", "登錄過期了，重新登錄一下") }
    static var err_kind_upstream: String { s("服务器那边没响应，等一下再试", "The server didn't respond - try again in a moment", "伺服器那邊沒響應，等一下再試") }
    static var err_tts_failed: String { s("没能念出来，文字还在 —— 再点一次试试", "Couldn't read it aloud - the text is still here, tap to retry", "沒能念出來，文字還在 —— 再點一次試試") }
    static var err_engine: String { s("录音没能开始，再试一次；还不行就重开一次 App", "Couldn't start recording - try again, or reopen the app", "錄音沒能開始，再試一次；還不行就重開一次 App") }
    static var kb_need_standby: String { s("Transless 没在后台了。打开一次 Transless 就好，不用再点任何开关。", "Transless isn't running. Just open Transless once — no switch to flip.", "Transless 沒在後臺了。打開一次 Transless 就好，不用再點任何開關。") }
    static var kb_host_gone: String { s("Transless 被系统关掉了，打开它再点一次「键盘语音」", "Transless was closed by the system — open it and turn Keyboard Voice on again", "Transless 被系統關掉了，打開它再點一次「鍵盤語音」") }
    static var kb_host_slow: String { s("等太久了，再说一次", "That took too long — try again", "等太久了，再說一次") }
    static var kb_standby_on: String { s("键盘语音 · 已开", "Keyboard Voice · On", "鍵盤語音 · 已開") }
    static var kb_standby_off: String { s("键盘语音 · 未开", "Keyboard Voice · Off", "鍵盤語音 · 未開") }
    static var kb_standby_why: String { s("打开后 Transless 会留在后台待命。没在说话时麦克风是关的，只有你按下键盘上的麦克风才会开。十分钟没用会自动关掉，每次说话都会续期。", "Transless stays ready in the background. The microphone is off unless you press the mic on the keyboard. It turns itself off after ten minutes idle, and every dictation extends it.", "打開後 Transless 會留在後臺待命。沒在說話時麥克風是關的，只有你按下鍵盤上的麥克風才會開。十分鐘沒用會自動關掉，每次說話都會續期。") }
    static var st_listening_ios: String { s("听着呢 %d:%02d　·　说完再按一下红色按钮", "Listening %d:%02d　·　tap the red button when you're done", "聽著呢 %d:%02d　·　說完再按一下紅色按鈕") }
    static var msg_update_unreachable: String { s("连不上更新服务器：%1$s\n新版安装包现在直接发到你的飞书，不再走 GitHub。\n（在家连着自己网时，这里可以自助更新）", "Can't reach the update server: %1$s\nNew builds are sent to your Feishu now, not GitHub.\n(Self-update works at home, on your own network.)", "連不上更新伺服器：%1$s\n新版安裝包現在直接發到你的飛書，不再走 GitHub。\n（在家連著自己網時，這裡可以自助更新）") }
    static var msg_already_latest: String { s("已经是最新版了（%1$s）", "You're already on the latest version (%1$s)", "已經是最新版了（%1$s）") }
    static var msg_new_version: String { s("发现新版 %1$s，下载中…", "Found version %1$s — downloading…", "發現新版 %1$s，下載中…") }
    static var msg_downloading: String { s("下载中… %1$s%%", "Downloading… %1$s%%", "下載中… %1$s%%") }
    static var msg_update_failed: String { s("更新失败：%1$s\n（App 内更新只在家里那台机器开着时可用；在外面我会把新版发你飞书）", "Update failed: %1$s\n(In-app update only works at home, with that machine on. When you're out, I send the build to your Feishu.)", "更新失敗：%1$s\n（App 內更新只在家裡那臺機器開著時可用；在外面我會把新版發你飛書）") }
    static var msg_dl_done: String { s("下载完成 %1$s，正在打开安装界面", "Downloaded %1$s — opening the installer", "下載完成 %1$s，正在打開安裝界面") }
    static var msg_hw_missing: String { s("手写没装上", "Handwriting isn't installed", "手寫沒裝上") }
    static var msg_speak_failed: String { s("朗读失败：%1$s", "Couldn't read it aloud: %1$s", "朗讀失敗：%1$s") }
    static var msg_mic_open_failed: String { s("打不开麦克风：%1$s", "Can't open the microphone: %1$s", "打不開麥克風：%1$s") }
    static var prefs_title: String { s("设置", "Settings", "設定") }
    static var kb_retry_hint: String { s("没传上去 · 再点一下", "Not sent · tap again", "沒傳上去 · 再點一下") }
    static var home_try_speak: String { s("随手翻译", "Translate as you go", "隨手翻譯") }
    static var ios_step_add: String { s("在系统设置里添加 Transless 键盘", "Add the Transless keyboard in Settings", "在系統設定裡添加 Transless 鍵盤") }
    static var ios_step_full: String { s("打开「允许完全访问」（联网要用）", "Turn on Allow Full Access (needed for network)", "打開「允許完全訪問」（聯網要用）") }
    static var ios_update_note: String { s("iOS 通过 TestFlight 更新", "Updates arrive through TestFlight", "iOS 通過 TestFlight 更新") }
    static var rec_log_empty: String { s("还没有记录", "Nothing recorded yet", "還沒有記錄") }
    static var prefs_soon: String { s("设置项还在做，下一版给你", "Settings are coming in the next version", "設定項還在做，下一版給你") }
    static var prefs_entry: String { s("设置", "Settings", "設定") }
    static var prefs_g_ime: String { s("输入法", "Keyboard", "輸入法") }
    static var prefs_g_pref: String { s("偏好", "Preferences", "偏好") }
    static var prefs_g_diag: String { s("诊断", "Diagnostics", "診斷") }
    static var prefs_g_about: String { s("关于", "About", "關於") }
    static var prefs_ime_on: String { s("已经是当前输入法", "Currently in use", "已經是當前輸入法") }
    static var prefs_ime_off: String { s("还没设为当前输入法", "Not your keyboard yet", "還沒設為當前輸入法") }
    static var prefs_diag_sub: String { s("看最近几次录音为什么没转出来", "Why recent recordings did not come through", "看最近幾次錄音為什麼沒轉出來") }
    static var prefs_about: String { s("关于 Transless", "About Transless", "關於 Transless") }
    static var prefs_check_update: String { s("检查更新", "Check for updates", "檢查更新") }
    static var prefs_copy: String { s("复制", "Copy", "複製") }
    static var msg_no_input_conn: String { s("输入框没连上，先点一下输入框再试", "Tap the text field once, then try again", "輸入框沒連上，先點一下輸入框再試") }
    static var msg_send_not_supported: String { s("这个 App 不让输入法代发，请点它自己的发送键", "This app doesn't let keyboards send — tap its own send button", "這個 App 不讓輸入法代發，請點它自己的發送鍵") }
    static var msg_send_unknown_fail: String { s("没转出来，原因不明。设置 → 录音诊断 里有详细记录", "Couldn't transcribe. See Settings → Recording log for details", "沒轉出來，原因不明。設定 → 錄音診斷 裡有詳細記錄") }
    static var msg_send_wechat: String { s("微信要先开「回车键发送消息」：我 → 设置 → 聊天", "Turn on \"Enter key sends messages\" in WeChat: Me → Settings → Chats", "微信要先開「回車鍵發送消息」：我 → 設定 → 聊天") }
    static var msg_mic_not_ready: String { s("麦克风没就绪，再点一次", "Microphone isn't ready — tap again", "麥克風沒就緒，再點一次") }
    static var msg_max_len: String { s("说满 %1$s 秒，这一段先帮你整理了", "Hit the %1$s-second limit — cleaning up what you said so far", "說滿 %1$s 秒，這一段先幫你整理了") }
    static var msg_mic_lost: String { s("麦克风断了（%1$s），先把已录到的转出来", "Microphone dropped (%1$s) — transcribing what was captured", "麥克風斷了（%1$s），先把已錄到的轉出來") }
    static var msg_no_audio: String { s("没录到声音：%1$s", "No audio captured: %1$s", "沒錄到聲音：%1$s") }
    static var msg_not_heard: String { s("没听清，再说一次", "Didn't catch that — say it again", "沒聽清，再說一次") }
    static var kb_chip_zh: String { s("中", "ZH", "中") }
    static var kb_chip_voice: String { s("语音", "Voice", "語音") }
    static var msg_cancelled: String { s("已取消", "Cancelled", "已取消") }
    static var msg_nothing_recorded: String { s("没录到", "Nothing recorded", "沒錄到") }
    static var msg_failed: String { s("失败：%1$s", "Failed: %1$s", "失敗：%1$s") }
    static var perm_title: String { s("权限", "Permissions", "權限") }
    static var cancel: String { s("取消", "Cancel", "取消") }
    static var nothing_to_speak: String { s("还没有可朗读的内容", "Nothing to read aloud yet", "還沒有可朗讀的內容") }
    static var ios_setup_title: String { s("权限与自测", "Permissions & self-test", "權限與自測") }
    static var ios_step1: String { s("第 1 步 · 允许麦克风", "Step 1 · Allow microphone", "第 1 步 · 允許麥克風") }
    static var ios_step1_why: String { s("只用要一次。语音识别在后端做，不用额外授权。", "Once only. Speech recognition runs on the server, so no extra permission is needed.", "只用要一次。語音識別在後端做，不用額外授權。") }
    static var ios_allow_mic: String { s("允许麦克风", "Allow microphone", "允許麥克風") }
    static var ios_step2: String { s("自测 · 后端通不通", "Self-test · Is the backend reachable?", "自測 · 後端通不通") }
    static var ios_test_once: String { s("测一次", "Run test", "測一次") }
    static var lang_follow_system: String { s("跟随系统", "Follow system", "跟隨系統") }
    static var lang_title: String { s("界面语言", "App language", "界面語言") }
    static var rec_log_title: String { s("录音诊断", "Recording log", "錄音診斷") }
    static var kb_translate: String { s("翻译", "Translate", "翻譯") }
    static var kb_transcribe: String { s("转写", "Transcribe", "轉寫") }
    static var kb_history: String { s("历史", "History", "歷史") }
    static var kb_type: String { s("⌨  打字", "⌨  Type", "⌨  打字") }
    static var kb_speak: String { s("朗读", "Speak", "朗讀") }
    static var kb_send: String { s("发送", "Send", "發送") }
    static var kb_stop: String { s("■ 停", "■ Stop", "■ 停") }
    static var tone_casual: String { s("随意", "Casual", "隨意") }
    static var tone_work: String { s("工作", "Work", "工作") }
    static var tone_email: String { s("邮件", "Email", "郵件") }
    static var kb_back: String { s("‹ 返回", "‹ Back", "‹ 返回") }
    static var kb_pinyin: String { s("拼音", "Pinyin", "拼音") }
    static var kb_wubi: String { s("五笔", "Wubi", "五筆") }
    static var kb_hand: String { s("手写", "Handwriting", "手寫") }
    static var kb_english: String { s("英文", "English", "英文") }
    static var kb_pinyin_s: String { s("拼", "PY", "拼") }
    static var kb_wubi_s: String { s("五", "WB", "五") }
    static var kb_hand_s: String { s("写", "HW", "寫") }
    static var kb_done: String { s("完成", "Done", "完成") }
    static var kb_space: String { s("空格", "Space", "空格") }
    static var kb_polish: String { s("整理", "Clean up", "整理") }
    static var kb_verbatim: String { s("逐字", "Verbatim", "逐字") }
    static var kb_resend: String { s("重新上屏", "Insert again", "重新上屏") }
    static var kb_undo: String { s("撤销", "Undo", "撤銷") }
    static var kb_clear: String { s("清空", "Clear", "清空") }
    static var kb_delete: String { s("删除", "Delete", "刪除") }
    static var hist_title: String { s("  历史记录", "  History", "  歷史記錄") }
    static var hist_empty: String { s("还没有记录 · 说一句就会自动存下来", "Nothing yet · Everything you say gets saved here", "還沒有記錄 · 說一句就會自動存下來") }
    static var rec_empty: String { s("还没有录音记录。", "No recordings yet.", "還沒有錄音記錄。") }
    static var dict_title: String { s("查词", "Look up", "查詞") }
    static var dict_hint: String { s("说一个词，或拼给它听", "Say a word, or spell it out", "說一個詞，或拼給它聽") }
    static var dict_recent: String { s("最近查过", "Recent", "最近查過") }
    static var dict_example: String { s("例句", "Example", "例句") }
    static var dict_collocation: String { s("搭配", "Collocations", "搭配") }
    static var wb_added: String { s("已加入", "Added", "已加入") }
    static var hist_tab_wordbook: String { s("单词本", "Wordbook", "單詞本") }
    static var lang_recent: String { s("最近用过", "Recent", "最近用過") }
    static var lang_all: String { s("全部语言", "All languages", "全部語言") }
    static var p_tone: String { s("语气", "Tone", "語氣") }
    static var p_lang: String { s("译成", "To", "譯成") }
    static var p_style: String { s("方式", "Mode", "方式") }
    static var home_try_sub: String { s("开口即译，不用找键盘", "Speak and it translates - no keyboard hunting", "開口即譯，不用找鍵盤") }
    static var try_title_zh: String { s("随手转写", "Quick transcribe", "隨手轉寫") }
    static var swipe_back_hint: String { s("⟵ 从这条边往回滑", "⟵ Swipe back from this edge", "⟵ 從這條邊往回滑") }
    static var home_ime_on: String { s("输入法 · 已启用", "Keyboard · on", "輸入法 · 已啟用") }
    static var home_ime_off: String { s("设为输入法", "Set as keyboard", "設為輸入法") }
    static var ex_style_menu_title: String { s("方式", "Style", "方式") }
    static var ex_tone_menu_title: String { s("语气", "Tone", "語氣") }
    static var ex_tone_pick: String { s("语气：点一下展开，直接挑一档。", "Tone: tap to open the list and pick one.", "語氣：點一下展開，直接挑一檔。") }
    static var err_no_speech: String { s("没听到你说话，再说一次", "I didn't hear anything - say it again", "沒聽到你說話，再說一次") }
    static var ok: String { s("确定", "OK", "確定") }
    static var account_edit: String { s("点这里填写", "Tap to fill in", "點這裡填寫") }
    static var account_none: String { s("未登录", "Not signed in", "未登入") }
    static var account_page: String { s("我的账户", "My account", "我的帳戶") }
    static var account_signout: String { s("退出登录", "Sign out", "登出") }
    static var account_signout_ask: String { s("确定要退出登录吗？下次要重新收验证码。", "Sign out? You\\'ll need a new code to sign back in.", "確定要登出嗎？下次要重新收驗證碼。") }
    static var account_title: String { s("账户", "Account", "帳戶") }
    static var act_manual: String { s("请手动开启", "Turn on manually", "請手動開啟") }
    static var full_note: String { s("在设置里打开就行。开好之后这一行不会变绿 —— iOS 不让 App 查这个状态，以键盘里的提示为准。", "Just switch it on in Settings. This line won't turn green afterwards — iOS doesn't let the app read that state. The keyboard will tell you.", "在設定裡打開就行。開好之後這一行不會變綠 —— iOS 不讓 App 查這個狀態，以鍵盤裡的提示為準。") }
    static var home_wordbook: String { s("单词本", "Word book", "單詞本") }
    static var home_wordbook_soon: String { s("单词本下个版本上线", "Word book is coming next version", "單詞本下個版本上線") }
    static var kb_keep: String { s("收藏", "Save", "收藏") }
    static var kb_kept: String { s("已收", "Saved", "已收") }
    static var login_checking: String { s("正在验证…", "Checking…", "正在驗證…") }
    static var login_code_ph: String { s("6 位验证码", "6-digit code", "6 位驗證碼") }
    static var login_do: String { s("登录", "Sign in", "登入") }
    static var login_email_ph: String { s("邮箱地址", "Email address", "電郵地址") }
    static var login_gate_go: String { s("去登录", "Sign in", "去登入") }
    static var login_gate_ime: String { s("登录后才能把 Transless 设成输入法。随手翻译不用登录，一直都能用。", "Sign in to set Transless as your keyboard. Translate as you go never needs an account.", "登入後才能把 Transless 設成輸入法。隨手翻譯不用登入，一直都能用。") }
    static var login_gate_later: String { s("以后再说", "Not now", "以後再說") }
    static var login_gate_wordbook: String { s("登录后才能用单词本。随手翻译不用登录，一直都能用。", "Sign in to use the word book. Translate as you go never needs an account.", "登入後才能用單詞本。隨手翻譯不用登入，一直都能用。") }
    static var login_gate_hotkey: String { s("登录后才能用热键在任何地方说话上屏。随手翻译不用登录，一直都能用。", "Sign in to talk into any app with the hotkey. Translate as you go never needs an account.", "登錄後才能用熱鍵在任何地方說話上屏。隨手翻譯不用登錄，一直都能用。") }
    static var login_mainland_only: String { s("目前手机号登录只支持中国内地号码，海外请用邮箱", "Phone sign-in currently supports mainland China numbers only — please use email", "目前手機號登入只支援中國內地號碼，海外請用電郵") }
    static var login_need_code: String { s("填一下收到的验证码", "Enter the code you received", "填一下收到的驗證碼") }
    static var login_need_email: String { s("填一个邮箱地址", "Enter an email address", "填一個電郵地址") }
    static var login_note: String { s("没注册过的手机号会自动创建账号。我们只用它做登录，不会发广告。", "A new number gets an account automatically. We only use it to sign you in — no marketing.", "沒註冊過的手機號會自動建立帳號。我們只用它做登入，不會發廣告。") }
    static var login_note_mail: String { s("没注册过的邮箱会自动创建账号。我们只用它做登录，不会发广告。", "A new email gets an account automatically. We only use it to sign you in — no marketing.", "沒註冊過的電郵會自動建立帳號。我們只用它做登入，不會發廣告。") }
    static var login_phone_ph: String { s("手机号", "Phone number", "手機號") }
    static var login_send_again: String { s("重新获取", "Send again", "重新獲取") }
    static var login_send_code: String { s("获取验证码", "Send code", "獲取驗證碼") }
    static var login_sending: String { s("正在发送…", "Sending…", "正在傳送…") }
    static var login_sent: String { s("验证码已发出，注意查收短信", "Code sent — check your SMS", "驗證碼已發出，注意查收簡訊") }
    static var login_sent_mail: String { s("验证码已发到邮箱，注意查收（也看一下垃圾邮件）", "Code sent to your email — check spam too", "驗證碼已發到電郵，注意查收（也看一下垃圾郵件）") }
    static var login_tab_email: String { s("邮箱", "Email", "電郵") }
    static var login_tab_phone: String { s("手机号", "Phone", "手機號") }
    static var login_too_often: String { s("发得太频繁了，%1$d 秒后再试", "Too many requests — try again in %1$ds", "發得太頻繁了，%1$d 秒後再試") }
    static var login_wait: String { s("%1$d 秒后可重发", "Resend in %1$ds", "%1$d 秒後可重發") }
    static var login_why: String { s("登录之后才能把 Transless 设为输入法，也方便你换手机时找回设置。", "Sign in to set Transless as your keyboard — it also keeps your settings when you switch phones.", "登入之後才能把 Transless 設為輸入法，也方便你換手機時找回設定。") }
    static var prefs_privacy: String { s("隐私政策", "Privacy Policy", "私隱政策") }
    static var profile_birth: String { s("出生日期（选填）", "Date of birth (optional)", "出生日期（選填）") }
    static var profile_country: String { s("国家/地区", "Country", "國家/地區") }
    static var profile_day: String { s("日", "Day", "日") }
    static var profile_done: String { s("完成", "Done", "完成") }
    static var profile_email: String { s("邮箱", "Email", "郵箱") }
    static var profile_job: String { s("职业", "Occupation", "職業") }
    static var profile_month: String { s("月", "Month", "月") }
    static var profile_nick: String { s("昵称", "Nickname", "暱稱") }
    static var profile_nick_ph: String { s("怎么称呼你", "What should we call you", "怎麼稱呼你") }
    static var profile_region: String { s("省份/州", "State / Province", "省份/州") }
    static var profile_sub: String { s("起个昵称，以后界面上就显示它，不用挂着一长串邮箱。", "Pick a nickname — it shows up instead of your full email.", "起個暱稱，以後介面上就顯示它，不用掛著一長串郵箱。") }
    static var profile_title: String { s("完善资料", "Set up your profile", "完善資料") }
    static var profile_year: String { s("年", "Year", "年") }
    static var save: String { s("保存", "Save", "儲存") }
    static var try_bigtext: String { s("大字", "Big text", "大字") }
    static var try_recent: String { s("最近", "Recent", "最近") }
    static var try_empty_guide: String { s("按住上面的麦克风，说一句中文\n比如：帮我订一张明天去香港的高铁票", "Hold the mic above and say a sentence\ne.g. Book me a train ticket to Hong Kong tomorrow", "按住上面的麥克風，說一句中文\n比如：幫我訂一張明天去香港的高鐵票") }
    static var try_cont_on: String { s("连续模式：说一句出一句，说完点停止", "Continuous mode: speak, and each sentence comes back. Tap to stop.", "連續模式：說一句出一句，說完點停止") }
    static var try_continuous: String { s("连续", "Continuous", "連續") }
    static var try_dir_me: String { s("⇄ 我说", "⇄ Me", "⇄ 我說") }
    static var try_dir_them: String { s("⇄ 对方说", "⇄ Them", "⇄ 對方說") }
    static var try_reverse_on: String { s("反向：对方说外语，译成你的语言", "Reverse: they speak, you read it in your language", "反向：對方說外語，譯成你的語言") }
    static var account_signout_done: String { s("已退出登录", "Signed out", "已登出") }
    static var f2f_empty: String { s("把手机转给对方看", "Turn the phone to show them", "把手機轉給對方看") }
    static var f2f_soon: String { s("面对面翻译（即将上线）", "Face-to-Face (coming soon)", "面對面翻譯（即將推出）") }
    static var f2f_title: String { s("面对面翻译", "Face-to-Face", "面對面翻譯") }
    static var f2f_wip: String { s("这个功能还没做完，正在做。\n\n现在要面对面用，先在「随手翻译」里说一句，再点【大字】把结果转给对方看。", "This isn't finished yet — we're building it.\n\nTo use it face-to-face today: say something in Quick Translate, then tap Big Text and turn the phone to show them.", "這個功能還沒做完，正在做。\n\n現在要面對面用，先在「隨手翻譯」裡說一句，再點【大字】把結果轉給對方看。") }
    static var f2f_place: String { s("把手机放在两人中间", "Put the phone between the two of you", "把手機放在兩人中間") }
    static var f2f_take_turns: String { s("轮流对着它说", "Take turns speaking to it", "輪流對著它說") }
    static var f2f_tap_speak: String { s("按一下说话", "Tap to speak", "按一下說話") }
    static var f2f_listening: String { s("正在听…", "Listening…", "正在聽…") }
    static var hist_screen_title: String { s("说话记录", "Speech Log", "說話記錄") }
    static var hist_chip_en: String { s("结构化英文", "Structured English", "結構化英文") }
    static var hist_chip_zh: String { s("整理中文", "Tidied Chinese", "整理中文") }
    static var hist_today: String { s("今天", "Today", "今天") }
    static var hist_delete_ask: String { s("删掉这一条？", "Delete this one?", "刪掉這一條？") }
    static var kpi_u_words: String { s("词", "words", "詞") }
    static var kpi_u_hours: String { s("小时", "h", "小時") }
    static var kpi_u_min: String { s("分钟", "min", "分鐘") }
    static var kpi_u_chars: String { s("字", "chars", "字") }
    static var kpi_nodata: String { s("还没有数据", "No data yet", "還沒有數據") }
    static var kpi_under_min: String { s("不到 1 分钟", "Under 1 min", "不到 1 分鐘") }
    static var f2f_more_langs: String { s("更多语言…", "More languages…", "更多語言…") }
    static var f2f_more_langs_hint: String { s("现在先支持这 9 种", "These 9 for now", "現在先支持這 9 種") }
    static var hist_yesterday: String { s("昨天", "Yesterday", "昨天") }
    static var hist_monthday: String { s("%d月%d日", "%d/%d", "%d月%d日") }
    static var kb_tap_speak: String { s("点一下\n开始说", "Tap to\nspeak", "點一下\n開始說") }
    static var kb_tap_stop: String { s("说完了\n点这里", "Done?\nTap here", "說完了\n點這裡") }
    static var msg_cant_record: String { s("这台机器录不了音", "This device can't record audio", "這台機器錄不了音") }
    static var msg_mic_denied_forever: String { s("录音权限被拒了，系统不会再问 —— 去「设置 → 应用 → Transless → 权限」打开麦克风", "Microphone access was denied and the system won't ask again — turn it on in Settings › Apps › Transless › Permissions", "錄音權限被拒了，系統不會再問 —— 去「設定 → 應用程式 → Transless → 權限」打開麥克風") }
    static var msg_need_mic: String { s("还没给录音权限 —— 点一下允许就能试", "Microphone access isn't on yet — tap Allow to try it", "還沒給錄音權限 —— 點一下允許就能試") }
    static var profile_birth_none: String { s("选填", "Optional", "選填") }
    static var try_big_close: String { s("关闭", "Close", "關閉") }
    static var try_big_empty: String { s("还没有内容\n点一下就能说", "Nothing yet\nTap to speak", "還沒有內容\n點一下就能說") }
    static var try_big_speaking: String { s("正在朗读…", "Speaking…", "正在朗讀…") }
    static var try_big_tap: String { s("点一下就能说 · 按返回键退出", "Tap anywhere to speak · Back to exit", "點一下就能說 · 按返回鍵退出") }
    static var try_dir_auto_me: String { s("自动判为：你在说", "Detected: you're speaking", "自動判為：你在說") }
    static var try_dir_auto_them: String { s("自动判为：对方在说", "Detected: they're speaking", "自動判為：對方在說") }
    static var try_dir_unknown: String { s("没判出是谁在说，先按【你在说】翻的。不对就点上面的 ⇄", "Couldn't tell who spoke — translated as you. Tap ⇄ above to switch.", "沒判出是誰在說，先按【你在說】翻的。不對就點上面的 ⇄") }
    static var try_dir_unknown_tap: String { s("没判出是谁在说，先按【你在说】翻的 —— 点这里改成【对方在说】", "Couldn't tell who spoke — translated as you. Tap here to switch to them.", "沒判出是誰在說，先按【你在說】翻的 —— 點這裡改成【對方在說】") }
    static var try_empty: String { s("没听到声音，再试一次", "Didn't catch that — try again", "沒聽到聲音，再試一次") }
    static var try_hint: String { s("点一下麦克风开始说，说完再点一下", "Tap the mic to start, tap again when you're done", "點一下麥克風開始說，說完再點一下") }
    static var try_listening: String { s("在听…", "Listening…", "在聽…") }
    static var try_reverse: String { s("⇄ 对方说", "⇄ They speak", "⇄ 對方說") }
    static var try_speak_timeout: String { s("朗读没回来，已经放开麦克风了。再点一次试试。", "Playback didn't come back — the mic is free again. Tap once more.", "朗讀沒回來，已經放開麥克風了。再點一次試試。") }
    static var try_title: String { s("随手翻译", "Quick Translate", "隨手翻譯") }
    static var try_tone_prefix: String { s("语气：", "Tone: ", "語氣：") }
    static var try_working: String { s("正在识别…", "Working…", "正在辨識…") }
    static var wb_front: String { s("正面显示", "Show front", "正面顯示") }
    static var try_reverse_tap: String { s("反向：对方说外语，译成你的语言 —— 点这里改回", "Reverse: they speak, you read it in your language — tap to undo", "反向：對方說外語，譯成你的語言 —— 點這裡改回") }
    static var wb_added_on: String { s("收于 %1$s", "Added %1$s", "收於 %1$s") }
    static var wb_back: String { s("返回", "Back", "返回") }
    static var wb_count: String { s("共 %1$d 条，今天要复习 %2$d 条", "%1$d saved · %2$d due today", "共 %1$d 條，今天要複習 %2$d 條") }
    static var wb_delete: String { s("删掉这条", "Delete", "刪掉這條") }
    static var wb_delete_ask: String { s("删掉之后复习进度也没了，确定吗？", "Deleting also clears its review progress. Sure?", "刪掉之後複習進度也沒了，確定嗎？") }
    static var wb_dupe: String { s("已经在单词本里了", "Already in your word book", "已經在單詞本裡了") }
    static var wb_empty: String { s("还没收东西。用随手翻译说一句，出结果后点 ＋ 就收进来了。", "Nothing yet. Say something in Translate as you go, then tap + on the result.", "還沒收東西。用隨手翻譯說一句，出結果後點 ＋ 就收進來了。") }
    static var wb_en: String { s("英文", "English", "英文") }
    static var wb_front_en: String { s("英文", "English", "英文") }
    static var wb_front_fmt: String { s("正面显示：%1$s", "Card front: %1$s", "正面顯示：%1$s") }
    static var wb_front_zh: String { s("中文", "Chinese", "中文") }
    static var wb_got: String { s("想起来了", "Got it", "想起來了") }
    static var wb_graduated: String { s("熟了", "Learned", "熟了") }
    static var wb_missed: String { s("没想起来", "Missed it", "沒想起來") }
    static var wb_nogroup: String { s("键盘里收的词现在同步不过来（App Group 没配好）。", "Words saved from the keyboard can't sync yet (App Group not set up).", "鍵盤裡收的詞現在同步不過來（App Group 沒配好）。") }
    static var wb_on: String { s("收进来的日期", "Saved on", "收進來的日期") }
    static var wb_progress: String { s("记住 %1$d 次 · 跨 %2$d 天", "%1$d hits · %2$d days", "記住 %1$d 次 · 跨 %2$d 天") }
    static var wb_progress_label: String { s("复习进度", "Progress", "複習進度") }
    static var wb_review_done: String { s("今天没有要复习的了。", "Nothing due today.", "今天沒有要複習的了。") }
    static var wb_review_n: String { s("复习（%1$d）", "Review (%1$d)", "複習（%1$d）") }
    static var wb_save_failed: String { s("没收成功，再试一次", "Couldn\\'t save, try again", "沒收成功，再試一次") }
    static var wb_saved: String { s("已收进单词本", "Saved to word book", "已收進單詞本") }
    static var wb_show: String { s("翻面看答案", "Show answer", "翻面看答案") }
    static var wb_title: String { s("单词本", "Word book", "單詞本") }
    static var wb_tone: String { s("语气", "Tone", "語氣") }
    static var wb_zh: String { s("你当时说的", "What you said", "你當時說的") }
    static var tab_f2f: String { s("面对面", "Face-to-face", "面對面") }
    static var ime_pill_on: String { s("输入法 · 已启用", "Keyboard · On", "輸入法 · 已啟用") }
    static var ime_pill_off: String { s("设为输入法", "Set as keyboard", "設為輸入法") }
    static var hist_tab_records: String { s("记录", "Records", "記錄") }
    static var wb_add: String { s("＋ 单词本", "+ Word book", "＋ 單詞本") }
    static var wb_added_tag: String { s("✓ 已加入", "✓ Added", "✓ 已加入") }
    static var wb_kind_word: String { s("词", "Words", "詞") }
    static var wb_kind_phrase: String { s("词组", "Phrases", "詞組") }
    static var wb_kind_sentence: String { s("句子", "Sentences", "句子") }
    static var wb_clear_ask: String { s("清空单词本？收藏的词和复习进度都会没。", "Clear the word book? Saved items and their review progress will be gone.", "清空單詞本？收藏的詞和複習進度都會沒。") }
}
