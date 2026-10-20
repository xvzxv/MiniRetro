#!/bin/bash
# build_cores.sh — 将三个 libretro core 交叉编译为 iOS xcframework（M0）
#
# 产物：Cores/artifacts/{mgba,sameboy,fceumm}-core.xcframework（真机 arm64 + 模拟器 arm64）
# 版本锁定（ADR-002，变更需同步更新计划书 ADR 备注）：
#   mGBA     mgba-emu/mgba @ 0.10.5 (tag)
#   SameBoy  LIJI32/SameBoy @ v1.0.4 (tag)
#   fceumm   libretro/libretro-fceumm @ ac0d00a7fc01166f84c7bac01d1084ebfd2b865e (master)
#
# 依赖：Xcode 16+（iOS 26 SDK，向下编译 17.0）、cmake（brew install cmake，mgba 用）、
#       rgbds（brew install rgbds，SameBoy boot ROM 汇编用）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORES_DIR="$ROOT/Cores"
ARTIFACTS_DIR="$CORES_DIR/artifacts"
# 关键：构建目录必须不含空格。libretro Makefile 的 $(abspath) 在含空格路径下会被截断
# （SameBoy/fceumm 官方 Makefile 均未处理空格），因此统一在 TMPDIR 下构建。
BUILD_DIR="${TMPDIR:-/tmp}/miniretro-cores-build"
BUILD_DIR="${BUILD_DIR%/}"
IPHONEOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
IPHONESIMULATOR_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
DEPLOYMENT_TARGET="17.0"
SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null || echo 27.1)"
JOBS="$(sysctl -n hw.ncpu)"

mkdir -p "$ARTIFACTS_DIR" "$BUILD_DIR"

log() { echo -e "\033[1;32m[build_cores]\033[0m $*"; }
warn() { echo -e "\033[1;33m[build_cores]\033[0m $*"; }
die() { echo -e "\033[1;31m[build_cores] ERROR:\033[0m $*" >&2; exit 1; }

check_dependencies() {
    command -v xcodebuild >/dev/null || die "需要 Xcode 命令行工具"
    # cmake 优先用 PATH，其次 Tools/vendor/cmake，都没有则尝试自动下载
    if ! command -v cmake >/dev/null; then
        local vendored="$ROOT/Tools/vendor/cmake/CMake.app/Contents/bin/cmake"
        if [ -x "$vendored" ]; then
            export PATH="$(dirname "$vendored"):$PATH"
        else
            log "未检测到 cmake，尝试通过 Tools/fetch_cmake.sh 获取 ..."
            "$ROOT/Tools/fetch_cmake.sh" || die "cmake 获取失败，请手动安装：brew install cmake"
            export PATH="$(dirname "$vendored"):$PATH"
        fi
    fi
    # rgbds（SameBoy boot ROM 汇编）：PATH → Tools/vendor/rgbds → 报错提示
    if ! command -v rgbasm >/dev/null; then
        local vendored_rgbds="$ROOT/Tools/vendor/rgbds/bin"
        if [ -x "$vendored_rgbds/rgbasm" ]; then
            export PATH="$vendored_rgbds:$PATH"
        else
            die "缺少 rgbds（SameBoy boot ROM 汇编需要）：brew install rgbds（或运行 Tools/fetch_rgbds.sh）"
        fi
    fi
    if ! command -v rgbgfx >/dev/null; then
        warn "未检测到 rgbgfx（SameBoy logo 转换需要）——缺它会卡在 BootROMs/SameBoyLogo 生成。brew install rgbds 或放入 Tools/vendor/rgbds/bin/"
    fi
}

# 为 xcframework 准备公共 headers 目录（只含 libretro.h）
prepare_headers() {
    local out="$1"
    mkdir -p "$out"
    cp "$CORES_DIR/libretro.h" "$out/"
}

# 把裸 dylib 包装成标准 .framework（xcframework 的一个 slice）
# 含 minos 校正：部分 core 的 Makefile 链接阶段未传 -miphoneos-version-min，
# 会让 dylib 的 minos 等于当前 SDK 版本（如 27.0），从而只能装到该版本系统。
make_framework() {
    local dylib="$1" name="$2" outdir="$3"
    local fw="$outdir/${name}_core.framework"
    rm -rf "$fw"
    mkdir -p "$fw"
    cp "$dylib" "$fw/${name}_core"
    install_name_tool -id "@rpath/${name}_core.framework/${name}_core" "$fw/${name}_core"

    local vt
    vt="$(xcrun --find vtool 2>/dev/null || echo /usr/bin/vtool)"
    if ! "$vt" -show-build "$fw/${name}_core" 2>/dev/null | grep -q "minos $DEPLOYMENT_TARGET"; then
        if "$vt" -set-build-version ios "$DEPLOYMENT_TARGET" "$SDK_VERSION" -replace \
            -output "$fw/${name}_core.tmp" "$fw/${name}_core"; then
            mv "$fw/${name}_core.tmp" "$fw/${name}_core"
            log "minos 已校正为 ${DEPLOYMENT_TARGET}（${name}）"
        else
            warn "minios 校正失败（${name}），dylib 可能只能在较新系统安装"
        fi
    fi

    cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key>
    <string>${name}_core</string>
    <key>CFBundleIdentifier</key>
    <string>com.miniretro.${name}-core</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>${DEPLOYMENT_TARGET}</string>
</dict></plist>
PLIST
    echo "$fw"
}

# 打包 xcframework：优先用 xcodebuild（标准）；不可用时回退到纯 shell 实现
# 两者都会把 dylib 的 minos 校正到部署目标（Makefile 链接阶段常漏传版本号）
package_xcframework() {
    local name="$1" device_dylib="$2" sim_dylib="$3"
    local output="$ARTIFACTS_DIR/${name}-core.xcframework"

    if command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
        local device_fw sim_fw
        device_fw="$(make_framework "$device_dylib" "$name" "$BUILD_DIR/frameworks-device")"
        sim_fw="$(make_framework "$sim_dylib" "$name" "$BUILD_DIR/frameworks-simulator")"
        rm -rf "$output"
        xcodebuild -create-xcframework \
            -framework "$device_fw" \
            -framework "$sim_fw" \
            -output "$output" >/dev/null
        log "已产出 ${output}（xcodebuild）"
    else
        warn "xcodebuild 不可用（未同意 Xcode 许可证？），改用纯 shell 打包"
        SDK_VERSION="$SDK_VERSION" DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
            "$ROOT/Tools/make_xcframework.sh" "$name" "$device_dylib" "$sim_dylib"
    fi
}

# MARK: - mGBA（CMake 构建，源文件列表由 CMake 解析，不怕版本变动）

build_mgba() {
    log "构建 mGBA (0.10.5) ..."
    local src="$CORES_DIR/mgba"
    [ -d "$src/src/platform/libretro" ] || die "缺少 mgba 源码：$src"

    for variant in device simulator; do
        local build="$BUILD_DIR/mgba-$variant"
        rm -rf "$build"
        local sysroot sdk arch triple
        if [ "$variant" = "device" ]; then
            sysroot="$IPHONEOS_SDK"; triple="arm64-apple-ios"
        else
            sysroot="$IPHONESIMULATOR_SDK"; triple="arm64-apple-ios-simulator"
        fi
        cmake -S "$src" -B "$build" \
            -DCMAKE_SYSTEM_NAME=iOS \
            -DCMAKE_OSX_SYSROOT="$sysroot" \
            -DCMAKE_OSX_ARCHITECTURES=arm64 \
            -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
            -DCMAKE_C_COMPILER=clang \
            -DBUILD_LIBRETRO=ON \
            -DLIBMGBA_ONLY=ON \
            -DDISABLE_FRONTENDS=ON \
            -DDISABLE_DEPS=ON \
            -DCMAKE_BUILD_TYPE=Release > "$build-cmake.log" 2>&1 || {
                tail -40 "$build-cmake.log"; die "mGBA cmake 配置失败（${variant}）"
            }
        cmake --build "$build" -j"$JOBS" > "$build-build.log" 2>&1 || {
                tail -40 "$build-build.log"; die "mGBA 编译失败（${variant}）"
            }
    done

    local device_lib="$BUILD_DIR/mgba-device/mgba_libretro.dylib"
    local sim_lib="$BUILD_DIR/mgba-simulator/mgba_libretro.dylib"
    [ -f "$device_lib" ] || die "未找到 mGBA device 产物"
    [ -f "$sim_lib" ] || die "未找到 mGBA simulator 产物"
    package_xcframework "mgba" "$device_lib" "$sim_lib"
}

# MARK: - SameBoy（libretro/Makefile，platform=ios-arm64；cheat 走构建期补丁，ADR-003）

build_sameboy() {
    log "构建 SameBoy (1.0.4) ..."
    local src="$CORES_DIR/sameboy"
    [ -f "$src/libretro/Makefile" ] || die "缺少 SameBoy 源码：$src"

    local work="$BUILD_DIR/sameboy"
    rm -rf "$work"
    mkdir -p "$work"
    # 拷贝源码树（构建补丁不污染上游 submodule 快照）
    cp -R "$src/." "$work/"
    rm -rf "$work/.git"

    # 补丁 1：启用原生 cheat 实现
    #   - Makefile.common 去掉 -DGB_DISABLE_CHEATS
    #   - SOURCES_C 补上 Core/cheats.c（原构建未编译该文件，去掉宏后需要链接实现）
    python3 - "$work" <<'PYEOF'
import sys, pathlib
work = pathlib.Path(sys.argv[1])
mk = work / "libretro" / "Makefile.common"
text = mk.read_text()
text = text.replace("-DGB_DISABLE_CHEATS", "")
if "Core/cheats.c" not in text:
    anchor = "$(CORE_DIR)/Core/rumble.c \\"
    if anchor in text:
        text = text.replace(anchor, anchor + "\n               $(CORE_DIR)/Core/cheats.c \\")
    else:
        # 兜底：追加到 SOURCES_C 首个条目后
        text = text.replace("SOURCES_C   := $(CORE_DIR)/Core/gb.c \\",
                            "SOURCES_C   := $(CORE_DIR)/Core/gb.c \\\n               $(CORE_DIR)/Core/cheats.c \\")
mk.write_text(text)
print(f"[patch] Makefile.common: DISABLE_CHEATS removed={'-DGB_DISABLE_CHEATS' not in text}, cheats.c added={'Core/cheats.c' in text}")
PYEOF

    # 补丁 2：把 libretro.c 里的 cheat 空 stub 替换为 SameBoy 原生 API 桥接
    #   (ADR-003 实测：SameBoy 1.0.4 的 retro_cheat_set 仅为空实现，需桥接 GB_import_cheat)
    python3 - "$work" <<'PYEOF'
import sys, pathlib
work = pathlib.Path(sys.argv[1])
c = work / "libretro" / "libretro.c"
text = c.read_text()
if "miniretro_cheat_patch" not in text:
    stub = '''void retro_cheat_reset(void)
{}

void retro_cheat_set(unsigned index, bool enabled, const char *code)
{
    (void)index;
    (void)enabled;
    (void)code;
}'''
    replacement = '''/* === miniretro_cheat_patch (ADR-003): stub -> SameBoy 原生 cheat API === */
#include "Core/cheats.h" /* -I.. 可解析 */

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
    assert stub in text, "未找到 SameBoy cheat stub 原文，版本可能已变化，请更新补丁"
    text = text.replace(stub, replacement, 1)
    c.write_text(text)
    print("[patch] libretro.c: cheat stub replaced with native bridge")
else:
    print("[patch] libretro.c: already patched, skip")
PYEOF

    for variant in device simulator; do
        local build="$BUILD_DIR/sameboy-$variant"
        rm -rf "$build"
        cp -R "$work/." "$build/"
        local sdk cc
        if [ "$variant" = "device" ]; then
            sdk="$IPHONEOS_SDK"
            cc="clang -arch arm64 -isysroot $sdk -miphoneos-version-min=$DEPLOYMENT_TARGET"
        else
            sdk="$IPHONESIMULATOR_SDK"
            cc="clang -arch arm64 -target arm64-apple-ios$DEPLOYMENT_TARGET-simulator -isysroot $sdk"
        fi
        # 不能走根 Makefile 的 libretro target —— 它用 `CC=$(CC) $(MAKE) ...` 拼进 shell，
        # CC 含空格（clang -arch arm64 -isysroot ...）会被解析成 `-arch: command not found`。
        # 改为两步：先单独生成 boot ROM，再直接编 libretro 子目录。
        local native_cc="/Library/Developer/CommandLineTools/usr/bin/clang -isysroot /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
        ( cd "$build" && make bootroms NATIVE_CC="$native_cc" -j"$JOBS" ) >> "$build-make.log" 2>&1 || {
            tail -20 "$build-make.log"; die "SameBoy boot ROM 生成失败（${variant}）"
        }
        make -C "$build/libretro" \
            platform=ios-arm64 \
            CC="$cc" \
            CXX="$cc" \
            IOSSDK="$sdk" \
            BOOTROMS_DIR="$build/build/bin/BootROMs" \
            BIN="$build/build/bin" \
            -j"$JOBS" >> "$build-make.log" 2>&1 || {
                tail -40 "$build-make.log"; die "SameBoy 编译失败（${variant}）"
            }
    done

    local device_lib="$BUILD_DIR/sameboy-device/build/bin/sameboy_libretro_ios.dylib"
    local sim_lib="$BUILD_DIR/sameboy-simulator/build/bin/sameboy_libretro_ios.dylib"
    [ -f "$device_lib" ] || die "未找到 SameBoy device 产物"
    [ -f "$sim_lib" ] || die "未找到 SameBoy simulator 产物"
    package_xcframework "sameboy" "$device_lib" "$sim_lib"
}

# MARK: - fceumm（libretro/Makefile，platform=ios-arm64）

build_fceumm() {
    log "构建 fceumm ..."
    local src="$CORES_DIR/fceumm"
    [ -f "$src/Makefile.libretro" ] || die "缺少 fceumm 源码：$src"

    for variant in device simulator; do
        local build="$BUILD_DIR/fceumm-$variant"
        rm -rf "$build"
        cp -R "$src/." "$build/"
        rm -rf "$build/.git"
        local sdk cc
        if [ "$variant" = "device" ]; then
            sdk="$IPHONEOS_SDK"
            cc="clang -arch arm64 -isysroot $sdk -miphoneos-version-min=$DEPLOYMENT_TARGET"
        else
            sdk="$IPHONESIMULATOR_SDK"
            cc="clang -arch arm64 -target arm64-apple-ios$DEPLOYMENT_TARGET-simulator -isysroot $sdk"
        fi
        make -C "$build" -f Makefile platform=ios-arm64 \
            CC="$cc" \
            IOSSDK="$sdk" \
            -j"$JOBS" > "$build-make.log" 2>&1 || {
                tail -40 "$build-make.log"; die "fceumm 编译失败（${variant}）"
            }
    done

    local device_lib="$BUILD_DIR/fceumm-device/fceumm_libretro_ios.dylib"
    local sim_lib="$BUILD_DIR/fceumm-simulator/fceumm_libretro_ios.dylib"
    [ -f "$device_lib" ] || die "未找到 fceumm device 产物"
    [ -f "$sim_lib" ] || die "未找到 fceumm simulator 产物"
    package_xcframework "fceumm" "$device_lib" "$sim_lib"
}

# MARK: - 入口

check_dependencies

TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
    TARGETS=(mgba sameboy fceumm)
fi

for target in "${TARGETS[@]}"; do
    case "$target" in
        mgba) build_mgba ;;
        sameboy) build_sameboy ;;
        fceumm) build_fceumm ;;
        *) die "未知 core: ${target}（可选 mgba|sameboy|fceumm）" ;;
    esac
done

log "全部完成。产物位于 ${ARTIFACTS_DIR}："
ls -la "$ARTIFACTS_DIR"
