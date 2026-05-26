#!/usr/bin/env bash
# Download prebuilt solo pool sidecar from https://github.com/ArqTras/FFI/releases
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLATFORMS="${ARQMA_SOLO_POOL_PLATFORMS:-linux-x86_64,macos-arm64,windows-x86_64-gnu}"
export ARQMA_SOLO_POOL_RELEASE_VERSION="${ARQMA_SOLO_POOL_RELEASE_VERSION:-${ARQMA_FFI_RELEASE_VERSION:-1.0.5}}"
case "$(uname -s 2>/dev/null || echo unknown)" in
  Linux|Darwin)
    export ARQMA_SOLO_POOL_PLATFORMS="${PLATFORMS}"
    exec bash "${ROOT}/build/ci/fetch-arqma-wallet-solo-pool-release-linux.sh"
    ;;
esac
if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -File "${ROOT}/build/ci/fetch-arqma-wallet-solo-pool-release.ps1" -Platforms $($PLATFORMS.replace(',', ' '))
elif command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${ROOT}/build/ci/fetch-arqma-wallet-solo-pool-release.ps1" -Platforms $($PLATFORMS.replace(',', ' '))
else
  echo "fetch-arqma-wallet-solo-pool-release.sh needs PowerShell on Windows or bash fetch on Linux/macOS" >&2
  exit 1
fi
