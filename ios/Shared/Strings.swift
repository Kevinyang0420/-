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
    /// 系统解析出来的界面语言代码。
    private static let code: String =
        Bundle.main.preferredLocalizations.first ?? "zh-Hans"

    /// 当前界面是不是英文。
    static let isEn: Bool = !code.hasPrefix("zh")

    /// 当前界面是不是繁体中文。
    /// 🚨 判据用 `zh-Hant` 前缀，**不要枚举 zh-TW/zh-HK/zh-MO** ——
    ///    系统在 App 声明支持 zh-Hant 时返回的就是 zh-Hant，
    ///    枚举地区码会漏掉它，然后静默掉回简体。
    static let isHant: Bool = code.hasPrefix("zh-Hant")

    private static func s(_ zh: String, _ en: String,
                          _ hant: String) -> String {
        isEn ? en : (isHant ? hant : zh)
    }

    static var ui_lang: String { s("zh", "en", "zh") }
    static var home_wordbook: String { s("单词本", "Word book", "單詞本") }
    static var home_wordbook_soon: String { s("单词本下个版本上线", "Word book is coming next version", "單詞本下個版本上線") }
    static var account_title: String { s("账户", "Account", "帳戶") }
    static var account_none: String { s("未登录", "Not signed in", "未登入") }
    static var account_signout_done: String { s("已退出登录", "Signed out", "已登出") }
    static var home_login: String { s("注册 / 登录", "Sign in", "註冊 / 登錄") }
    static var home_set_ime: String { s("设为当前输入法", "Set as keyboard", "設為當前輸入法") }
    static var login_next_ver: String { s("登录功能下一版做", "Sign-in arrives in the next version", "登錄功能下一版做") }
    static var step_mic: String { s("允许录音", "Allow microphone", "允許錄音") }
    static var step_enable: String { s("启用输入法", "Enable keyboard", "啟用輸入法") }
    static var step_default: String { s("设为默认", "Make it default", "設為預設") }
    static var act_allow: String { s("去允许 ›", "Allow ›", "去允許 ›") }
    static var act_enable: String { s("去启用 ›", "Enable ›", "去啟用 ›") }
    /// 「这一步只能你自己去系统设置里开，App 查不到状态」。
    /// 🚨 不能用「—」：其他两步写着「去启用 ›」，突然一个破折号，
    ///    "已完成 / 不可点 / 状态未知"分不出来（Grok 评审指出）。
    // ---- 登录页 ----
    static var login_why: String {
        s("登录之后才能把 Transless 设为输入法，也方便你换手机时找回设置。",
          "Sign in to set Transless as your keyboard — it also keeps your "
          + "settings when you switch phones.",
          "登入之後才能把 Transless 設為輸入法，也方便你換手機時找回設定。")
    }
    static var login_tab_email: String { s("邮箱", "Email", "電郵") }
    static var login_tab_phone: String { s("手机号", "Phone", "手機號") }
    static var login_email_ph: String { s("邮箱地址", "Email address", "電郵地址") }
    static var login_need_email: String { s("填一个邮箱地址", "Enter an email address", "填一個電郵地址") }
    /// 🚨 后端走阿里云短信，**它只发中国内地**。当场说清比让人等一个
    ///    看不懂的服务端错误强。
    static var login_mainland_only: String {
        s("目前手机号登录只支持中国内地号码，海外请用邮箱",
          "Phone sign-in currently supports mainland China numbers only — "
          + "please use email",
          "目前手機號登入只支援中國內地號碼，海外請用電郵")
    }
    static var login_sent_mail: String {
        s("验证码已发到邮箱，注意查收（也看一下垃圾邮件）",
          "Code sent to your email — check spam too",
          "驗證碼已發到電郵，注意查收（也看一下垃圾郵件）")
    }

    static var login_phone_ph: String { s("手机号", "Phone number", "手機號") }
    static var login_code_ph: String { s("6 位验证码", "6-digit code", "6 位驗證碼") }
    static var login_send_code: String { s("获取验证码", "Send code", "獲取驗證碼") }
    static var login_send_again: String { s("重新获取", "Send again", "重新獲取") }
    static var login_wait: String { s("%d 秒后可重发", "Resend in %ds", "%d 秒後可重發") }
    static var login_do: String { s("登录", "Sign in", "登入") }
    static var login_sending: String { s("正在发送…", "Sending…", "正在傳送…") }
    static var login_sent: String { s("验证码已发出，注意查收短信", "Code sent — check your SMS", "驗證碼已發出，注意查收簡訊") }
    static var login_checking: String { s("正在验证…", "Checking…", "正在驗證…") }
    static var login_need_phone: String { s("先填手机号", "Enter your phone number first", "先填手機號") }
    static var login_need_code: String { s("填一下收到的验证码", "Enter the code you received", "填一下收到的驗證碼") }
    static var login_too_often: String { s("发得太频繁了，%d 秒后再试", "Too many requests — try again in %ds", "發得太頻繁了，%d 秒後再試") }
    /// 🚨 说清「没注册过会自动建号」——不然他会去找"注册"按钮找不到。
    /// 🚨 **跟着 tab 换**：邮箱 tab 下写"手机号"是明显的错话
    ///    （截图上看到过一次）。
    static var login_note: String {
        s("没注册过的手机号会自动创建账号。我们只用它做登录，不会发广告。",
          "A new number gets an account automatically. We only use it to sign "
          + "you in — no marketing.",
          "沒註冊過的手機號會自動建立帳號。我們只用它做登入，不會發廣告。")
    }
    static var login_note_mail: String {
        s("没注册过的邮箱会自动创建账号。我们只用它做登录，不会发广告。",
          "A new email gets an account automatically. We only use it to sign "
          + "you in — no marketing.",
          "沒註冊過的電郵會自動建立帳號。我們只用它做登入，不會發廣告。")
    }

    static var act_manual: String { s("请手动开启", "Turn on manually", "請手動開啟") }
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
    static var ex_lang_pick: String { s("翻译成哪种语言。支持英文、日语、法语、德语、西班牙语、韩语。", "Which language to translate into. English, Japanese, French, German, Spanish and Korean are supported.", "翻譯成哪種語言。支持英文、日語、法語、德語、西班牙語、韓語。") }
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
    static var prefs_privacy: String { s("隐私政策", "Privacy Policy", "私隱政策") }
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
    static var kb_history_none: String { s("还没有记录", "Nothing yet", "還沒有記錄") }
    static var kb_history: String { s("历史", "History", "歷史") }
    static var kb_type: String { s("⌨  打字", "⌨  Type", "⌨  打字") }
    /// 🚨 不带 emoji 的版本 —— 图标改用 SF Symbol setImage()，
    ///    文案里的 ⌨ 在 iOS 上是彩色 emoji，跟旁边的描边图标打架。
    static var kb_type_plain: String { s("打字", "Type", "打字") }
    /// 轻警告条用的短文案（Grok：原文太长、一行放不下）。
    static var kb_need_full_short: String { s("设置 › 通用 › 键盘 › Transless 开启「允许完全访问」", "Settings › General › Keyboard › Transless › Allow Full Access", "設定 › 一般 › 鍵盤 › Transless 開啟「允許完全存取」") }
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
    /// 引导页第 2 项的说明。🚨 iOS 不给容器 App 查「完全访问」的接口，
    /// 所以这里如实说明，不假装知道状态。
    static var full_note: String {
        s("在设置里打开就行。开好之后这一行不会变绿 —— iOS 不让 App 查这个状态，"
          + "以键盘里的提示为准。",
          "Just switch it on in Settings. This line won't turn green afterwards — "
          + "iOS doesn't let the app read that state. The keyboard will tell you.",
          "在設定裡打開就行。開好之後這一行不會變綠 —— iOS 不讓 App 查這個狀態，"
          + "以鍵盤裡的提示為準。")
    }
    /// 键盘扩展里没有完全访问时挂的提示。
    static var kb_need_full: String {
        s("请到 设置 › 通用 › 键盘 › Transless 打开「允许完全访问」，否则联网用不了",
          "Open Settings › General › Keyboard › Transless and turn on Allow Full "
          + "Access — networking won't work without it",
          "請到 設定 › 一般 › 鍵盤 › Transless 打開「允許完全存取」，否則聯網用不了")
    }
    static var try_bigtext: String { s("大字", "Big text", "大字") }
    static var try_dir_me: String { s("⇄ 我说", "⇄ Me", "⇄ 我說") }
    static var try_dir_them: String { s("⇄ 对方说", "⇄ Them", "⇄ 對方說") }
    static var try_reverse: String { s("⇄ 对方说", "⇄ Them", "⇄ 對方說") }
    static var try_reverse_on: String { s("反向：对方说外语，译成你的语言", "Reverse: they speak, you read it in your language", "反向：對方說外語，譯成你的語言") }
    static var try_continuous: String { s("连续", "Continuous", "連續") }
    static var try_cont_on: String { s("连续模式：说一句出一句，说完点停止", "Continuous mode: speak, and each sentence comes back. Tap to stop.", "連續模式：說一句出一句，說完點停止") }
    static var kb_polish: String { s("整理", "Clean up", "整理") }
    static var kb_verbatim: String { s("逐字", "Verbatim", "逐字") }
    static var kb_resend: String { s("重新上屏", "Insert again", "重新上屏") }
    static var kb_undo: String { s("撤销", "Undo", "撤銷") }
    static var kb_clear: String { s("清空", "Clear", "清空") }
    static var kb_delete: String { s("删除", "Delete", "刪除") }
    static var hist_title: String { s("  历史记录", "  History", "  歷史記錄") }
    static var hist_empty: String { s("还没有记录 · 说一句就会自动存下来", "Nothing yet · Everything you say gets saved here", "還沒有記錄 · 說一句就會自動存下來") }
    static var rec_empty: String { s("还没有录音记录。", "No recordings yet.", "還沒有錄音記錄。") }
}
