#!/bin/bash
# Tools/make_xcframework.sh — 纯 shell 构造 xcframework（不依赖 xcodebuild）
#
# 用途：在 xcodebuild 不可用（如未同意 Xcode 许可证）时，仍能把已编译的
#       device/simulator dylib 打包成 Xcode 可嵌入的 .xcframework。
# 用法：./Tools/make_xcframework.sh <name> <device.dylib> [simulator.dylib]
#   例：./Tools/make_xcframework.sh mgba /tmp/mgba.dylib /tmp/mgba_sim.dylib
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAME="$1"
DEVICE_DYLIB="$2"
SIM_DYLIB="${3:-}"
OUT="$ROOT/Cores/artifacts/${NAME}-core.xcframework"
SDK_VERSION="${SDK_VERSION:-27.1}"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-17.0}"
VT="/Library/Developer/CommandLineTools/usr/bin/vtool"

log() { echo -e "\033[1;36m[xcf]\033[0m $*"; }
die() { echo -e "\033[1;31m[xcf] ERROR:\033[0m $*" >&2; exit 1; }

[ -f "$DEVICE_DYLIB" ] || die "device dylib 不存在: $DEVICE_DYLIB"
mkdir -p "$(dirname "$OUT")"
rm -rf "$OUT"

# 修正 minos（Makefile 链接阶段可能没传版本号，导致 dylib 只能装到当前 SDK 版本）
normalize_minos() {
    local src="$1" dst="$2"
    if "$VT" -show-build "$src" 2>/dev/null | grep -q "minos $DEPLOYMENT_TARGET"; then
        cp "$src" "$dst"
    else
        "$VT" -set-build-version ios "$DEPLOYMENT_TARGET" "$SDK_VERSION" -replace -output "$dst" "$src"
        log "已修正 minos → $DEPLOYMENT_TARGET ($(basename "$src"))"
    fi
}

# 单 slice：framework 目录结构
make_slice() {
    local dylib="$1" slice_dir="$2" platform="$3"
    local fw="$slice_dir/${NAME}_core.framework"
    mkdir -p "$fw"
    normalize_minos "$dylib" "$fw/${NAME}_core"
    chmod +x "$fw/${NAME}_core"
    cat > "$fw/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>${NAME}_core</string>
<key>CFBundleIdentifier</key><string>com.miniretro.${NAME}-core</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>MinimumOSVersion</key><string>${DEPLOYMENT_TARGET}</string>
</dict></plist>
PLIST
}

make_slice "$DEVICE_DYLIB" "$OUT/ios-arm64" "ios"
IDENTIFIERS='<dict>
                <key>LibraryIdentifier</key>
                <string>ios-arm64</string>
                <key>LibraryPath</key>
                <string>'"${NAME}"'_core.framework</string>
                <key>SupportedArchitectures</key>
                <array><string>arm64</string></array>
                <key>SupportedPlatform</key>
                <string>ios</string>
            </dict>'

if [ -n "$SIM_DYLIB" ] && [ -f "$SIM_DYLIB" ]; then
    make_slice "$SIM_DYLIB" "$OUT/ios-arm64-simulator" "ios-simulator"
    IDENTIFIERS="$IDENTIFIERS
            <dict>
                <key>LibraryIdentifier</key>
                <string>ios-arm64-simulator</string>
                <key>LibraryPath</key>
                <string>${NAME}_core.framework</string>
                <key>SupportedArchitectures</key>
                <array><string>arm64</string></array>
                <key>SupportedPlatform</key>
                <string>ios</string>
                <key>SupportedPlatformVariant</key>
                <string>simulator</string>
            </dict>"
fi

cat > "$OUT/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>AvailableLibraries</key>
    <array>
            $IDENTIFIERS
    </array>
    <key>CFBundlePackageType</key>
    <string>XFWK</string>
    <key>XCFrameworkFormatVersion</key>
    <string>1.0</string>
</dict></plist>
PLIST

log "已生成 $OUT"
find "$OUT" -name '*.dylib' -o -name "${NAME}_core" | while read -r f; do
    echo "  $(basename "$f") : $("$VT" -show-build "$f" 2>/dev/null | grep -E 'minos' | head -1 | tr -s ' ')"
done
