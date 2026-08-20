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


def main():
    accepted = swift_accepted_codes()
    print("Swift 接受的状态码 : %s" % accepted)

    code, body = backend_submit_code()
    print("后端实际返回       : %s  keys=%s" % (code, list(body)))

    ok = True

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
