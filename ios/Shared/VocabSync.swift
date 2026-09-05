import Foundation

/// 常用词的**云端同步**。逐条对应安卓 `VocabSync.java`。
///
/// 判据出处：`_后端_常用词接口_契约.md`（1.1）+ `_裁定_常用词客户端同步规则_20260902.md`（2.1）。
///
/// 🚨🚨 **判断都不在这里** —— 「503 算不算空」「能不能覆盖本地」「变更落在哪份上」
///    全在 `VocabCore`（三端共用的纯逻辑）。2.1 明写「不许三端各自发挥」，
///    写在网络层里三端必漂。这个文件只管**发请求和搬数据**。
///
/// 🚨 什么时候拉（SYNC-6）：
///    · App 启动拉一次  · 登录之后发一次 `merge`  · 本地有变更走 SYNC-1 三步
///    · **每次按麦克风之前绝对不许拉** —— 不能让他按一次麦克风多等一个网络往返。
///
/// 🚨 2026-09-04 补：iOS 之前**整个没有这一层**，安卓早就有了 ——
///    也就是他在安卓上加的常用词，iPhone 上看不到，反过来也一样。
///    这不是"按一期规格只存本地"，是**落后安卓一版**。
enum VocabSync {

    /// 一次拉取的结果。`kind` 是 `VocabCore.PULL_*`。
    struct Pulled {
        let kind: Int
        let terms: [VocabCore.Term]
    }

    private static let timeout: TimeInterval = 12

    // MARK: - 搬数据（跟 `KbBridge` 的存档用同一套字段）

    /// 🚨 `status` **始终写全，哪怕是 "on"**（跟 `KbBridge.saveVocab` 同一条理由）：
    ///    省略的话，另一台设备上的客户端做 replace 时会把 cand/no 抹平成 on。
    private static func toJson(_ terms: [VocabCore.Term]) -> [[String: Any]] {
        VocabCore.dedup(terms).map { t -> [String: Any] in
            var d: [String: Any] = ["id": t.id, "text": t.text, "kind": t.kind,
                                    "src": t.src, "at": t.at, "status": t.status]
            if t.count > 0 { d["count"] = t.count }
            return d
        }
    }

    private static func fromJson(_ arr: [[String: Any]]?) -> [VocabCore.Term] {
        (arr ?? []).compactMap { d in
            guard let t = d["text"] as? String, VocabCore.usable(t) else { return nil }
            return VocabCore.Term(
                id: (d["id"] as? String) ?? VocabCore.idOf(t),
                text: t,
                kind: VocabCore.kindOf(d["kind"] as? String),
                src: (d["src"] as? String) ?? VocabCore.SRC_MANUAL,
                at: (d["at"] as? Int64) ?? Int64((d["at"] as? Double) ?? 0),
                status: VocabCore.statusOf(d["status"] as? String),
                count: (d["count"] as? Int) ?? 0)
        }
    }

    // MARK: - 网络

    /// `GET /api/terms`。**不抛异常** —— 任何读不通都归成 `PULL_UNREACHABLE`。
    ///
    /// 🚨 归成"读不到"而不是"空的"，是 SYNC-3/SYNC-5 的全部要害：
    ///    1.1 特意让读不通回 503 而不是空列表，就是为了让客户端分得开。
    ///    这两种世界长得一模一样（都是"没拿到词"），但拿"读不到"去覆盖本地
    ///    就是**把他的词删光**。
    static func pull(_ done: @escaping (Pulled) -> Void) {
        guard let url = URL(string: Backend.base + "/api/terms") else {
            return done(Pulled(kind: VocabCore.PULL_UNREACHABLE, terms: []))
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = timeout
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            // 🚨 拿不到 HTTP 状态时用 **-1**，不是 0 也不是 200 ——
            //    `VocabCore.pullKind` 靠 `< 0` 认出"断网/超时"。
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            var anon = false
            var arr: [[String: Any]]? = nil
            if let d = data,
               let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                anon = (o["anon"] as? Bool) ?? false
                arr = o["terms"] as? [[String: Any]]
            }
            let kind = VocabCore.pullKind(code, anon: anon)
            // 🚨 **每次都留一行**：不留的话「本地没被冲掉」是个**空洞的通过** ——
            //    分不清是"判对了没覆盖"还是"这段代码压根没跑"。
            //    401/200 都是正常返回、不抛异常，没有这行就一条痕迹都没有。
            KbBridge.note("常用词拉取：HTTP \(code) anon=\(anon) -> kind=\(kind)"
                          + "（0=正常 1=未登录 2=读不到 3=鉴权）"
                          + " 条数=\(arr?.count ?? -1)")
            done(Pulled(kind: kind, terms: fromJson(arr)))
        }.resume()
    }

    /// `POST /api/terms`。回 true 表示**后端说存下了**。
    ///
    /// 🚨 判据是响应体里的 `saved`，**不是 HTTP 200** —— 后端可能 200 但没存
    ///    （比如超限静默截断）。拿状态码当成功是最典型的假检查。
    private static func push(_ terms: [VocabCore.Term], mode: String,
                             _ done: @escaping (Bool) -> Void) {
        guard let url = URL(string: Backend.base + "/api/terms"),
              let body = try? JSONSerialization.data(
                  withJSONObject: ["terms": toJson(terms), "mode": mode])
        else { return done(false) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json; charset=utf-8",
                     forHTTPHeaderField: "Content-Type")
        req.setValue(DeviceId.pass, forHTTPHeaderField: "X-Alex-Pass")
        req.httpBody = body
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard code >= 200, code < 300, let d = data,
                  let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
            else {
                KbBridge.note("常用词上传 HTTP \(code)（mode=\(mode)）：没存下")
                return done(false)
            }
            let saved = (o["saved"] as? Bool) ?? false
            KbBridge.note("常用词上传 mode=\(mode) \(terms.count) 条 -> saved=\(saved)")
            done(saved)
        }.resume()
    }

    // MARK: - 三个入口（SYNC-6）

    /// App 启动拉一次。**静默** —— 拉不到就当没这回事。
    ///
    /// 🚨 **只有 `canOverwriteLocal` 为真才覆盖本地**（SYNC-3/5）：
    ///    读不到、未登录，一律**保留本地那份，绝不清空**。
    ///    这里"什么都不做"是对的 —— 同类地方的错法是「拿回来的空列表存下去」，
    ///    代价是他自己加的词全没。
    static func pullAsync() {
        pull { p in
            guard VocabCore.canOverwriteLocal(p.kind) else { return }
            KbBridge.saveVocab(p.terms)
        }
    }

    /// 登录之后发一次 `merge` —— **唯一用 merge 的时刻**。
    ///
    /// 把未登录期间攒的本地词并上去；服务端做并集，两边的词都留着。
    /// 之后一律走 `pushChangeAsync` / `pushStatusAsync`。
    static func mergeAfterLoginAsync() {
        push(KbBridge.loadVocab(), mode: "merge") { ok in
            guard ok else { return }
            pull { p in
                guard VocabCore.canOverwriteLocal(p.kind) else { return }
                KbBridge.saveVocab(p.terms)
            }
        }
    }

    /// 本地加/删一个词之后的同步 —— **SYNC-1 那三步**。
    ///
    /// ```
    /// ① GET  拉云端全量
    /// ② 在【拉回来的那份】上应用这一次变更   ← 不是在本地那份上
    /// ③ POST mode=replace
    /// ```
    ///
    /// 🚨 为什么不能直接拿本地那份发 `replace`：**别的设备离线时加的词会被抹掉**
    ///    （SYNC-1b）。为什么不能只发 `merge`：**删除永远传播不出去**（SYNC-1a）。
    ///
    /// 🚨 拉不到就**不写**：宁可这次不同步，也不拿一份缺了别人词的表去覆盖云端。
    ///    本地那份已经改好了，下次启动还会再同步一次。
    /// 🚨 未登录（`PULL_ANON`）直接收工：本地存着就行，等他登录时 merge 上去。
    static func pushChangeAsync(added: VocabCore.Term?, removed: String?) {
        pull { p in
            guard p.kind == VocabCore.PULL_OK else { return }
            let merged = VocabCore.applyChange(p.terms, added: added,
                                               removed: removed)
            push(merged, mode: "replace") { ok in
                if ok { KbBridge.saveVocab(merged) }
            }
        }
    }

    /// 改一个词的态（收录/否掉/收回候选）之后的同步。同样是 SYNC-1 三步。
    static func pushStatusAsync(_ term: VocabCore.Term, _ status: String) {
        pull { p in
            guard p.kind == VocabCore.PULL_OK else { return }
            let merged = VocabCore.applyStatus(p.terms, term, status)
            push(merged, mode: "replace") { ok in
                if ok { KbBridge.saveVocab(merged) }
            }
        }
    }
}
