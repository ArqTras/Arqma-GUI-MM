#!/usr/bin/env bash
# Reconfigure + build libwallet_merged.a on macOS (Homebrew deps expected).
set +o posix 2>/dev/null || true
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UP="${ARQMA_WALLET2_UPSTREAM_DIR:-$ROOT/rust/arqma-rpc-upstream}"
cd "$UP"

bash "$ROOT/build/ci/patch-arqma-epee-floor.sh" "$UP"

BUILD_DIR="${ARQMA_CMAKE_BUILD_DIR:-$UP/build/ci-native-release}"
mkdir -p "$BUILD_DIR"

cmake -S "$UP" -B "$BUILD_DIR" \
  -D CMAKE_BUILD_TYPE=Release \
  -D BUILD_GUI_DEPS=ON \
  -D BUILD_TESTS=OFF

# rust/arqma-wallet2-api/src/lib.rs links these static libs (+ wallet_merged). Building only
# wallet_merged leaves libepee.a etc. unbuilt → rustc: could not find native static library `epee`.
J="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
cmake --build "$BUILD_DIR" \
  --target epee easylogging randomx lmdb cryptonote_format_utils_basic wallet_merged \
  -j"$J"
test -f "$BUILD_DIR/src/wallet/libwallet_merged.a"
echo "[build-arqma-macos] OK: $BUILD_DIR/src/wallet/libwallet_merged.a"
