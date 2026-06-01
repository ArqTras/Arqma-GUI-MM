#!/usr/bin/env bash
# Fetch wallet FFI + solo pool sidecar for Flutter desktop (Latest ArqTras/FFI release).
# Android/iOS: use fetch-arqma-wallet-ffi-release* with mobile platforms only (no solo pool).
#
# Usage (repo root):
#   bash build/ci/fetch-arqma-desktop-prebuilts.sh linux|macos|mingw
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="${1:-}"
if [[ -z "${HOST}" ]]; then
  echo "usage: $0 linux|macos|mingw" >&2
  exit 2
fi

case "${HOST}" in
  linux) PLATFORM="linux-x86_64" ;;
  macos) PLATFORM="macos-arm64" ;;
  mingw) PLATFORM="windows-x86_64-gnu" ;;
  *)
    echo "error: unknown host: ${HOST} (use linux, macos, or mingw)" >&2
    exit 2
    ;;
esac

chmod +x "${ROOT}/build/ci/"*.sh 2>/dev/null || true
VER="$(bash "${ROOT}/build/ci/ensure-desktop-latest-ffi.sh")"
echo "[desktop-prebuilts] ArqTras/FFI release ${VER} (${PLATFORM})"

ARQMA_FFI_PLATFORMS="${PLATFORM}" bash "${ROOT}/build/ci/fetch-arqma-wallet-ffi-release-linux.sh"
ARQMA_SOLO_POOL_PLATFORMS="${PLATFORM}" bash "${ROOT}/build/ci/fetch-arqma-wallet-solo-pool-release-linux.sh"

echo "[desktop-prebuilts] OK"
