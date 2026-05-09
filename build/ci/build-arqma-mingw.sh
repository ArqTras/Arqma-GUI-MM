#!/usr/bin/env bash
# Build libwallet_merged.a with MinGW (run inside MSYS2 MINGW64 shell). CMake output: <upstream>/build-mingw/...
set +o posix 2>/dev/null || true
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UP="${ARQMA_WALLET2_UPSTREAM_DIR:-$ROOT/rust/arqma-rpc-upstream}"
BUILD_DIR="${ARQMA_MINGW_BUILD_DIR:-$UP/build-mingw}"

bash "$ROOT/build/ci/patch-arqma-epee-floor.sh" "$UP"
bash "$ROOT/build/ci/patch-arqma-mingw-gui.sh" "$UP"

mkdir -p "$BUILD_DIR"
# RandomX only adds `jit_compiler_x86.cpp` when ARCH_ID matches x86_64 (derived from
# CMAKE_SYSTEM_PROCESSOR). Some MSYS2 CMake runs leave it empty / wrong — then
# `librandomx.a` lacks `JitCompilerX86` and GNU ld fails when linking `wallet_merged`.
# `ARCH=native` enables `-march=native` for RandomX (optional; drop for strict reproducibility).
cmake -S "$UP" -B "$BUILD_DIR" \
  -G "MinGW Makefiles" \
  -D CMAKE_BUILD_TYPE=Release \
  -D CMAKE_SYSTEM_PROCESSOR=x86_64 \
  -D ARCH=native \
  -D BUILD_GUI_DEPS=ON \
  -D BUILD_TESTS=OFF

cmake --build "$BUILD_DIR" \
  --target epee easylogging randomx lmdb cryptonote_format_utils_basic wallet_merged \
  -j"$(nproc 2>/dev/null || echo 4)"
test -f "$BUILD_DIR/src/wallet/libwallet_merged.a"
echo "[build-arqma-mingw] OK: $BUILD_DIR/src/wallet/libwallet_merged.a"
