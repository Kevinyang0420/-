import Foundation

/// 录音诊断台账。键名取值跟安卓一致（对齐 RecLog.java）。
///
/// 🚨🚨 **它现在只在本进程内有效，不跨进程。**
///
///    我第一版写的是「照 DeviceId 已经验证过的路子走（Keychain 跨进程共享）」——
///    **那是个假前提**：Keychain 项的默认访问组是
///    `$(AppIdentifierPrefix)<bundle id>`，主 App 是 `…transless`、
///    键盘扩展是 `…transless.keyboard`，**不是同一个组**。
///    要真共享，两个 target 都得声明 `keychain-access-groups`
///    并且读写带 `kSecAttrAccessGroup` —— 而这个工程**一条 entitlement 都没有**。
///    `DeviceId.swift` 也没被验证过，它只是同样在两个进程里各存各的。
///
///    **我把「别处也这么写」当成了「这么写是对的」。**（交叉审查 H5）
///
///    要修得动签名和描述文件（配 App Group + entitlements），那是单独一件事。
///    在那之前**别在注释里写"共享"** —— 写了下一个人就会当真。
enum RecLog {

    private static let service = "com.kevin.transless.prefs"
    private static let account = "rec_log"
    /// 跟安卓一致：只留最近这些条，别让它无限长。
    private static let maxItems = 20

    struct Item: Codable {
        let t: Double          // 时间戳（秒）
        let sec: Double        // 录了几秒
        let bytes: Int         // 音频字节数
        let r: String          // 结果：成功 / 失败原因
        let d: String          // 细节
        // 🚨🚨 09-18 新增，给 `/api/reclog` 回传用——都是 Optional，
        //    旧数据(Keychain里已经存着的)解码时缺这几个键会自动落 nil，
        //    不需要自定义 Decodable，也不会让老条目解码失败。
        var peak: Double? = nil      // 这一轮的电平峰值（0~1）
        var zeroPct: Int? = nil      // 零采样点占比（0~100）
        var arming: Bool? = nil      // 触发这条记录那一刻 voice.arming 的值
        var fg: Bool? = nil          // 触发那一刻是不是前台（App 级 applicationState）
        var failStep: String? = nil  // 给后端的短枚举，不传就在回传时从 r 推
        // 🚨🚨 09-18 0要求：App 级状态(`fg`)和 Scene 级状态**必须分开记**——
        //    `AppDelegate.swift:1102` 09-16 就留了技术债注释：`startWhenTrulyActive()`
        //    等的是 App 级 `didBecomeActiveNotification`，起录 URL 走的是 Scene 级
        //    `scene(_:openURLContexts:)`，三个状态源没对齐可能就是"6秒必然超时"的
        //    真根因。这个字段是那条债第一次真正被记进能自动回传的地方。
        var scenePhase: String? = nil
    }

    // MARK: - Keychain

    private static func readRaw() -> String {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let d = out as? Data,
              let s = String(data: d, encoding: .utf8) else { return "[]" }
        return s
    }

    private static func writeRaw(_ s: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(s.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    // MARK: - 对外

    static func items() -> [Item] {
        guard let d = readRaw().data(using: .utf8),
              let a = try? JSONDecoder().decode([Item].self, from: d)
        else { return [] }
        return a
    }

    /// 记一条。**成功失败都记** —— 只记失败的话，
    /// 「这次到底有没有跑」这个问题永远答不上来。
    ///
    /// 🚨 新增的 5 个参数全部可选，**旧调用点一个字都不用改**——
    ///    只有 09-18 之后新写/改过的几个调用点会传结构化值，其余的
    ///    在回传时用 `mapResultToFailStep(r)` 从 `r` 这个中文短语现推。
    static func add(sec: Double, bytes: Int, result: String, detail: String,
                    peak: Double? = nil, zeroPct: Int? = nil,
                    arming: Bool? = nil, fg: Bool? = nil,
                    failStep: String? = nil, scenePhase: String? = nil) {
        var a = items()
        a.append(Item(t: Date().timeIntervalSince1970, sec: sec,
                      bytes: bytes, r: result, d: detail,
                      peak: peak, zeroPct: zeroPct, arming: arming, fg: fg,
                      failStep: failStep, scenePhase: scenePhase))
        if a.count > maxItems { a = Array(a.suffix(maxItems)) }
        if let d = try? JSONEncoder().encode(a),
           let s = String(data: d, encoding: .utf8) {
            writeRaw(s)
        }
        // 🚨🚨 0 09-18 要求：失败时自动回传一次，不等他去设置里点按钮。
        //    只有手动按钮＝还是要他动手＝等于没做这件事。
        //    🚨 判据用**白名单**（见 `isFailureResult`），别把"回传失败·"
        //    这条自己记的日志也算进去——那样一次真失败会导致
        //    "回传→失败→记一条→又算失败→又回传→…" 死循环。
        if isFailureResult(result) {
            uploadRecent()
        }
    }

    /// 值得自动触发一次回传的失败形态。**白名单，不是"非成功都算"**——
    /// 后者会把"回传失败·…"这条自己写的日志也吃进去，变成死循环。
    private static func isFailureResult(_ r: String) -> Bool {
        let set: Set<String> = ["起录闸放弃", "麦克风没收到声音·未上传",
                                "起录失败", "出稿失败", "重架被拒",
                                "冷启梯子兜底·两档都失败"]
        return set.contains(r) || r.hasPrefix("失败·")
    }

    /// 中文短语 → 给后端的短枚举。后端 `fail_step` 白名单只要短token，
    /// 不要长文本——这里只做**映射**，不传原始中文。
    private static func mapResultToFailStep(_ r: String) -> String {
        let table: [String: String] = [
            "重按重来": "retry_press",
            "收到起录URL": "gate_start",
            "起录闸放弃": "gate_timeout",
            "起录闸通过": "gate_pass",
            "起录成功": "success",
            "录到了但太短": "too_short",
            "起录失败": "start_fail",
            "麦克风没收到声音·未上传": "mic_silent",
            "已上传": "uploaded",
            "出稿完成": "success",
            "出稿失败": "deliver_fail",
        ]
        if let v = table[r] { return v }
        if r.hasPrefix("失败·") {
            let tail = r.dropFirst("失败·".count)
            return "fail_" + tail.lowercased()
                .replacingOccurrences(of: " ", with: "_")
        }
        return "other"
    }

    // MARK: - 回传 /api/reclog

    /// 把最近的条目回传给后端。**`d`(转写正文) 绝不传**——那是他说的话，
    /// 诊断只需要形态不需要内容。见 0 09-18 的三条硬约束。
    ///
    /// 🚨 判据是 HTTP 200，不是"发出去了"——发送失败要落一条本地记录，
    ///    否则"库里是空的"分不清是"没出过问题"还是"传不上去"。
    ///    这条记录的 result 不在 `isFailureResult` 白名单里，不会递归触发。
    static func uploadRecent(done: @escaping (Bool) -> Void = { _ in }) {
        let recent = items()
        guard !recent.isEmpty else { return done(true) }
        let rows: [[String: Any]] = recent.map { it in
            var o: [String: Any] = ["ts": it.t, "sec": it.sec, "bytes": it.bytes]
            var step = it.failStep ?? mapResultToFailStep(it.r)
            // 🚨🚨 09-18 0急需：Scene级状态没有独立的服务端白名单字段
            //    （新增字段会被后端静默丢弃，见1.1的约束），等不起再跟1.1
            //    协调加字段那一轮——直接拼进`fail_step`这个已经通的字段里。
            //    不优雅，但今晚就能让0在`/api/diag`里看到，不用等。
            if let sp = it.scenePhase { step += "_scene_" + sp }
            o["fail_step"] = step
            if let p = it.peak { o["peak"] = p }
            if let z = it.zeroPct { o["zero_pct"] = z }
            if let f = it.fg { o["fg_bg"] = f ? "foreground" : "background" }
            if let a = it.arming { o["arming"] = a ? 1 : 0 }
            return o
        }
        guard let url = URL(string: Backend.base + "/api/reclog"),
              let body = try? JSONSerialization.data(
                  withJSONObject: ["platform": "ios", "items": rows])
        else { return done(false) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 12
        req.setValue("application/json; charset=utf-8",
                     forHTTPHeaderField: "Content-Type")
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        req.httpBody = body
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            DispatchQueue.main.async {
                if code == 200 {
                    KbBridge.note("录音诊断回传：成功，共 " + String(rows.count) + " 条")
                    done(true)
                } else {
                    KbBridge.note("录音诊断回传：HTTP " + String(code) + " 失败")
                    // 🚨 不走 `add(...)` 的公开入口（会再判一次 isFailureResult，
                    //    这条本身就不在白名单里，直接调内部写入更清楚）。
                    var a = items()
                    a.append(Item(t: Date().timeIntervalSince1970, sec: 0, bytes: 0,
                                  r: "回传失败·HTTP" + String(code),
                                  d: "共 " + String(rows.count) + " 条没传上去"))
                    if a.count > maxItems { a = Array(a.suffix(maxItems)) }
                    if let d = try? JSONEncoder().encode(a),
                       let s = String(data: d, encoding: .utf8) {
                        writeRaw(s)
                    }
                    done(false)
                }
            }
        }.resume()
    }

    /// 给设置页显示用的文本。最新的在最上面。
    static func dump() -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return items().reversed().map { it in
            let when = f.string(from: Date(timeIntervalSince1970: it.t))
            // 🚨 格式只有一份，在 `RecLine` —— 判据挂在那儿才测得到
            //    「他粘出来的文本里到底有没有数」。
            return RecLine.render(when: when, sec: it.sec, bytes: it.bytes,
                                  result: it.r, detail: it.d)
        }.joined(separator: "\n")
    }

    static func clear() { writeRaw("[]") }
}
