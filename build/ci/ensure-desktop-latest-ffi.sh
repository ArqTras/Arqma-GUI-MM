#!/usr/bin/env bash
# Desktop Flutter GUI (Windows / Linux / macOS) always uses GitHub Latest ArqTras/FFI.
# Sets ARQMA_FFI_RELEASE_VERSION=latest and re-downloads when Latest tag changes.
# Override for emergency CI/debug only: ARQMA_FFI_DESKTOP_ALLOW_PIN=1 ARQMA_FFI_RELEASE_VERSION=1.0.x
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAMP="${ROOT}/.prebuilt/arqma-wallet-ffi/.desktop-active-version"

if [[ "${ARQMA_FFI_DESKTOP_ALLOW_PIN:-}" == "1" && -n "${ARQMA_FFI_RELEASE_VERSION:-}" && "${ARQMA_FFI_RELEASE_VERSION}" != "latest" ]]; then
  echo "[desktop-ffi] pinned ARQMA_FFI_RELEASE_VERSION=${ARQMA_FFI_RELEASE_VERSION} (allow-pin mode)"
else
  if [[ -n "${ARQMA_FFI_RELEASE_VERSION:-}" && "${ARQMA_FFI_RELEASE_VERSION}" != "latest" ]]; then
    echo "[desktop-ffi] ignoring ARQMA_FFI_RELEASE_VERSION=${ARQMA_FFI_RELEASE_VERSION} — desktop GUI uses Latest ArqTras/FFI" >&2
  fi
  export ARQMA_FFI_RELEASE_VERSION=latest
fi

VER="$(bash "${ROOT}/build/ci/resolve-arqma-ffi-release-version.sh")"
if [[ -f "${STAMP}" ]] && [[ "$(tr -d '[:space:]' < "${STAMP}")" != "${VER}" ]]; then
  export ARQMA_FFI_FORCE=1
  echo "[desktop-ffi] Latest FFI release changed: $(tr -d '[:space:]' < "${STAMP}") -> ${VER} (refreshing prebuilts)"
fi
mkdir -p "$(dirname "${STAMP}")"
printf '%s\n' "${VER}" > "${STAMP}"
echo "${VER}"
