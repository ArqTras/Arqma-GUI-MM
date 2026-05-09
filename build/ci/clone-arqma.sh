#!/usr/bin/env bash
# Clone Arqma core into rust/arqma-rpc-upstream (CI / local). Override with env vars.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEST="${ARQMA_CLONE_DIR:-$ROOT/rust/arqma-rpc-upstream}"
REPO="${ARQMA_UPSTREAM_REPO:-https://github.com/arqtras/arqma.git}"
REF="${ARQMA_UPSTREAM_REF:-pospow}"

if [[ ! -f "$DEST/src/wallet/api/wallet2_api.h" ]]; then
  rm -rf "$DEST"
  mkdir -p "$(dirname "$DEST")"
  git clone --depth 1 --branch "$REF" "$REPO" "$DEST"
  echo "[clone-arqma] cloned $REF from $REPO -> $DEST"
else
  echo "[clone-arqma] existing checkout at $DEST"
fi

# MinGW g++ 16+ (MSYS2 / CI): epee uses floor() without <cmath> — must run for cached clones too.
bash "$ROOT/build/ci/patch-arqma-epee-floor.sh" "$DEST"
# RandomX ARCH_ID, wallet_merged+daemonizer, stack_trace MinGW — must run for cached clones too.
bash "$ROOT/build/ci/patch-arqma-mingw-gui.sh" "$DEST"
