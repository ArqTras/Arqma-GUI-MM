#!/usr/bin/env bash
# Copy Arqma executables from the Tauri bundle dir into a Flutter desktop build output
# (same files as `tauri.conf.json` → `bundle.resources`: `rust/tauri-app/src-tauri/bin/`).
#
# Usage:
#   macOS:   tool/copy_arqma_tauri_bins.sh "build/macos/Build/Products/Release/Arqma-Wallet.app"
#   Linux:   tool/copy_arqma_tauri_bins.sh "build/linux/x64/release/bundle"
#   Windows: tool/copy_arqma_tauri_bins.sh "build/windows/x64/runner/Release"   (Git Bash / MSYS)
#
set -euo pipefail
if [[ "${1:-}" == "" ]]; then
  echo "usage: $0 <path-to-.app | linux/bundle | windows/runner/Release>" >&2
  exit 2
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/../../rust/tauri-app/src-tauri/bin"
TARGET="$1"
if [[ ! -d "${SRC}" ]]; then
  echo "error: missing bin source: ${SRC}" >&2
  exit 1
fi

OS="$(uname -s)"
DEST=""
FFI_DEST=""
FFI_LIB=""

if [[ "${OS}" == "Darwin" ]] && [[ "${TARGET}" == *.app ]]; then
  DEST="${TARGET}/Contents/Resources/bin"
  FFI_DEST="${TARGET}/Contents/Frameworks"
  FFI_LIB="libarqma_wallet_flutter_ffi.dylib"
elif [[ "${OS}" == "Linux" ]] && [[ -d "${TARGET}/bin" ]]; then
  DEST="${TARGET}/bin"
  mkdir -p "${TARGET}/lib"
  FFI_DEST="${TARGET}/lib"
  FFI_LIB="libarqma_wallet_flutter_ffi.so"
elif [[ -f "${TARGET}/Arqma-Wallet.exe" ]]; then
  DEST="${TARGET}/bin"
  FFI_DEST="${TARGET}"
  FFI_LIB="arqma_wallet_flutter_ffi.dll"
else
  DEST="${TARGET}/bin"
fi

mkdir -p "${DEST}"

resolve_src () {
  local base="$1"
  if [[ -f "${SRC}/${base}" ]]; then
    echo "${SRC}/${base}"
  elif [[ -f "${SRC}/${base}.exe" ]]; then
    echo "${SRC}/${base}.exe"
  fi
}

shopt -s nullglob
for base in arqmad arqma_flutter_solo_pool; do
  f="$(resolve_src "${base}")"
  [[ -n "${f}" ]] || continue
  cp -f "${f}" "${DEST}/"
  chmod +x "${DEST}/$(basename "${f}")" 2>/dev/null || true
  echo "copied $(basename "${f}") -> ${DEST}/"
done

SOLO_REL="${ROOT}/../../rust/tauri-app/src-tauri/target/release/arqma_flutter_solo_pool"
SOLO_REL_EXE="${ROOT}/../../rust/tauri-app/src-tauri/target/release/arqma_flutter_solo_pool.exe"
SOLO_DBG="${ROOT}/../../rust/tauri-app/src-tauri/target/debug/arqma_flutter_solo_pool"
SOLO_DBG_EXE="${ROOT}/../../rust/tauri-app/src-tauri/target/debug/arqma_flutter_solo_pool.exe"
if [[ ! -f "${DEST}/arqma_flutter_solo_pool" ]] && [[ ! -f "${DEST}/arqma_flutter_solo_pool.exe" ]]; then
  if [[ -f "${SOLO_REL}" ]]; then
    cp -f "${SOLO_REL}" "${DEST}/"
    chmod +x "${DEST}/arqma_flutter_solo_pool" 2>/dev/null || true
    echo "copied arqma_flutter_solo_pool (release) -> ${DEST}/"
  elif [[ -f "${SOLO_REL_EXE}" ]]; then
    cp -f "${SOLO_REL_EXE}" "${DEST}/"
    echo "copied arqma_flutter_solo_pool.exe (release) -> ${DEST}/"
  elif [[ -f "${SOLO_DBG}" ]]; then
    cp -f "${SOLO_DBG}" "${DEST}/"
    chmod +x "${DEST}/arqma_flutter_solo_pool" 2>/dev/null || true
    echo "copied arqma_flutter_solo_pool (debug) -> ${DEST}/"
  elif [[ -f "${SOLO_DBG_EXE}" ]]; then
    cp -f "${SOLO_DBG_EXE}" "${DEST}/"
    echo "copied arqma_flutter_solo_pool.exe (debug) -> ${DEST}/"
  fi
fi

if [[ -n "${FFI_DEST}" ]] && [[ -n "${FFI_LIB}" ]]; then
  mkdir -p "${FFI_DEST}"
  for rel in \
    "${ROOT}/../../rust/target/release/${FFI_LIB}" \
    "${ROOT}/../../rust/target/x86_64-pc-windows-gnu/release/${FFI_LIB}" \
    "${ROOT}/../../rust/target/debug/${FFI_LIB}" \
    "${ROOT}/../../rust/target/x86_64-pc-windows-gnu/debug/${FFI_LIB}" \
    "${ROOT}/../../rust/tauri-app/src-tauri/target/release/${FFI_LIB}" \
    "${ROOT}/../../rust/tauri-app/src-tauri/target/x86_64-pc-windows-gnu/release/${FFI_LIB}" \
    "${ROOT}/../../rust/tauri-app/src-tauri/target/debug/${FFI_LIB}" \
    "${ROOT}/../../rust/tauri-app/src-tauri/target/x86_64-pc-windows-gnu/debug/${FFI_LIB}"; do
    if [[ -f "${rel}" ]]; then
      cp -f "${rel}" "${FFI_DEST}/"
      echo "copied ${FFI_LIB} -> ${FFI_DEST}/ (from ${rel})"
      break
    fi
  done
  if [[ ! -f "${FFI_DEST}/${FFI_LIB}" ]]; then
    echo "warning: ${FFI_LIB} not found; run: bash rust/tool/build_wallet_flutter_ffi.sh" >&2
  fi
fi
