#!/usr/bin/env bash
# Reconfigure + build libwallet_merged.a on macOS (Homebrew deps expected).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UP="${ARQMA_WALLET2_UPSTREAM_DIR:-$ROOT/rust/arqma-rpc-upstream}"
cd "$UP"

BUILD_DIR="${ARQMA_CMAKE_BUILD_DIR:-$UP/build/ci-native-release}"
mkdir -p "$BUILD_DIR"

cmake -S "$UP" -B "$BUILD_DIR" \
  -D CMAKE_BUILD_TYPE=Release \
  -D BUILD_GUI_DEPS=ON \
  -D BUILD_TESTS=OFF

cmake --build "$BUILD_DIR" --target wallet_merged -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
test -f "$BUILD_DIR/src/wallet/libwallet_merged.a"
echo "[build-arqma-macos] OK: $BUILD_DIR/src/wallet/libwallet_merged.a"
