# -*- coding: utf-8 -*-
r"""把 iOS 键盘的源码 + CI 推到 Kevinyang0420/- 仓库。

用 contents API 逐文件写，不克隆 —— 那个仓库带游戏素材，克隆会超时（实测 5 分钟没完）。

    py push_ios.py
"""
import base64
import io
import json
import os
import re
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")
sys.stderr.reconfigure(encoding="utf-8")

OWNER, REPO, BRANCH = "Kevinyang0420", "-", "main"
HERE = os.path.dirname(os.path.abspath(__file__))
CTX = ssl.create_default_context()

# 🚨 这张表原来是**手写死的**，于是每加一个源文件就得记得回来补一行 ——
#    2026-08-21 就漏了 `Shared/Theme.swift`、`Shared/Speaker.swift` 和整个
#    `Assets.xcassets`：本地改了、CI 上编的还是旧代码，而且**推送本身不会报错**，
#    只有等 CI 编译失败（或编过了但图标是空白）才发现。
#    改成**从目录扫**：project.yml 里列到的每个 source 目录下的 .swift 全带上，
#    资源目录整个带上。清单只有一个来源，不会再走散。
SWIFT_DIRS = ["App", "Keyboard", "Shared", "Probe"]


def _asset_dirs():
    """资源表目录**不再手写** —— 从 project.yml 里真正列到的 `.xcassets` 推导。

    🚨 2026-08-25：这里原来是 `ASSET_DIRS = ["Assets.xcassets"]` 一行写死。
       当天把图表拆成 Assets(只给 App，含 AppIcon) + SharedAssets(两个 target 共用)
       之后，新那张表就落在推送范围外了 —— **本地改了、CI 编的还是旧的，而且推送不报错**。
       （下面 main() 里那道覆盖闸门当场把它抓出来了，不是靠我记得。）
       改成推导之后，加表只改 project.yml 一处。
    """
    proj = io.open(os.path.join(HERE, "project.yml"), encoding="utf-8").read()
    dirs = sorted({m.group(1).strip().strip('"\'')
                   for m in re.finditer(r"-\s+path:\s*(\S+)", proj)
                   if m.group(1).strip().strip('"\'').endswith(".xcassets")})
    if not dirs:
        sys.exit("FAIL: project.yml 里一张 .xcassets 都没解析到，这条推导自己失效了")
    return dirs


ASSET_DIRS = _asset_dirs()


def _res_dirs():
    """普通资源目录（码表等）—— 同样**从 project.yml 推导**，不手写。

    🚨 2026-08-28 实撞：`Resources`（拼音 dict.txt / 五笔 wubi.txt）
       在 project.yml 里被两个 target 收进来编，**却不在推送范围里**。
       表现是「本地改了码表、CI 编的还是旧的，而且推送不报错」——
       跟 2026-08-25 那次 SharedAssets 落在范围外是同一个错。
       （那次也是被 main() 里那道覆盖闸门抓出来的，不是靠我记得。）

    🚨 判据是"project.yml 里列到的、既不是 .xcassets 也不是 .swift 文件的
       那些 path"，所以以后再加一个资源目录只改 project.yml 一处。
    """
    proj = io.open(os.path.join(HERE, "project.yml"), encoding="utf-8").read()
    out = []
    for m in re.finditer(r"-\s+path:\s*(\S+)", proj):
        v = m.group(1).strip().strip("\"'")
        if v.endswith(".xcassets") or v.endswith(".swift"):
            continue
        if os.path.isdir(os.path.join(HERE, v)) and v not in SWIFT_DIRS:
            out.append(v)
    return sorted(set(out))


RES_DIRS = _res_dirs()
#: 码表这类纯文本资源放行的扩展名。**白名单**，不是黑名单 ——
#: 黑名单挡不住下一个没想到的垃圾文件。
RES_EXT = {".txt", ".json", ".dat"}
EXTRA = [
    ("project.yml",       "ios/project.yml"),
    ("prompt.txt",        "ios/prompt.txt"),
    ("prompt_zh.txt",     "ios/prompt_zh.txt"),
    ("contract_test.py",  "ios/contract_test.py"),
    ("sync_prompts.py",   "ios/sync_prompts.py"),
    # 🚨 CI 构建时用它从 ASC 现取描述文件（取代那两个 IOS_PROFILE_* secret）
    ("ci_fetch_profiles.py", "ios/ci_fetch_profiles.py"),
    # 🚨 上传后回 ASC 确认真的多了一个构建（altool 会打 ERROR 却返回 0）
    ("ci_verify_upload.py", "ios/ci_verify_upload.py"),
    ("ci-workflow.yml",   ".github/workflows/ios-keyboard.yml"),
    # 🚨 2026-08-25 补：这份**一直没在清单里**，全靠我手推 —— 也就是说它随时可能
    #    本地改了、远端还是旧的，而且不报错。加进来之后只有一个推送入口。
    ("ci-release-workflow.yml", ".github/workflows/ios-release.yml"),
]
# 这些绝不推：CI 自己生成，且含口令
NEVER = {"Shared/Secrets.swift"}
# 资源目录只放行这些扩展名，并挡掉 Windows/OneDrive 的垃圾文件
ASSET_EXT = {".png", ".jpg", ".jpeg", ".pdf", ".svg", ".json"}
JUNK = {"desktop.ini", "thumbs.db", ".ds_store"}


def collect():
    out = []
    for d in SWIFT_DIRS:
        base = os.path.join(HERE, d)
        if not os.path.isdir(base):
            continue
        for root, _, files in os.walk(base):
            for f in sorted(files):
                if not f.endswith((".swift", ".plist")):
                    continue
                full = os.path.join(root, f)
                rel = os.path.relpath(full, HERE).replace("\\", "/")
                if rel in NEVER:
                    continue
                out.append((rel, "ios/" + rel))
    for d in ASSET_DIRS:
        base = os.path.join(HERE, d)
        if not os.path.isdir(base):
            continue
        for root, _, files in os.walk(base):
            for f in sorted(files):
                # 🚨 这套代码就跑在 OneDrive 同步目录下：OneDrive 会生成 desktop.ini，
                #    浏览过图片目录会生成 Thumbs.db。不过滤就会被原样推成
                #    ios/Assets.xcassets/desktop.ini，asset catalog 编译会报错。
                if f.lower() in JUNK:
                    continue
                if os.path.splitext(f)[1].lower() not in ASSET_EXT:
                    continue
                full = os.path.join(root, f)
                rel = os.path.relpath(full, HERE).replace("\\", "/")
                out.append((rel, "ios/" + rel))
    for d in RES_DIRS:
        base = os.path.join(HERE, d)
        if not os.path.isdir(base):
            continue
        for root, _, files in os.walk(base):
            for f in sorted(files):
                if f.lower() in JUNK:
                    continue
                if os.path.splitext(f)[1].lower() not in RES_EXT:
                    continue
                full = os.path.join(root, f)
                rel = os.path.relpath(full, HERE).replace("\\", "/")
                out.append((rel, "ios/" + rel))
    for local, remote in EXTRA:
        if os.path.exists(os.path.join(HERE, local)):
            out.append((local, remote))
    return out


FILES = collect()


def gh(method, path, body=None):
    tok = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN", "")
    if not tok:
        sys.exit("GH_TOKEN 未设置")
    req = urllib.request.Request(
        "https://api.github.com" + path,
        data=json.dumps(body).encode("utf-8") if body is not None else None,
        headers={"Authorization": "Bearer " + tok,
                 "Accept": "application/vnd.github+json",
                 "User-Agent": "shuoyingwen-ios-push"},
        method=method)
    try:
        with urllib.request.urlopen(req, timeout=90, context=CTX) as r:
            return r.status, json.loads(r.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode("utf-8") or "{}")


def gate_swift_sanity():
    """闸门⓪：Swift 本地体检 —— 那些编译才会报、而这台编不了的低级错。

    🚨 2026-08-25：一轮 CI（十几分钟）就为了告诉我三件本地一秒能查的事：
       `onAppear()` 定义两次、`SetupViewController` 定义两次、
       `L.home_try_speak` 不存在。六条编译错**全是我那个补丁自己造成的**。
       Kevin 的原话：「两个跑完了都说……都等着出结果，一点反应都没有」。

    🚨 它**不替代 CI** —— 类型推断、协议一致性只有编译器知道。
       它只是把"一眼能看出来的"挡在十几分钟的前面。
    """
    import subprocess as _sp
    g = r"D:\_build\gate_swift_sanity.py"
    if not os.path.exists(g):
        print("⚠ 找不到 %s，跳过本地体检" % g)
        return
    r = _sp.run([sys.executable, g], capture_output=True, timeout=120)
    out = (r.stdout + r.stderr).decode("utf-8", "replace")
    if r.returncode != 0:
        print(out.strip())
        sys.exit("FAIL: Swift 本地体检没过 —— 先修掉再推，"
                 "别让 CI 花十几分钟告诉你这些")
    print("  Swift 本地体检                    PASS")


def main():
    gate_swift_sanity()
    # 闸门①：**Xcode 实际会编的每个目录**都必须在推送范围里。
    #
    # 🚨🚨 上一版这条是**同源自比的假检查**（cross review 2026-08-21 H2）：
    #    它拿 `SWIFT_DIRS` 走一遍得到 on_disk，再拿 `collect()`（同样走 SWIFT_DIRS）
    #    得到 listed，然后断言 on_disk ⊆ listed —— **代数恒成立**，
    #    任何输入都不可能让它失败。而清单改成扫目录之后，真正的风险早就转移到
    #    「SWIFT_DIRS 这张表 vs project.yml 里真正列的 source 目录」这一层，
    #    那一层当时根本没查。典型的「判据缺了一整个维度」。
    #
    # 正解：期望值取**独立来源** —— 从 project.yml 的 `sources:` 里解析出目录。
    listed = {l for l, _ in FILES}
    proj = io.open(os.path.join(HERE, "project.yml"), encoding="utf-8").read()
    declared = set()
    for m in re.finditer(r"-\s+path:\s*(\S+)", proj):
        p = m.group(1).strip().strip('"\'')
        top = p.split("/")[0]
        if os.path.isdir(os.path.join(HERE, top)):
            declared.add(top)
    if not declared:
        sys.exit("FAIL: 从 project.yml 解析不出任何 source 目录，闸门自己失效了")
    covered = (set(SWIFT_DIRS) | set(ASSET_DIRS) | set(RES_DIRS)
               | {l.split("/")[0] for l in listed})
    uncovered = sorted(declared - covered)
    if uncovered:
        sys.exit("FAIL: project.yml 里这些目录 Xcode 会编，但推送范围没覆盖，"
                 "CI 会编旧代码: %s" % uncovered)
    print("覆盖检查: project.yml 声明 %d 个目录(%s)，全在推送范围内 ✓"
          % (len(declared), "、".join(sorted(declared))))

    # 闸门②：推之前扫一遍，公开仓库里绝不许出现凭据。二进制资源跳过文本扫描。
    # 🚨 判据不能用裸子串。原来写 `"sk-" in text`，那么源码里任何 `risk-free`、
    #    `task-based`、`disk-cache` 都会中止整次推送，而人看到报错只会去找密钥、
    #    找不到（cross review M8）。改成带边界 + 要求后面真跟着一长串。
    SECRET_RE = re.compile(
        r"(?<![A-Za-z0-9])(?:sk|ark|ghp|gho|github_pat)[-_][A-Za-z0-9_\-]{16,}"
        r"|(?<![A-Za-z0-9])AKLT[A-Za-z0-9]{10,}")
    n_scanned = 0
    for local, _ in FILES:
        p = os.path.join(HERE, local)
        if os.path.splitext(p)[1].lower() in (".png", ".jpg", ".jpeg", ".car", ".pdf"):
            continue
        text = io.open(p, encoding="utf-8", errors="replace").read()
        m = SECRET_RE.search(text)
        if m:
            sys.exit("FAIL: %s 里像是有凭据（%s…）—— 这是公开仓库，中止"
                     % (local, m.group(0)[:12]))
        n_scanned += 1
    # 自检：这条判据必须能响，也必须不误伤
    assert SECRET_RE.search("sk-" + "a" * 30), "凭据正则失效了：真 key 都抓不到"
    assert not SECRET_RE.search("this is risk-free and task-based"), "凭据正则会误伤"
    print("密钥扫描: %d 个文本文件全干净 ✓（共 %d 个待推）" % (n_scanned, len(FILES)))

    # 闸门③：Secrets.swift 绝不能被推上去（它是 CI 生成的，含口令）
    if os.path.exists(os.path.join(HERE, "Shared", "Secrets.swift")):
        if "Shared/Secrets.swift" in listed:
            sys.exit("FAIL: Secrets.swift 混进推送清单了，中止")
        print("提醒: 本地有 Shared/Secrets.swift，已确认不在清单里 ✓")

    # 闸门⑤：workflow 里不许出现「裸 $变量 紧跟非 ASCII 字符」。
    #
    # 🚨 bash 会把紧跟着的多字节字符**吃进变量名**：`profile=「$NAME」`
    #    在 runner 上报 `NAME」: unbound variable`，而 `set -u` 之下直接退出。
    #    2026-08-25 run #5 整个死在这一行注释性的 echo 上。
    #    我这边的 Git Bash 不复现（本地根本不跑 workflow），所以只能靠这条静态闸门。
    #    解法一律加花括号：`${NAME}`。
    BARE = re.compile(r"\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7f]")
    hits = []
    for local, remote in EXTRA:
        if not local.endswith((".yml", ".yaml")):
            continue
        for i, ln in enumerate(io.open(os.path.join(HERE, local), encoding="utf-8"), 1):
            if BARE.search(ln):
                hits.append("%s:%d %s" % (local, i, ln.strip()[:110]))
    if hits:
        sys.exit("FAIL: workflow 里有裸 $变量 紧跟非 ASCII（bash 会连着吃进变量名），"
                 "改成 ${变量}：\n  " + "\n  ".join(hits))
    print("workflow 变量写法: 没有裸 $变量紧跟中文 ✓")
    # 闸门④：清掉远端的镜像残留。
    #
    # 🚨 这个推送脚本**只 PUT、从不 DELETE**。本地把一个文件挪走或删掉之后，
    #    远端那份会一直留着，CI 编的是「新的 + 旧的」两份合起来。
    #    2026-08-25 差点就中：图表拆成 Assets(只给 App) + SharedAssets(共用) 之后，
    #    远端旧的 `ios/Assets.xcassets/mic.imageset/` 还在 —— 两张表都定义 `mic`
    #    且都编进主 App，actool 会判成同名冲突，而**本地怎么跑都看不出来**。
    #
    # 只在**本脚本自己镜像的那几个目录**里清，别的路径一概不碰。
    MIRRORED = tuple("ios/%s/" % d for d in SWIFT_DIRS + ASSET_DIRS)
    listed_remote = {r for _, r in FILES}
    orphans = []
    for d in SWIFT_DIRS + ASSET_DIRS:
        stack = ["ios/" + d]
        while stack:
            cur = stack.pop()
            code, items = gh("GET",
                             "/repos/%s/%s/contents/%s?ref=%s"
                             % (OWNER, REPO, urllib.parse.quote(cur), BRANCH))
            if code != 200 or not isinstance(items, list):
                continue          # 目录远端还不存在，正常
            for it in items:
                if it.get("type") == "dir":
                    stack.append(it["path"])
                elif it.get("path") not in listed_remote:
                    orphans.append((it["path"], it["sha"]))
    if orphans:
        # 刹车：万一上面的清单算错了，别让它把整棵树删掉
        n_remote = len(listed_remote) + len(orphans)
        if len(orphans) > 0.4 * n_remote:
            sys.exit("FAIL: 算出 %d/%d 个远端文件是残留，比例高得不合理，"
                     "先人工核对再说：%s" % (len(orphans), n_remote,
                                        [p for p, _ in orphans][:10]))
        for path, sha in orphans:
            assert path.startswith(MIRRORED), "越界了，拒绝删 " + path
            code, res = gh("DELETE", "/repos/%s/%s/contents/%s"
                           % (OWNER, REPO, urllib.parse.quote(path)),
                           {"message": "说英文 iOS 键盘: 清残留 " + path,
                            "branch": BRANCH, "sha": sha})
            if code not in (200, 201):
                sys.exit("FAIL: 删残留 %s HTTP %s" % (path, code))
            print("  清残留 %-40s HTTP %s" % (path, code))
    else:
        print("残留检查: 远端没有本地已删掉的文件 ✓")

    ok = 0
    for local, remote in FILES:
        content = io.open(os.path.join(HERE, local), "rb").read()
        # 🚨 远端路径必须 URL 编码：资源是从 Windows/OneDrive 目录扫出来的，
        #    文件名带空格很常见，不编码请求行直接畸形（GitHub 返 400）；
        #    非 ASCII 更是在 http.client 里抛 UnicodeEncodeError，堆栈跟"推送"毫无关系。
        q = urllib.parse.quote(remote)
        code, info = gh("GET", f"/repos/{OWNER}/{REPO}/contents/{q}?ref={BRANCH}")
        sha = info.get("sha") if code == 200 else None
        body = {"message": f"说英文 iOS 键盘: {remote}",
                "branch": BRANCH,
                "content": base64.b64encode(content).decode("ascii")}
        if sha:
            body["sha"] = sha
        code, res = gh("PUT", f"/repos/{OWNER}/{REPO}/contents/{q}", body)
        if code not in (200, 201):
            sys.exit(f"FAIL: {remote} HTTP {code}: {json.dumps(res, ensure_ascii=False)[:250]}")
        print("  %-46s HTTP %s" % (remote, code))
        ok += 1

    print("\n推了 %d 个文件。" % ok)
    return 0


if __name__ == "__main__":
    sys.exit(main())
