#!/usr/bin/env bash
# Install arqma_flutter_solo_pool into build/flutter-desktop-bin/ for Flutter **desktop** bundles.
# Downloads from ArqTras/FFI release (see ARQMA_FFI_RELEASE_VERSION / ARQMA_SOLO_POOL_RELEASE_VERSION).
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

chmod +x "${ROOT}/build/ci/"*.sh 2>/dev/null || true

case "${PLATFORM}" in
  linux) FETCH_PLATFORM="linux-x86_64" ;;
  macos) FETCH_PLATFORM="macos-arm64" ;;
  mingw) FETCH_PLATFORM="windows-x86_64-gnu" ;;
  *)
    echo "error: unknown platform: ${PLATFORM} (use linux, macos, or mingw)" >&2
    exit 2
    ;;
esac

DESKTOP_BIN="${ROOT}/build/flutter-desktop-bin"
solo_present() {
  [[ -f "${DESKTOP_BIN}/arqma_flutter_solo_pool" ]] || [[ -f "${DESKTOP_BIN}/arqma_flutter_solo_pool.exe" ]]
}

if solo_present; then
  echo "[build-flutter-solo-pool] already present under ${DESKTOP_BIN}"
else
  if [[ "${PLATFORM}" == mingw ]]; then
    pwsh -NoProfile -File "${ROOT}/build/ci/fetch-arqma-wallet-solo-pool-release.ps1" -Platforms "${FETCH_PLATFORM}"
  else
    ARQMA_SOLO_POOL_PLATFORMS="${FETCH_PLATFORM}" \
      bash "${ROOT}/build/ci/fetch-arqma-wallet-solo-pool-release-linux.sh"
  fi
fi

if ! solo_present; then
  echo "::error::arqma_flutter_solo_pool missing under ${DESKTOP_BIN} (fetch ArqTras/FFI or see branch outdated for source build)" >&2
  exit 1
fi

echo "[build-flutter-solo-pool] OK (${PLATFORM})"
