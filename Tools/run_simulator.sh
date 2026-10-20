#!/bin/bash
# Tools/run_simulator.sh — 在 iOS 模拟器中安装并启动 App，截图验证
#
# 前置：已安装模拟器 runtime（xcodebuild -downloadPlatform iOS）
# 用法：./Tools/run_simulator.sh [设备名]   默认 "iPad Air"
# 产物：/tmp/miniretro-sim/screenshot-*.png
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Build/Products/Release-iphoneos/MiniRetro.app"
OUT="/tmp/miniretro-sim"
DEVICE_NAME="${1:-iPad Air}"
BUNDLE_ID="com.miniretro.app"

log() { echo -e "\033[1;36m[sim]\033[0m $*"; }
die() { echo -e "\033[1;31m[sim] ERROR:\033[0m $*" >&2; exit 1; }

[ -d "$APP" ] || die "未找到 $APP，请先运行 ./Tools/build.sh"
mkdir -p "$OUT"

# 1. runtime 检查
if ! xcrun simctl list runtimes | grep -q "iOS"; then
    die "未安装 iOS 模拟器 runtime。请运行：xcodebuild -downloadPlatform iOS"
fi

# 2. 找设备（没有就创建）
UDID="$(xcrun simctl list devices available | grep -E "^\s+${DEVICE_NAME} \(" | head -1 | grep -oE '[0-9A-F-]{36}' || true)"
if [ -z "$UDID" ]; then
    RT="$(xcrun simctl list runtimes | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+' | tail -1)"
    DT="$(xcrun simctl list devicetypes | grep -E "${DEVICE_NAME}" | head -1 | grep -oE 'com\.apple\.CoreSimulator\.SimDeviceType\.[A-Za-z0-9.-]+' || true)"
    [ -n "$DT" ] && [ -n "$RT" ] || die "找不到设备类型「${DEVICE_NAME}」或 runtime"
    UDID="$(xcrun simctl create "MiniRetro-${DEVICE_NAME}" "$DT" "$RT")"
    log "已创建模拟器 $UDID"
fi
log "使用设备 $UDID"

# 3. 启动
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1 || true
open -a Simulator --args -CurrentDeviceUDID "$UDID" 2>/dev/null || true
sleep 3

# 4. 安装 + 启动
log "安装 App ..."
xcrun simctl install "$UDID" "$APP"
log "启动 App ..."
xcrun simctl launch "$UDID" "$BUNDLE_ID" 2>&1 | tee "$OUT/launch.log"
sleep 6

# 5. 截图
xcrun simctl io "$UDID" screenshot "$OUT/screenshot-1-launch.png" > /dev/null 2>&1 || true
log "启动截图: $OUT/screenshot-1-launch.png"

# 6. 崩溃检查
if xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -q "$BUNDLE_ID"; then
    log "进程存活（未崩溃）"
else
    echo "[sim] 警告：进程可能已退出，检查日志："
    xcrun simctl spawn "$UDID" log show --last 1m --predicate "process == \"MiniRetro\"" 2>/dev/null | tail -20 || true
fi

log "完成。截图目录: $OUT"
