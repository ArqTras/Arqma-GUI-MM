#!/usr/bin/env bash
# Optional local path: after `wallet_merged`, build **daemon** from the upstream tree and copy **arqmad**
# into `rust/tauri-app/src-tauri/bin/`. CI Flutter/macOS/Linux uses **GitHub Releases** instead:
# `build/ci/fetch-arqmad-github-release.sh` (binaries from `arqma/arqma` latest release).
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

# MSYS2: libunwind + libgcc_eh duplicate unwind symbols when linking arqmad.exe.
if [ -n "${ARQMA_MINGW:-}" ]; then
  export LDFLAGS="-Wl,--allow-multiple-definition"
  cmake --build "$BUILD_DIR" --target daemon -j"$J"
  unset LDFLAGS
else
  cmake --build "$BUILD_DIR" --target daemon -j"$J"
fi

BIN="$BUILD_DIR/bin"
if [ -n "${ARQMA_MINGW:-}" ]; then
  test -f "$BIN/arqmad.exe"
  cp -f "$BIN/arqmad.exe" "$DST/"
else
  test -f "$BIN/arqmad"
  cp -f "$BIN/arqmad" "$DST/"
fi

echo "[build-arqma-daemon-copy] OK -> $DST (arqmad only)"
ls -la "$DST" | head -20
