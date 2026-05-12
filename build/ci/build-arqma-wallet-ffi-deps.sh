#!/usr/bin/env bash
# Build only the CMake targets needed for arqma-wallet2-api / arqma-wallet-flutter-ffi:
# static archives that rustc links (see rust/arqma-wallet2-api/build.rs), plus wallet_merged.
# This does NOT run a blanket `cmake --build` of the whole Arqma tree (no arqmad, no rpc, etc.).
#
# Upstream: arqtras/arqma (fork) — clone with build/ci/clone-arqma.sh first (ARQMA_UPSTREAM_REF, default pospow).
#
# Usage:
#   bash build/ci/build-arqma-wallet-ffi-deps.sh linux|macos|mingw
#   ARQMA_WALLET_FFI_PLATFORM=linux bash build/ci/build-arqma-wallet-ffi-deps.sh
#
# Env:
#   ARQMA_WALLET2_UPSTREAM_DIR  — Arqma core root (default: <repo>/rust/arqma-rpc-upstream)
#   ARQMA_CMAKE_BUILD_DIR       — Linux/macOS CMake build dir (default: <upstream>/build/ci-native-release)
#   ARQMA_MINGW_BUILD_DIR       — MinGW build dir (default: <upstream>/build-mingw)
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UP="${ARQMA_WALLET2_UPSTREAM_DIR:-$ROOT/rust/arqma-rpc-upstream}"

PLATFORM="${ARQMA_WALLET_FFI_PLATFORM:-${1:-}}"
case "$PLATFORM" in
  linux|macos|mingw) ;;
  "")
    echo "error: set ARQMA_WALLET_FFI_PLATFORM or pass linux|macos|mingw" >&2
    exit 1
    ;;
  *)
    echo "error: unknown platform: $PLATFORM (use linux, macos, or mingw)" >&2
    exit 1
    ;;
esac

bash "$ROOT/build/ci/patch-arqma-epee-floor.sh" "$UP"
if [[ "$PLATFORM" == mingw ]]; then
  bash "$ROOT/build/ci/patch-arqma-mingw-gui.sh" "$UP"
fi

if [[ "$PLATFORM" == mingw ]]; then
  BUILD_DIR="${ARQMA_MINGW_BUILD_DIR:-$UP/build-mingw}"
else
  BUILD_DIR="${ARQMA_CMAKE_BUILD_DIR:-$UP/build/ci-native-release}"
fi
mkdir -p "$BUILD_DIR"

# Keep in sync with rust/arqma-wallet2-api/build.rs (rustc-link-search for epee, easylogging, randomx, lmdb, cryptonote_basic).
WALLET_FFI_TARGETS=(epee easylogging randomx lmdb cryptonote_format_utils_basic wallet_merged)

# Trim configure-time work: full project is still configured, but we skip doc/debug extras.
CMAKE_EXTRA=(
  -D CMAKE_BUILD_TYPE=Release
  -D BUILD_GUI_DEPS=ON
  -D BUILD_TESTS=OFF
  -D BUILD_DOCUMENTATION=OFF
  -D BUILD_DEBUG_UTILITIES=OFF
)

if [[ "$PLATFORM" == mingw ]]; then
  cmake -S "$UP" -B "$BUILD_DIR" \
    -G "MinGW Makefiles" \
    "${CMAKE_EXTRA[@]}" \
    -D CMAKE_SYSTEM_PROCESSOR=x86_64 \
    -D ARCH_ID=x86_64 \
    -D ARCH=native
else
  cmake -S "$UP" -B "$BUILD_DIR" "${CMAKE_EXTRA[@]}"
fi

if [[ "$PLATFORM" == macos ]]; then
  J="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
else
  J="$(nproc 2>/dev/null || echo 4)"
fi

cmake --build "$BUILD_DIR" --target "${WALLET_FFI_TARGETS[@]}" -j"$J"

test -f "$BUILD_DIR/src/wallet/libwallet_merged.a"

echo "[build-arqma-wallet-ffi-deps] OK ($PLATFORM): $BUILD_DIR/src/wallet/libwallet_merged.a"
