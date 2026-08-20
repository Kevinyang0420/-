# -*- coding: utf-8 -*-
r"""把 Kevin 选中的那张 Grok icon 装进 iOS 的 AppIcon.appiconset。

🚨 iOS 的两条硬规矩，违反了要么被拒、要么桌面上显示成双重圆角/黑边：
   1. App icon **不能有 alpha 通道** —— 必须完全不透明的 RGB
   2. App icon **不能自己切圆角** —— 系统会切，自己切了就是双重圆角
   Grok 出的这批本来就是满方形黑底，正好合规；但下面照样逐条查，
   因为「合规」得是量出来的，不是看出来的。

用法：
  py apply_icon.py --check            # 只查四个候选合不合规，不写任何东西
  py apply_icon.py G3                 # 把 G3 装进 appiconset
"""
import argparse
import json
import os
import shutil
import sys

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")

SRC_DIR = r"D:\_build\transless_grok"
DEST = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                    "Assets.xcassets", "AppIcon.appiconset")
SIZE = 1024


def load(tag):
    p = os.path.join(SRC_DIR, "transless_%s.jpg" % tag)
    if not os.path.exists(p):
        raise SystemExit("FAIL: 找不到 %s" % p)
    return p, Image.open(p)


def inspect(tag):
    """返回 (合规?, 明细)。判据全部可机械验证。"""
    p, im = load(tag)
    rgb = im.convert("RGB")
    w, h = im.size
    corners = [rgb.getpixel(c) for c in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]]
    # 圆角是「角落被抠成透明或纯白」；这里的判据是四角必须都是深色底
    dark = [max(c) < 60 for c in corners]
    # 四角互相接近 = 底色一致，没有被切出奇怪的形状
    spread = max(max(c) for c in corners) - min(min(c) for c in corners)
    checks = [
        ("正方形", w == h),
        ("边长 >= 1024（够缩不够放）", min(w, h) >= SIZE),
        ("无 alpha 通道", im.mode in ("RGB", "L", "CMYK")),
        ("四角都是深色底（没自己切圆角）", all(dark)),
        ("四角底色一致（差 %d）" % spread, spread < 40),
    ]
    ok = all(c[1] for c in checks)
    return ok, w, h, checks


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tag", nargs="?", help="G1 / G2 / G3 / G4")
    ap.add_argument("--check", action="store_true", help="只查不写")
    a = ap.parse_args()

    tags = ["G1", "G2", "G3", "G4"] if a.check else [a.tag]
    if not a.check and not a.tag:
        raise SystemExit("FAIL: 要么给个 G1~G4，要么加 --check")

    allok = True
    for t in tags:
        ok, w, h, checks = inspect(t)
        print("=== %s (%dx%d) ===" % (t, w, h))
        for n, good in checks:
            print("   %-34s %s" % (n, "PASS" if good else "FAIL"))
        allok = allok and ok

    # 阴性对照：拿一张**真切了圆角**的图过同一套检查，必须被判 FAIL。
    # 不做这一步的话，「四角都是深色底」有可能是恒真的（黑底图天然过），查了等于没查。
    from PIL import ImageDraw
    probe = Image.new("RGB", (SIZE, SIZE), (10, 10, 12))
    ImageDraw.Draw(probe).rounded_rectangle(
        [0, 0, SIZE - 1, SIZE - 1], radius=int(SIZE * 0.2237),
        fill=(10, 10, 12), outline=None)
    # 圆角外补白，模拟「自己切了圆角、角落露白」
    m = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, SIZE - 1, SIZE - 1],
                                        radius=int(SIZE * 0.2237), fill=255)
    probe = Image.composite(probe, Image.new("RGB", (SIZE, SIZE), (255, 255, 255)), m)
    pc = [probe.getpixel(c) for c in [(0, 0), (SIZE - 1, 0), (0, SIZE - 1), (SIZE - 1, SIZE - 1)]]
    caught = not all(max(c) < 60 for c in pc)
    print("\n阴性对照（切了圆角的假图应被判出）  %s"
          % ("PASS" if caught else "FAIL 这条检查是恒真的"))
    allok = allok and caught

    if a.check:
        print("\n=== %s ===" % ("四个候选都合规，等他选" if allok else "有候选不合规"))
        return 0 if allok else 1

    if not allok:
        print("\n=== FAIL：不合规，没写入 ===")
        return 1

    p, im = load(a.tag)
    out = im.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    if os.path.isdir(DEST):
        shutil.rmtree(DEST)
    os.makedirs(DEST)
    png = os.path.join(DEST, "icon-1024.png")
    out.save(png)
    with open(os.path.join(DEST, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump({"images": [{"filename": "icon-1024.png", "idiom": "universal",
                               "platform": "ios", "size": "1024x1024"}],
                   "info": {"author": "xcode", "version": 1}}, f,
                  ensure_ascii=False, indent=2)

    # 写完再从磁盘读回来查一遍 —— 不拿「save 没报错」当落盘成功
    chk = Image.open(png)
    final = [
        ("落盘是 1024x1024", chk.size == (SIZE, SIZE)),
        ("落盘是 RGB 无 alpha", chk.mode == "RGB"),
        ("Contents.json 在", os.path.exists(os.path.join(DEST, "Contents.json"))),
    ]
    print("\n=== 写入复核 ===")
    good = True
    for n, g in final:
        print("   %-34s %s" % (n, "PASS" if g else "FAIL"))
        good = good and g
    print("\n=== %s ===  %s -> %s" % ("通过" if good else "FAIL", a.tag, DEST))
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
