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
# XcodeGen：PATH → Tools/vendor → 报错
if ! command -v xcodegen >/dev/null; then
    if [ -x "$ROOT/Tools/vendor/xcodegen/bin/xcodegen" ]; then
        export PATH="$ROOT/Tools/vendor/xcodegen/bin:$PATH"
    else
        die "需要 XcodeGen：brew install xcodegen（或放到 Tools/vendor/xcodegen/bin/）"
    fi
fi

# 2. 编译 core xcframeworks
if [ "$SKIP_CORES" -eq 0 ]; then
    log "编译 libretro cores ..."
    "$ROOT/Cores/build_cores.sh"
else
    log "跳过 core 编译（--skip-cores）"
    for core in mgba sameboy fceumm; do
        [ -d "Cores/artifacts/${core}-core.xcframework" ] || die "缺少 $core xcframework，请先不带 --skip-cores 构建"
    done
    # FBNeo 产物 99MB 不入库：缺失时自动补建（仅首次，约 40 分钟）
    if [ ! -d "Cores/artifacts/fbneo-core.xcframework" ]; then
        log "缺少 FBNeo xcframework，自动补建（首次约 40 分钟）..."
        "$ROOT/Cores/build_cores.sh" fbneo || die "FBNeo 补建失败"
    fi
fi

# 3. 生成 Xcode 工程
log "xcodegen generate ..."
xcodegen generate

# 4. 构建 App（真机，Release，不签名）
log "xcodebuild ..."
BUILD_DIR="$ROOT/build"

# Xcode 27 的宏服务（swift-plugin-server）两类故障，都不是代码问题：
#  1) 进程僵死 → 100+ 条 "SwiftUIMacros.StateMacro ... produced malformed response"；
#     杀掉僵死进程 + 低并发（-jobs 4）可恢复。
#  2) 宏服务本身要再套一层 sandbox-exec（"sandbox_apply: Operation not permitted"）→
#     在已受沙箱约束的终端/CI 里必然失败，症状与 1) 完全一样。
#     根治办法：给 swiftc 传 -disable-sandbox，不再为宏服务套沙箱（见 3)。
clear_plugin_server() {
    pkill -9 -f swift-plugin-server 2>/dev/null || true
    sleep 2   # 实测 1s 不够，宏服务可能尚未退出干净
}

run_xcodebuild() {
    local extra_flags=("$@")
    xcodebuild \
        -scheme MiniRetro \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR" \
        -destination 'generic/platform=iOS' \
        -jobs 4 \
        OTHER_SWIFT_FLAGS="-disable-sandbox" \
        "${extra_flags[@]}" \
        clean build
}

if [ "$ADHOC" -eq 1 ]; then
    log "使用 ad-hoc 签名（CODE_SIGN_IDENTITY=-）"
    EXTRA=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=)
else
    EXTRA=(CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=)
fi

# 默认不做文件系统级整目录删除（本机安全钩子会拦截批量 rm），
# xcodebuild 的 clean build 已足够；如需彻底清派生数据：MR_CLEAN_BUILD_DIR=1 ./Tools/build.sh
clean_build_dir() {
    if [ "${MR_CLEAN_BUILD_DIR:-0}" = "1" ]; then
        rm -rf "$BUILD_DIR"
    fi
}

clear_plugin_server
clean_build_dir
if ! run_xcodebuild "${EXTRA[@]}"; then
    echo ""
    log "构建失败，按 Xcode 27 已知问题流程重试一次（重启宏服务后重试）..."
    clear_plugin_server
    clean_build_dir
    run_xcodebuild "${EXTRA[@]}" || die "xcodebuild 仍失败，请查看上方错误；若为宏错误见 docs/maintenance.md 第 6 节"
fi

# 5. 打包未签名 ipa
log "打包 ipa ..."
"$ROOT/Tools/package_ipa.sh"

# 交付产物统一放 dist/（git 不跟踪，便于用户直接取用）
mkdir -p "$ROOT/dist"
cp -f "$ROOT"/build/*.ipa "$ROOT/dist/" 2>/dev/null || true

log "完成！"
