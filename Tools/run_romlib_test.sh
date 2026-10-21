#!/bin/bash
# Tools/run_romlib_test.sh — 运行 ROM 库逻辑回归测试（macOS 命令行，秒级）
#
# 覆盖：真实 ROM 识别、重复导入去重、旧索引幽灵条目自愈、街机 romset 入库。
# 用法：./Tools/run_romlib_test.sh [ROM 路径]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# 可选：传入真实 ROM 以额外验证识别；不传则用脚本生成的合成 ROM 跑结构用例
REAL_ROM="${1:-}"
ROM=""
WORK="${TMPDIR:-/tmp}/miniretro-romlib-test"
OUT="$WORK/romlib_test"
rm -rf "$WORK"
mkdir -p "$WORK/home"

# Python 只用来构造测试用 zip / 合成 ROM，这里探测系统解释器即可
PYTHON="${PYTHON:-$(command -v python3 || true)}"
[ -n "$PYTHON" ] || { echo "需要 python3（构造测试文件用）" >&2; exit 1; }

# 隔离 HOME，让 FileManager.documentsDirectory 指向临时目录
export HOME="$WORK/home"
mkdir -p "$HOME/Documents"

# 生成一个最小可识别的 iNES ROM（仅用于库逻辑，不含游戏内容）
SYNTH_ROM="$WORK/synthetic.nes"
"$PYTHON" - "$SYNTH_ROM" <<'PY2'
import sys
path = sys.argv[1]
header = b"NES\x1a" + bytes([1, 1, 0, 0]) + bytes(8)
with open(path, "wb") as fh:
    fh.write(header + bytes(16384) + bytes(8192))
print(f"built {path}")
PY2

# 有真实 ROM 就用真实 ROM，否则用合成 ROM
if [ -n "$REAL_ROM" ] && [ -f "$REAL_ROM" ]; then
    ROM="$REAL_ROM"
else
    ROM="$SYNTH_ROM"
fi

# 构造一个「街机 romset」zip（只含 arcade 风格文件）
ARCADE_ZIP="$WORK/kov.zip"
"$PYTHON" - "$ARCADE_ZIP" <<'PY'
import sys, zipfile
path = sys.argv[1]
with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("kov-p1.bin", b"\x55" * 4096)
    z.writestr("kov-c1.bin", b"\xAA" * 4096)
print(f"built {path}")
PY

CLANG=$(xcrun --find clang)
SWIFTC="$(xcrun --find swiftc)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"

echo "[test] 编译 C 注册表 ..."
"$CLANG" -c "$ROOT/CoreBridge/CoreRegistry.c" -I "$ROOT/CoreBridge" \
    -isysroot "$SDK" -target arm64-apple-macosx14.0 \
    -o "$WORK/CoreRegistry.o"

echo "[test] 编译 Swift 测试 ..."
"$SWIFTC" -O -sdk "$SDK" -swift-version 5 -target arm64-apple-macosx14.0 \
    -disable-sandbox \
    -import-objc-header "$ROOT/CoreBridge/CoreRegistry.h" \
    -Xcc -I"$ROOT/CoreBridge" \
    "$ROOT/App/Models/AppTypes.swift" \
    "$ROOT/App/Models/SettingsStore.swift" \
    "$ROOT/App/Utilities/Utilities.swift" \
    "$ROOT/App/Library/ZipArchive.swift" \
    "$ROOT/App/Library/ROMImporter.swift" \
    "$ROOT/App/Game/CommunityCheatService.swift" \
    "$ROOT/Tests/romlib/main.swift" \
    "$WORK/CoreRegistry.o" \
    -o "$OUT"

echo "[test] 运行 ..."
TEST_ROM="$ROM" ARCADE_ZIP="$ARCADE_ZIP" \
    CHEAT_INDEX="$ROOT/App/Resources/CheatIndex.json" "$OUT"
