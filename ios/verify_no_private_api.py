# -*- coding: utf-8 -*-
"""私有 API 闸 —— 0 总协调写，判据不许下游改。

起因：2026-09-16 16:14 苹果第二次拒（Guideline 2.5.1），
拒信原文只点名 `LSApplicationWorkspace`。
🚨 但源码里一共有 **6 个私有类**（RBS/FBS/SBS 全家）——
   **苹果的自动扫描一次只报它撞到的第一个**，修一个放行、下一个再拒＝又一轮排队。
   所以这个闸一次扫全部。

🚨 两个「范围缺一整块」的坑，这个闸专门堵：
  ① **键盘扩展是独立的可执行文件** —— 只扫主 App 等于没扫。
     这里递归找包里每一个 Mach-O，一个都不放过。
  ② 只查符号表不够 —— `NSClassFromString("X")` 的 X 是**字符串字面量**，
     所以判据挂在 `strings` 上，跟苹果拒信自己给的方法一致。

用法（在 Mac 上跑）：
    python3 verify_no_private_api.py <Xxx.app 或解开的 Payload 目录>
    python3 verify_no_private_api.py --selftest
退出码 = 命中的符号数（0 才算过）。
"""
import os
import re
import subprocess
import sys

# 🚨 加新符号只加这里一处。别在别的脚本里再抄一份。
BANNED = [
    "LSApplicationWorkspace",      # 苹果 2026-09-16 点名的那个
    "LSApplicationProxy",
    "LSApplicationRecord",
    "LSBundleProxy",
    "RBSProcessHandle",            # RunningBoard
    "RBSProcessIdentifier",
    "RBSAuditToken",
    "FBSSystemService",            # FrontBoard
    "SBSAppSwitcherSystemService",  # SpringBoard
]

MACHO_MAGIC = (b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe",
               b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce",
               b"\xca\xfe\xba\xbe")


def is_macho(path):
    """🚨 判据挂在**文件头魔数**上，不是挂在扩展名/目录名上 ——
    可执行文件没有扩展名，按名字猜必然漏。"""
    try:
        with open(path, "rb") as f:
            return f.read(4) in MACHO_MAGIC
    except Exception:
        return False


def find_binaries(root):
    out = []
    if os.path.isfile(root):
        return [root] if is_macho(root) else []
    for dirpath, _, files in os.walk(root):
        for fn in files:
            p = os.path.join(dirpath, fn)
            if is_macho(p):
                out.append(p)
    return out


def scan(path):
    """返回 {符号: 次数}，只列非 0 的。

    🚨🚨 2026-09-16 · **`strings` 这条路已删除，别再加回来。**
    上一版是「有 `strings` 就用它，没有就自己扒字节」——**同一个判据两条实现**，
    而它们在两个平台上分叉了，分叉方向正好是最坏的那个：

        Windows（没有 strings）→ 走扒字节 → 坏样本全部命中 ✅
        macOS（有 strings）    → `strings -a` 对这些文件**一个串都不吐**
                               → 坏样本**全部漏掉** ❌

    也就是说：我在 Windows 上自测全绿，而**真正出包上架的那台 Mac 上这道闸是瞎的**，
    它会对着一个带私有符号的二进制报「干净」。
    是 CI 里那趟 `--selftest` 把它抓出来的 —— 这就是为什么闸门必须在
    **它真正要跑的那个环境里**先过自测（📖 `feedback_same_rule_two_impls_drifts`、
    `feedback_crash_reads_as_green`）。

    现在只有一条实现：**整个文件按字节搜**。符号名都是 ASCII，
    不依赖任何外部工具，跨平台结果完全一致。
    """
    data = open(path, "rb").read()
    return {s: data.count(s.encode("ascii")) for s in BANNED
            if s.encode("ascii") in data}


def run(root):
    bins = find_binaries(root)
    if not bins:
        print("\u2717 \u4e00\u4e2a Mach-O \u90fd\u6ca1\u627e\u5230\uff1a%s" % root)
        print("  \U0001f6a8 \u8fd9\u4e0d\u662f\u300c\u5e72\u51c0\u300d\uff0c\u662f**\u626b\u9519\u4e86\u76ee\u5f55**\u3002")
        return -1
    print("\u626b\u63cf %d \u4e2a\u53ef\u6267\u884c\u6587\u4ef6\uff1a" % len(bins))
    total = 0
    for b in bins:
        hits = scan(b)
        rel = os.path.relpath(b, root if os.path.isdir(root) else os.path.dirname(root))
        if hits:
            total += sum(hits.values())
            print("  \u2717 %s" % rel)
            for s, n in sorted(hits.items(), key=lambda kv: -kv[1]):
                print("      %-30s %d \u5904" % (s, n))
        else:
            print("  \u2713 %s" % rel)
    print()
    if total:
        print("=== \u79c1\u6709 API \u95f8 FAIL\uff1a\u5171 %d \u5904 ===" % total)
    else:
        print("=== \u79c1\u6709 API \u95f8\u5168\u8fc7\uff08%d \u4e2a\u53ef\u6267\u884c\u6587\u4ef6\u3001%d \u4e2a\u7b26\u53f7\u90fd=0\uff09==="
              % (len(bins), len(BANNED)))
    return total


def _selftest():
    """\U0001f6a8 \u597d\u6837\u672c\u8fc7 + \u574f\u6837\u672c\u54cd\uff0c\u4e24\u8fb9\u90fd\u9a8c\u624d\u7b97\u6d4b\u8fc7\u3002"""
    import tempfile
    rc = 0
    d = tempfile.mkdtemp(prefix="_papi_")
    head = MACHO_MAGIC[0]

    good = os.path.join(d, "Clean")
    open(good, "wb").write(head + b"\x00" * 64 + b"UIApplication__hello__world")
    n = run(good)
    print("\u597d\u6837\u672c\uff08\u5e72\u51c0\u4e8c\u8fdb\u5236\uff09 \u2192 %s\n" % ("PASS \u2705" if n == 0 else "FAIL \u274c"))
    if n != 0:
        rc = 1

    for sym in ("LSApplicationWorkspace", "RBSProcessHandle", "SBSAppSwitcherSystemService"):
        bad = os.path.join(d, "Bad_" + sym)
        open(bad, "wb").write(head + b"\x00" * 32 + sym.encode() + b"\x00extra")
        n = run(bad)
        print("\u574f\u6837\u672c %-28s \u2192 %s\n" % (sym, "\u54cd \u2705" if n > 0 else "\u6ca1\u54cd \u274c \u5047\u68c0\u67e5"))
        if n <= 0:
            rc = 1

    # 🚨 范围反向控制：扩展藏在子目录里，必须照样被扫到
    ext = os.path.join(d, "App", "PlugIns", "Keyboard.appex")
    os.makedirs(ext)
    open(os.path.join(ext, "Keyboard"), "wb").write(head + b"\x00" * 16 + b"FBSSystemService")
    open(os.path.join(d, "App", "MainApp"), "wb").write(head + b"\x00" * 16 + b"clean")
    n = run(os.path.join(d, "App"))
    print("\u8303\u56f4\u53cd\u5411\u63a7\u5236\uff08\u4e3bApp \u5e72\u51c0\u3001**\u952e\u76d8\u6269\u5c55\u810f**\uff09\u2192 %s"
          % ("\u54cd \u2705\uff08\u6ca1\u6f0f\u6389\u6269\u5c55\uff09" if n > 0 else "\u6ca1\u54cd \u274c \u53ea\u626b\u4e86\u4e3bApp"))
    if n <= 0:
        rc = 1

    # 🚨 非 Mach-O 不许被当成"干净"
    os.makedirs(os.path.join(d, "Empty"))
    open(os.path.join(d, "Empty", "readme.txt"), "w").write("LSApplicationWorkspace")
    n = run(os.path.join(d, "Empty"))
    print("\u7a7a\u76ee\u5f55\uff08\u53ea\u6709\u6587\u672c\u6587\u4ef6\uff09\u2192 %s"
          % ("\u62a5\u300c\u626b\u9519\u76ee\u5f55\u300d \u2705" if n == -1 else "\u8bef\u62a5\u6210\u5e72\u51c0 \u274c"))
    if n != -1:
        rc = 1

    # 🚨🚨 退出码也要自测 —— 上面五条判的全是 run() 的**返回值**，
    #    而 CI 和 preflight 判的是**退出码**。两者之间隔着一行 `sys.exit(...)`，
    #    2026-09-16 就是这一行把「没查成」压成了 0＝PASS。
    #    判据挂在**被使用的那个东西**上：调用方用退出码，就测退出码。
    print("\n--- 退出码自测（CI 真正读的是它，不是返回值）---")
    me = os.path.abspath(__file__)
    for label, target, want in (("干净二进制", good, 0),
                                ("脏二进制", os.path.join(d, "Bad_LSApplicationWorkspace"), 1),
                                ("扫错目录", os.path.join(d, "Empty"), 2)):
        got = subprocess.run([sys.executable, me, target],
                             capture_output=True).returncode
        ok = (got == want)
        print("  %s %-12s 期望 %d  实得 %d" % ("✓" if ok else "✗", label, want, got))
        if not ok:
            rc = 1
    return rc


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if "--selftest" in sys.argv:
        sys.exit(_selftest())
    if len(sys.argv) < 2:
        print("\u7528\u6cd5: verify_no_private_api.py <Xxx.app | Payload \u76ee\u5f55> | --selftest")
        sys.exit(2)
    # \ud83d\udea8\ud83d\udea8 2026-09-16 \u63a5\u8fdb CI \u4e4b\u524d\u6293\u5230\u7684\u81ea\u8eab\u7f3a\u9677\uff1a\u539f\u6765\u8fd9\u91cc\u5199
    #    `sys.exit(max(0, run(...)))` \u2014\u2014 run() \u626b\u9519\u76ee\u5f55\u8fd4\u56de -1\uff0c
    #    `max(0,-1)` \u628a\u5b83\u538b\u6210 **0\uff1dPASS**\u3002
    #    \u81ea\u6d4b\u91cc\u90a3\u6761\u300c\u7a7a\u76ee\u5f55 \u2192 \u62a5\u300e\u626b\u9519\u76ee\u5f55\u300f\u300d\u5224\u7684\u662f**\u8fd4\u56de\u503c**\uff0c
    #    \u800c CI \u5224\u7684\u662f**\u9000\u51fa\u7801**\uff0c\u4e24\u8005\u5728\u8fd9\u91cc\u6b63\u597d\u5206\u53c9\uff1a
    #    \u8def\u5f84\u4e00\u5199\u9519\uff0c\u8fd9\u9053\u95f8\u5c31\u4e00\u8def\u7eff\u5230\u82f9\u679c\u90a3\u513f\u3002
    #    \u2192 \u300c\u6ca1\u67e5\u6210\u300d\u5fc5\u987b\u6709\u81ea\u5df1\u7684\u975e\u96f6\u9000\u51fa\u7801\uff0c\u4e14\u8ddf\u300c\u67e5\u51fa\u810f\u4e1c\u897f\u300d\u533a\u5206\u5f00\u3002
    n = run(sys.argv[1])
    if n < 0:
        sys.exit(2)          # 2 = \u6ca1\u67e5\u6210\uff08\u626b\u9519\u76ee\u5f55/\u4e00\u4e2a Mach-O \u90fd\u6ca1\u6709\uff09
    sys.exit(1 if n else 0)  # 1 = \u67e5\u51fa\u79c1\u6709\u7b26\u53f7\uff1b0 = \u771f\u7684\u5e72\u51c0
