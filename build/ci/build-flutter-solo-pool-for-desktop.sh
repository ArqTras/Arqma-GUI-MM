#!/usr/bin/env bash
# Build arqma_flutter_solo_pool into rust/tauri-app/src-tauri/bin/ for Flutter desktop bundles.
# Requires wallet_merged (build/ci/build-arqma-*.sh) — run before `flutter build`.
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
  *)
    echo "error: unknown platform: ${PLATFORM} (use linux, macos, or mingw)" >&2
    exit 2
    ;;
esac

bash "${ROOT}/build/ci/ensure-tauri-dist-stub.sh" "${ROOT}"
bash "${ROOT}/rust/tool/build_flutter_solo_pool.sh" --skip-upstream

TAURI_BIN="${ROOT}/rust/tauri-app/src-tauri/bin"
if [[ ! -f "${TAURI_BIN}/arqma_flutter_solo_pool" ]] \
  && [[ ! -f "${TAURI_BIN}/arqma_flutter_solo_pool.exe" ]]; then
  echo "::error::arqma_flutter_solo_pool missing under ${TAURI_BIN} after build" >&2
  exit 1
fi

echo "[build-flutter-solo-pool] OK (${PLATFORM})"
