#!/usr/bin/env bash
# Copy built Android FFI .so from WSL native target dir to Windows jniLibs.
set -euo pipefail
APP="${1:-}"
if [[ -z "${APP}" ]]; then
  echo "Usage: $0 /path/to/flutter-android/arqma_wallet_android" >&2
  exit 1
fi
NATIVE_ROOT="${ARQMA_ANDROID_NATIVE_ROOT:-${HOME}/arqma-android-build/GUI-Rust}"
TARGET="${ARQMA_CARGO_TARGET_DIR:-${NATIVE_ROOT}/rust/target}"
LIB=libarqma_wallet_flutter_ffi.so
JNILIBS="${APP}/android/app/src/main/jniLibs"
ALT="${APP}/native/jniLibs"
mkdir -p "${JNILIBS}" "${ALT}"

copy_abi() {
  local triple="$1" abi="$2"
  local src="${TARGET}/${triple}/release/${LIB}"
  if [[ ! -f "${src}" ]]; then
    echo "skip ${abi}: missing ${src}" >&2
    return 1
  fi
  mkdir -p "${JNILIBS}/${abi}" "${ALT}/${abi}"
  cp -f "${src}" "${JNILIBS}/${abi}/${LIB}"
  cp -f "${src}" "${ALT}/${abi}/${LIB}"
  echo "copied ${abi} <- ${src}"
}

copy_abi aarch64-linux-android arm64-v8a || true
copy_abi x86_64-linux-android x86_64 || true
copy_abi armv7-linux-androideabi armeabi-v7a || true

if ! find "${JNILIBS}" -name "${LIB}" -print -quit | grep -q .; then
  echo "No ${LIB} under ${JNILIBS}" >&2
  exit 1
fi
