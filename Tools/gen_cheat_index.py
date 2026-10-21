#!/usr/bin/env python3
"""生成内置金手指索引 App/Resources/CheatIndex.json

数据源：libretro-database 的 cht 目录（社区维护）。
为什么预生成：GitHub 未认证 API 限流 60 次/小时且共享出口 IP 常被打满，
运行期调 API 列目录不可靠；预生成后搜索完全离线，只有命中后抓具体 .cht。

用法（需要一次性拿到文件清单，不下载文件内容）：
  git clone --depth 1 --filter=blob:none --no-checkout \
      https://github.com/libretro/libretro-database.git /tmp/lrdb2
  git -C /tmp/lrdb2 ls-tree -r --name-only HEAD cht/ > /tmp/lrdb-cht.txt
  python3 Tools/gen_cheat_index.py /tmp/lrdb-cht.txt
"""
import json
import os
import sys
from datetime import date

# 索引 key → 数据库目录名
PLATFORMS = {
    "fc": "Nintendo - Nintendo Entertainment System",
    "gb": "Nintendo - Game Boy",
    "gbc": "Nintendo - Game Boy Color",
    "gba": "Nintendo - Game Boy Advance",
}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "App", "Resources", "CheatIndex.json")


def main() -> int:
    src = sys.argv[1] if len(sys.argv) > 1 else "/tmp/lrdb-cht.txt"
    with open(src, encoding="utf-8") as fh:
        lines = [line.strip() for line in fh if line.strip()]

    platforms = {}
    for key, folder in PLATFORMS.items():
        prefix = f"cht/{folder}/"
        files = sorted(
            os.path.basename(line)
            for line in lines
            if line.startswith(prefix) and line.lower().endswith(".cht")
        )
        platforms[key] = {"folder": folder, "files": files}
        print(f"{key:<4} {folder:<45} {len(files)} 个文件")

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    payload = {"generated": date.today().isoformat(), "platforms": platforms}
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(OUT)
    print(f"已写入 {OUT} ({size / 1024:.0f} KB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
