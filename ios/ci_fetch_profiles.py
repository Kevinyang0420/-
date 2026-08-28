# -*- coding: utf-8 -*-
"""CI 构建时**从 App Store Connect 直接取描述文件**，不再走 GitHub secret。

## 为什么改成这样（2026-08-28 实撞，差点发出一个静默失效的包）

原来描述文件存在两个 secret 里（`IOS_PROFILE_APP_BASE64` / `IOS_PROFILE_KB_BASE64`）。
那天我在苹果那边给两个 App ID 挂上 App Group、重签了描述文件 ——
**secret 里还是旧的**。于是：

  · CI 构建 **success**
  · 导出的 IPA 里内嵌的描述文件**没有** `com.apple.security.application-groups`
  · 装到手机上 `containerURL(...)` 返回 nil → **键盘语音整条链静默失效**

**同一个东西有两个配置点，我只改了一个。** 而且这个错**全程没有任何红色**
—— 是我去拆 IPA 才发现的。

→ 现在只剩一个来源：**苹果那边的描述文件**。CI 每次构建现取。

## 判据（写在这里，工作流里那道闸照着查）

取回来的每一份都必须：
  · `application-identifier` 是期望的那个 bundle id（防两份装反）
  · **含 `com.apple.security.application-groups` 且包含我们那个组**

🚨 第二条就是这次抓到问题的那条。**让它每次构建都跑**，
   而不是靠人想起来去拆一次 IPA。

用法（CI 里）：
    python3 ci_fetch_profiles.py "$PROF_DIR"
需要环境变量：`ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_B64`（.p8 的 base64）
"""
import base64
import json
import os
import plistlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"

#: (落盘名, 描述文件名, 期望的 bundle id)
WANT = [
    ("app", "Transless AppStore", "com.kevin.transless"),
    ("kb", "Transless Keyboard AppStore", "com.kevin.transless.keyboard"),
]

#: 🚨 组名。**唯一真值在 `Shared/KbBridge.swift`**，这里从那个文件读，不写死。
def group_name():
    import re
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                     "Shared", "KbBridge.swift")
    s = open(p, encoding="utf-8").read()
    m = re.search(r'static let group\s*=\s*"([^"]+)"', s)
    if not m:
        sys.exit("FAIL: KbBridge.swift 里读不到 group —— 组名的唯一真值不见了")
    return m.group(1)


def token():
    import jwt  # pyjwt
    key_id = os.environ["ASC_KEY_ID"]
    issuer = os.environ["ASC_ISSUER_ID"]
    p8 = base64.b64decode(os.environ["ASC_KEY_B64"]).decode("utf-8")
    now = int(time.time())
    return jwt.encode({"iss": issuer, "iat": now, "exp": now + 900,
                       "aud": "appstoreconnect-v1"}, p8, algorithm="ES256",
                      headers={"kid": key_id, "typ": "JWT"})


def api(path):
    req = urllib.request.Request(
        API + path, headers={"Authorization": "Bearer " + token(),
                             "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def ents(raw):
    """从 .mobileprovision 里取 Entitlements。

    🚨 里面那段 plist 是**明文嵌在 CMS 里**的，直接找 `<plist>…</plist>` 就行。
    🚨 找不到就抛 —— **别返回空字典**，那样"解析失败"和"真的没有这一条"
       会长得一模一样，而这两件事该做的处置完全不同。
    """
    i, j = raw.find(b"<plist"), raw.find(b"</plist>")
    if i < 0 or j < 0:
        sys.exit("FAIL: 描述文件里找不到 plist 段（%d 字节）" % len(raw))
    d = plistlib.loads(raw[i:j + 8])
    e = d.get("Entitlements") or {}
    if "application-identifier" not in e:
        sys.exit("FAIL: 解析到的不是 Entitlements（键：%s）" % sorted(e)[:6])
    return d.get("Name", ""), e


def main():
    if len(sys.argv) < 2:
        sys.exit("用法: ci_fetch_profiles.py <描述文件目录>")
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    grp = group_name()
    print("组名（取自 KbBridge.swift）：%s" % grp)

    bad = []
    for tag, name, want_bid in WANT:
        st, res = api("/profiles?filter[name]=" + urllib.parse.quote(name))
        if st != 200:
            sys.exit("FAIL: 取描述文件失败 %s %s" % (st, str(res)[:200]))
        hit = [d for d in (res.get("data") or [])
               if d["attributes"].get("name") == name
               and d["attributes"].get("profileState") == "ACTIVE"]
        if not hit:
            sys.exit("FAIL: 苹果那边没有名为「%s」的 ACTIVE 描述文件" % name)
        raw = base64.b64decode(hit[0]["attributes"]["profileContent"])
        path = os.path.join(out_dir, tag + ".mobileprovision")
        open(path, "wb").write(raw)

        pname, e = ents(raw)
        aid = e["application-identifier"]
        bid = aid.split(".", 1)[1]
        groups = e.get("com.apple.security.application-groups") or []
        print("  %-3s %-30s bundle=%s" % (tag, "[%s]" % pname, bid))
        print("      app-groups = %s" % (groups or "（空）"))
        if bid != want_bid:
            bad.append("%s 的描述文件对应 %s，应为 %s（两份取反了？）"
                       % (tag, bid, want_bid))
        # 🚨 这条就是 2026-08-28 抓到"CI 用了旧描述文件"的那条判据。
        if grp not in groups:
            bad.append("%s 的描述文件**不含 App Group %s** —— "
                       "装到手机上键盘语音会静默失效" % (tag, grp))
        # 名字要回传给导出那步（两个 target 各挂各的，只能靠名字点名）
        gh_env = os.environ.get("GITHUB_ENV")
        if gh_env:
            var = "PROF_APP_NAME" if tag == "app" else "PROF_KB_NAME"
            with open(gh_env, "a", encoding="utf-8") as f:
                f.write("%s=%s\n" % (var, pname))

    if bad:
        for b in bad:
            print("::error::" + b)
        return 1
    print("两份描述文件都对，且都带着 %s" % grp)
    return 0


if __name__ == "__main__":
    sys.exit(main())
