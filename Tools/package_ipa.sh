#!/bin/bash
# Tools/package_ipa.sh — 将 xcodebuild 产物打包为未签名 .ipa
# 结构：Payload/MiniRetro.app → zip → MiniRetro-<version>.ipa
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
PRODUCTS_DIR="$BUILD_DIR/Build/Products/Release-iphoneos"
APP="$PRODUCTS_DIR/MiniRetro.app"

log() { echo -e "\033[1;32m[package]\033[0m $*"; }
die() { echo -e "\033[1;31m[package] ERROR:\033[0m $*" >&2; exit 1; }

[ -d "$APP" ] || die "未找到 $APP（xcodebuild 是否成功？）"

# 读取版本号
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Info.plist" 2>/dev/null || echo "1.0")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Info.plist" 2>/dev/null || echo "1")"
IPA_NAME="MiniRetro-${VERSION}-${BUILD_NUMBER}-unsigned.ipa"
if [ -n "${ADHOC:-}" ]; then
    IPA_NAME="MiniRetro-${VERSION}-${BUILD_NUMBER}-adhoc.ipa"
fi

STAGING="$BUILD_DIR/ipa-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING/Payload"
cp -R "$APP" "$STAGING/Payload/"

# 校验三个 core framework 已嵌入
for core in mgba_core sameboy_core fceumm_core; do
    [ -d "$APP/Frameworks/${core}.framework" ] || die "App 缺少 ${core}.framework（检查 project.yml embed 配置）"
done

cd "$STAGING"
rm -f "$ROOT/build/$IPA_NAME"
zip -qry "$ROOT/build/$IPA_NAME" Payload
cd "$ROOT"

log "已产出: build/$IPA_NAME"
log "大小: $(du -h "$ROOT/build/$IPA_NAME" | cut -f1)"
log ""
log "安装方式（用户自备签名工具）："
log "  - Sideloadly / AltStore：拖入 ipa 后用 Apple ID 签名安装"
log "  - 若签名工具不接受未签名 ipa，请使用 ./Tools/build.sh --adhoc 重新构建"
