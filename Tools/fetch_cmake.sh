#!/bin/bash
# Tools/fetch_cmake.sh — 下载 cmake 官方二进制到 Tools/vendor/cmake（macOS universal）
# 背景：ghcr.io 被部分网络环境拦截导致 brew install cmake 失败；
#       cmake.org 官方 tarball 通常可达。vendor 目录已加入 .gitignore。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/Tools/vendor"
CMAKE_HOME="$VENDOR/cmake"
CMAKE_BIN="$CMAKE_HOME/CMake.app/Contents/bin/cmake"

if [ -x "$CMAKE_BIN" ]; then
    echo "cmake 已存在: $CMAKE_BIN"
    exit 0
fi

VERSION="${1:-3.31.6}"
URL="https://cmake.org/files/v3.31/cmake-${VERSION}-macos-universal.tar.gz"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "下载 $URL ..."
curl -fL --retry 3 --max-time 300 -o "$TMP/cmake.tar.gz" "$URL"
mkdir -p "$VENDOR"
tar xzf "$TMP/cmake.tar.gz" -C "$TMP"
rm -rf "$CMAKE_HOME"
mv "$TMP/cmake-${VERSION}-macos-universal" "$CMAKE_HOME"

if [ -x "$CMAKE_BIN" ]; then
    echo "已安装: $CMAKE_BIN"
    "$CMAKE_BIN" --version | head -1
else
    echo "ERROR: 未找到 cmake 二进制" >&2
    exit 1
fi
