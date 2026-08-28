# -*- coding: utf-8 -*-
"""App Group 建好之后，把两个描述文件重签上去 —— 并**验证真的带上了**。

## 什么时候跑

只在 `group.com.kevin.transless` **已经在苹果开发者门户里建好、并且挂到了
两个 Bundle ID 上**之后跑。在那之前跑没有意义：门户没建组，
重签出来的描述文件里照样没有这个 entitlement。

    py asc_appgroup_wire.py            # 只看现状，不改任何东西
    py asc_appgroup_wire.py --apply    # 删旧的、重建、并验证

## 🚨 为什么必须重建描述文件而不是"等它自己更新"

描述文件是**签发那一刻的快照**。门户上给 Bundle ID 加了新能力之后，
**已经签发的描述文件不会跟着变** —— 它还是旧的那份，里面没有
`com.apple.security.application-groups`。用它签出来的包，
`containerURL(forSecurityApplicationGroupIdentifier:)` 返回 nil，
于是键盘和主 App 互相递不了话，**而且两边都不报错**。

## 🚨 判据挂在描述文件的内容上，不是"重建成功了"

`profileContent` 是 base64 的 mobileprovision。里面是一段 CMS 签名数据，
但那段 XML plist 是**明文嵌在里面**的 —— 直接找 `<plist` … `</plist>` 就能取出来，
不用解 CMS。取出来之后看 `Entitlements` 里有没有那个 group。

**「API 返回 200」不算数** —— 那只说明苹果收下了这个请求。
"""
import base64
import plistlib
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.path.insert(0, __file__.rsplit("\\", 1)[0])

import asc_setup as A  # noqa: E402

#: 🚨 组名的唯一真值在 `Shared/KbBridge.swift`。这里从那个文件读，不写死。
KB = __file__.rsplit("\\", 1)[0] + "\\Shared\\KbBridge.swift"

TARGETS = [
    ("Transless AppStore", "com.kevin.transless"),
    ("Transless Keyboard AppStore", "com.kevin.transless.keyboard"),
]


def group_name():
    import io
    s = io.open(KB, encoding="utf-8").read()
    m = re.search(r'static let group\s*=\s*"([^"]+)"', s)
    assert m, "KbBridge.swift 里读不到 group"
    return m.group(1)


def profile_groups(b64):
    """从 base64 的 mobileprovision 里取出它声明的 App Group 列表。

    🚨 找不到 plist 时**抛异常**，不是返回空列表 —— 返回空的话
       「解析失败」和「真的没有这个 entitlement」长得一模一样，
       而这两件事该做的处置完全不同。
    """
    raw = base64.b64decode(b64)
    i = raw.find(b"<plist")
    j = raw.find(b"</plist>")
    if i < 0 or j < 0:
        raise ValueError("描述文件里找不到 plist 段（%d 字节）" % len(raw))
    d = plistlib.loads(raw[i:j + 8])
    ent = d.get("Entitlements") or {}
    # 🚨🚨 **正控**：没有这一步的话，「读错了地方」和「真的没有这个组」
    #    长得一模一样 —— 两种情况都返回空列表。
    #    描述文件必然带 `application-identifier`，读不到它就说明我解析的
    #    根本不是 Entitlements 那一段，这时候必须抛，不许安静地返回空。
    if "application-identifier" not in ent:
        raise ValueError("解析到的不是 Entitlements（拿到的键：%s）"
                         % sorted(ent)[:6])
    return list(ent.get("com.apple.security.application-groups") or []), ent


def find_profile(c, name):
    code, res = A.api(c, "GET", "/profiles?filter[name]=" +
                      __import__("urllib.parse", fromlist=["quote"]).quote(name))
    if code != 200:
        return None
    for d in res.get("data") or []:
        if d["attributes"].get("name") == name:
            return d
    return None


def main():
    apply = "--apply" in sys.argv
    want = group_name()
    print("=== App Group 接线 ===")
    print("组名（取自 KbBridge.swift）：%s" % want)
    print("模式：%s" % ("真改" if apply else "只看，不改任何东西"))
    print()

    c, err = A.load_creds()
    if err:
        print("🚨 " + err)
        return 1

    # Bundle ID 的内部 id
    code, res = A.api(c, "GET", "/bundleIds?limit=200")
    if code != 200:
        print("🚨 列 Bundle ID 失败：%s" % A.err_text(res))
        return 1
    ids = {d["attributes"]["identifier"]: d["id"] for d in res["data"]}

    cert_ids = None
    bad = []
    for name, ident in TARGETS:
        print("--- %s（%s）" % (name, ident))
        bid = ids.get(ident)
        if not bid:
            print("  🚨 找不到这个 Bundle ID")
            bad.append(name)
            continue
        p = find_profile(c, name)
        if p:
            try:
                has, ent = profile_groups(p["attributes"]["profileContent"])
            except ValueError as e:
                print("  🚨 描述文件解析不了：%s" % e)
                bad.append(name)
                continue
            print("  现有描述文件声明的组：%s" % (has or "（一个都没有）"))
            print("     （正控：这份文件里共读到 %d 条 entitlement，"
                  "含 application-identifier —— 说明解析的是对的地方）"
                  % len(ent))
            if want in has:
                print("  ✅ 已经带上了，不用动")
                continue
        else:
            print("  （还没有这个描述文件）")

        if not apply:
            print("  ⬜ 需要重建 —— 加 --apply 才会真做")
            bad.append(name)
            continue

        # 🚨🚨 **必须先删掉再建。** `ensure_profile` 看到一个 ACTIVE 且绑对
        #    Bundle ID 的描述文件就**直接复用**，压根不重签 ——
        #    于是"跑了 --apply 却还是没有组"，而真相是它根本没重新签发。
        #    描述文件是**签发那一刻的快照**，门户上加了能力它不会自己更新。
        if p:
            print("  ⟳ 先删掉旧的（否则会被原样复用，等于没重签）")
            A.api(c, "DELETE", "/profiles/" + p["id"])

        if cert_ids is None:
            # 🚨 要的是证书**id**，不是 `ensure_cert()` 返回的证书内容。
            #    传错时苹果回的 409 指着别处（"没有兼容的证书"），
            #    而证书本身好好的 —— 会白查一轮。
            if not A.ensure_cert(c):
                print("  🚨 拿不到证书")
                return 1
            cert_ids = A.dist_cert_ids(c)
            if not cert_ids:
                print("  🚨 查不到 Distribution 证书的 id")
                return 1
        content = A.ensure_profile(c, name, bid, cert_ids)
        if not content:
            bad.append(name)
            continue
        # 🚨 重建之后**立刻回读验证**，不是信 ensure_profile 打的那句成功
        try:
            has, ent = profile_groups(content)
        except ValueError as e:
            print("  🚨 新描述文件解析不了：%s" % e)
            bad.append(name)
            continue
        if want in has:
            print("  ✅ 重建后确认带上了：%s" % has)
        else:
            print("  🚨 重建了但**还是没有** %s（实际：%s，共 %d 条 entitlement）"
                  % (want, has or "空", len(ent)))
            print("     —— 说明门户那边这个组还没挂到这个 Bundle ID 上。")
            bad.append(name)

    print()
    if bad:
        print("=== 还没接通：%s ===" % "、".join(bad))
        return 1
    print("=== 两个描述文件都带着 %s ===" % want)
    return 0


if __name__ == "__main__":
    sys.exit(main())
