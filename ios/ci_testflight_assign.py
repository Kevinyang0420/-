# -*- coding: utf-8 -*-
r"""把刚上传的构建**分配给 TestFlight 测试组** —— 否则它装不到。

## 为什么需要这一步（2026-09-06 实撞）

链路上原来只做到「上传 → 确认进了 App Store Connect」，然后就当交付完成了。
但实测：
```
构建 1177.1   processingState = VALID   ← 处理完了
Kevin 的 TestFlight                     ← 仍然只有 08-28 的 734
```
**「进了 ASC」和「TestFlight 里能装」是两件事。** 中间还差一步：
构建必须被加进某个 beta 测试组，组里的人才看得见。

📌 今天这条链上，同一形状出现了四次：
```
CI 绿了        ≠ 包上去了      （上传那步是 skipped）
UPLOAD SUCCEEDED ≠ 进了 ASC    （被 ITMS-90683 拒，只有邮件说）
进了 ASC        ≠ 处理完了      （PROCESSING）
处理完了(VALID) ≠ 装得到        ← 就是这一步
```
**每一层都有一个"看起来成功"的信号，而下一层才是他真正要的东西。**

需要环境变量：`ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_B64` / `WANT_BUILD`
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE = "com.kevin.transless"
TRIES = 40
WAIT = 30


def token():
    import jwt  # pyjwt
    key = base64.b64decode(os.environ["ASC_KEY_B64"]).decode("utf-8")
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"],
                       "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
                      key, algorithm="ES256",
                      headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def api(path, method="GET", body=None):
    req = urllib.request.Request(
        API + path,
        data=json.dumps(body).encode("utf-8") if body is not None else None,
        headers={"Authorization": "Bearer " + token(),
                 "Content-Type": "application/json"},
        method=method)
    try:
        r = urllib.request.urlopen(req, timeout=60)
        raw = r.read()
        return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw.decode("utf-8", "replace")[:300]}


def main():
    want = os.environ["WANT_BUILD"]
    st, r = api("/apps?limit=200")
    if st != 200:
        print("::error::列 App 失败 %s" % st)
        return 1
    hit = [d for d in r["data"] if d["attributes"]["bundleId"] == BUNDLE]
    if not hit:
        print("::error::找不到 %s" % BUNDLE)
        return 1
    app = hit[0]["id"]

    # ── 等这个构建变成 VALID（PROCESSING 时还不能分配）──────────
    build_id = None
    for i in range(TRIES):
        st, r = api("/apps/%s/builds?limit=200" % app)
        if st != 200:
            print("::error::列构建失败 %s" % st)
            return 1
        for d in r.get("data", []):
            a = d["attributes"]
            if a.get("version") != want:
                continue
            state = a.get("processingState")
            if state in ("INVALID", "FAILED"):
                print("::error::构建 %s 被苹果判为 %s —— 分配没有意义，包要改"
                      % (want, state))
                return 1
            if state == "VALID":
                build_id = d["id"]
            print("第 %d 次：构建 %s 状态 %s" % (i + 1, want, state))
            break
        if build_id:
            break
        time.sleep(WAIT)
    if not build_id:
        print("::error::等了 %d 分钟，构建 %s 还没变成 VALID —— "
              "**这不是失败**，苹果处理慢的时候就这样；"
              "过一会儿手动跑一次分配即可。" % (TRIES * WAIT // 60, want))
        return 1

    # ── 找测试组 ────────────────────────────────────────────
    st, r = api("/apps/%s/betaGroups?limit=50" % app)
    if st != 200:
        print("::error::列测试组失败 %s %s" % (st, str(r)[:200]))
        return 1
    groups = r.get("data", [])
    if not groups:
        print("::error::这个 App **一个 beta 测试组都没有** —— "
              "构建就算 VALID 也没人装得到。")
        print("::error::要在 App Store Connect 的 TestFlight 里先建一个内部测试组"
              "（把自己加进去），这一步只能在网页上做一次。")
        return 1
    # 内部组优先：内部测试不需要审核，传完就能装
    internal = [g for g in groups
                if g["attributes"].get("isInternalGroup")] or groups
    ok = 0
    for g in internal:
        name = g["attributes"].get("name", "?")
        st, r = api("/builds/%s/relationships/betaGroups" % build_id,
                    method="POST",
                    body={"data": [{"type": "betaGroups", "id": g["id"]}]})
        if st in (200, 201, 204):
            print("✅ 构建 %s 已加入测试组「%s」" % (want, name))
            ok += 1
        else:
            print("::warning::加入「%s」失败 %s %s" % (name, st, str(r)[:200]))
    if ok == 0:
        print("::error::一个测试组都没加成 —— TestFlight 里仍然装不到")
        return 1
    print("这个构建现在在 %d 个测试组里，组里的人刷新 TestFlight 就能看到。" % ok)
    return 0


if __name__ == "__main__":
    sys.exit(main())
