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
import engine  # noqa: E402

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
PAIRS = [
    ("prompt.txt", engine.SYSTEM_PROMPT, "PASS 2 - STRUCTURE"),
    ("prompt_zh.txt", engine.TRANSCRIBE_PROMPT, "speech-cleanup engine"),
    ("prompt_punct.txt", engine.PUNCT_PROMPT, ""),
    # 🚨 ASR 那一步的提示词（2026-08-31 提到 engine.py）。
    #    iOS 原来自己硬写了一句「只输出这段话的**中文**逐字转写」——
    #    他说英文时那句话会把模型往中文上拽。特征串挑 SAME language，
    #    因为那正是这一份存在的理由。
    ("prompt_asr.txt", engine.ASR_PROMPT, "SAME language"),
]


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
