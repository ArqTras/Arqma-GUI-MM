#!/usr/bin/env bash
# After `wallet_merged`: build `daemon` (arqmad) + `wallet_rpc_server` (arqma-wallet-rpc) and copy into
# `rust/tauri-app/src-tauri/bin/` so Flutter/Tauri CMake bundles match Tauri `bundle.resources`.
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UP="${ARQMA_WALLET2_UPSTREAM_DIR:-$ROOT/rust/arqma-rpc-upstream}"
DST="$ROOT/rust/tauri-app/src-tauri/bin"
mkdir -p "$DST"

if [ -n "${ARQMA_MINGW:-}" ]; then
  BUILD_DIR="${ARQMA_MINGW_BUILD_DIR:-$UP/build-mingw}"
  J="$(nproc 2>/dev/null || echo 4)"
else
  BUILD_DIR="${ARQMA_CMAKE_BUILD_DIR:-$UP/build/ci-native-release}"
  J="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
fi

if [ ! -d "$BUILD_DIR" ]; then
  echo "error: CMake build dir missing: $BUILD_DIR (run build-arqma-*.sh first)" >&2
  exit 1
fi

# MSYS2: libunwind + libgcc_eh duplicate unwind symbols for arqmad.exe only — pass LDFLAGS for that link
# only (wallet_rpc_server must link without stripping/changing its dependency closure).
if [ -n "${ARQMA_MINGW:-}" ]; then
  export LDFLAGS="-Wl,--allow-multiple-definition"
  cmake --build "$BUILD_DIR" --target daemon -j"$J"
  unset LDFLAGS
  cmake --build "$BUILD_DIR" --target wallet_rpc_server -j"$J"
else
  cmake --build "$BUILD_DIR" --target daemon wallet_rpc_server -j"$J"
fi

BIN="$BUILD_DIR/bin"
if [ -n "${ARQMA_MINGW:-}" ]; then
  test -f "$BIN/arqmad.exe"
  test -f "$BIN/arqma-wallet-rpc.exe"
  cp -f "$BIN/arqmad.exe" "$DST/"
  cp -f "$BIN/arqma-wallet-rpc.exe" "$DST/"
else
  test -f "$BIN/arqmad"
  test -f "$BIN/arqma-wallet-rpc"
  cp -f "$BIN/arqmad" "$DST/"
  cp -f "$BIN/arqma-wallet-rpc" "$DST/"
fi

echo "[build-arqma-daemon-wallet-rpc-copy] OK -> $DST"
ls -la "$DST" | head -20
