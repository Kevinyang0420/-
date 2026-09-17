# -*- coding: utf-8 -*-
r"""🚨 换账号清本地数据 —— iOS / 安卓【两端判据一致性】闸门。

起因（2026-09-17 晨）：同一条规矩两端各写一份，安卓改对了、iOS 原封不动，
**而 iOS 的注释里还白纸黑字写着「跟安卓同一份语义，改这里必须两端一起改」**。
注释没有执行力，漂了也不会响 —— 这正是铁规
`feedback_same_rule_two_impls_drifts` 的活标本。

## 查什么（不查什么）

不解析两边的实现逻辑（那太脆，改个写法就误报）。查的是**两端自测里
钉下来的那张真值表**：每条断言都是一个 `(prev, new) -> 该不该清` 的样本，
两端的样本集必须**逐条相同**。

    iOS   Shared/Auth.swift            selftestAccountSwitch()
    安卓  AccountSwitchCheck.java      selfTest()

一端改了行为必然要改自己的自测（不然自测当场报红），于是这个闸门就会看到
两端真值表不一致 —— **漂移在这里现形**。

## 🚨 为什么这不是假检查

自问「什么输入能让它红」：把 iOS 那条 `prev==""` 的期望改回旧值（不清），
安卓仍是「要清」→ 真值表对不上 → 红。`--selftest` 里就是拿这个当坏样本。

自问「什么输入能让它绿」：两端真值表逐条相同。

判据挂的是**两端各自的源文件**，不是我手写的期望表 —— 手写期望表会变成
第三份实现，同样会漂。

用法：
    py gate_account_switch_parity.py              # rc=0 一致 / rc=1 漂了
    py gate_account_switch_parity.py --selftest   # 好样本过 + 坏样本响
"""
from __future__ import annotations

import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
IOS = os.path.join(HERE, "ios", "Shared", "Auth.swift")
AND = os.path.join(HERE, "android", "java", "com", "kevin", "transless",
                   "AccountSwitchCheck.java")

# iOS:   if  shouldClearOnSwitch(prev: "x", new: "y")   -> 期望「不该清」
#        if !shouldClearOnSwitch(prev: "x", new: "y")   -> 期望「该清」
RE_IOS = re.compile(
    r"""if\s*(!?)\s*shouldClearOnSwitch\(prev:\s*"([^"]*)"\s*,\s*new:\s*"([^"]*)"\s*\)""")
# 安卓: if  shouldClear("x", "y")  /  if !shouldClear("x", "y")
#       null 参数没有引号，单独认
RE_AND = re.compile(
    r"""if\s*\(\s*(!?)\s*shouldClear\(\s*(null|"[^"]*")\s*,\s*(null|"[^"]*")\s*\)\s*\)""")


def _lit(tok):
    """`null` 和 `""` 在这条规矩里是同一个输入（都是"没有上一个人"）。"""
    return "" if tok == "null" else tok.strip('"')


def truth_table(src, which):
    """-> {(prev, new): 该不该清}。

    🚨 `if !f(...) { return 报错 }` 的含义是「f 必须为真」-> 期望 = 该清。
       `if  f(...) { return 报错 }` 的含义是「f 必须为假」-> 期望 = 不该清。
    """
    out = {}
    rx = RE_IOS if which == "ios" else RE_AND
    for m in rx.finditer(src):
        neg = m.group(1) == "!"
        prev, new = _lit(m.group(2)), _lit(m.group(3))
        out[(prev, new)] = neg           # 带 ! => 期望该清
    return out


def call_sites(src, which):
    """数【函数名】在自测里被调了多少次 —— **不管什么写法**。

    🚨 2026-09-17·2.2 跑出来的真漏洞：`truth_table()` 只认
       `if [!]shouldClearOnSwitch(prev: "x", new: "y")` 这**一种字面写法**。
       存变量、`guard`、三元、`XCTAssert` …… 全都被**安静地吃掉**，
       而闸门照样报「两端判据逐条一致」。
       他嗂了一段 4 条老写法 + 1 条新写法的假源码，
       提取到 4 条、第 5 条的行为分歧静默消失。

    🚨 为什么不用他建议的「让自测自己声明跑了几条」：
       那个计数**要人同步维护**，而「改了一处忘了另一处」
       正是这个闸门要防的病本身 —— 用它做判据等于把病当药。
       数【函数名出现次数】不需要任何人维护，换什么写法都跑不掉。
    """
    fn = "shouldClearOnSwitch" if which == "ios" else "shouldClear"
    body = src
    # 只数自测函数里的；数不到就数全文（宁可多数不可少数）
    m = re.search(r"(selftestAccountSwitch|selfTest)\s*\(", src)
    if m:
        body = src[m.start():]
    n = 0
    for mm in re.finditer(re.escape(fn) + r"\s*\(", body):
        # 🚨 用 chr(10) 不写反斜杠字面量：这个文件今晚被 heredoc 吃过一次
        #    反斜杠（"\n" 变成了真换行），当场语法错误。
        line = body[body.rfind(chr(10), 0, mm.start()) + 1: mm.start()]
        if line.lstrip().startswith(("//", "*", "#", "/*")):
            continue        # 注释里的不算（项目铁规：查代码别连注释一起查）
        if re.search(r"(func|static)\s+$", line):
            continue        # 函数定义本身不算
        n += 1
    return n


def compare(t_ios, t_and):
    """-> (一致?, 差异行列表)"""
    diffs = []
    for k in sorted(set(t_ios) | set(t_and)):
        a, b = t_ios.get(k), t_and.get(k)
        if a == b:
            continue
        diffs.append((k, a, b))
    return (not diffs), diffs


def _fmt(v):
    return "\u8be5\u6e05" if v is True else ("\u4e0d\u8be5\u6e05" if v is False
                                             else "\u2014\uff08\u8fd9\u7aef\u6839\u672c\u6ca1\u8fd9\u6761\uff09")


def report(t_ios, t_and):
    ok, diffs = compare(t_ios, t_and)
    print("iOS  \u771f\u503c\u8868 %d \u6761\uff1a" % len(t_ios))
    for k in sorted(t_ios):
        print("   prev=%-4r new=%-4r -> %s" % (k[0], k[1], _fmt(t_ios[k])))
    print("\u5b89\u5353 \u771f\u503c\u8868 %d \u6761\uff1a" % len(t_and))
    for k in sorted(t_and):
        print("   prev=%-4r new=%-4r -> %s" % (k[0], k[1], _fmt(t_and[k])))
    print()
    if ok:
        print("=== \u2705 \u4e24\u7aef\u5224\u636e\u9010\u6761\u4e00\u81f4 ===")
        return 0
    print("=== \U0001f6a8 \u4e24\u7aef\u5224\u636e\u6f02\u4e86\uff0c%d \u5904 ===" % len(diffs))
    for (prev, new), a, b in diffs:
        print("   prev=%-4r new=%-4r   iOS: %-22s \u5b89\u5353: %s"
              % (prev, new, _fmt(a), _fmt(b)))
    print()
    print("   \U0001f6a8 \u4e00\u7aef\u6539\u4e86\u884c\u4e3a\u3001\u53e6\u4e00\u7aef\u6ca1\u8ddf\u4e0a\u3002")
    print("   \u8fd9\u6761\u89c4\u77e9\u7684\u6b63\u786e\u8bed\u4e49\uff1anew \u4e3a\u7a7a -> \u4e0d\u6e05\uff1b"
          "\u5176\u4f59\u53ea\u770b prev != new\u3002")
    print("   prev \u4e3a\u7a7a\uff08\u771f\u9996\u88c5 \u6216 \u4ece\u65e7\u7248\u672c\u5347\u7ea7\uff09**\u4e5f\u8981\u6e05** \u2014\u2014 "
          "\u6e05\u4e2a\u7a7a\u7684\u65e0\u5bb3\uff0c\u8be5\u6e05\u6ca1\u6e05\u662f\u771f\u4f1a\u5458 bug\u3002")
    return 1


SICK_IOS = '''
    static func selftestAccountSwitch() -> String? {
        if shouldClearOnSwitch(prev: "", new: "u1") { return "x" }
        if shouldClearOnSwitch(prev: "u1", new: "u1") { return "x" }
        if !shouldClearOnSwitch(prev: "u1", new: "u2") { return "x" }
        if shouldClearOnSwitch(prev: "u1", new: "") { return "x" }
    }
'''
CURED_IOS = '''
    static func selftestAccountSwitch() -> String? {
        if !shouldClearOnSwitch(prev: "", new: "u1") { return "x" }
        if shouldClearOnSwitch(prev: "u1", new: "u1") { return "x" }
        if !shouldClearOnSwitch(prev: "u1", new: "u2") { return "x" }
        if shouldClearOnSwitch(prev: "u1", new: "") { return "x" }
    }
'''
REF_AND = '''
    public static String selfTest() {
        if (!shouldClear("", "u1")) return "x";
        if (!shouldClear(null, "u1")) return "x";
        if (shouldClear("u1", "u1")) return "x";
        if (!shouldClear("u1", "u2")) return "x";
        if (shouldClear("u1", "")) return "x";
    }
'''


# 🚨 2026-09-17·2.2 实跑复现的逃逸样本：前 4 条是正则认识的字面写法，
#    第 5 条把结果存进变量再判 —— 正则提取不到，行为分歧静默消失。
#    这一段是**常驻坏样本**，不许删：它钉的是「闸门自己会不会瞎」。
ESCAPED_IOS = '''
    static func selftestAccountSwitch() -> String? {
        if !shouldClearOnSwitch(prev: "", new: "u1") { return "x" }
        if shouldClearOnSwitch(prev: "u1", new: "u1") { return "x" }
        if !shouldClearOnSwitch(prev: "u1", new: "u2") { return "x" }
        if shouldClearOnSwitch(prev: "u1", new: "") { return "x" }
        let r = shouldClearOnSwitch(prev: "U1", new: "u1")
        if r { return "x" }
    }
'''


def selftest():
    rc = 0
    t_and = truth_table(REF_AND, "and")
    cases = [("\u574f\u6837\u672c\u00b7iOS \u505c\u5728\u65e7\u884c\u4e3a\uff08\u5fc5\u987b\u7ea2\uff09",
              SICK_IOS, 1),
             ("\u597d\u6837\u672c\u00b7iOS \u8ddf\u5b89\u5353\u5bf9\u9f50\uff08\u5fc5\u987b\u7eff\uff09",
              CURED_IOS, 0)]
    for label, src, want in cases:
        ok, diffs = compare(truth_table(src, "ios"), t_and)
        got = 0 if ok else 1
        good = (got == want)
        print("  %s %-40s \u671f\u671b rc=%d \u5b9e\u5f97 rc=%d%s"
              % ("\u2713" if good else "\u2717", label, want, got,
                 ("   \u5dee\u5f02: %r" % (diffs[0][0],)) if diffs else ""))
        if not good:
            rc = 1

    # \U0001f6a8 \u53cd\u5411\u63a7\u5236\u7684\u53cd\u5411\u63a7\u5236\uff1a\u574f\u6837\u672c\u5fc5\u987b\u662f\u88ab
    #    \u3010prev \u4e3a\u7a7a\u3011\u90a3\u4e00\u6761\u62b3\u7ea2\u7684\uff0c\u4e0d\u662f\u78b0\u5de7\u88ab\u522b\u7684\u6761\u76ee\u5224\u7ea2\u3002
    _ok, diffs = compare(truth_table(SICK_IOS, "ios"), t_and)
    keys = [k for k, _a, _b in diffs]
    hit = ("", "u1") in keys
    print("  %s \u574f\u6837\u672c\u62b3\u7ea2\u7684\u662f prev=\"\" \u90a3\u4e00\u6761      \u5b9e\u5f97 %s"
          % ("\u2713" if hit else "\u2717", keys))
    if not hit:
        rc = 1

    # \ud83d\udea8\ud83d\udea8 2.2 \u8dd1\u51fa\u6765\u7684\u90a3\u4e2a\u6d1e\uff0c\u505a\u6210\u5e38\u9a7b\u574f\u6837\u672c\uff1a
    #    4 \u6761\u8001\u5199\u6cd5 + 1 \u6761\u3010\u5b58\u53d8\u91cf\u3011\u5199\u6cd5\u3002\u6b63\u5219\u53ea\u8ba4\u524d 4 \u6761\uff0c
    #    \u7b2c 5 \u6761\u7684\u884c\u4e3a\u5206\u6b67\u4f1a\u88ab\u5b89\u9759\u541e\u6389 \u2014\u2014 `call_sites` \u5fc5\u987b\u628a\u5b83\u6293\u51fa\u6765\u3002
    n_tbl = len(list(RE_IOS.finditer(ESCAPED_IOS)))
    n_call = call_sites(ESCAPED_IOS, "ios")
    ok = (n_call > n_tbl)
    print("  %s \u9003\u9038\u5199\u6cd5\u88ab\u6293\u4f4f\uff08\u8c03\u7528 %d \u6b21 vs \u63d0\u53d6 %d \u6761\uff09"
          "      \u671f\u671b\u8c03\u7528\u6570 > \u63d0\u53d6\u6570" % ("\u2713" if ok else "\u2717", n_call, n_tbl))
    if not ok:
        rc = 1

    # \ud83d\udea8 \u53cd\u5411\u63a7\u5236\uff1a\u6b63\u5e38\u5199\u6cd5\u4e0b\u4e24\u4e2a\u6570\u5fc5\u987b\u3010\u76f8\u7b49\u3011\uff0c
    #    \u5426\u5219\u8fd9\u6761\u65b0\u5224\u636e\u4f1a\u5bf9\u6240\u6709\u6587\u4ef6\u6052\u62a5\u7ea2 \u2014\u2014 \u90a3\u662f\u53e6\u4e00\u79cd\u5047\u68c0\u67e5\u3002
    n2_tbl = len(list(RE_IOS.finditer(CURED_IOS)))
    n2_call = call_sites(CURED_IOS, "ios")
    ok2 = (n2_call == n2_tbl)
    print("  %s \u6b63\u5e38\u5199\u6cd5\u4e0d\u8bef\u62a5\uff08\u8c03\u7528 %d vs \u63d0\u53d6 %d\uff09"
          "            \u671f\u671b\u76f8\u7b49" % ("\u2713" if ok2 else "\u2717", n2_call, n2_tbl))
    if not ok2:
        rc = 1
    return rc


#: \ud83d\udea8 iOS \u90a3\u4e00\u7aef\u3010\u5355\u72ec\u3011\u8be5\u957f\u4ec0\u4e48\u6837 \u2014\u2014 \u53ea\u5728 CI \u4e0a\uff08\u62ff\u4e0d\u5230\u5b89\u5353\u6e90\u7801\u65f6\uff09\u7528\u3002
#:    \u8fd9\u662f\u8fd9\u4efd\u89c4\u77e9\u7684**\u7b2c\u4e8c\u5904\u5b9e\u73b0**\uff0c\u6b63\u5e38\u60c5\u51b5\u4e0b\u4e0d\u8bb8\u7528\u5b83\u505a\u5224\u636e\uff08\u4f1a\u6f02\uff09\u3002
#:    \u5b83\u5b58\u5728\u7684\u552f\u4e00\u7406\u7531\uff1aCI \u4ed3\u5e93\u91cc**\u6ca1\u6709\u4efb\u4f55\u5b89\u5353\u6587\u4ef6**\uff08`push_ios.py` \u53ea\u63a8 ios/\uff09\uff0c
#:    \u4e24\u7aef\u6bd4\u5bf9\u5728\u90a3\u513f\u5fc5\u7136\u62ff\u4e0d\u5230\u53e6\u4e00\u534a\u3002**\u5b81\u53ef\u53ea\u9a8c\u4e00\u534a\u5e76\u8bf4\u6e05\u695a\uff0c\u4e5f\u4e0d\u8981\u9759\u9ed8\u8df3\u8fc7** \u2014\u2014
#:    \u9759\u9ed8\u8df3\u8fc7\u7684\u95f8\u95e8\u5728 CI \u4e0a\u6c38\u8fdc\u7eff\uff0c\u90a3\u6bd4\u6ca1\u6709\u95f8\u95e8\u66f4\u7cdf\u3002
IOS_EXPECTED = {
    ("", "u1"): True,      # prev \u4e3a\u7a7a\uff08\u771f\u9996\u88c5 \u6216 \u4ece\u65e7\u7248\u672c\u5347\u7ea7\uff09-> \u4e5f\u8981\u6e05
    ("u1", "u1"): False,   # \u540c\u8d26\u53f7\u91cd\u767b -> \u4e0d\u6e05\uff08\u4f1a\u628a\u4ed6\u81ea\u5df1\u7684\u8d44\u6599\u5220\u6389\uff09
    ("u1", "u2"): True,    # \u6362\u4e86\u4e0d\u540c\u8d26\u53f7 -> \u8981\u6e05
    ("u1", ""): False,     # newUid \u4e3a\u7a7a\uff08\u4e0d\u8be5\u53d1\u751f\u7684\u8c03\u7528\uff09-> \u4e0d\u6e05
}


def main():
    if "--selftest" in sys.argv:
        return selftest()
    if not os.path.exists(IOS):
        print("\U0001f6a8 \u627e\u4e0d\u5230 %s" % IOS)
        return 3

    # \ud83d\udea8 CI \u4e0a\u6ca1\u6709\u5b89\u5353\u6e90\u7801 \u2014\u2014 \u964d\u7ea7\u6210\u300c\u53ea\u9a8c iOS \u4e00\u534a\u300d\uff0c**\u4f46\u8981\u543c\u51fa\u6765**\uff0c
    #    \u4e0d\u8bb8\u5f53\u6210\u901a\u8fc7\u3002\u5224\u636e\u6765\u6e90\u89c1 IOS_EXPECTED \u4e0a\u9762\u90a3\u6bb5\u6ce8\u91ca\u3002
    if not os.path.exists(AND):
        t_ios = truth_table(io.open(IOS, encoding="utf-8").read(), "ios")
        print("\u26a0\ufe0f  \u62ff\u4e0d\u5230\u5b89\u5353\u6e90\u7801\uff08%s\uff09"
              " \u2014\u2014 **\u53ea\u9a8c iOS \u8fd9\u4e00\u534a**\uff0c"
              "\u4e24\u7aef\u4e00\u81f4\u6027\u8fd9\u4e00\u6761\u672c\u6b21\u6ca1\u67e5\u5230" % AND)
        bad = [(k, IOS_EXPECTED.get(k), t_ios.get(k))
               for k in sorted(set(IOS_EXPECTED) | set(t_ios))
               if IOS_EXPECTED.get(k) != t_ios.get(k)]
        for k in sorted(t_ios):
            print("   prev=%-4r new=%-4r -> %s" % (k[0], k[1], _fmt(t_ios[k])))
        if bad:
            print("=== \U0001f6a8 iOS \u81ea\u6d4b\u7684\u771f\u503c\u8868\u8ddf\u9884\u671f\u4e0d\u7b26\uff0c%d \u5904 ===" % len(bad))
            for k, want, got in bad:
                print("   prev=%-4r new=%-4r  \u5e94\u4e3a %-8s \u5b9e\u4e3a %s"
                      % (k[0], k[1], _fmt(want), _fmt(got)))
            return 1
        print("=== \u2705 iOS \u8fd9\u4e00\u534a\u8ddf\u9884\u671f\u4e00\u81f4"
              "\uff08\u5b89\u5353\u90a3\u4e00\u534a\u8bf7\u5728\u672c\u673a\u8dd1\u5168\u91cf\uff09===")
        return 0
    src_ios = io.open(IOS, encoding="utf-8").read()
    src_and = io.open(AND, encoding="utf-8").read()
    t_ios = truth_table(src_ios, "ios")
    t_and = truth_table(src_and, "and")

    # 🚨🚨 漏提取兜底（2026-09-17·2.2 跑出来的洞）：正则只认一种字面写法，
    #    换个写法（存变量／guard／三元／XCTAssert）就被**安静吃掉**，
    #    而闸门照样报「两端一致」—— 那是最坏的一种假检查：**它在漏的时候说通过**。
    #    判据：源码里函数名被调了几次，就该提取到几条。对不上 = 有写法逃逸了。
    # 🚨 比的是【正则匹配次数】不是【字典大小】——
    #    同一个语义可以被测两遍（安卓就有 shouldClear("","u1") 和
    #    shouldClear(null,"u1")，`_lit()` 把 null 和空串规整成同一个 key，
    #    5 次调用去重成 4 条）。拿去重后的大小去比 = **必然误报**，
    #    而误报比漏报更糟：它训练人无视这个闸门。我第一版就这么写错了。
    bad_count = False
    for who, src, _tbl, which in (("iOS", src_ios, t_ios, "ios"),
                                  ("安卓", src_and, t_and, "and")):
        n_call = call_sites(src, which)
        n_match = len(list((RE_IOS if which == "ios" else RE_AND).finditer(src)))
        if n_call != n_match:
            print("🚨 %s：自测里调了 %d 次，正则只提取到 %d 条 —— "
                  "有写法逃过了提取，闸门对那几条是【瞎的】。"
                  % (who, n_call, n_match))
            bad_count = True
    if bad_count:
        print("   修法：要么把那几条改回 `if [!]shouldClear…(prev: \"x\", new: \"y\")` 的写法，")
        print("   要么扩 truth_table 的模式 —— 但**不许无视这条红**，")
        print("   它说明真值表是不完整的，『逐条一致』这个结论当场作废。")
        return 1

    if not t_ios or not t_and:
        print("\U0001f6a8 \u6709\u4e00\u7aef\u4e00\u6761\u65ad\u8a00\u90fd\u6ca1\u63d0\u53d6\u5230"
              "\uff08iOS %d / \u5b89\u5353 %d\uff09\u2014\u2014 \u5199\u6cd5\u53d8\u4e86\uff0c"
              "\u8fd9\u4e2a\u95f8\u95e8\u5f53\u573a\u5931\u6548\uff0c\u5fc5\u987b\u62a5\u7ea2"
              % (len(t_ios), len(t_and)))
        return 1
    return report(t_ios, t_and)


if __name__ == "__main__":
    sys.exit(main())
