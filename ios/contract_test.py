# -*- coding: utf-8 -*-
r"""
契约测试：Swift 客户端接受的 HTTP 状态码，必须覆盖后端真实返回的。

为什么要有这个：
2026-08-20 真机上报 "HTTP 202" 失败。后端提交 job 返回的是 202 Accepted，
而 Swift 里写死了 `code == 200`。
🚨 我自己的 Python 验证脚本**根本没查状态码**，直接读 j['job'] 就往下走 ——
   所以 Python 一路绿灯，Swift 在真机上才炸。
   这是典型的假检查：两边判据不一致时，宽松的那边先通过、掩盖了严格那边的问题。
判据必须挂在**真实被使用的那个对象**（Swift 源码）上，不能只测我方便测的那个。

用法：py contract_test.py
"""
import io
import json
import os
import re
import sys
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")

HERE = os.path.dirname(os.path.abspath(__file__))
SWIFT = os.path.join(HERE, "Shared", "Backend.swift")
COACH = r"D:\OneDrive\OneDrive - personal\OneDrive\Claude\english_coach"
BASE = "https://sqg75i2mlmanf4sqde6nh.apigateway-cn-beijing.volceapi.com"


def swift_accepted_codes():
    """从 Swift 源码里抠出它在提交 job 那步接受哪些状态码。"""
    src = io.open(SWIFT, encoding="utf-8").read()
    m = re.search(r"guard\s+(code\s*==\s*\d+(?:\s*\|\|\s*code\s*==\s*\d+)*)", src)
    if not m:
        raise SystemExit("FAIL: 在 Backend.swift 里找不到状态码判断，测试本身失效了")
    return sorted(int(x) for x in re.findall(r"\d+", m.group(1)))


def backend_submit_code():
    """真打一次后端，看提交 job 到底返回什么状态码。"""
    sys.path.insert(0, COACH)
    cwd = os.getcwd()
    os.chdir(COACH)
    try:
        import deploy_vefaas as dv
        res = dv.call("GetFunction", "2021-03-03", {"Id": "a6w6d6bm"}).get("Result", {})
        pw = {e["Key"]: e["Value"] for e in res.get("Envs", [])}["ALEX_PASS"]
    finally:
        os.chdir(cwd)

    body = json.dumps({"messages": [{"role": "user", "content": "hi"}],
                       "max_tokens": 10}, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        BASE + "/api/llm", data=body, method="POST",
        headers={"Content-Type": "application/json; charset=utf-8", "X-Alex-Pass": pw})
    resp = urllib.request.urlopen(req, timeout=40)
    return resp.status, json.loads(resp.read().decode("utf-8"))


def check_assets():
    """两条，方向相反：

    A. 凡是调用 `UIImage(named:)`/`Theme.micGlyph` 的 target，它的 sources 里必须有
       **一张真的装着 mic.imageset 的** asset catalog。
       🚨 2026-08-21 补：键盘扩展是独立 bundle，`UIImage(named:)` 只找自己 bundle 里的
          资源。漏配时**编译照样通过**、按钮静默变空白，只有装到手机上才看得出来。
       🚨 2026-08-25 改：原来写死查「路径叫不叫 Assets.xcassets」。拆表之后那个判据会
          对着正确的配置报 FAIL —— 判据要挂在**素材在不在**，不是**目录叫什么名**。

    B. app-extension 的 sources 里**不许**出现装着 AppIcon.appiconset 的 catalog。
       理由是体积和语义：appex 有自己的 bundle，把容器 App 的图标打进去纯属白搭。
       ⚠️ 更正（2026-08-25）：这条**当初是按错误的诊断加的** —— 我以为 CI 那个
          `No simulator runtime version ...` 是 appex 渲染 AppIcon 引起的，
          于是拆表 + 加这道闸门。结果 run #3 照挂，报错对象换成了只装 mic 的
          SharedAssets，证明跟 AppIcon 无关（真根因是 Xcode 版本，见 CI 那份 yml）。
          闸门留着，因为它守的规矩本身成立；但**它不是那个构建错误的防线**，
          别下次看到同样的报错就来查这里。
    """
    proj = io.open(os.path.join(HERE, "project.yml"), encoding="utf-8").read()
    # 按 target 切块：顶格两空格的 `  <名字>:` 是一个 target 的起点
    blocks = {}
    cur = None
    in_targets = False
    for line in proj.splitlines():
        if line.startswith("targets:"):
            in_targets = True
            continue
        if not in_targets:
            continue
        m = re.match(r"^  ([A-Za-z][\w]*):\s*$", line)
        if m:
            cur = m.group(1)
            blocks[cur] = []
        elif cur:
            blocks[cur].append(line)

    # 哪些 target 的源码里真的用到了图片资源
    需要 = set()
    for name, lines in blocks.items():
        paths = re.findall(r"-\s+path:\s*(\S+)", "\n".join(lines))
        for p in paths:
            d = os.path.join(HERE, p)
            if not os.path.isdir(d):
                continue
            for root, _, files in os.walk(d):
                for f in files:
                    if not f.endswith(".swift"):
                        continue
                    s = io.open(os.path.join(root, f), encoding="utf-8").read()
                    if "UIImage(named:" in s or "Theme.micGlyph" in s:
                        需要.add(name)

    def catalogs(name):
        pat = "-" + chr(92) + "s+path:" + chr(92) + "s*(" + chr(92) + "S+)"
        return [p for p in re.findall(pat, "\n".join(blocks[name]))
                if p.endswith(".xcassets")]

    def 装着(cat, item):
        return os.path.exists(os.path.join(HERE, cat, item, "Contents.json"))

    # A. 用图的 target 都拿得到 mic
    results = []
    for name in sorted(需要):
        results.append((name, any(装着(c, "mic.imageset") for c in catalogs(name))))

    # B. app-extension 里不许混进 AppIcon（见上面 docstring 的原因）
    leaks = []
    for name, lines in sorted(blocks.items()):
        if not any(l.strip() == "type: app-extension" for l in lines):
            continue
        bad = [c for c in catalogs(name) if 装着(c, "AppIcon.appiconset")]
        leaks.append((name, bad))

    # 素材本身在不在（不写死目录 —— 全簿扫，拆表时判据不会跟着腐化）
    mic_ok = any(装着(d, "mic.imageset")
                 for d in os.listdir(HERE) if d.endswith(".xcassets"))
    return results, mic_ok, len(需要), leaks


def check_two_level():
    """两级 Tab 必须跟安卓对齐（Kevin：两端一起改）。

    🚨🚨 2026-08-25 大改。原来查的是「源码里有没有这四个中文字面量」，
       两处都错了：

       一、**措辞早就换过了**。原来找的是「结构化转写／逐字转录」——
          那正是被他否掉的说法，现在是「整理／逐字」。闸门守着一份作废的答案，
          于是对着正确的界面报 FAIL。
       二、**再也不该查文案**。文案现在从 `D:/_build/i18n_map.py` 生成
          （安卓、iOS 共用一份），拿 `Strings.swift` 跟它比是**同源自比**，
          永远相等，查了等于没查。

    所以这条只查**接线**：两级结构、四个按钮各自挂的是哪个文案 key。
    这是生成器管不着、只能靠人手写、因而真会写错的那一层。
    """
    src = io.open(os.path.join(HERE, "App", "AppDelegate.swift"),
                  encoding="utf-8").read()

    # 🚨 只数 **tab** 开头的成员：那一排里除了两个 Tab 还挂着 logoView，
    #    数「arrangedSubviews 有几项」会把 logo 算成第三个 Tab（2026-08-21 撞过）。
    #    判据要说清查的是什么对象，不是数一排里有几个东西。
    m = re.search(r"UIStackView\(arrangedSubviews:\s*\[([^\]]*)\]\)", src)
    items = [x.strip() for x in m.group(1).split(",") if x.strip()] if m else []
    n_tabs = len([x for x in items if x.startswith("tab")])

    # 按钮 -> 文案 key：从 `for (b, t, sel) in [(按钮, L.key, #selector(…)), …]` 里取
    wiring = dict(re.findall(r"\(\s*(\w+)\s*,\s*L\.(\w+)\s*,\s*#selector", src))

    # 第二级那一排的成员
    m2 = re.search(r"subStack = UIStackView\(arrangedSubviews:\s*\[([^\]]*)\]\)", src)
    subs = [x.strip() for x in m2.group(1).split(",") if x.strip()] if m2 else []

    want_top = ["kb_translate", "kb_transcribe"]
    want_sub = ["kb_polish", "kb_verbatim"]
    got_top = [wiring.get(x, "<没接>") for x in items if x.startswith("tab")]
    got_sub = [wiring.get(x, "<没接>") for x in subs]

    # 四个 key 在文案表里真的有定义（改名/漏生成时这里会响）
    st = io.open(os.path.join(HERE, "Shared", "Strings.swift"), encoding="utf-8").read()
    missing = [k for k in want_top + want_sub
               if not re.search(r"static var %s\s*:" % re.escape(k), st)]

    return n_tabs, got_top, got_sub, want_top, want_sub, missing


def check_mic_bar():
    """说话键必须是**正圆**且居中（跟安卓 MIC_CIRCLE_DP 那条对应）。

    🚨 这条改过两次方向：先是长条，后来 Kevin 把说明行删掉后又要圆的。
       判据永远跟着**当前的意图**走，别留着上一轮的：
         ① 宽高都引用同一个 Theme.micBarHeight（正圆）
         ② 水平居中（不是左右拉满）
    """
    src = io.open(os.path.join(HERE, "App", "AppDelegate.swift"),
                  encoding="utf-8").read()
    code = "\n".join(ln for ln in src.splitlines()
                     if not ln.strip().startswith(("//", "///", "*", "/*")))
    square = ("micButton.widthAnchor.constraint(equalToConstant: Theme.micBarHeight)" in code
              and "micButton.heightAnchor.constraint(equalToConstant: Theme.micBarHeight)" in code)
    centered = "micButton.centerXAnchor" in code
    not_full = "micButton.leadingAnchor" not in code
    return square and centered and not_full, square, centered, not_full, ""


def check_tones():
    """iOS 那份语气表必须跟 engine.py 一模一样（顺序也要一样）。

    🚨 iOS 没走构建期生成，语气表是**手抄的第三份**。靠"记得改三处"必然走散 ——
       2026-08-21 安卓已经并成三档时，iOS 还留着四档、带着已经删掉的「正式」。

    🚨🚨 2026-08-25 大改，两处病根：

    一、**查错了对象**。原来只读 `App/AppDelegate.swift`，而
        `Keyboard/KeyboardViewController.swift` ——**他真正在用的那个界面**——
        一直留着 `["work","email","casual","formal"]`，四档，闸门从没看过它一眼。
        现在 iOS 侧的语气表收进 `Shared/Prompts.all` 一处，
        并且**反过来查**：任何界面文件再写字面量数组就 FAIL。

    二、**判据没跟上那层间接**。标签早就改成 `L.tone_casual` 走本地化表了，
        闸门还在拿它跟中文字面量比，于是对着正确的代码报 FAIL。
        现在穿过 `Shared/Strings.swift` 取简体那一栏再比。
    """
    import importlib.util
    eng_path = os.path.join(os.path.dirname(HERE), "engine.py")
    spec = importlib.util.spec_from_file_location("engine_for_gate", eng_path)
    eng = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(eng)

    # 1) 唯一一份档位表
    pr = io.open(os.path.join(HERE, "Shared", "Prompts.swift"), encoding="utf-8").read()
    m = re.search(r"static let all = \[([^\]]*)\]", pr)
    got_c = [x.strip().strip('"') for x in m.group(1).split(",")] if m else []

    # 2) 标签穿过本地化表取简体那一栏（s(简, en, 繁) 的第一个参数）
    st = io.open(os.path.join(HERE, "Shared", "Strings.swift"), encoding="utf-8").read()
    got_l = []
    for c in got_c:
        mm = re.search(r'static var tone_%s: String \{ s\("([^"]*)"' % re.escape(c), st)
        got_l.append(mm.group(1) if mm else "<缺 tone_%s>" % c)

    # 3) 🚨 反向闸门：界面文件不许再自己写一份字面量档位表
    offenders = []
    for root, _, files in os.walk(HERE):
        for f in files:
            if not f.endswith(".swift"):
                continue
            fp = os.path.join(root, f)
            s = io.open(fp, encoding="utf-8").read()
            if re.search(r"let tones\s*(:[^=]*)?=\s*\[\s*\"", s):
                offenders.append(os.path.relpath(fp, HERE).replace("\\", "/"))

    want_c = list(eng.TONES)
    want_l = [eng.TONE_LABELS[k] for k in eng.TONES]
    ok = got_c == want_c and got_l == want_l and not offenders
    return ok, got_c, got_l, want_c, want_l, offenders


def check_langs():
    """iOS 的目标语言表必须跟 engine.LANGS 一一对应（顺序也要一样）。

    🚨 跟语气那条同型：iOS 是**手抄的第三份**。2026-08-21 加粤语时，
       engine 和安卓都加了，iOS 差点漏掉 —— 加语言要改三处，靠记性必然走散。
    """
    import importlib.util
    eng_path = os.path.join(os.path.dirname(HERE), "engine.py")
    spec = importlib.util.spec_from_file_location("engine_for_lang_gate", eng_path)
    eng = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(eng)
    src = io.open(os.path.join(HERE, "Shared", "Backend.swift"), encoding="utf-8").read()
    seg = src[src.find("static let langs"):]
    seg = seg[:seg.find("\n    ]") + 6]
    got = re.findall(r'\("([a-z]{2,3})",\s*"([^"]+)"', seg)
    got_c = [c for c, _ in got]
    got_l = [l for _, l in got]
    want_c = list(eng.LANGS)
    want_l = [eng.LANGS[k][0] for k in eng.LANGS]
    return got_c == want_c and got_l == want_l, got_c, want_c


def main():
    print("--- 版式闸门（不联网） ---")
    tone_ok, gc, gl, wc, wl, offenders = check_tones()
    if tone_ok:
        detail = "PASS %s" % "/".join(gl)
    elif gc != wc:
        detail = "FAIL 档位 iOS=%s 应为 %s" % (gc, wc)
    elif gl != wl:
        detail = "FAIL 标签 iOS=%s 应为 %s" % (gl, wl)
    else:
        detail = "FAIL 这些文件自己另写了一份档位表：%s" % ", ".join(offenders)
    print("  %-28s %s" % ("语气档位跟 engine.py 一致", detail))
    lang_ok, glc, wlc = check_langs()
    print("  %-28s %s" % ("目标语言跟 engine.py 一致",
                          "PASS %d 种" % len(glc) if lang_ok
                          else "FAIL iOS=%s 应为 %s" % (glc, wlc)))
    if not tone_ok or not lang_ok:
        print("\n=== 版式闸门未过 ===")
        return 1
    bar_ok, square, centered, not_full, _ = check_mic_bar()
    print("  %-28s %s" % ("说话键是正圆且居中",
                          "PASS" if bar_ok else
                          "FAIL 等宽高=%s 居中=%s 没左右拉满=%s"
                          % (square, centered, not_full)))
    if not bar_ok:
        print("\n=== 版式闸门未过 ===")
        return 1

    n_tabs, got_top, got_sub, want_top, want_sub, missing = check_two_level()
    two = n_tabs == 2
    print("  %-28s %s" % ("第一级 Tab 恰好 2 个(现 %d)" % n_tabs,
                          "PASS" if two else "FAIL"))
    top_ok = got_top == want_top
    print("  %-28s %s" % ("第一级接的文案 key 对",
                          "PASS %s" % "/".join(got_top) if top_ok
                          else "FAIL 现为 %s 应为 %s" % (got_top, want_top)))
    sub_ok = got_sub == want_sub
    print("  %-28s %s" % ("第二级接的文案 key 对",
                          "PASS %s" % "/".join(got_sub) if sub_ok
                          else "FAIL 现为 %s 应为 %s" % (got_sub, want_sub)))
    no_miss = not missing
    print("  %-28s %s" % ("四个 key 在文案表里有",
                          "PASS" if no_miss else "FAIL 缺 %s" % missing))
    if not (two and top_ok and sub_ok and no_miss):
        print("\n=== 版式闸门未过 ===")
        return 1

    print("\n--- 资源闸门（不联网） ---")
    targets, mic_ok, n, leaks = check_assets()
    ok = True
    if n == 0:
        print("  FAIL 一个用图的 target 都没扫到 —— 闸门自己失效了")
        ok = False
    for name, has in targets:
        print("  %-28s %s" % ("target %s 带 Assets" % name, "PASS" if has else "FAIL"))
        ok = ok and has
    print("  %-28s %s" % ("mic.imageset 存在", "PASS" if mic_ok else "FAIL"))
    ok = ok and mic_ok
    if not leaks:
        print("  FAIL 一个 app-extension 都没扫到 —— AppIcon 闸门自己失效了")
        ok = False
    for name, bad in leaks:
        print("  %-28s %s%s" % ("appex %s 不带 AppIcon" % name,
                                "PASS" if not bad else "FAIL",
                                "" if not bad else "  ← " + ", ".join(bad)))
        ok = ok and not bad
    if not ok:
        print("\n=== 资源闸门未过，真机上图标会是空白 ===")
        return 1

    print("")
    print("--- 设备令牌闸门（不联网） ---")
    _bk = open(os.path.join(HERE, "Shared", "Backend.swift"), encoding="utf-8").read()
    _ad = open(os.path.join(HERE, "App", "AppDelegate.swift"), encoding="utf-8").read()
    _ok1 = "Secrets.pass" not in _bk
    _ok2 = "DeviceId.pass" in _bk
    _ok3 = os.path.exists(os.path.join(HERE, "Shared", "DeviceId.swift"))
    _ok4 = "DeviceId.ensure" in _ad
    print("  Backend 不再用共享口令        %s" % ("PASS" if _ok1 else "FAIL"))
    print("  Backend 改用设备令牌          %s" % ("PASS" if _ok2 else "FAIL"))
    print("  DeviceId.swift 存在          %s" % ("PASS" if _ok3 else "FAIL"))
    print("  App 启动时触发注册            %s" % ("PASS" if _ok4 else "FAIL"))
    ok = ok and _ok1 and _ok2 and _ok3 and _ok4

    print("\n--- 契约测试（要联网） ---")
    accepted = swift_accepted_codes()
    print("Swift 接受的状态码 : %s" % accepted)

    code, body = backend_submit_code()
    print("后端实际返回       : %s  keys=%s" % (code, list(body)))

    hit = code in accepted
    print("  %-28s %s" % ("客户端接受后端的返回码", "PASS" if hit else "FAIL"))
    ok = ok and hit

    has_job = "job" in body
    print("  %-28s %s" % ("返回体里有 job id", "PASS" if has_job else "FAIL"))
    ok = ok and has_job

    # 阴性对照：证明这个检查会分辨，不是恒真
    fake = 599
    print("  %-28s %s" % ("阴性对照(599 不该被接受)",
                          "PASS" if fake not in accepted else "FAIL 恒真"))
    ok = ok and (fake not in accepted)

    print("\n=== %s ===" % ("契约一致" if ok else "契约不一致，真机会炸"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
