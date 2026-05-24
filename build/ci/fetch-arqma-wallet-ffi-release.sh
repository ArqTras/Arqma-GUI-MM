#!/usr/bin/env bash
# Download prebuilt wallet FFI from https://github.com/ArqTras/FFI/releases
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLATFORMS="${ARQMA_FFI_PLATFORMS:-windows-x86_64-gnu,android-arm64,android-x86_64}"
export ARQMA_FFI_RELEASE_VERSION="${ARQMA_FFI_RELEASE_VERSION:-1.0.0}"
if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -File "${ROOT}/build/ci/fetch-arqma-wallet-ffi-release.ps1" -Platforms $($PLATFORMS.replace(',', ' '))
elif command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "${ROOT}/build/ci/fetch-arqma-wallet-ffi-release.ps1" -Platforms $($PLATFORMS.replace(',', ' '))
else
  echo "fetch-arqma-wallet-ffi-release.sh needs PowerShell on Windows or pwsh on Linux/macOS" >&2
  exit 1
fi
