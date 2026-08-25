# -*- coding: utf-8 -*-
r"""每次出完包跑这一条，把新构建送进 TestFlight。

    py asc_testflight.py            # 只看现状，不改任何东西
    py asc_testflight.py --ensure   # 等处理完 → 填合规 → 建组/加构建/加测试员（幂等）

🚨 为什么要有它：2026-08-25 第一次上架时这四步是我在对话里散着敲的
   （建组、加构建、加测试员、填出口合规），下次出包又得重敲一遍。
   合成一份，且**没有写死的 id** —— App 按 bundle id 找，构建取最新，组按名字找。

🚨 每一步都**重新 GET 一次做独立复核**，不拿 POST/PATCH 的返回当结论。
   `PATCH 返回 200` 和「那个字段真的变了」是两回事。
"""
import sys
import time

sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, __file__.rsplit("\\", 1)[0] if "\\" in __file__ else ".")
import asc_setup as A  # noqa: E402

APP_BID = "com.kevin.transless"
GROUP = "Internal"
TESTER = ("kevinyang5425@gmail.com", "Kevin", "Yang")
ENSURE = "--ensure" in sys.argv


def one(c, path, want_key=None):
    code, res = A.api(c, "GET", path)
    if code != 200:
        sys.exit("FAIL: GET %s -> %s %s" % (path, code, A.err_text(res)))
    return res.get("data", [])


def main():
    c, err = A.load_creds()
    if not c:
        sys.exit(err)

    # ---- App（按 bundle id 逐字匹配，别取 data[0]：filter 不是精确匹配，见 asc_setup 的注释）
    apps = [d for d in one(c, "/apps?limit=50")
            if d["attributes"].get("bundleId") == APP_BID]
    if not apps:
        sys.exit("FAIL: ASC 上没有 bundleId=%s 的 App —— 先在网页上建记录" % APP_BID)
    app = apps[0]
    print("App      : %s  (%s)  id=%s"
          % (app["attributes"]["name"], APP_BID, app["id"]))

    # ---- 最新构建
    builds = one(c, "/apps/%s/builds?limit=10" % app["id"])
    if not builds:
        sys.exit("FAIL: 这个 App 一个构建都没有 —— 先跑 CI 上传")
    # 🚨 **按上传时间挑，不信接口顺序**（2026-08-25 实测被坑）：
    #    那次 API 返回的是 464 / 5 / 465，最新的 465 排在最后，
    #    取 builds[0] 就把 464 当成了最新，新包传上去却没进测试组。
    #    接口从没承诺过顺序，是我当它有。
    def _up(x):
        return (x.get("attributes") or {}).get("uploadedDate") or ""
    builds = sorted(builds, key=_up, reverse=True)
    b = builds[0]
    if len(builds) > 1:
        print("  （候选 %s，按上传时间挑了 %s）"
              % ("/".join((x.get("attributes") or {}).get("version", "?")
                          for x in builds[:4]),
                 (b.get("attributes") or {}).get("version", "?")))
    st = b["attributes"].get("processingState")
    print("最新构建 : 版本 %s  %s  合规=%s"
          % (b["attributes"].get("version"), st,
             b["attributes"].get("usesNonExemptEncryption")))

    if ENSURE and st == "PROCESSING":
        print("  等苹果处理完……")
        for _ in range(40):
            time.sleep(60)
            b = one(c, "/apps/%s/builds?limit=1" % app["id"])[0]
            st = b["attributes"].get("processingState")
            print("   状态 =", st)
            if st != "PROCESSING":
                break
    if st != "VALID":
        sys.exit("FAIL: 构建状态是 %s，不是 VALID，后面的事先别做" % st)

    # ---- 出口合规（空着的话 TestFlight 显示 Missing Compliance，谁都测不了）
    if b["attributes"].get("usesNonExemptEncryption") is None:
        if not ENSURE:
            print("  ⚠ 合规未填 —— 加 --ensure 才会写")
        else:
            code, res = A.api(c, "PATCH", "/builds/" + b["id"], {
                "data": {"type": "builds", "id": b["id"],
                         "attributes": {"usesNonExemptEncryption": False}}})
            if code != 200:
                sys.exit("FAIL: 填合规 %s %s" % (code, A.err_text(res)))
            got = one(c, "/apps/%s/builds?limit=1" % app["id"])[0]
            v = got["attributes"].get("usesNonExemptEncryption")
            print("  ✓ 合规已填，复核 =", v)
            if v is not False:
                sys.exit("FAIL: 写完复核不是 False，是 %r" % v)

    # ---- 内部测试组
    groups = [g for g in one(c, "/apps/%s/betaGroups?limit=20" % app["id"])
              if g["attributes"].get("name") == GROUP]
    if groups:
        gid = groups[0]["id"]
        print("测试组   : %s（已存在）id=%s" % (GROUP, gid))
    elif not ENSURE:
        print("  ⚠ 没有名为 %s 的测试组 —— 加 --ensure 才会建" % GROUP)
        return 0
    else:
        code, res = A.api(c, "POST", "/betaGroups", {
            "data": {"type": "betaGroups",
                     "attributes": {"name": GROUP, "isInternalGroup": True},
                     "relationships": {"app": {"data": {"id": app["id"], "type": "apps"}}}}})
        if code not in (200, 201):
            sys.exit("FAIL: 建组 %s %s" % (code, A.err_text(res)))
        gid = res["data"]["id"]
        print("  ✓ 已建组 %s  id=%s" % (GROUP, gid))

    # ---- 构建挂进组
    in_group = [x["id"] for x in one(c, "/betaGroups/%s/builds?limit=50" % gid)]
    if b["id"] in in_group:
        print("  构建已在组里 ✓")
    elif ENSURE:
        code, res = A.api(c, "POST", "/betaGroups/%s/relationships/builds" % gid,
                          {"data": [{"id": b["id"], "type": "builds"}]})
        if code not in (200, 204):
            sys.exit("FAIL: 加构建 %s %s" % (code, A.err_text(res)))
        again = [x["id"] for x in one(c, "/betaGroups/%s/builds?limit=50" % gid)]
        if b["id"] not in again:
            sys.exit("FAIL: 加完复核，构建还是不在组里")
        print("  ✓ 构建已加进组（复核过）")
    else:
        print("  ⚠ 构建不在组里 —— 加 --ensure 才会加")

    # ---- 测试员
    testers = one(c, "/betaGroups/%s/betaTesters?limit=50" % gid)
    mails = {t["attributes"].get("email") for t in testers}
    if TESTER[0] in mails:
        t = [x for x in testers if x["attributes"]["email"] == TESTER[0]][0]
        print("  测试员 %s 已在组里，state=%s" % (TESTER[0], t["attributes"].get("state")))
    elif ENSURE:
        code, res = A.api(c, "POST", "/betaTesters", {
            "data": {"type": "betaTesters",
                     "attributes": {"email": TESTER[0], "firstName": TESTER[1],
                                    "lastName": TESTER[2]},
                     "relationships": {"betaGroups": {
                         "data": [{"id": gid, "type": "betaGroups"}]}}}})
        if code not in (200, 201):
            sys.exit("FAIL: 加测试员 %s %s" % (code, A.err_text(res)))
        after = one(c, "/betaGroups/%s/betaTesters?limit=50" % gid)
        if TESTER[0] not in {t["attributes"].get("email") for t in after}:
            sys.exit("FAIL: 加完复核，测试员还是不在组里")
        print("  ✓ 测试员已加（复核过），邀请邮件已发")
    else:
        print("  ⚠ %s 不在组里 —— 加 --ensure 才会加" % TESTER[0])
    return 0


if __name__ == "__main__":
    sys.exit(main())
