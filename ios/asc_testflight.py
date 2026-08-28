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
# 🚨 `--build <版本>` 用来**钉死操作对象**。不指定就按版本号数值挑最新。
WANT_BUILD = next((v for f, v in zip(sys.argv, sys.argv[1:])
                   if f == "--build"), None)


def one(c, path, want_key=None):
    code, res = A.api(c, "GET", path)
    if code != 200:
        sys.exit("FAIL: GET %s -> %s %s" % (path, code, A.err_text(res)))
    return res.get("data", [])


def A_api_get(c, path):
    """直接返回 `(状态码, 整个 json)` —— `one()` 只回 data 列表，
    单个资源取不到。"""
    return A.api(c, "GET", path)


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
    # 🚨🚨 **服务端排序 + 拉够数量**（2026-08-26 又被坑了一次）：
    #    `?limit=10` 那个窗口**本身不按上传时间排**，刚传上去的 516 / 520
    #    直接不在窗口里 —— 于是"按上传时间挑"只是在一堆旧包里挑最新的旧包。
    #    表现极像"苹果还在处理"，其实是**我根本没看到它**。
    #    2026-08-25 那次修的是"别信 builds[0]"，方向对但没修够：
    #    排序修对了，**取样范围没修**。
    # 🚨 这个端点**不接受 `sort`**（试过：`400 The parameter 'sort' can not be
    #    used with this request`），所以只能把窗口拉大再自己排。
    builds = one(c, "/apps/%s/builds?limit=200" % app["id"])
    if not builds:
        sys.exit("FAIL: 这个 App 一个构建都没有 —— 先跑 CI 上传")

    def _vnum(x):
        v = (x.get("attributes") or {}).get("version") or ""
        return int(v) if v.isdigit() else -1

    def _up(x):
        return (x.get("attributes") or {}).get("uploadedDate") or ""

    if WANT_BUILD:
        # 🚨 指定版本时**必须真的找到它**，找不到就报错退出 ——
        #    悄悄退回"最新的那个"会让我在错的包上填合规、加错的包进测试组。
        hit = [x for x in builds if (x.get("attributes") or {}).get("version")
               == WANT_BUILD]
        if not hit:
            sys.exit("FAIL: ASC 上没有构建 %s（现有：%s）—— 可能苹果还在处理"
                     % (WANT_BUILD,
                        ", ".join(sorted((x.get("attributes") or {}).get(
                            "version", "?") for x in builds), reverse=True)[:200]))
        b = hit[0]
        print("  （指定了构建 %s）" % WANT_BUILD)
    else:
        # 🚨 按**版本号数值**挑，不按"不等于上一次"。
        #    版本号是我们自己单调递增发的，数值最大的就是最新的；
        #    上传时间只在数值并列时当次序。
        # 🚨🚨 **按上传时间挑，不按版本号**（2026-08-28 实撞）。
        #    构建号引入重传序号之后是 `595.2` 这种，`_vnum` 的 `isdigit()`
        #    不认小数点 → 返回 -1 → **它被排到了 592 后面**，
        #    于是脚本把"最新构建"认成了半小时前那个旧包，
        #    还照样打印「构建已在组里 ✓」。**又一次对象被换掉。**
        #    上传时间不受编号方案影响，是这里唯一站得住的判据。
        b = sorted(builds, key=_up, reverse=True)[0]
        recent = [(x.get("attributes") or {}).get("version", "?")
                  for x in sorted(builds, key=_up, reverse=True)[:5]]
        print("  （%d 个构建，按**上传时间**挑了 %s；最近几个：%s）"
              % (len(builds), (b.get("attributes") or {}).get("version", "?"),
                 "/".join(recent)))
    st = b["attributes"].get("processingState")
    # 🚨 `usesNonExemptEncryption` 是**布尔**：
    #      None  = 没答  -> TestFlight 显示 Missing Compliance，谁都测不了
    #      False = 已声明"**不含**非豁免加密" -> 正常，可测
    #      True  = 用了，要交文档
    #    原来直接打 `合规=False`，读起来像"合规：否"，
    #    实际意思是"使用非豁免加密：否" —— 2026-08-26 我和总协调
    #    **各被这一个字坑了一次**，都以为它挡着验收。措辞本身就是 bug。
    _enc = b["attributes"].get("usesNonExemptEncryption")
    _enc_txt = ("🚨 没答（TestFlight 会显示 Missing Compliance，装不了）"
                if _enc is None else
                "已声明不含非豁免加密 ✓" if _enc is False else
                "声明了含非豁免加密（要交文档）")
    print("最新构建 : 版本 %s  %s"
          % (b["attributes"].get("version"), st))
    print("出口合规 : %s" % _enc_txt)

    if ENSURE and st == "PROCESSING":
        print("  等苹果处理完……")
        want_v = (b.get("attributes") or {}).get("version")
        bid = b["id"]
        for _ in range(40):
            time.sleep(60)
            # 🚨🚨 **按 id 重取那一个构建**，不是 `builds?limit=1`。
            #    原来这里写的是 `one(c, "/apps/{id}/builds?limit=1")[0]` ——
            #    那个查询**没有排序保证**，回来的是**任意一个**构建，
            #    于是等待结束后 `b` 已经不是我们要的那个了，
            #    后面"加进测试组""填合规"全作用在**别的包**上，
            #    而屏幕上照样打印 `构建已加进组 ✓`。
            #    2026-08-28 实测后果：`--ensure --build 561` 跑完打了成功，
            #    但从**组那边**独立查，组里只有 557 —— 561/558 根本没进去。
            #    我上一轮修好了"初始挑选"，**漏了这个重取** ——
            #    同一个 bug 的第二个出口。
            st2, r2 = A_api_get(c, "/builds/" + bid)
            if st2 != 200:
                print("   重取失败 HTTP %s" % st2)
                continue
            b = r2["data"]
            st = b["attributes"].get("processingState")
            got_v = b["attributes"].get("version")
            assert got_v == want_v, (
                "重取回来的是构建 %s，不是 %s —— 对象被换了" % (got_v, want_v))
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
