#!/bin/bash
# Tools/run_e2e.sh — macOS 上的端到端验证（无需 iOS SDK）
#
# 作用：用真实 core dylib + 真实 CoreBridge + 自动生成的极简 ROM，
#       验证「加载 → 运行 → 抓帧 → 存档往返 → 退出」完整链路。
# 这是在没有完整 Xcode 的环境里，能对桥接层做的最强验证。
#
# 用法：./Tools/run_e2e.sh [mgba|sameboy|fceumm]   # 缺省跑全部
# 产物：/tmp/mr-e2e/（ROM、framework 布局、测试二进制）
#
# 说明：SameBoy 的 boot ROM 在此脚本中用占位数据（生成需 rgbds + rgbgfx/libpng）；
#       验证的是桥接层 + core 运行链路，不是 boot ROM 内容保真度。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="/tmp/mr-e2e"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
JOBS="$(sysctl -n hw.ncpu)"
CMAKE="$ROOT/Tools/vendor/cmake/CMake.app/Contents/bin/cmake"
[ -x "$CMAKE" ] || CMAKE="$(command -v cmake || true)"

log() { echo -e "\033[1;36m[e2e]\033[0m $*"; }
die() { echo -e "\033[1;31m[e2e] ERROR:\033[0m $*" >&2; exit 1; }

mkdir -p "$WORK/Frameworks" "$WORK/work"

# ---------- 1. 准备测试 ROM（极简 homebrew：仅用于验证链路，可自由分发） ----------

make_nes_rom() {
    python3 - <<'PY'
prg = bytearray(16 * 1024)
code = bytes([
    0x78, 0xD8, 0xA2, 0xFF, 0x9A,              # SEI CLD LDX #FF TXS
    0xA9, 0x00, 0x8D, 0x00, 0x20,              # LDA #0 / STA $2000
    0x8D, 0x01, 0x20,                          # STA $2001
    0xA9, 0x3F, 0x8D, 0x06, 0x20,              # palette 地址高
    0xA9, 0x00, 0x8D, 0x06, 0x20,              # palette 地址低
    0xA9, 0x1A, 0x8D, 0x07, 0x20,              # 背景色
    0x4C, 0x15, 0xC0,                          # JMP 自身循环
])
prg[0:len(code)] = code
for addr, val in ((0x3FFA, 0xC0), (0x3FFB, 0x00), (0x3FFC, 0x00),
                  (0x3FFD, 0xC0), (0x3FFE, 0x00), (0x3FFF, 0xC0)):
    prg[addr] = val
rom = bytes([0x4E, 0x45, 0x53, 0x1A, 1, 1, 0, 0]) + bytes(8) + bytes(prg) + bytes(8 * 1024)
open('/tmp/mr-e2e/test.nes', 'wb').write(rom)
print('  test.nes (NROM-128, 24KB)')
PY
}

make_gb_rom() {
    python3 - <<'PY'
LOGO = bytes([
    0xCE,0xED,0x66,0x66,0xCC,0x0D,0x00,0x0B,0x03,0x73,0x00,0x83,0x00,0x0C,0x00,0x0D,
    0x00,0x08,0x11,0x1F,0x88,0x89,0x00,0x0E,0xDC,0xCC,0x6E,0xE6,0xDD,0xDD,0xD9,0x99,
    0xBB,0xBB,0x67,0x63,0x6E,0x0E,0xEC,0xCC,0xDD,0xDC,0x99,0x9F,0xBB,0xB9,0x33,0x3E,
])
rom = bytearray(32 * 1024)
rom[0x100:0x104] = bytes([0x00, 0xC3, 0x50, 0x01])
rom[0x104:0x134] = LOGO
rom[0x134:0x13E] = b"MINIRETRO"
rom[0x147] = 0x00   # ROM only
rom[0x148] = 0x00   # 32KB
rom[0x14A] = 0x01
rom[0x14B] = 0x33
x = 0
for i in range(0x134, 0x14D):
    x = (x - rom[i] - 1) & 0xFF
rom[0x14D] = x
rom[0x150:0x153] = bytes([0x76, 0x18, 0xFD])   # HALT; JR -3
open('/tmp/mr-e2e/test.gb', 'wb').write(rom)
print(f'  test.gb (32KB, header checksum 0x{x:02X})')
PY
}

make_gba_rom() {
    python3 - <<'PY'
rom = bytearray(1024 * 1024)
rom[0x00:0x04] = bytes([0x2E, 0x00, 0x00, 0xEA])          # b 0x080000C0
rom[0x04:0x9C] = bytes([0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21]) * 19
rom[0xA0:0xAC] = b'MINIRETRO\x00\x00\x00'
rom[0xB2] = 0x96
rom[0xC0:0xC4] = bytes([0xFE, 0xFF, 0xFF, 0xEA])          # b .
open('/tmp/mr-e2e/test.gba', 'wb').write(rom)
print('  test.gba (1MB)')
PY
}

# ---------- 2. 编译 macOS core dylib ----------

build_fceumm_macos() {
    local out="$WORK/cores/fceumm"
    [ -f "$out/fceumm_libretro.dylib" ] && return 0
    log "编译 fceumm (macOS) ..."
    rm -rf "$out" && mkdir -p "$out"
    cp -R "$ROOT/Cores/fceumm/." "$out/"
    make -C "$out" -f Makefile platform=osx -j"$JOBS" > "$out/build.log" 2>&1 || {
        tail -20 "$out/build.log"; die "fceumm 编译失败"
    }
}

build_sameboy_macos() {
    local out="$WORK/cores/sameboy"
    [ -f "$out/sameboy_libretro.dylib" ] && return 0
    log "编译 SameBoy (macOS, 含 cheat 补丁 + 占位 boot ROM) ..."
    rm -rf "$out" && mkdir -p "$out"
    cp -R "$ROOT/Cores/sameboy/." "$out/"
    # 复用 build_cores.sh 的补丁逻辑（去掉 GB_DISABLE_CHEATS + 加 cheats.c + 替换 stub）
    python3 - "$out" <<'PY'
import sys, pathlib
work = pathlib.Path(sys.argv[1])
mk = work / "libretro" / "Makefile.common"
t = mk.read_text().replace("-DGB_DISABLE_CHEATS", "")
if "Core/cheats.c" not in t:
    anchor = "$(CORE_DIR)/Core/rumble.c \\"
    t = t.replace(anchor, anchor + "\n               $(CORE_DIR)/Core/cheats.c \\")
mk.write_text(t)
c = work / "libretro" / "libretro.c"
t = c.read_text()
stub = '''void retro_cheat_reset(void)
{}

void retro_cheat_set(unsigned index, bool enabled, const char *code)
{
    (void)index;
    (void)enabled;
    (void)code;
}'''
repl = '''/* === miniretro_cheat_patch (ADR-003) === */
#include "Core/cheats.h"

void retro_cheat_reset(void)
{
    for (unsigned i = 0; i < 2; i++) {
        GB_remove_all_cheats(&gameboy[i]);
    }
}

void retro_cheat_set(unsigned index, bool enabled, const char *code)
{
    (void)index;
    if (!code || !*code) {
        return;
    }
    for (unsigned i = 0; i < 2; i++) {
        GB_import_cheat(&gameboy[i], code, "", enabled);
    }
}
/* === end miniretro_cheat_patch === */'''
assert stub in t, "cheat stub 未找到（上游已变更）"
c.write_text(t.replace(stub, repl, 1))
PY
    # 占位 boot ROM（真实生成需 rgbds + rgbgfx/libpng）
    for name in agb cgb cgb0 dmg mgb sgb sgb2; do
        python3 -c "
name = '$name'
data = bytes([0xFF]) * 512
open('$out/libretro/' + name + '_boot.c', 'w').write(
    '/* placeholder boot rom (e2e only) */\n'
    'const unsigned char ' + name + '_boot[] = {' + ','.join(map(str, data)) + '};\n'
    'const unsigned ' + name + '_boot_length = sizeof(' + name + '_boot);\n')
"
    done
    make -C "$out/libretro" platform=osx -j"$JOBS" > "$out/build.log" 2>&1 || {
        tail -20 "$out/build.log"; die "SameBoy 编译失败"
    }
}

build_mgba_macos() {
    local out="$WORK/cores/mgba"
    [ -f "$out/mgba_libretro.dylib" ] && return 0
    log "编译 mGBA (macOS) ..."
    [ -n "$CMAKE" ] || die "需要 cmake：brew install cmake 或 ./Tools/fetch_cmake.sh"
    rm -rf "$out" && mkdir -p "$out"
    "$CMAKE" -S "$ROOT/Cores/mgba" -B "$out/build" \
        -DCMAKE_SYSTEM_NAME=Darwin \
        -DBUILD_LIBRETRO=ON -DLIBMGBA_ONLY=ON -DDISABLE_FRONTENDS=ON -DDISABLE_DEPS=ON \
        -DCMAKE_BUILD_TYPE=Release > "$out/cmake.log" 2>&1 || {
        tail -20 "$out/cmake.log"; die "mGBA cmake 配置失败"
    }
    "$CMAKE" --build "$out/build" -j"$JOBS" > "$out/build.log" 2>&1 || {
        tail -20 "$out/build.log"; die "mGBA 编译失败"
    }
    cp "$out/build/mgba_libretro.dylib" "$out/mgba_libretro.dylib"
}

# ---------- 3. framework 布局（复刻 iOS App 的 Frameworks/ 结构） ----------

layout_framework() {
    local name="$1" dylib="$2"
    local fw="$WORK/Frameworks/${name}_core.framework"
    mkdir -p "$fw"
    cp "$dylib" "$fw/${name}_core"
    chmod +x "$fw/${name}_core"
    cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>${name}_core</string>
<key>CFBundleIdentifier</key><string>com.miniretro.${name}-core</string>
<key>CFBundlePackageType</key><string>FMWK</string>
</dict></plist>
PLIST
}

# ---------- 4. 编译测试程序 ----------

build_harness() {
    log "编译端到端测试程序 ..."
    local logf="$WORK/harness-build.log"
    if ! clang++ -fobjc-arc -std=c++17 -isysroot "$SDK" -Wall -Wno-unused-function \
        -I "$ROOT/CoreBridge" \
        -framework Foundation -framework CoreGraphics -framework QuartzCore \
        -o "$WORK/e2e_test" \
        "$ROOT/Tests/e2e_test.mm" \
        "$ROOT/CoreBridge/RetroCore.mm" \
        "$ROOT/CoreBridge/FramePipeline.mm" \
        "$ROOT/CoreBridge/AudioRingBuffer.mm" \
        "$ROOT/CoreBridge/CoreRegistry.c" > "$logf" 2>&1; then
        grep -E 'error' "$logf" | head -8
        die "测试程序编译失败（完整日志：$logf）"
    fi
    [ -x "$WORK/e2e_test" ] || die "测试程序未生成"
}

# ---------- 主流程 ----------

TARGETS=("$@")
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=(fceumm sameboy mgba)

log "生成极简测试 ROM（homebrew，无版权内容）"
make_nes_rom; make_gb_rom; make_gba_rom

build_harness

FAILED=0
for t in "${TARGETS[@]}"; do
    case "$t" in
        fceumm)
            build_fceumm_macos
            layout_framework fceumm "$WORK/cores/fceumm/fceumm_libretro.dylib"
            echo ""
            echo "########## fceumm (FC/NES) ##########"
            ( cd "$WORK" && ./e2e_test fceumm test.nes 256 240 ) || FAILED=1
            ;;
        sameboy)
            build_sameboy_macos
            layout_framework sameboy "$WORK/cores/sameboy/sameboy_libretro.dylib"
            echo ""
            echo "########## SameBoy (GB) ##########"
            ( cd "$WORK" && ./e2e_test sameboy test.gb 160 144 ) || FAILED=1
            ;;
        mgba)
            build_mgba_macos
            layout_framework mgba "$WORK/cores/mgba/mgba_libretro.dylib"
            echo ""
            echo "########## mGBA (GBA) ##########"
            ( cd "$WORK" && ./e2e_test mgba test.gba 240 160 ) || FAILED=1
            ;;
        *) die "未知 core: $t" ;;
    esac
done

echo ""
if [ "$FAILED" -eq 0 ]; then
    log "全部通过。"
else
    die "有用例失败，见上方输出。"
fi
