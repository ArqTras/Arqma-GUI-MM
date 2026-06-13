#!/usr/bin/env bash
# Fetch **arqmad** from the latest GitHub Release of `arqma/arqma` (static binaries in the published archive).
# Native `wallet_merged` must still be built from **arqtras/arqma** (CI default: branch pospow) via `build/ci/build-arqma-*.sh` — this script supplies the **arqmad** binary for `build/flutter-desktop-bin/` from **`arqma/arqma` latest GitHub Release** (same source family as Windows `flutter-windows-fetch-arqma-binaries.ps1`).
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
    for c in \
      "$ROOT/downloads/latest.tar.xz" \
      "$ROOT/downloads/latest.xz" \
      "$ROOT/downloads/latest.tar.gz" \
      "$ROOT/downloads/latest.tgz" \
      "$ROOT/downloads/latest.gz"
    do
      if [[ -f "$c" ]]; then f="$c"; break; fi
    done
    if [[ -z "$f" ]]; then
      echo "[fetch-arqmad-github-release] error: no downloads/latest.{tar.xz,xz,tar.gz,tgz,gz}" >&2
      ls -la "$ROOT/downloads" || true
      exit 1
    fi
    case "$f" in
      *.tar.xz|*.txz|*.xz) tar -xJf "$f" --directory "$ROOT" ;;
      *.tar.gz|*.tgz|*.gz) tar -xzvf "$f" --directory "$ROOT" ;;
      *) echo "[fetch-arqmad-github-release] error: unhandled archive $f" >&2; exit 1 ;;
    esac
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

# Linux: some archives unpack `arqmad` at repo root (not under ./bin/); stage for copy-to-flutter-desktop-bins.
if [[ "$(uname -s)" == "Linux" ]] && [[ ! -f "$ROOT/bin/arqmad" ]]; then
  found=""
  while IFS= read -r f; do
    case "$f" in
      *.app/*) continue ;;
    esac
    found="$f"
    break
  done < <(find "$ROOT" \( -path "$ROOT/.git" -o -path "$ROOT/rust/target" -o -path "$ROOT/flutter" -o -path "$ROOT/node_modules" -o -path "$ROOT/downloads" \) -prune -o -type f -name arqmad ! -path "*.app/*" -print 2>/dev/null)
  if [[ -n "$found" ]]; then
    mkdir -p "$ROOT/bin"
    cp -f "$found" "$ROOT/bin/arqmad"
    chmod +x "$ROOT/bin/arqmad" || true
    echo "[fetch-arqmad-github-release] staged Linux daemon from $found -> bin/arqmad"
  fi
fi

node "$ROOT/build/copy-to-flutter-desktop-bins.js"
if [[ ! -f "$ROOT/build/flutter-desktop-bin/arqmad" ]]; then
  echo "[fetch-arqmad-github-release] error: arqmad missing under build/flutter-desktop-bin/ after copy (see ./bin layout and build/copy-to-flutter-desktop-bins.js)" >&2
  find "$ROOT/bin" -type f 2>/dev/null | head -80 || true
  exit 1
fi
echo "[fetch-arqmad-github-release] OK"
