#!/bin/bash
# Tools/fetch_rgbds.sh — 在 brew 不可用时，从源码构建 rgbds（rgbasm/rgblink/rgbfix）
#
# 背景：SameBoy 的 boot ROM 由 BootROMs/*.asm 经 rgbds 汇编生成；
#       brew install rgbds 是首选，本脚本是备选（沙箱/受限网络环境已验证可行）。
# 依赖：clang++（Xcode CLT）、bison >= 3.x（系统自带 2.3 太老时自动源码编译）、m4
# 注意：rgbgfx（PNG → 2bpp，SameBoy logo 用）需要 libpng；本脚本不构建 rgbgfx，
#       若缺 rgbgfx，SameBoy 构建会卡在 BootROMs/SameBoyLogo 生成步骤。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/Tools/vendor"
BIN_DIR="$VENDOR/rgbds/bin"
RGBDS_VERSION="${1:-1.0.4}"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ -x "$BIN_DIR/rgbasm" ]; then
    echo "rgbds 已存在: $BIN_DIR/rgbasm"
    "$BIN_DIR/rgbasm" --version
    exit 0
fi

mkdir -p "$BIN_DIR"

# 1. bison 版本检查（rgbds 要求 >= 3.0）
BISON_BIN="$(command -v bison || true)"
BISON_OK=0
if [ -n "$BISON_BIN" ]; then
    BISON_VER="$("$BISON_BIN" --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
    MAJOR="${BISON_VER%%.*}"
    if [ "${MAJOR:-0}" -ge 3 ]; then
        BISON_OK=1
    fi
fi

if [ "$BISON_OK" -eq 0 ]; then
    echo "系统 bison 过旧或缺失，构建 bison 3.8.2 ..."
    curl -fL --retry 3 -o "$WORK/bison.tar.xz" "https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.xz"
    tar xf "$WORK/bison.tar.xz" -C "$WORK"
    ( cd "$WORK/bison-3.8.2" && ./configure --prefix="$WORK/bison-install" >/dev/null && make -j"$(sysctl -n hw.ncpu)" >/dev/null && make install >/dev/null )
    export PATH="$WORK/bison-install/bin:$PATH"
fi

# 2. 下载 rgbds 源码
echo "下载 rgbds v${RGBDS_VERSION} 源码 ..."
curl -fL --retry 3 -o "$WORK/rgbds.tar.gz" "https://codeload.github.com/gbdev/rgbds/tar.gz/refs/tags/v${RGBDS_VERSION}"
tar xzf "$WORK/rgbds.tar.gz" -C "$WORK"
SRC="$WORK/rgbds-${RGBDS_VERSION}"

# 3. 编译（只构建 Asm/Link/Fix，跳过需要 libpng 的 rgbgfx）
echo "编译 rgbasm / rgblink / rgbfix ..."
make -C "$SRC" CXX=clang++ \
    CXXFLAGS="-O2 -isysroot $SDK -I$SDK/usr/include/c++/v1" \
    rgbasm rgblink rgbfix -j"$(sysctl -n hw.ncpu)" >"$WORK/build.log" 2>&1 || {
        tail -30 "$WORK/build.log"
        echo "编译失败。可尝试：brew install rgbds" >&2
        exit 1
    }

cp "$SRC/rgbasm" "$SRC/rgblink" "$SRC/rgbfix" "$BIN_DIR/"
echo "已安装到 $BIN_DIR:"
"$BIN_DIR/rgbasm" --version
"$BIN_DIR/rgblink" --version
