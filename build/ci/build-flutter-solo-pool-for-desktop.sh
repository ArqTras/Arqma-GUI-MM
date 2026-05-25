#!/usr/bin/env bash
# Install arqma_flutter_solo_pool into rust/tauri-app/src-tauri/bin/ for Flutter **desktop** bundles only.
# Default: download from ArqTras/FFI release (same tag as ARQMA_FFI_RELEASE_VERSION / ARQMA_SOLO_POOL_RELEASE_VERSION).
# Fallback: build from source when ARQMA_SOLO_POOL_BUILD_FROM_SOURCE=1 or fetch miss with ALLOW_MISS.
#
# Usage:
#   bash build/ci/build-flutter-solo-pool-for-desktop.sh linux|macos|mingw
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLATFORM="${1:-${ARQMA_WALLET_FFI_PLATFORM:-}}"
if [[ -z "${PLATFORM}" ]]; then
  echo "usage: $0 linux|macos|mingw" >&2
  exit 2
fi

chmod +x "${ROOT}/build/ci/"*.sh "${ROOT}/rust/tool/"*.sh 2>/dev/null || true

case "${PLATFORM}" in
  linux) FETCH_PLATFORM="linux-x86_64" ;;
  macos) FETCH_PLATFORM="macos-arm64" ;;
  mingw) FETCH_PLATFORM="windows-x86_64-gnu" ;;
  *)
    echo "error: unknown platform: ${PLATFORM} (use linux, macos, or mingw)" >&2
    exit 2
    ;;
esac

TAURI_BIN="${ROOT}/rust/tauri-app/src-tauri/bin"
solo_present() {
  [[ -f "${TAURI_BIN}/arqma_flutter_solo_pool" ]] || [[ -f "${TAURI_BIN}/arqma_flutter_solo_pool.exe" ]]
}

build_from_source() {
  echo "[build-flutter-solo-pool] building from source (${PLATFORM})..."
  bash "${ROOT}/build/ci/clone-arqma.sh"
  case "${PLATFORM}" in
    linux)
      export ARQMA_WALLET_FFI_USE_DEPENDS=1
      bash "${ROOT}/build/ci/build-arqma-linux.sh"
      ;;
    macos)
      export ARQMA_WALLET_FFI_USE_DEPENDS=1
      bash "${ROOT}/build/ci/build-arqma-macos.sh"
      ;;
    mingw)
      bash "${ROOT}/build/ci/build-arqma-mingw.sh"
      ;;
  esac
  bash "${ROOT}/build/ci/ensure-tauri-dist-stub.sh" "${ROOT}"
  bash "${ROOT}/rust/tool/build_flutter_solo_pool.sh" --skip-upstream
}

if [[ "${ARQMA_SOLO_POOL_BUILD_FROM_SOURCE:-0}" == "1" ]]; then
  build_from_source
elif solo_present; then
  echo "[build-flutter-solo-pool] already present under ${TAURI_BIN}"
else
  if ARQMA_SOLO_POOL_PLATFORMS="${FETCH_PLATFORM}" \
    bash "${ROOT}/build/ci/fetch-arqma-wallet-solo-pool-release-linux.sh"; then
  :
  elif [[ "${PLATFORM}" == mingw ]]; then
    echo "[build-flutter-solo-pool] linux fetch script cannot run on Windows host; use fetch ps1 or build from source" >&2
    exit 1
  else
    echo "[build-flutter-solo-pool] fetch miss — building from source" >&2
    build_from_source
  fi
fi

if ! solo_present; then
  echo "::error::arqma_flutter_solo_pool missing under ${TAURI_BIN}" >&2
  exit 1
fi

echo "[build-flutter-solo-pool] OK (${PLATFORM})"
