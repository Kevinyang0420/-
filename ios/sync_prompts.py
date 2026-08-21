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

PAIRS = [
    ("prompt.txt", engine.SYSTEM_PROMPT, "PASS 2 - STRUCTURE"),
    ("prompt_zh.txt", engine.TRANSCRIBE_PROMPT, "Chinese speech-cleanup engine"),
]


def main():
    ok = True
    for name, text, marker in PAIRS:
        p = HERE / name
        p.write_text(text, encoding="utf-8")
        back = p.read_text(encoding="utf-8")          # 读回真磁盘，不信 write 的返回
        same = (back == text)
        has_marker = marker in back
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
