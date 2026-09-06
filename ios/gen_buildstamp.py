# -*- coding: utf-8 -*-
r"""生成 `Shared/BuildStamp.swift`（包戳）—— **模板只有这一份**。

    python3 ios/gen_buildstamp.py [戳]      # 不给戳就用当前时间 MMDD-HHMMSS

## 🚨 为什么要有这个文件（2026-09-06 事故）

包戳原来只由 `D:\_build\mac.py sync()` 在 **Mac 上**现写。于是：

```
Mac（我编、我装机）      有 Shared/BuildStamp.swift  → 编得过
GitHub（CI 编）          没有                        → cannot find 'BuildStamp' in scope
```

**这个洞藏了很久没人撞到**，因为我一直走 Mac 出包、CI 又红着。
`push_ios.py` 的「源码目录覆盖闸」也放行了它 —— 那道闸查的是
**project.yml 声明的目录在不在推送范围**，而 `Shared/` 明明在范围内；
真正的风险是「Mac 上有、本地没有的**文件**」，闸门量的对象不对。

## 🚨 为什么不在 CI 的 yml 里再抄一份模板

那就是「同一规矩两处实现」，改一处等于没改 —— 今天 `push_ios.py`
（`D:\_build` 一份旧副本 + iOS 目录一份带闸门的）刚栽过同一跤。
`mac.py` 和两个 workflow **都调这个脚本**，模板只在这里。
"""
import datetime
import io
import os
import sys

HEAD = "// 由 ios/gen_buildstamp.py 生成，别手改。"


def body(stamp):
    """Swift 源码正文。**只有这一处定义它长什么样。**"""
    return "\n".join([
        HEAD,
        "enum BuildStamp {",
        "    /// 这个包是什么时候构建的。**启动时写进面包屑**，用来确定",
        "    /// 他机上跑的到底是哪一版 —— `CFBundleVersion` 写死了，分辨不出。",
        '    static let value = "%s"' % stamp,
        "}",
    ]) + "\n"


def main(argv):
    stamp = argv[1] if len(argv) > 1 else \
        datetime.datetime.now().strftime("%m%d-%H%M%S")
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "Shared", "BuildStamp.swift")
    io.open(out, "w", encoding="utf-8", newline="\n").write(body(stamp))

    # 🚨 判据是**回读到这个戳**，不是"我写了"。
    back = io.open(out, encoding="utf-8").read()
    if stamp not in back:
        sys.stderr.write("FAIL 包戳没写进去：%s\n" % stamp)
        return 1
    if "enum BuildStamp" not in back:
        sys.stderr.write("FAIL 写出来的不是 BuildStamp\n")
        return 1
    sys.stdout.write("BuildStamp.swift 包戳 %s\n" % stamp)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
