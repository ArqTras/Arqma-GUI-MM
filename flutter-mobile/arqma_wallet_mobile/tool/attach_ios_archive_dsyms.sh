#!/usr/bin/env bash
# Attach dSYM bundles for embedded dylibs/frameworks to Runner.xcarchive (TestFlight symbol upload).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "${ROOT}/../.." && pwd)"
ARCHIVE="${1:-${ROOT}/build/ios/archive/Runner.xcarchive}"
export PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:${PATH}"

if [[ ! -d "${ARCHIVE}" ]]; then
  echo "error: archive not found: ${ARCHIVE}" >&2
  echo "Run 'flutter build ipa' first." >&2
  exit 1
fi

DSYM_DIR="${ARCHIVE}/dSYMs"
mkdir -p "${DSYM_DIR}"

FFI_DYLIB="${REPO}/rust/target/aarch64-apple-ios/release/libarqma_wallet_flutter_ffi.dylib"
if [[ ! -f "${FFI_DYLIB}" ]]; then
  echo "error: missing ${FFI_DYLIB}" >&2
  exit 1
fi

OBJC_BIN="${ARCHIVE}/Products/Applications/Runner.app/Frameworks/objective_c.framework/objective_c"
if [[ ! -f "${OBJC_BIN}" ]]; then
  echo "warning: ${OBJC_BIN} not in archive — skip objective_c dSYM"
  OBJC_BIN=""
fi

make_dsym() {
  local bin="$1"
  local name="$2"
  local out="${DSYM_DIR}/${name}.dSYM"
  rm -rf "${out}"
  dsymutil -o "${out}" "${bin}" 2>&1 | grep -v 'warning: no debug symbols' || true
  if dwarfdump --uuid "${out}" >/dev/null 2>&1; then
    echo "[dSYM] ${name} ← ${bin}"
    dwarfdump --uuid "${out}" | head -1
  else
    echo "error: failed to create dSYM for ${name}" >&2
    exit 1
  fi
}

FFI_IN_ARCHIVE="${ARCHIVE}/Products/Applications/Runner.app/Frameworks/libarqma_wallet_flutter_ffi.framework/libarqma_wallet_flutter_ffi"
if [[ -f "${FFI_IN_ARCHIVE}" ]]; then
  make_dsym "${FFI_IN_ARCHIVE}" "libarqma_wallet_flutter_ffi.framework"
else
  make_dsym "${FFI_DYLIB}" "libarqma_wallet_flutter_ffi.dylib"
fi
if [[ -n "${OBJC_BIN}" ]]; then
  make_dsym "${OBJC_BIN}" "objective_c.framework"
fi

echo "dSYMs ready under ${DSYM_DIR}"
