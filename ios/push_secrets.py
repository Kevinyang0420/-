# -*- coding: utf-8 -*-
r"""把 `asc_setup.py` 生成的那批 secrets 推到 GitHub Actions。

🚨 为什么要有这个脚本：上一次是我在对话里临时敲的一次性代码，
   于是 2026-08-25 重建描述文件之后没有现成的东西可跑，差点又手工贴一遍。
   secrets 的**唯一来源**是 `D:\ShareDrive\ios_cert\secrets_粘这里\*.txt`，
   目录里有几个就推几个，不在这里再写一份名字清单。

🚨 GitHub 的 secret 必须用仓库公钥做 libsodium sealed box 加密后再传，
   明文 PUT 会被拒。依赖 PyNaCl。
"""
import base64
import glob
import io
import json
import os
import ssl
import sys
import urllib.error
import urllib.request

sys.stdout.reconfigure(encoding="utf-8")

SRC = r"D:\ShareDrive\ios_cert\secrets_粘这里"
OWNER, REPO = "Kevinyang0420", "-"
CTX = ssl.create_default_context()


def gh(method, path, body=None):
    tok = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN", "")
    if not tok:
        sys.exit("GH_TOKEN 未设置")
    req = urllib.request.Request(
        "https://api.github.com" + path,
        data=json.dumps(body).encode("utf-8") if body is not None else None,
        headers={"Authorization": "Bearer " + tok,
                 "Accept": "application/vnd.github+json",
                 "User-Agent": "transless-secrets"},
        method=method)
    try:
        with urllib.request.urlopen(req, timeout=60, context=CTX) as r:
            return r.status, json.loads(r.read().decode("utf-8") or "{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode("utf-8") or "{}")


def main():
    try:
        from nacl import encoding, public
    except ImportError:
        sys.exit("缺 PyNaCl：py -m pip install pynacl")

    files = sorted(glob.glob(os.path.join(SRC, "*.txt")))
    if not files:
        sys.exit("FAIL: %s 里一个 .txt 都没有 —— 先跑 asc_setup.py" % SRC)

    code, key = gh("GET", "/repos/%s/%s/actions/secrets/public-key" % (OWNER, REPO))
    if code != 200:
        sys.exit("FAIL: 取仓库公钥 HTTP %s: %s" % (code, key))
    pk = public.PublicKey(key["key"].encode(), encoding.Base64Encoder())
    box = public.SealedBox(pk)

    for f in files:
        name = os.path.splitext(os.path.basename(f))[0]
        val = io.open(f, encoding="utf-8").read().strip()
        if not val:
            sys.exit("FAIL: %s 是空的" % name)
        enc = base64.b64encode(box.encrypt(val.encode("utf-8"))).decode()
        code, res = gh("PUT", "/repos/%s/%s/actions/secrets/%s" % (OWNER, REPO, name),
                       {"encrypted_value": enc, "key_id": key["key_id"]})
        if code not in (201, 204):
            sys.exit("FAIL: %s HTTP %s: %s" % (name, code, res))
        print("  %-26s %5d 字符  HTTP %s" % (name, len(val), code))

    # 🚨 闸门：GitHub 不会把 secret 读回来，能核的只有「名字齐不齐」。
    #    所以这里明确只声称这一层，不假装验过内容。
    code, res = gh("GET", "/repos/%s/%s/actions/secrets?per_page=100" % (OWNER, REPO))
    remote = {s["name"] for s in res.get("secrets", [])}
    want = {os.path.splitext(os.path.basename(f))[0] for f in files}
    missing = sorted(want - remote)
    if missing:
        sys.exit("FAIL: 推完了但远端查不到这些名字：%s" % missing)
    print("\n推了 %d 个。远端名字齐 ✓（内容 GitHub 不给读回，只能核到这一层）" % len(files))
    return 0


if __name__ == "__main__":
    sys.exit(main())
