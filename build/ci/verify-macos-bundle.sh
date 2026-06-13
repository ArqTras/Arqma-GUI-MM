#!/usr/bin/env bash
# Verify Flutter macOS .app bundle includes wallet FFI, arqmad, and solo pool sidecar.
# Usage: bash build/ci/verify-macos-bundle.sh path/to/Arqma-Wallet.app
set -euo pipefail

APP="${1:-}"
if [[ -z "${APP}" ]] || [[ ! -d "${APP}" ]]; then
  echo "::error::bundle verify: not an app bundle: ${APP:-<missing>}" >&2
  exit 1
fi

failed=0
req() {
  if [[ ! -e "$1" ]]; then
    echo "::error::bundle verify: missing $1" >&2
    failed=1
  fi
}

req "${APP}/Contents/MacOS/Arqma-Wallet"
req "${APP}/Contents/Frameworks/libarqma_wallet_flutter_ffi.dylib"
req "${APP}/Contents/Resources/bin/arqmad"
req "${APP}/Contents/Resources/bin/arqma_flutter_solo_pool"

if [[ "${failed}" -ne 0 ]]; then
  exit 1
fi
echo "bundle verify: OK - ${APP}"
