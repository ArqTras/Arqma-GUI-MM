#!/usr/bin/env bash
# All Flutter targets (Windows / Linux / macOS / Android / iOS) use GitHub Latest ArqTras/FFI.
# Sets ARQMA_FFI_RELEASE_VERSION=latest and re-downloads when the Latest tag changes.
# Emergency CI/debug override only: ARQMA_FFI_ALLOW_PIN=1 ARQMA_FFI_RELEASE_VERSION=1.0.x
# (Legacy alias: ARQMA_FFI_DESKTOP_ALLOW_PIN=1)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAMP="${ROOT}/.prebuilt/arqma-wallet-ffi/.active-latest-version"

ALLOW_PIN=0
if [[ "${ARQMA_FFI_ALLOW_PIN:-}" == "1" || "${ARQMA_FFI_DESKTOP_ALLOW_PIN:-}" == "1" ]]; then
  ALLOW_PIN=1
fi

if [[ "${ALLOW_PIN}" == "1" && -n "${ARQMA_FFI_RELEASE_VERSION:-}" && "${ARQMA_FFI_RELEASE_VERSION}" != "latest" ]]; then
  echo "[ffi] pinned ARQMA_FFI_RELEASE_VERSION=${ARQMA_FFI_RELEASE_VERSION} (allow-pin mode)"
else
  if [[ -n "${ARQMA_FFI_RELEASE_VERSION:-}" && "${ARQMA_FFI_RELEASE_VERSION}" != "latest" ]]; then
    echo "[ffi] ignoring ARQMA_FFI_RELEASE_VERSION=${ARQMA_FFI_RELEASE_VERSION} — project policy uses Latest ArqTras/FFI" >&2
  fi
  export ARQMA_FFI_RELEASE_VERSION=latest
fi

VER="$(bash "${ROOT}/build/ci/resolve-arqma-ffi-release-version.sh")"
if [[ -f "${STAMP}" ]] && [[ "$(tr -d '[:space:]' < "${STAMP}")" != "${VER}" ]]; then
  export ARQMA_FFI_FORCE=1
  echo "[ffi] Latest release changed: $(tr -d '[:space:]' < "${STAMP}") -> ${VER} (refreshing prebuilts)"
fi
mkdir -p "$(dirname "${STAMP}")"
printf '%s\n' "${VER}" > "${STAMP}"
echo "${VER}"
