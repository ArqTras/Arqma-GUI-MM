#!/usr/bin/env bash
# Configure + build libwallet_merged.a on Linux (Debian/Ubuntu-style CI).
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

# rust/arqma-wallet2-api/src/lib.rs expects libepee.a, libeasylogging.a, etc. on the link path.
cmake --build "$BUILD_DIR" \
  --target epee easylogging randomx lmdb cryptonote_format_utils_basic wallet_merged \
  -j"$(nproc)"
test -f "$BUILD_DIR/src/wallet/libwallet_merged.a"
echo "[build-arqma-linux] OK: $BUILD_DIR/src/wallet/libwallet_merged.a"
