# -*- coding: utf-8 -*-
r"""「这个 target 要不要 App Group」——**唯一真值，从 `project.yml` 现读**。

    python3 ios/wants_app_group.py Keyboard        # 打印 yes / no，找不到则 exit 2
    python3 ios/wants_app_group.py --for-bundle LiveActivity.appex

## 🚨 为什么要单独一个文件

2026-09-06 发版连挂两道闸，**两道都在拦同一个不存在的问题**：

```
ci_fetch_profiles.py   ✗ live 的描述文件不含 App Group
ci-release-workflow.yml ✗ LiveActivity.appex 的 entitlements 里没有 group.…
```

而 `project.yml` 里**只有 `Transless` 和 `Keyboard` 声明了
`com.apple.security.application-groups`，`LiveActivity` 压根没有**。
两道闸都把三个 target 一刀切了 —— 判据没写错，是**它们对"该不该有"的
认知跟工程文件不同源**。（同一时间 `dev_install.py` 还打印着
「LiveActivity.appex：不需要 App Group」，同一件事三处说法两样。）

修一处不算修：我先改了 `ci_fetch_profiles.py`，发版就往前走了一步、
然后撞上第二道一模一样的。**所以判据只留这一份，两边都调它。**

## 判据是双向的

- 工程里声明了 → 产物/描述文件里**必须有**
- 工程里没声明 → 产物/描述文件里**必须没有**（有了说明两边已经不同源）
- 工程里**找不到这个 target** → 返回 unknown，调用方必须报错。
  「找不到」不等于「不需要」—— 把未知当成否，就是那种永远不会失败的检查。
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KEY = "com.apple.security.application-groups"

# appex 文件名 → project.yml 里的 target 名。
# 🚨 只在这里写一次；shell 那边按 basename 查表，不再自己拼。
BUNDLE_TO_TARGET = {
    "Transless.app": "Transless",
    "Keyboard.appex": "Keyboard",
    "LiveActivity.appex": "LiveActivity",
    "ProbeKeyboard.appex": "ProbeKeyboard",
}


def wants(target_name, yml_text=None):
    """True=要 / False=不要 / None=project.yml 里找不到这个 target。"""
    if yml_text is None:
        with open(os.path.join(HERE, "project.yml"), encoding="utf-8") as f:
            yml_text = f.read()
    m = re.search(r"^  %s:[ \t]*$" % re.escape(target_name), yml_text, re.M)
    if not m:
        return None
    nxt = re.search(r"^  [A-Za-z_][A-Za-z0-9_]*:[ \t]*$", yml_text[m.end():], re.M)
    seg = yml_text[m.end(): m.end() + (nxt.start() if nxt else len(yml_text))]
    return KEY in seg


def selftest():
    """🚨 判据本身要能分辨 —— 三向各来一个样本，不是只跑好样本。"""
    yml = ("targets:\n"
           "  Alpha:\n"
           "    entitlements:\n"
           "      properties:\n"
           "        %s:\n"
           "          - group.x\n"
           "  Beta:\n"
           "    type: application\n"
           "    settings: {}\n" % KEY)
    cases = [("Alpha", True), ("Beta", False), ("Gamma", None)]
    bad = []
    for name, want in cases:
        got = wants(name, yml)
        if got is not want:
            bad.append("%s 期望 %r 得到 %r" % (name, want, got))
    # 真工程也过一遍：至少要有一个 True 和一个 False，否则解析八成整体失效
    real = {t: wants(t) for t in BUNDLE_TO_TARGET.values()}
    if True not in real.values():
        bad.append("真 project.yml 里一个 True 都没有 —— 解析可能整体失效：%r" % real)
    if False not in real.values():
        bad.append("真 project.yml 里一个 False 都没有 —— 解析可能整体失效：%r" % real)
    for b in bad:
        sys.stderr.write("FAIL " + b + "\n")
    if bad:
        return 1
    print("selftest 过：合成三向 + 真工程 %r" % real)
    return 0


def main(argv):
    if len(argv) > 1 and argv[1] == "--selftest":
        return selftest()
    if len(argv) > 2 and argv[1] == "--for-bundle":
        t = BUNDLE_TO_TARGET.get(os.path.basename(argv[2].rstrip("/")))
        if t is None:
            sys.stderr.write("FAIL 不认识这个 bundle：%s —— "
                             "新加了 appex 就要在 BUNDLE_TO_TARGET 里登记，"
                             "不许默默放行\n" % argv[2])
            return 2
    elif len(argv) > 1:
        t = argv[1]
    else:
        sys.stderr.write("用法：wants_app_group.py <Target> | --for-bundle <名字>"
                         " | --selftest\n")
        return 2
    r = wants(t)
    if r is None:
        sys.stderr.write("FAIL project.yml 里找不到 target「%s」—— "
                         "这条判据没有依据，不许当成\"不需要\"放行\n" % t)
        return 2
    print("yes" if r else "no")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
