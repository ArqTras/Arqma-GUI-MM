#!/usr/bin/env bash
# Verify Flutter Linux release bundle (GTK binary, engine .so, FFI, assets, arqmad).
# Usage: ./tool/verify_linux_bundle.sh [path-to-bundle]
# Env: FAIL_IF_NO_ARQMAD=0 to warn only when bin/arqmad is missing (default: 1 = fail).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
B="${1:-${GUI_ROOT}/build/linux/x64/release/bundle}"
FAIL_IF_NO_ARQMAD="${FAIL_IF_NO_ARQMAD:-1}"

if [[ ! -d "$B" ]]; then
  echo "::error::bundle verify: not a directory: $B" >&2
  exit 1
fi

failed=0
req() {
  if [[ ! -e "$1" ]]; then
    echo "::error::bundle verify: missing $1" >&2
    failed=1
  fi
}

req "${B}/Arqma-Wallet"
req "${B}/lib/libarqma_wallet_flutter_ffi.so"
if ! compgen -G "${B}/lib/libflutter_linux_gtk.so"* >/dev/null; then
  echo "::error::bundle verify: missing lib/libflutter_linux_gtk.so*" >&2
  failed=1
fi
req "${B}/data/flutter_assets/AssetManifest.bin"

if [[ ! -f "${B}/bin/arqmad" ]]; then
  msg="bundle verify: missing bin/arqmad (CMake install from rust/tauri-app/src-tauri/bin/)"
  if [[ "${FAIL_IF_NO_ARQMAD}" == "1" ]]; then
    echo "::error::${msg}" >&2
    failed=1
  else
    echo "::warning::${msg}" >&2
  fi
fi

if [[ "${failed}" -ne 0 ]]; then
  exit 1
fi
echo "bundle verify: OK - ${B}"
