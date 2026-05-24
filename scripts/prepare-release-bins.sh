#!/usr/bin/env bash
# Prepare rust/tauri-app/src-tauri/bin/ from ./bin for bundled Linux/macOS builds.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [[ "${1:-}" == "--download" ]]; then
  echo "[prepare-release-bins] download-binaries.js..."
  node ./build/download-binaries.js
  echo "[prepare-release-bins] Extract the downloaded archive into ./bin (arqmad only), then re-run without --download."
fi
echo "[prepare-release-bins] copy-to-tauri-bins.js..."
node ./build/copy-to-tauri-bins.js
DST="$ROOT/rust/tauri-app/src-tauri/bin"
if [[ ! -f "$DST/arqmad" ]]; then
  echo "[prepare-release-bins] WARNING: missing $DST/arqmad — add binary or use ARQMA_BUILD_DIR at runtime."
fi
echo "[prepare-release-bins] done."
