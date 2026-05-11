#!/usr/bin/env bash
# Fetch **arqmad** from the latest GitHub Release of `arqma/arqma` (static binaries in the published archive).
# Native `wallet_merged` must still be built from **arqtras/arqma** via `build/ci/build-arqma-*.sh` — this script only supplies the daemon executable for `rust/tauri-app/src-tauri/bin/`.
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

mkdir -p "$ROOT/downloads" "$ROOT/bin"

if ! command -v node >/dev/null 2>&1; then
  echo "[fetch-arqmad-github-release] error: node is required" >&2
  exit 1
fi

node "$ROOT/build/download-binaries.js"

OS="$(uname -s)"
case "$OS" in
  Linux)
    # Same layout as `.github/workflows/desktop-release.yml` job `tauri` (extract into repo root, expect ./bin/arqmad).
    f=""
    for c in "$ROOT/downloads/latest.gz" "$ROOT/downloads/latest.tar.gz" "$ROOT/downloads/latest.tgz"; do
      if [[ -f "$c" ]]; then f="$c"; break; fi
    done
    if [[ -z "$f" ]]; then
      echo "[fetch-arqmad-github-release] error: no downloads/latest.{gz,tar.gz,tgz}" >&2
      ls -la "$ROOT/downloads" || true
      exit 1
    fi
    tar -xvf "$f" --directory "$ROOT"
    ;;
  Darwin)
    z="$ROOT/downloads/latest.zip"
    if [[ ! -f "$z" ]]; then
      echo "[fetch-arqmad-github-release] error: missing $z" >&2
      exit 1
    fi
    mkdir -p "$ROOT/bin"
    unzip -o "$z" -d "$ROOT/bin"
    ;;
  *)
    echo "[fetch-arqmad-github-release] error: unsupported OS: $OS (use download-binaries.js + extract manually on Windows)" >&2
    exit 1
    ;;
esac

node "$ROOT/build/copy-to-tauri-bins.js"
echo "[fetch-arqmad-github-release] OK"
