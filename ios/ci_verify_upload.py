# -*- coding: utf-8 -*-
"""上传之后回 App Store Connect 确认**真的多了一个构建**。

## 为什么（2026-08-28 实撞，第二个"绿色的假象"）

上传那步写着 `set -euo pipefail`、`altool` 是最后一条命令 —— 看起来它一失败
整步就该红。**实际不是**：altool 打了

    ERROR: Failed to upload package.
    The bundle version must be higher than the previously uploaded version: '585'

**却返回退出码 0**，于是整个 CI 报 success，而 TestFlight 上一个新构建都没有。

🚨 **我差点把几小时前那个坏包当成"新包已发"** —— 因为我按"版本号最大的那个"
   去查。**判据必须挂在上传时间上，不是版本号排序。**

## 判据

**存在一个构建，版本号 == 本次的 `CFBundleVersion`，且上传时间在最近 `MAX_AGE_MIN` 分钟内。**

两个条件缺一不可：
- 只比版本号 → 上一次成功传的同号包会让它假绿
- 只比时间 → 别人同时传的别的包会让它假绿

需要环境变量：`ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_B64` / `WANT_BUILD`
"""
import base64
import datetime
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE = "com.kevin.transless"
MAX_AGE_MIN = 40
#: 苹果入库有延迟，轮询几次再判。
TRIES = 10
WAIT = 30


def token():
    import jwt
    now = int(time.time())
    p8 = base64.b64decode(os.environ["ASC_KEY_B64"]).decode("utf-8")
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now,
                       "exp": now + 900, "aud": "appstoreconnect-v1"},
                      p8, algorithm="ES256",
                      headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def api(path):
    req = urllib.request.Request(API + path, headers={
        "Authorization": "Bearer " + token(), "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def main():
    want = os.environ.get("WANT_BUILD", "").strip()
    if not want:
        print("::error::WANT_BUILD 没传 —— 判据不知道该找哪个构建")
        return 1
    st, r = api("/apps?limit=50")
    if st != 200:
        print("::error::列 App 失败 %s" % st)
        return 1
    hit = [d for d in r["data"] if d["attributes"]["bundleId"] == BUNDLE]
    if not hit:
        print("::error::找不到 %s" % BUNDLE)
        return 1
    app = hit[0]["id"]
    now = datetime.datetime.now(datetime.timezone.utc)
    for i in range(TRIES):
        st, r = api("/apps/%s/builds?limit=200" % app)
        if st != 200:
            print("::error::列构建失败 %s" % st)
            return 1
        rows = []
        for d in r.get("data", []):
            a = d["attributes"]
            up = a.get("uploadedDate") or ""
            rows.append((a.get("version"), up, a.get("processingState")))
        rows.sort(key=lambda x: x[1], reverse=True)
        print("第 %d 次查，最近三个：%s" % (i + 1, rows[:3]))
        for ver, up, state in rows:
            if ver != want or not up:
                continue
            try:
                t = datetime.datetime.fromisoformat(up.replace("Z", "+00:00"))
            except ValueError:
                continue
            age = (now - t).total_seconds() / 60
            # 🚨 版本号对上**且**是刚传的，两个条件缺一不可
            if age <= MAX_AGE_MIN:
                print("✅ 构建 %s 已入库（%.1f 分钟前，%s）" % (ver, age, state))
                return 0
            print("  版本对上但是 %.0f 分钟前的旧包 —— 不算数" % age)
        if i < TRIES - 1:
            time.sleep(WAIT)
    print("::error::等了 %d 分钟，App Store Connect 上没有出现刚上传的构建 %s"
          % (TRIES * WAIT // 60, want))
    print("::error::altool 可能打了 ERROR 却返回 0（2026-08-28 就是这样）——"
          "去看上一步的完整输出")
    return 1


if __name__ == "__main__":
    sys.exit(main())
