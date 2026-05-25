#!/usr/bin/env bash
# Resolve solo-pool release tag (defaults to same Latest ArqTras/FFI release as wallet FFI).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOLO_RAW="${ARQMA_SOLO_POOL_RELEASE_VERSION:-}"
SOLO_RAW="${SOLO_RAW#v}"
if [[ -n "${SOLO_RAW}" && "${SOLO_RAW}" != "latest" ]]; then
  echo "${SOLO_RAW}"
  exit 0
fi
bash "${ROOT}/build/ci/resolve-arqma-ffi-release-version.sh"
