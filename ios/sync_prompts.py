# -*- coding: utf-8 -*-
r"""把 engine.py 的两份 prompt 同步到 ios/prompt.txt 和 ios/prompt_zh.txt。

🚨 为什么要有这个脚本，而不是一行 `py -c`：
   2026-08-21 我用 `py -c "...(not Wednesday)..."` 同步，PowerShell 把
   括号里的内容当命令解析、整条挂掉，**文件根本没被写**，我却以为同步好了
   （后来靠 hash 比对才发现 iOS 那份还是旧的 3588 字符）。
   落成脚本 + 自带校验，就不会再有「命令悄悄没跑成」这种事。

判据：写完立刻读回来，跟 engine.py 的内容逐字节比对。
"""
import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")
HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
# 🚨🚨 **`engine` 只在本机有，CI 上没有**（`engine.py` 不在 iOS 仓库里，
#    `ci-workflow.yml` 里那段注释早就写过这件事）。
#    这个模块现在同时被 CI 调用（`secrets_body`），所以**顶层不许硬 import** ——
#    硬 import 的话 CI 一 `import sync_prompts` 就 ImportError，
#    而那正是我 2026-09-06 差点埋进去的雷：为了修「两个生成器走散」，
#    把一条「在 CI 上必然失败」的 import 写进了 CI。
#    → 同步（`main`）需要 engine；生成 `Secrets.swift` 只需要 .txt。**分开。**
try:
    import engine  # noqa: E402
except ImportError:
    engine = None

# 🚨🚨 **三份，不是两份**（2026-08-31 补）。
#    原来只同步翻译档和整理档，**逐字档 `PUNCT_PROMPT` 从来没同步过** ——
#    于是 iOS 那边压根没有它，只好走"直接短路不加标点"的老做法，
#    而那正是 Kevin 2026-08-23 在安卓上否掉的：
#    「它就真的是逐字记录，连逗号、句号这些标点符号都没有」。
#    **同一条规矩必须按每个出口落地**，少一个出口就等于那个平台没这条规矩。
#
# 🚨 第三列是特征串。它跟着 prompt 走 —— prompt 改了这里也要改，
#    否则会出现"内容同步对了、闸门却报 FAIL"（2026-08-31 就是这样：
#    engine.py 早把 "Chinese speech-cleanup engine" 改成了不带 Chinese 的版本，
#    这里还在找旧串）。**特征串要挑那种改文案也不会动的结构性标记。**
# 🚨 **文件名 + 特征串这一层不依赖 engine** —— CI 上要用它生成 Secrets.swift。
#    engine 里对应的变量名单独放在下面，本机同步时才需要。
FILES = [
    ("prompt.txt", "PASS 2 - STRUCTURE"),
    ("prompt_zh.txt", "speech-cleanup engine"),
    ("prompt_card.txt", "VERBATIM SUBSTRING"),
    # 🚨 查词提示词（2026-09-06 接进来）。原来 iOS 手写了两份中文的，
    #    跟 engine 那份是"手抄的近亲" —— 1.1 修好 engine 之后改动到不了这里，
    #    实测 register 填成了 finance/business（领域，不是语域）。
    #    特征串取 "DIRECTION" —— 它是这份 prompt 的结构骨架
    #    （让模型自己判中→英还是英→中），改文案不会动它。
    ("prompt_lookup.txt", "DIRECTION"),
    # 2026-09-06 补：这一份原来**没有特征串** —— CI 上拿不到 engine.py 时，
    #   逐字比对那层用不了，只剩特征串这层，而它是空的 = 这份文件无人看管。
    #   挑 "subsequence"：它是这份 prompt 的**技术不变量**（输出必须是输入的子序列），
    #   改文案不会把它改掉，改掉了就说明契约真的变了 —— 那时本来就该报。
    ("prompt_punct.txt", "subsequence"),
    ("prompt_asr.txt", "SAME language"),
]

_ENGINE_VARS = {
    "prompt.txt": "SYSTEM_PROMPT",
    "prompt_zh.txt": "TRANSCRIBE_PROMPT",
    "prompt_card.txt": "CARD_PROMPT",
    "prompt_lookup.txt": "LOOKUP_PROMPT",
    "prompt_punct.txt": "PUNCT_PROMPT",
    "prompt_asr.txt": "ASR_PROMPT",
}

# 🚨 `PAIRS` 需要 engine，所以只在本机成立；CI 上是空的（那边也用不到它）。
#    **判据别挂在 `PAIRS` 上** —— 它在 CI 上恒空，挂上去就是个永远不失败的检查。
PAIRS = ([(fn, getattr(engine, _ENGINE_VARS[fn]), mk) for fn, mk in FILES]
         if engine else [])



# --------------------------------------------------------------
# Secrets.swift 的**唯一生成实现**（2026-09-06）
# --------------------------------------------------------------
# 三个生成器（本机 Mac 构建 / ci-workflow / ci-release-workflow）一律调
# 下面这两个函数，成员表从 `FILES` 派生 —— 以后往 `FILES` 里加一份 prompt，
# 三处自动都有，不会再漏。
#
# 在这之前它们各写各的：本机 5 个成员、两份 CI 各 3 个，
# 而 Swift 用 5 个 → CI 出包必然 `cannot find 'promptPunct' in scope`。
#
# 这里**只读 .txt、不读 engine** —— `engine.py` 不在 iOS 仓库里，
# CI 上 import 不到（ci-workflow.yml 里那段注释已经写过这件事）。
# 逐字节比对由本机 `push_ios.py` 在推之前做，那才是能真失败的地方。


def member(filename):
    """`prompt_zh.txt` -> `promptZh`。成员名从文件名派生，不另写一张表。"""
    stem = filename[:-4] if filename.endswith(".txt") else filename
    head, *rest = stem.split("_")
    return head + "".join(w[:1].upper() + w[1:] for w in rest)


def secrets_body(root, password, json_str):
    """拼出整份 `Secrets.swift`。

    - `root`      : `ios/` 目录（pathlib.Path）
    - `json_str`  : 把 Python 字符串转成 Swift 字面量的函数（各处已有各自的）

    回 `(正文, 问题清单)`。清单非空时**调用方必须中止**，别写出半份。
    """
    bad = []
    lines = [
        "// 构建时生成，勿提交。提示词来自 ios/prompt*.txt（源头是 engine.py）。",
        "// 成员表由 sync_prompts.PAIRS 派生 —— 别在这里手加，加了会跟别处走散。",
        "enum Secrets {",
        "    static let pass = %s" % json_str(password),
    ]
    # 🚨 走 `FILES` 不走 `PAIRS` —— PAIRS 在 CI 上恒空（那边没有 engine），
    #    挂上去就是个永远不失败的检查。
    for fn, marker in FILES:
        p = root / fn
        if not p.exists():
            bad.append("%s 不存在 —— 是不是没推上来？" % fn)
            continue
        txt = p.read_text(encoding="utf-8")
        if marker and marker not in txt:
            bad.append("%s 缺结构性标记 %r —— 内容不对劲" % (fn, marker))
            continue
        lines.append("    static let %s = %s" % (member(fn), json_str(txt)))
    lines.append("}")
    return "\n".join(lines) + "\n", bad


def main():
    ok = True
    for name, text, marker in PAIRS:
        p = HERE / name
        p.write_text(text, encoding="utf-8")
        back = p.read_text(encoding="utf-8")          # 读回真磁盘，不信 write 的返回
        same = (back == text)
        has_marker = (marker in back) if marker else True
        print("  %-16s %5d 字符  逐字一致=%s  特征串=%s"
              % (name, len(back), "PASS" if same else "FAIL",
                 "PASS" if has_marker else "FAIL"))
        ok = ok and same and has_marker

    # 阴性对照：证明「逐字一致」这条查得动 —— 拿一份改过的比一比
    tampered = engine.SYSTEM_PROMPT + "x"
    caught = (tampered != (HERE / "prompt.txt").read_text(encoding="utf-8"))
    print("  %-16s %s" % ("阴性对照", "PASS" if caught else "FAIL 这条恒真"))
    ok = ok and caught

    print("=== %s ===" % ("两份 prompt 已同步" if ok else "同步有问题"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
