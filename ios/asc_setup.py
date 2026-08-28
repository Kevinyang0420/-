# -*- coding: utf-8 -*-
"""用 App Store Connect API 一把梭：建 Bundle ID → 建证书 → 建描述文件 → 下载 → 出 Secrets。

🚨 Kevin 只需要做一件事：在 App Store Connect 生成一把 API 密钥（3 次点击），
   把 .p8 文件丢进本目录。**其余全部由本脚本完成，不用进开发者后台点任何东西。**

依赖：pip install pyjwt cryptography

用法：
    py asc_setup.py            # 全流程
    py asc_setup.py --check    # 只检查凭据齐不齐，不做任何创建
"""
import base64
import glob
import io
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

HERE = os.path.dirname(os.path.abspath(__file__))
CERT_DIR = r"D:\ShareDrive\ios_cert"
API = "https://api.appstoreconnect.apple.com/v1"

APP_BID = "com.kevin.transless"
KB_BID = "com.kevin.transless.keyboard"
P12_PW = "transless"


# ----------------------------------------------------------- 凭据
def load_creds():
    """从 CERT_DIR 读 .p8 私钥 + key.json（含 key_id / issuer_id）。"""
    p8s = glob.glob(os.path.join(CERT_DIR, "AuthKey_*.p8"))
    meta_path = os.path.join(CERT_DIR, "asc_key.json")
    if not p8s:
        return None, "没找到 AuthKey_XXXX.p8（把从 App Store Connect 下载的密钥放进 %s）" % CERT_DIR
    p8 = p8s[0]
    key_id = os.path.basename(p8).replace("AuthKey_", "").replace(".p8", "")
    issuer = ""
    if os.path.exists(meta_path):
        try:
            issuer = json.load(open(meta_path, encoding="utf-8-sig")).get("issuer_id", "")
        except Exception:
            pass
    if not issuer:
        issuer = os.environ.get("ASC_ISSUER_ID", "")
    if not issuer:
        return None, ("找到密钥 %s，但缺 Issuer ID。\n"
                      "  → 在 %s 建一个 asc_key.json，内容：\n"
                      '     {"issuer_id": "在 App Store Connect 密钥页顶部那串"}'
                      % (os.path.basename(p8), CERT_DIR))
    return {"p8": p8, "key_id": key_id, "issuer": issuer}, None


def make_token(c):
    import jwt  # pyjwt
    key = open(c["p8"], "r").read()
    now = int(time.time())
    payload = {"iss": c["issuer"], "iat": now, "exp": now + 1200,
               "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, key, algorithm="ES256",
                      headers={"kid": c["key_id"], "typ": "JWT"})


def api(c, method, path, body=None):
    tok = make_token(c)
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + tok,
                                          "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw.decode("utf-8", "replace")[:400]}


def err_text(res):
    errs = res.get("errors") or []
    if errs:
        return "; ".join((e.get("title", "") + ": " + e.get("detail", "")) for e in errs)[:300]
    return str(res)[:300]


# ----------------------------------------------------------- 步骤
def ensure_bundle_id(c, identifier, name):
    """🚨 Apple 的 `filter[identifier]` **不是精确匹配**（2026-08-25 实测）。

    查 `com.kevin.transless` 会把 `com.kevin.transless.AX3W379KV8` 一起返回 ——
    那个是当初用 SideStore/Sideloadly 侧载时自动建的（`tprobe`、`shuoyingwen`、
    `SideStore` 都有同样的 `.<TeamID>` 后缀）。
    上一版直接取 `data[0]` 还打印「✓ 已存在」，于是**主 App 的描述文件绑到了一个
    根本不存在于工程里的 Bundle ID 上**，一路到 CI 导出时才会炸，
    而那时的报错跟这里毫无关系。判据必须落在 `attributes.identifier` 的**逐字相等**上。
    """
    code, res = api(c, "GET", "/bundleIds?filter[identifier]=" + identifier)
    exact = [d for d in (res.get("data") or [])
             if d["attributes"].get("identifier") == identifier] if code == 200 else []
    others = [d["attributes"].get("identifier") for d in (res.get("data") or [])
              if d["attributes"].get("identifier") != identifier]
    if others:
        print("  ⓘ 同名前缀的还有 %s（不是我们要的，已忽略）" % others)
    if exact:
        print("  ✓ Bundle ID 已存在: %s" % identifier)
        return exact[0]["id"]
    code, res = api(c, "POST", "/bundleIds", {
        "data": {"type": "bundleIds",
                 "attributes": {"identifier": identifier, "name": name,
                                "platform": "IOS"}}})
    if code in (200, 201):
        print("  ✓ Bundle ID 已创建: %s" % identifier)
        return res["data"]["id"]
    print("  ✗ 建 Bundle ID 失败 (%s): %s" % (code, err_text(res)))
    return None


def ensure_cert(c):
    """有可用的 Distribution 证书就复用，没有就用本地 CSR 新建。"""
    code, res = api(c, "GET", "/certificates?filter[certificateType]=IOS_DISTRIBUTION")
    if code == 200 and res.get("data"):
        d = res["data"][0]
        print("  ✓ 已有 Distribution 证书，复用: %s"
              % d["attributes"].get("name", "")[:50])
        return d["attributes"]["certificateContent"]

    csr_path = os.path.join(CERT_DIR, "ios.csr")
    if not os.path.exists(csr_path):
        print("  ✗ 缺 %s（CSR）" % csr_path)
        return None
    csr = open(csr_path).read()
    csr_b64 = csr.replace("-----BEGIN CERTIFICATE REQUEST-----", "") \
                 .replace("-----END CERTIFICATE REQUEST-----", "") \
                 .replace("\n", "").replace("\r", "").strip()
    code, res = api(c, "POST", "/certificates", {
        "data": {"type": "certificates",
                 "attributes": {"certificateType": "IOS_DISTRIBUTION",
                                "csrContent": csr_b64}}})
    if code in (200, 201):
        print("  ✓ Distribution 证书已创建")
        return res["data"]["attributes"]["certificateContent"]
    print("  ✗ 建证书失败 (%s): %s" % (code, err_text(res)))
    return None


def dist_cert_ids(c):
    """Distribution 证书的 **id** 列表（描述文件的关系里要的是 id）。

    🚨🚨 别拿 `ensure_cert()` 的返回值当 id —— 它返回的是
       `certificateContent`（证书本体的 base64）。传错的表现是苹果回一条
       **指着别处的** 409：
       `There are no current certificates on this team matching the provided
        certificate IDs compatible with IOS_APP_STORE profiles.`
       —— 读起来像"证书过期了/类型不对"，去查证书会白查（证书好好的）。
       2026-08-28 我在 `asc_appgroup_wire.py` 里就这么传的，
       **而且旧描述文件已经先被删掉了**，等于把发布链路留在半坏状态。
       所以把取 id 这件事收成一个函数，别让下一个人再拼一次。
    """
    code, res = api(c, "GET",
                    "/certificates?filter[certificateType]=IOS_DISTRIBUTION")
    if code != 200:
        return []
    return [d["id"] for d in res.get("data", [])][:1]


def ensure_profile(c, name, bid_id, cert_ids):
    """🚨 跟 ensure_bundle_id 同型的坑：`filter[name]` 也不保证精确匹配，
    而且**光看 profileState=ACTIVE 不够** —— 一个活得好好的描述文件完全可能
    绑在**错的 Bundle ID** 上（2026-08-25 就是这样：「Transless AppStore」
    绑到了侧载工具建的 `com.kevin.transless.AX3W379KV8`）。
    所以复用之前必须把它绑的 bundleId 拉出来逐字比对，不对就删掉重建。
    """
    code, res = api(c, "GET", "/profiles?filter[name]=" + urllib.parse.quote(name))
    for d in (res.get("data") or []) if code == 200 else []:
        if d["attributes"].get("name") != name:
            continue
        c2, r2 = api(c, "GET", "/profiles/%s/bundleId" % d["id"])
        bound = (r2.get("data") or {}).get("id")
        if d["attributes"].get("profileState") == "ACTIVE" and bound == bid_id:
            print("  ✓ 描述文件已存在且绑对了: %s" % name)
            return d["attributes"]["profileContent"]
        why = "状态 %s" % d["attributes"].get("profileState") if bound == bid_id \
              else "绑的是别的 Bundle ID(%s)，应为 %s" % (bound, bid_id)
        print("  ⟳ 删掉重建「%s」—— %s" % (name, why))
        api(c, "DELETE", "/profiles/" + d["id"])
    code, res = api(c, "POST", "/profiles", {
        "data": {"type": "profiles",
                 "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
                 "relationships": {
                     "bundleId": {"data": {"id": bid_id, "type": "bundleIds"}},
                     "certificates": {"data": [{"id": i, "type": "certificates"}
                                               for i in cert_ids]}}}})
    if code in (200, 201):
        print("  ✓ 描述文件已创建: %s" % name)
        return res["data"]["attributes"]["profileContent"]
    print("  ✗ 建描述文件失败 (%s): %s" % (code, err_text(res)))
    return None


def main():
    print("【App Store Connect 一键配置】\n")
    c, msg = load_creds()
    if not c:
        print("缺凭据，没法继续：\n  " + msg)
        print("""
────────────────────────────────────────────────────
你只需要做这一件事（3 次点击，2 分钟）：

1. 打开 https://appstoreconnect.apple.com/access/integrations/api
2. 点「团队密钥」→ ➕ → 名字随便填，权限选 **App Manager**
3. 点「生成」→ **下载那个 .p8 文件**（只能下一次）
   → 丢进 %s
4. 同一页面顶部有个 **Issuer ID**（一串 UUID），复制它，
   在 %s 建个 asc_key.json：
   {"issuer_id": "粘在这里"}

然后再跑一次这个脚本，剩下的全自动。
────────────────────────────────────────────────────""" % (CERT_DIR, CERT_DIR))
        return 1

    print("凭据就绪：key_id=%s issuer=%s\n" % (c["key_id"], c["issuer"][:8] + "..."))
    if "--check" in sys.argv:
        code, res = api(c, "GET", "/apps?limit=1")
        print("连通性测试: HTTP %s %s" % (code, "OK" if code == 200 else err_text(res)))
        return 0 if code == 200 else 1

    print("① Bundle IDs")
    app_id = ensure_bundle_id(c, APP_BID, "Transless")
    kb_id = ensure_bundle_id(c, KB_BID, "Transless Keyboard")
    if not (app_id and kb_id):
        return 1

    print("\n② 证书")
    cert_content = ensure_cert(c)
    if not cert_content:
        return 1
    cert_ids = dist_cert_ids(c)

    print("\n③ 描述文件")
    prof_app = ensure_profile(c, "Transless AppStore", app_id, cert_ids)
    prof_kb = ensure_profile(c, "Transless Keyboard AppStore", kb_id, cert_ids)
    if not (prof_app and prof_kb):
        return 1

    print("\n④ 落盘 + 合成 p12")
    os.makedirs(CERT_DIR, exist_ok=True)
    open(os.path.join(CERT_DIR, "dist.cer"), "wb").write(base64.b64decode(cert_content))
    open(os.path.join(CERT_DIR, "app.mobileprovision"), "wb").write(base64.b64decode(prof_app))
    open(os.path.join(CERT_DIR, "kb.mobileprovision"), "wb").write(base64.b64decode(prof_kb))

    os.chdir(CERT_DIR)
    subprocess.run('openssl x509 -in dist.cer -inform DER -out dist.pem -outform PEM',
                   shell=True, capture_output=True)
    r = subprocess.run('openssl pkcs12 -export -inkey ios_private.key -in dist.pem '
                       '-out dist.p12 -passout pass:%s -legacy' % P12_PW,
                       shell=True, capture_output=True, text=True)
    if not os.path.exists("dist.p12"):
        subprocess.run('openssl pkcs12 -export -inkey ios_private.key -in dist.pem '
                       '-out dist.p12 -passout pass:%s' % P12_PW,
                       shell=True, capture_output=True)
    if not os.path.exists("dist.p12"):
        print("  ✗ p12 合成失败")
        return 1
    # 🚨 闸门：p12 要能被读回来
    chk = subprocess.run('openssl pkcs12 -in dist.p12 -nodes -passin pass:%s -legacy' % P12_PW,
                         shell=True, capture_output=True, text=True)
    if "BEGIN CERTIFICATE" not in (chk.stdout or ""):
        chk = subprocess.run('openssl pkcs12 -in dist.p12 -nodes -passin pass:%s' % P12_PW,
                             shell=True, capture_output=True, text=True)
    ok = "BEGIN CERTIFICATE" in (chk.stdout or "")
    print("  p12 可读回  %s" % ("PASS" if ok else "FAIL"))
    if not ok:
        return 1

    print("\n⑤ 生成 GitHub Secrets")
    out = os.path.join(CERT_DIR, "secrets_粘这里")
    os.makedirs(out, exist_ok=True)

    def w(n, v):
        open(os.path.join(out, n + ".txt"), "w").write(v)

    w("IOS_CERT_P12_BASE64", base64.b64encode(open("dist.p12", "rb").read()).decode())
    w("IOS_CERT_PASSWORD", P12_PW)
    w("IOS_PROFILE_APP_BASE64", prof_app)
    w("IOS_PROFILE_KB_BASE64", prof_kb)
    w("ASC_API_KEY_ID", c["key_id"])
    w("ASC_API_ISSUER_ID", c["issuer"])
    w("ASC_API_KEY_BASE64", base64.b64encode(open(c["p8"], "rb").read()).decode())

    # Team ID 从描述文件里抠
    try:
        import plistlib
        raw = open("app.mobileprovision", "rb").read()
        s, e = raw.find(b"<?xml"), raw.find(b"</plist>") + 8
        pl = plistlib.loads(raw[s:e])
        team = (pl.get("TeamIdentifier") or [""])[0]
        if team:
            w("IOS_TEAM_ID", team)
            print("  ✓ Team ID 自动抠出: %s" % team)
    except Exception as ex:
        print("  ! Team ID 没抠出来（%s），去 Membership 页看" % str(ex)[:40])

    print("\n=== 全部完成 ===")
    for f in sorted(os.listdir(out)):
        print("  %-26s %d 字符" % (f.replace(".txt", ""),
                                   os.path.getsize(os.path.join(out, f))))
    print("\n粘到 https://github.com/Kevinyang0420/-/settings/secrets/actions")
    return 0


if __name__ == "__main__":
    import urllib.parse
    sys.exit(main())
