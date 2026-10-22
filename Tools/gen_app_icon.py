#!/usr/bin/env python3
"""生成 App 图标（1024×1024，无 alpha，iOS 会自动裁圆角）

设计：红白机手柄的正面剪影 —— 米白底 + 朱红十字方向键 + 深红双按键。
为什么不用文字：40pt 图标下文字必然糊成一团，只有形状能认出来。

用法：
  python3 Tools/gen_app_icon.py
产物：
  App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""
import os
import struct
import zlib

W = H = 1024

CREAM_TOP = (247, 240, 226)
CREAM_BOTTOM = (232, 219, 197)
RED = (208, 52, 44)
RED_DARK = (150, 28, 22)
MAROON = (74, 20, 16)
SHADOW = (203, 181, 158)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def canvas():
    """米白竖向渐变 + 中心柔光，模拟塑料机壳"""
    px = bytearray()
    for y in range(H):
        base = lerp(CREAM_TOP, CREAM_BOTTOM, y / (H - 1))
        for x in range(W):
            # 中心提亮（径向），让画面不闷
            dx = (x - W * 0.42) / (W * 0.75)
            dy = (y - H * 0.36) / (H * 0.75)
            glow = max(0.0, 1.0 - (dx * dx + dy * dy)) * 0.16
            r = min(255, round(base[0] + (255 - base[0]) * glow))
            g = min(255, round(base[1] + (255 - base[1]) * glow))
            b = min(255, round(base[2] + (255 - base[2]) * glow))
            px += bytes((r, g, b))
    return px


def rounded_rect(buf, x0, y0, x1, y1, radius, color):
    r2 = radius * radius
    for y in range(max(0, y0), min(H, y1)):
        for x in range(max(0, x0), min(W, x1)):
            cx = min(max(x, x0 + radius), x1 - radius - 1)
            cy = min(max(y, y0 + radius), y1 - radius - 1)
            if (x - cx) ** 2 + (y - cy) ** 2 > r2:
                continue
            i = (y * W + x) * 3
            buf[i:i + 3] = bytes(color)


def disc(buf, cx, cy, radius, color, ring=None, ring_w=26):
    r2 = radius * radius
    inner = (radius - ring_w) ** 2
    for y in range(max(0, cy - radius), min(H, cy + radius)):
        for x in range(max(0, cx - radius), min(W, cx + radius)):
            d2 = (x - cx) ** 2 + (y - cy) ** 2
            if d2 > r2:
                continue
            i = (y * W + x) * 3
            if ring and d2 > inner:
                buf[i:i + 3] = bytes(ring)
            else:
                buf[i:i + 3] = bytes(color)


def build(path):
    buf = canvas()

    # 手柄机身：居中的圆角矩形，底部一层柔和投影增加厚度感
    body = (96, 236, 928, 828)
    rounded_rect(buf, body[0] + 10, body[1] + 16, body[2] + 10, body[3] + 16, 150, SHADOW)  # 投影
    rounded_rect(buf, *body, 150, RED_DARK)
    rounded_rect(buf, body[0] + 12, body[1] + 8, body[2] - 12, body[3] - 20, 140, RED)

    # 十字方向键：横臂（宽 arm、高 thick）+ 竖臂（宽 thick、高 arm），同心叠加成十字
    arm, thick = 300, 116
    cx, cy = 354, 532
    rounded_rect(buf, cx - arm // 2, cy - thick // 2, cx + arm // 2, cy + thick // 2, 26, CREAM_TOP)
    rounded_rect(buf, cx - thick // 2, cy - arm // 2, cx + thick // 2, cy + arm // 2, 26, CREAM_TOP)

    # 双按键：与方向键同高的并排两颗（红白机 B/A 布局），留出明确间隙
    for bx in (652, 838):
        disc(buf, bx, 532, 76, CREAM_TOP)
        disc(buf, bx, 532, 34, MAROON)

    # 顶部两颗装饰圆点（模拟机身螺钉位）
    for sx in (206, 818):
        disc(buf, sx, 308, 18, RED_DARK)

    write_png(path, buf)


def write_png(path, rgb):
    raw = bytearray()
    for y in range(H):
        raw.append(0)  # filter type 0
        raw += rgb[y * W * 3:(y + 1) * W * 3]

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)  # 8bit truecolor，无 alpha
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(png)
    print(f"已生成 {path} ({len(png) / 1024:.0f} KB, {W}×{H})")


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(root, "App", "Resources", "Assets.xcassets",
                       "AppIcon.appiconset", "icon-1024.png")
    build(out)
