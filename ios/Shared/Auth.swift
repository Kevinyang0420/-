import Foundation

/// 手机号/邮箱验证码登录。**只做网络这一层**，界面另说。
///
/// 后端契约（2026-08-25 全链路实测过，Kevin 手机真收到过码）：
///   ① `POST /api/auth/send`   `{kind, target}`            → 202 `{job}`
///   ② 轮询 `/api/auth/result?job=<jid>`                    → `{done, result|error}`
///   ③ `POST /api/auth/verify` `{kind, target, code, device_token}` → 202 `{job}`
///   ④ 再轮询同一个 result 口
///
/// 🚨 **为什么是"提交任务 + 轮询"而不是直接返回**：这两步都要联网调阿里云
///    （几百毫秒），而网关上游慢过约 0.1 秒就 504。同步返回**必然失败**。
///
/// 🚨 **限流是同步返回的**（429 带 `retry_after`），不走任务 ——
///    被限流时立刻告诉用户，没必要再轮询一圈。
///
/// 🚨 **「验证码不对」和「这个号没注册过」后端返回同一句话**，
///    否则这个接口就成了查「某人有没有用过 Transless」的工具。
///    客户端不许试图区分这两种，也别自作聪明改文案。
enum Auth {

    enum Kind: String {
        case phone, email
    }

    enum Failure: Error {
        /// 业务结果：码不对、已失效。**不是异常** ——
        /// 🚨 后端踩过这个坑：阿里云用 HTTP 400 表示"码不对"，
        ///    原来一律当调用失败抛，用户输错码看到的是「验证码没发出去」。
        case badCode(String)
        /// 被限流，`after` 秒之后再试
        case rateLimited(Int)
        /// 真的出错了（网络、服务端）
        case failed(String)
    }

    /// 登录成功后拿到的东西。
    ///
    /// 🚨 **没有 token 这个东西**。后端 `verify_code` 返回的只有
    ///    `{"user_id": …, "new_user": …}` —— 登录后的凭证**还是设备令牌**
    ///    （`DeviceId.pass`）。后端 `bind_user` 的注释写着
    ///    「绑定后设备令牌继续有效 —— 不能因为登录一下就把他正在用的输入法踢下线」。
    ///
    ///    我上一版在这里要了一个 `token` 字段，而后端从来不返回它，
    ///    于是**所有人**（新老用户都一样）都卡在「返回里没有 user_id/token」
    ///    这句话上，一个都登不进去。Kevin 2026-08-25 实测撞到。
    ///    —— 后端那份代码就在手边，读一眼就知道它返回什么，我没读。
    struct Session {
        let userId: String
        /// 这次是不是**新建的号**。后端本来就是"没注册过自动建号"，
        /// 不存在"注册 / 登录"两条路 —— 这个字段只用来决定欢迎语。
        let isNew: Bool
    }

    // MARK: - 对外

    /// 发验证码。
    static func sendCode(_ kind: Kind, _ target: String,
                         done: @escaping (Result<Void, Failure>) -> Void) {
        post("/api/auth/send", ["kind": kind.rawValue, "target": target]) { r in
            switch r {
            case .success(let job):
                poll(job) { pr in
                    switch pr {
                    case .success: done(.success(()))
                    case .failure(let e): done(.failure(e))
                    }
                }
            case .failure(let e):
                done(.failure(e))
            }
        }
    }

    /// 验码 + 绑设备。成功后**自动存下会话**。
    static func verify(_ kind: Kind, _ target: String, code: String,
                       done: @escaping (Result<Session, Failure>) -> Void) {
        var body: [String: Any] = ["kind": kind.rawValue, "target": target,
                                   "code": code]
        // 🚨 上报**设备地区**（ISO 国家码，如 CN / US / HK）。
        //    Kevin 要按国家统计用户，而 `users` 表原来只有
        //    `source(android|ios)`，看不出国家。
        //    这不是定位：地区设置是他自己在系统里设的，
        //    不需要位置权限、也不用问他。
        //    🚨 它反映"他是哪儿人"；IP 反映"他此刻在哪"（出差/VPN 会污染）。
        //       两个都存，交叉起来才有意思。
        if #available(iOS 16, *) {
            body["region"] = Locale.current.region?.identifier ?? ""
        } else {
            body["region"] = Locale.current.regionCode ?? ""
        }
        body["locale"] = Locale.current.identifier
        // 🚨🚨 **时区可能是三个信号里最准的一个**（Kevin 2026-08-25 点出
        //    前两个都会被污染之后想到的）：
        //      · 设备地区 —— 他自己设的，「我经常会设置为我的美区账户」
        //      · IP 国家   —— VPN 一开就废
        //      · **时区**   —— 手机**自动**跟着实际位置设，
        //                     而 VPN 改 IP **不改时区**
        //    三个都存，冲突时才看得出是哪种情况：
        //      地区 US + 时区 Asia/Shanghai ＝ 华人在国内用美区账号
        //      地区 CN + 时区 America/*      ＝ 中国人在美国
        //      IP 和时区对不上               ＝ 多半在用 VPN
        body["tz"] = TimeZone.current.identifier
        // 系统首选语言（"zh-Hans-CN" 这种也带地区信息，可作旁证）
        body["lang"] = Locale.preferredLanguages.first ?? ""
        // 🚨 设备令牌走请求体的 `device_token`，**不要只靠 `X-Alex-Pass` 头** ——
        //    后端踩过：那个头也可能装的是共享口令（不是设备令牌），
        //    原来写成「头 or 体」，只要带了头就盖掉体，
        //    于是拿口令去验签必然失败，最后被报成"验证码不对"，排查了很久。
        // 🚨🚨 **发之前先确保设备真的注册过**。
        //    `DeviceId.pass` 在没注册时会**回落到共用口令**
        //    （回落本身是对的：注册失败也不能让人用不了），
        //    而后端拿共用口令去验设备签名必然失败，
        //    报「验证码是对的，但这台设备的登录凭据无效」——
        //    用户会以为是自己输错了码。
        //    安卓那边 2026-08-26 真机 e2e 抓到过，两端结构一样。
        //
        //    🚨 `ensure` 是**异步**的，必须在它的回调里再发 verify。
        //       写成 `if !registered { ensure() }` 然后往下走的话，
        //       ensure 还没回来就把旧令牌发出去了 —— 等于没修。
        func send() {
            var b = body
            b["device_token"] = DeviceId.pass
            postVerify(b, done)
        }
        if DeviceId.registered {
            send()
        } else {
            DeviceId.ensure { _ in send() }
        }
    }

    /// verify 的实际发送 —— 从 `verify` 里拆出来，好在设备注册回调里复用。
    private static func postVerify(
        _ body: [String: Any],
        _ done: @escaping (Result<Session, Failure>) -> Void) {
        post("/api/auth/verify", body) { r in
            switch r {
            case .success(let job):
                poll(job) { pr in
                    switch pr {
                    case .success(let obj):
                        // 🚨 只要 `user_id`。**别再要 token** —— 后端不返回它。
                        guard let uid = obj["user_id"] as? String,
                              !uid.isEmpty else {
                            done(.failure(.failed("服务端没返回 user_id")))
                            return
                        }
                        let s = Session(
                            userId: uid,
                            isNew: (obj["new_user"] as? Bool) ?? false)
                        save(s)
                        // 🚨 登录成功的**唯一咽喉**，所以常用词的 merge 挂在这儿
                        //    （跟安卓 `LoginActivity` 登录后调 `mergeAfterLoginAsync`
                        //     同一时机）。这是**唯一**用 merge 的时刻：
                        //    把未登录期间攒的本地词并上去，服务端做并集，两边都留着。
                        //    之后一律走 replace 三步（否则删除传播不出去）。
                        // 🚨 挂在这里而不是登录页的回调里：登录页有好几条成功路径
                        //    （验证码/自动登录/重试），挂在页面上必然漏一条。
                        VocabSync.mergeAfterLoginAsync()
                        done(.success(s))
                    case .failure(let e):
                        done(.failure(e))
                    }
                }
            case .failure(let e):
                done(.failure(e))
            }
        }
    }

    // MARK: - 会话存储

    private static let kUser = "transless.auth.userId"
    private static let kAccount = "transless.auth.account"
    private static let kNick = "transless.auth.nickname"
    private static let kBirth = "auth_birthday"

    /// 🚨🚨 **这台设备上一次真正登录成功的 uid** —— `signOut()` **故意不清它**。
    ///
    /// 为什么不能直接用 `kUser` 当"上一个人"：`signOut()` 把 `kUser` 清成了空，
    /// 事后就分不出「同一个人退出再登回来」和「换了另一个人登进来」。
    /// 这两种情况的正确行为**相反**（前者不许清他自己的资料，后者必须清），
    /// 所以必须有一个独立的、不随登出消失的字段来记住身份。
    /// （2.4 在 PC 端踩过这个坑后单独加了 `Settings.LastSignedUid`，三端同一个做法。）
    private static let kLastUid = "transless.auth.lastSignedUid"

    /// 登录了没有。
    static var loggedIn: Bool { current != nil }

    static var current: Session? {
        guard let u = UserDefaults.standard.string(forKey: kUser), !u.isEmpty
        else { return nil }
        return Session(userId: u, isNew: false)
    }

    /// 这次登录算不算「换了个账号」，需不需要先把上一个人的本地数据清掉。
    ///
    /// 🚨 跟安卓 `AccountSwitchCheck.shouldClear` **同一份语义**，五条判据逐条对齐。
    ///    同一个规矩两端各写一套必漂（项目里已经栽过好几次），改这里必须两端一起改。
    ///
    /// - Parameters:
    ///   - prev: 这台设备上一次记住的 uid（从没登录过是空串）
    ///   - new:  这次要写入的 uid
    static func shouldClearOnSwitch(prev: String, new: String) -> Bool {
        if new.isEmpty { return false }
        if prev.isEmpty { return false }     // 第一次登录，没有上一个人可清
        return prev != new
    }

    /// 把**上一个账号**留在这台设备上的资料痕迹清掉。
    ///
    /// 🚨 **只在真的换了人时调**（`shouldClearOnSwitch` 说了算）。
    ///    Kevin 2026-09-16 亲口否掉过"一律清"的方案：
    ///    「那这个肯定要跟着账号走了，怎么可能还要让所有人退出登录一遍，
    ///    　还要再填一遍这些信息呢？」——无条件清 = 把他自己填的东西也删了。
    ///
    /// 🚨 **昵称和账号各有两个键，两个都要清**：`profileKeys` 里是
    ///    `auth_nickname` / `auth_account`（账户页在用），而 `kNick` / `kAccount`
    ///    是另一对（首页显示名、注册流程在用）。只清表里那份，
    ///    首页仍会显示上一个人的名字。
    ///    （这两对键本身就是"同一件事两处实现"的老账，该收成一份——
    ///    但那是独立的重构，不在今晚范围，已记给 2.2 下一稿。）
    static func clearLocalProfile() {
        let d = UserDefaults.standard
        for kv in profileKeys { d.removeObject(forKey: kv.key) }
        d.removeObject(forKey: kNick)
        d.removeObject(forKey: kAccount)
        d.removeObject(forKey: kBirth)
    }

    private static func save(_ s: Session) {
        // 🚨🚨 09-17 Kevin 亲报：「我之前登录过的账号，登进去之后居然还要我
        //    再选一次生日」——生日其实是**上一个账号**的，串到了新账号头上。
        //    比"资料丢了"更糟：那是**数据串了**，A 的生日/国家/职业被 B 看见。
        //    根因是 `profileKeys` 这些字段按**设备**存、不跟账号走，换账号时没人清。
        //    真正的解是把资料存到服务端（队列④，1.1 在做）；在那之前先堵串号这个洞。
        let prev = UserDefaults.standard.string(forKey: kLastUid) ?? ""
        if shouldClearOnSwitch(prev: prev, new: s.userId) { clearLocalProfile() }

        UserDefaults.standard.set(s.userId, forKey: kUser)
        UserDefaults.standard.set(s.userId, forKey: kLastUid)
        // 🚨🚨 09-17：新会话建立（登录成功的唯一咽喉，见 postVerify 的注释）
        //    也要清——哪怕是同一个人重新登进来，也该让 refresh() 重新问一遍
        //    服务端，而不是继续信上一段会话留下的缓存。清了绝不会比不清更错，
        //    真实状态照样在 viewDidLoad/viewWillAppear/登录回调那几处 refresh() 里补上。
        //    🚨 会员缓存跟资料不一样：会员真值服务端随时问得到，清了必被 refresh 补回；
        //    资料清了就真没了，所以资料只在换人时清、会员每次都清。
        ProStatus.clearCache()
    }

    /// 自测：好样本过 + 坏样本响。全过返回 `nil`。
    /// 🚨 逐条对齐安卓 `AccountSwitchCheck.selfTest()` —— 两端判据必须一模一样。
    static func selftestAccountSwitch() -> String? {
        if shouldClearOnSwitch(prev: "", new: "u1") {
            return "第一次登录（没有上一个人）不该清"
        }
        // 🚨🚨 反向控制：同账号重登不许清——那会把这个人自己填的资料当成
        //    "上一个人的痕迹"删掉，正是 Kevin 否掉的那个方案。
        if shouldClearOnSwitch(prev: "u1", new: "u1") {
            return "🚨 同一账号重登不该清（会把他自己的本地资料也删掉）"
        }
        // 🚨🚨 坏样本 = 这次要修的洞本身：换了不同账号必须判要清
        if !shouldClearOnSwitch(prev: "u1", new: "u2") {
            return "🚨 换了不同账号却没判要清（就是串账号那个 bug 的根因本身）"
        }
        if shouldClearOnSwitch(prev: "u1", new: "") {
            return "newUid 为空（不该发生的调用）不该判要清"
        }
        return nil
    }

    static func signOut() {
        UserDefaults.standard.removeObject(forKey: kUser)
        UserDefaults.standard.removeObject(forKey: kAccount)
        // 🚨🚨 09-17：身份变了，会员本地缓存必须跟着清——不然下一个登进来的
        //    账号在 refresh() 网络回来之前，界面读到的是上一个人的会员状态。
        ProStatus.clearCache()
    }

    // MARK: - 账号显示（跟安卓 `Onboard` 同口径）

    /// 登录用的账号（邮箱或手机号）。**只为了显示**，不参与鉴权。
    static func setAccount(_ a: String) {
        UserDefaults.standard.set(a, forKey: kAccount)
    }

    static var account: String {
        UserDefaults.standard.string(forKey: kAccount) ?? ""
    }

    /// 出生日期，格式固定 `yyyy-MM-dd`（跟安卓 `Onboard.birthday` 同一口径）。
    /// **没填就是空串**，不是某个默认日期 —— 存了假默认值以后
    /// 就分不出"他生日就是这天"和"他压根没填"。
    static func setBirthday(_ d: String) {
        UserDefaults.standard.set(d, forKey: kBirth)
    }

    static var birthday: String {
        UserDefaults.standard.string(forKey: kBirth) ?? ""
    }

    /// 昵称填过没 —— 决定登录之后要不要推「完善资料」。
    ///
    /// 🚨 判据是**昵称填过没**，不是"是不是新注册"：
    ///    这个功能上线前就登录过的老用户也该有机会填一次，
    ///    而填过的人不管登录多少次都不该再被拦。
    static var hasNickname: Bool {
        !(UserDefaults.standard.string(forKey: kNick) ?? "")
            .trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func setNickname(_ n: String) {
        UserDefaults.standard.set(n, forKey: kNick)
    }

    /// 首页顶部显示的名字。
    ///
    /// 🚨 **不要把一长串邮箱挂在首页**（Kevin 2026-08-26：
    ///    「账号尽量加个昵称，不要把那么长的邮箱一直放在左上角」）。
    ///    真昵称要用户注册时填、且要后端加字段；在那之前用
    ///    **邮箱 @ 前那一截**兜底 —— 那已经是他自己起的名字了。
    ///    手机号只留后四位。
    ///    🚨 截取逻辑**只有这一份**，界面层不许再抄一遍。
    static var displayName: String {
        let n = UserDefaults.standard.string(forKey: kNick) ?? ""
        if !n.isEmpty { return n }
        let a = account
        if let at = a.firstIndex(of: "@") { return String(a[a.startIndex..<at]) }
        if a.count >= 4 { return "***" + String(a.suffix(4)) }
        return a
    }

    // MARK: - 账户资料

    /// 账户页上那些**选填项**。`(资料 id, UserDefaults 键名)`。
    ///
    /// Kevin 2026-08-26：「用户信息页需要完善，可以多加一些选填项
    /// （如邮箱、生日、国家、省份、职业等）」。
    ///
    /// 🚨 **表驱动，不给每个字段手写一对读写**。六个字段各写一对，
    ///    加第七个时必然漏改一处，而漏的那处不报错。
    ///
    /// 🚨 生日复用注册那一步已经在写的 `auth_birthday`，**不新开键**。
    ///
    /// 🚨 顺序就是界面上的显示顺序，跟安卓 `Onboard.PROFILE_KEYS`
    ///    必须一模一样 —— `gate_pure_logic.py` 的 Profile 单元会比。
    static let profileKeys: [(id: String, key: String)] = [
        ("nick", "auth_nickname"),
        ("account", "auth_account"),
        ("birthday", "auth_birthday"),
        ("country", "auth_country"),
        ("region", "auth_region"),
        ("job", "auth_job"),
    ]

    /// 读一个资料项。没填就是空串。
    static func profile(_ id: String) -> String {
        guard let kv = profileKeys.first(where: { $0.id == id }) else { return "" }
        return UserDefaults.standard.string(forKey: kv.key) ?? ""
    }

    /// 写一个资料项。写空串 = 清掉。
    static func setProfile(_ id: String, _ v: String) {
        guard let kv = profileKeys.first(where: { $0.id == id }) else { return }
        UserDefaults.standard.set(
            v.trimmingCharacters(in: .whitespaces), forKey: kv.key)
    }

    // MARK: - 网络

    private static func post(_ path: String, _ body: [String: Any],
                             done: @escaping (Result<String, Failure>) -> Void) {
        guard let url = URL(string: Backend.base + path) else {
            done(.failure(.failed("URL 拼不出来"))); return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err = err {
                done(.failure(.failed(err.localizedDescription))); return
            }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let obj = (try? JSONSerialization.jsonObject(with: data ?? Data()))
                as? [String: Any] ?? [:]
            // 🚨 429 是**同步**返回的（限流在联网之前判掉），不走任务口。
            if code == 429 {
                let after = (obj["retry_after"] as? Int) ?? 60
                done(.failure(.rateLimited(after))); return
            }
            guard let job = obj["job"] as? String, !job.isEmpty else {
                done(.failure(.failed((obj["error"] as? String)
                                      ?? "服务端没给任务号（HTTP \(code)）")))
                return
            }
            done(.success(job))
        }.resume()
    }

    /// 轮询任务结果。
    /// 🚨 有**上限**：不设的话服务端一直不 done 就会永远转下去，
    ///    界面卡在"发送中"，用户既不知道成没成也没法重来。
    private static func poll(_ job: String, tries: Int = 40,
                             done: @escaping (Result<[String: Any], Failure>) -> Void) {
        guard tries > 0 else {
            done(.failure(.failed("等太久了，再试一次"))); return
        }
        guard let url = URL(string: Backend.base
                            + "/api/auth/result?job=" + job) else {
            done(.failure(.failed("URL 拼不出来"))); return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let obj = (try? JSONSerialization.jsonObject(with: data ?? Data()))
                as? [String: Any] ?? [:]
            if (obj["done"] as? Bool) != true {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
                    poll(job, tries: tries - 1, done: done)
                }
                return
            }
            if let e = obj["error"] as? String, !e.isEmpty {
                // 🚨 「码不对」是**业务结果**，跟"连不上服务器"分开报。
                //    混在一起的话用户输错码会看到「验证码没发出去」，
                //    而真相是「你输错了」——后端修过这个，客户端别再混回去。
                if e.contains("验证码") || e.contains("失效") {
                    done(.failure(.badCode(e)))
                } else {
                    done(.failure(.failed(e)))
                }
                return
            }
            let result = (obj["result"] as? [String: Any]) ?? obj
            done(.success(result))
        }.resume()
    }
}
