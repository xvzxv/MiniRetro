#!/bin/bash
# Tools/build.sh — Mac 本地一键构建：cores → xcodegen → xcodebuild → 未签名 ipa
#
# 用法：
#   ./Tools/build.sh            # 全量构建，产出未签名 .ipa（CODE_SIGNING_ALLOWED=NO）
#   ./Tools/build.sh --adhoc    # ad-hoc 签名（CODE_SIGN_IDENTITY=-），部分签名工具需要
#   ./Tools/build.sh --skip-cores   # 跳过 core 编译（调试 App 层时加速）
#
# 依赖（README 有完整说明）：
#   Xcode 16+ / XcodeGen / cmake / rgbds（brew install xcodegen cmake rgbds）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ADHOC=0
SKIP_CORES=0
for arg in "$@"; do
    case "$arg" in
        --adhoc) ADHOC=1 ;;
        --skip-cores) SKIP_CORES=1 ;;
        *) echo "未知参数: $arg" >&2; exit 1 ;;
    esac
done

log() { echo -e "\033[1;32m[build]\033[0m $*"; }
die() { echo -e "\033[1;31m[build] ERROR:\033[0m $*" >&2; exit 1; }

# 1. 依赖检查
command -v xcodebuild >/dev/null || die "需要 Xcode 命令行工具（xcode-select --install 或安装 Xcode）"
command -v xcodegen >/dev/null || die "需要 XcodeGen：brew install xcodegen"

# 2. 编译 core xcframeworks
if [ "$SKIP_CORES" -eq 0 ]; then
    log "编译 libretro cores ..."
    "$ROOT/Cores/build_cores.sh"
else
    log "跳过 core 编译（--skip-cores）"
    for core in mgba sameboy fceumm; do
        [ -d "Cores/artifacts/${core}-core.xcframework" ] || die "缺少 $core xcframework，请先不带 --skip-cores 构建"
    done
fi

# 3. 生成 Xcode 工程
log "xcodegen generate ..."
xcodegen generate

# 4. 构建 App（真机，Release，不签名）
log "xcodebuild ..."
BUILD_DIR="$ROOT/build"
rm -rf "$BUILD_DIR"

if [ "$ADHOC" -eq 1 ]; then
    log "使用 ad-hoc 签名（CODE_SIGN_IDENTITY=-）"
    xcodebuild \
        -scheme MiniRetro \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR" \
        -destination 'generic/platform=iOS' \
        -archivePath "$BUILD_DIR/MiniRetro.xcarchive" \
        CODE_SIGNING_ALLOWED=YES \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        DEVELOPMENT_TEAM="" \
        clean build
else
    xcodebuild \
        -scheme MiniRetro \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR" \
        -destination 'generic/platform=iOS' \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGN_IDENTITY="" \
        DEVELOPMENT_TEAM="" \
        clean build
fi

# 5. 打包未签名 ipa
log "打包 ipa ..."
"$ROOT/Tools/package_ipa.sh"

log "完成！"
