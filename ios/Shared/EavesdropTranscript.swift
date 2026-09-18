import Foundation

/// 「旁听」会议的**逐段转写文本**落盘 —— 只存文字，不存音频。
///
/// 规格：`_规格_面对面旁听实时字幕_20260918.md` §6.1 第②点。
///
/// 🚨 存在的理由：现有整段录音（`Voice.swift`）和分段转写（`Segments.swift`）
///    都是**纯内存**——`Segments.Slot.text` 转完就一直留在那个实例里，进程被系统杀掉
///    （旁听一开就是几十分钟，后台存活没有保证）就整段会议的转写全部消失，包括
///    已经成功转完的那些段。规格要求把"最坏情况丢全部"降到"最坏情况丢最后未完成的
///    那一小段"——做法是**每一段转写成功就立刻追加落盘**，不等会议结束才写一次。
///
/// 🚨 **这不是改 `History.swift` 也不是改 `Segments.swift`**：
///    ① `History` 存的是"已经上屏的一句话"，跟会议转写是不同的数据、不同的生命周期
///      （旁听纪要要能整段删除，History 是永久滚动记录，语义不一样）。
///    ② `Segments` 是长录音听写和旁听**共用**的分段/去重逻辑，旁听要的"转完就落盘"
///      是旁听自己的新要求，长录音听写不需要——加进 `Segments` 会让不需要这条的
///      调用方也背上磁盘 I/O，所以旁听自己包一层，不动共用件。
///
/// 🚨 **音频本身不落盘**：`Backend.transcribe(wav:)` 直接把 `Data` base64 编码进
///    JSON body 发出去（`Backend.swift:1329`），`Voice.swift` 全文没有任何
///    `.write(to:)`/`createFile` —— 现有管线本来就没有把原始音频写过磁盘。
///    只要旁听复用这条既有管线（不额外发明自己的上传路径），§8.2「转写后不留音频」
///    这条**天然成立，不需要"删除并验证"那一步**——没写过的东西不需要删。
///    这条是**读代码验证过的事实**，不是推断；旁听的录音/上传实现完成后，
///    仍要在真机上抓一次进程的沙盒目录确认没有多出 wav/m4a 文件，才算闭环。
enum EavesdropTranscript {

    /// 一段会议的所有转写文本，放 **App Group** 的 Application Support，
    /// 一个会议一个文件：`eavesdrop_<sessionId>.jsonl`。
    ///
    /// 🚨 **每个会议单独一个文件，不是一个大文件里按 sessionId 过滤**——
    ///    结束一场会议要能整个删掉它的转写（存进笔记本之后，或用户放弃这场会议），
    ///    单独文件删除是 O(1) 且不会动到别的会议；共用一个文件还得先读全量再重写。
    ///
    /// 落点逻辑照抄 `History.fileURL()`：优先 App Group 共享容器，
    /// 拿不到（模拟器没装 entitlement）才回落本进程容器，且回落必须留痕。
    private static func fileURL(sessionId: String) -> URL? {
        let fm = FileManager.default
        let name = "eavesdrop_" + sanitize(sessionId) + ".jsonl"
        if let g = fm.containerURL(forSecurityApplicationGroupIdentifier: KbBridge.group) {
            let dir = g.appendingPathComponent("Library/Application Support/eavesdrop",
                                               isDirectory: true)
            if !fm.fileExists(atPath: dir.path) {
                try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            return dir.appendingPathComponent(name)
        }
        KbBridge.note("🚨 EavesdropTranscript 回落到本进程容器（App Group 拿不到）—— "
                      + "只应该在模拟器上发生")
        guard let dir = fm.urls(for: .applicationSupportDirectory,
                                in: .userDomainMask).first?
            .appendingPathComponent("eavesdrop", isDirectory: true) else { return nil }
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(name)
    }

    /// `sessionId` 进文件名前只留字母数字和下划线，防止意外传进路径分隔符。
    private static func sanitize(_ s: String) -> String {
        String(s.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? Character($0) : "_"
        })
    }

    /// 追加一段。**转写成功的回调里立刻调用**，不攒批。
    /// - Parameters:
    ///   - index: 这是这场会议的第几段（从 0 开始，跟 `Segments` 的段号对齐）。
    ///   - text: 这一段转出来的文字。
    static func append(sessionId: String, index: Int, text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = fileURL(sessionId: sessionId) else { return }
        let obj: [String: Any] = ["idx": index, "text": text,
                                   "ts": Date().timeIntervalSince1970]
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              var line = String(data: d, encoding: .utf8) else { return }
        line += "\n"
        guard let lineData = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            h.seekToEndOfFile()
            h.write(lineData)
        } else {
            try? lineData.write(to: url)
        }
    }

    /// 读出一场会议目前已经落盘的所有段，**按段号排序**（写入顺序未必等于段号顺序——
    /// 转写是并发发出去的，谁先回调谁先落盘）。
    static func readAll(sessionId: String) -> [(index: Int, text: String)] {
        guard let url = fileURL(sessionId: sessionId),
              let s = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [(Int, String)] = []
        for line in s.split(separator: "\n") {
            guard let d = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let idx = obj["idx"] as? Int,
                  let text = obj["text"] as? String else { continue }
            out.append((idx, text))
        }
        return out.sorted { $0.0 < $1.0 }
    }

    /// 会议收尾（存进笔记本，或用户主动放弃）之后删掉这份逐段转写。
    /// 🚨 **不是"删除音频"**——这份从来就不含音频，删的是文字草稿本身，
    ///    收尾后不再需要它，留着只是占地方。
    static func delete(sessionId: String) {
        guard let url = fileURL(sessionId: sessionId) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // ------------------------------------------------------------ 自测

    /// 由 `gate_all_selftests.py` 自动发现并运行。
    static func selfTest() -> String? {
        var bad: [String] = []
        let sid = "selftest_" + String(Int(Date().timeIntervalSince1970 * 1000))
        defer { delete(sessionId: sid) }

        // ① 乱序追加（模拟并发转写：段 1 比段 0 先回调），读出来必须按段号排好
        append(sessionId: sid, index: 1, text: "第二段")
        append(sessionId: sid, index: 0, text: "第一段")
        let r1 = readAll(sessionId: sid)
        if r1.map({ $0.text }) != ["第一段", "第二段"] {
            bad.append("排序：读出来没按段号排 -> \(r1)")
        }

        // ② 空文本不落盘（转写失败/空结果不该占一行）
        append(sessionId: sid, index: 2, text: "   ")
        if readAll(sessionId: sid).count != 2 {
            bad.append("空文本被落盘了")
        }

        // ③ 删除之后读出来是空的
        delete(sessionId: sid)
        if !readAll(sessionId: sid).isEmpty {
            bad.append("delete 之后还能读到内容")
        }

        // ④ 不同 sessionId 互不干扰
        let sidB = sid + "_b"
        append(sessionId: sid, index: 0, text: "会议A")
        append(sessionId: sidB, index: 0, text: "会议B")
        let onlyA = readAll(sessionId: sid).map { $0.text }
        let onlyB = readAll(sessionId: sidB).map { $0.text }
        if onlyA != ["会议A"] || onlyB != ["会议B"] {
            bad.append("两场会议串档了 -> A=\(onlyA) B=\(onlyB)")
        }
        delete(sessionId: sidB)

        return bad.isEmpty ? nil : bad.joined(separator: "; ")
    }
}
