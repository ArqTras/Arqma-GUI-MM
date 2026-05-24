#!/usr/bin/env bash
# Copy libarqma_wallet_flutter_ffi.so into jniLibs for Flutter Android builds.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
APP="$(cd "$(dirname "$0")/.." && pwd)"
JNILIBS="${APP}/android/app/src/main/jniLibs"
ALT="${APP}/native/jniLibs"
LIB=libarqma_wallet_flutter_ffi.so

copy_abi() {
  local triple="$1"
  local abi="$2"
  local src="${ROOT}/rust/target/${triple}/release/${LIB}"
  if [[ ! -f "${src}" ]]; then
    echo "skip ${abi}: missing ${src}"
    return 1
  fi
  mkdir -p "${JNILIBS}/${abi}" "${ALT}/${abi}"
  cp -f "${src}" "${JNILIBS}/${abi}/${LIB}"
  cp -f "${src}" "${ALT}/${abi}/${LIB}"
  echo "copied ${abi} <- ${src}"
}

mkdir -p "${JNILIBS}" "${ALT}"
copy_abi aarch64-linux-android arm64-v8a || true
copy_abi x86_64-linux-android x86_64 || true
copy_abi armv7-linux-androideabi armeabi-v7a || true

if ! find "${JNILIBS}" -name "${LIB}" -print -quit | grep -q .; then
  echo "No ${LIB} under ${JNILIBS}. Build first:" >&2
  echo "  bash rust/tool/build_mobile_wallet_ffi_android.sh" >&2
  exit 1
fi
