#!/usr/bin/env bash
# Copy Arqma executables from build/flutter-desktop-bin/ into a Flutter desktop build output.
#
# Usage:
#   macOS:   tool/copy_arqma_desktop_bins.sh "build/macos/Build/Products/Release/Arqma-Wallet.app"
#   Linux:   tool/copy_arqma_desktop_bins.sh "build/linux/x64/release/bundle"
#   Windows: tool/copy_arqma_desktop_bins.sh "build/windows/x64/runner/Release"   (Git Bash / MSYS)
#
set -euo pipefail
if [[ "${1:-}" == "" ]]; then
  echo "usage: $0 <path-to-.app | linux/bundle | windows/runner/Release>" >&2
  exit 2
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ROOT}/../../build/flutter-desktop-bin"
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

if [[ ! -f "${DEST}/arqma_flutter_solo_pool" ]] && [[ ! -f "${DEST}/arqma_flutter_solo_pool.exe" ]]; then
  for rel in \
    "${ROOT}/../../rust/target/release/arqma_flutter_solo_pool" \
    "${ROOT}/../../rust/target/release/arqma_flutter_solo_pool.exe" \
    "${ROOT}/../../rust/target/x86_64-pc-windows-gnu/release/arqma_flutter_solo_pool.exe"; do
    if [[ -f "${rel}" ]]; then
      cp -f "${rel}" "${DEST}/"
      chmod +x "${DEST}/$(basename "${rel}")" 2>/dev/null || true
      echo "copied $(basename "${rel}") (rust/target) -> ${DEST}/"
      break
    fi
  done
fi

if [[ -n "${FFI_DEST}" ]] && [[ -n "${FFI_LIB}" ]]; then
  mkdir -p "${FFI_DEST}"
  FFI_SRC_USED=""
  for rel in \
    "${ROOT}/../../rust/target/release/${FFI_LIB}" \
    "${ROOT}/../../rust/target/x86_64-pc-windows-gnu/release/${FFI_LIB}" \
    "${ROOT}/../../rust/target/debug/${FFI_LIB}" \
    "${ROOT}/../../rust/target/x86_64-pc-windows-gnu/debug/${FFI_LIB}"; do
    if [[ -f "${rel}" ]]; then
      cp -f "${rel}" "${FFI_DEST}/"
      FFI_SRC_USED="${rel}"
      echo "copied ${FFI_LIB} -> ${FFI_DEST}/ (from ${rel})"
      break
    fi
  done
  if [[ ! -f "${FFI_DEST}/${FFI_LIB}" ]]; then
    echo "warning: ${FFI_LIB} not found; fetch ArqTras/FFI prebuilt or run rust/tool/build_wallet_flutter_ffi.sh" >&2
  fi
  if [[ -f "${FFI_DEST}/${FFI_LIB}" ]] && [[ "${FFI_SRC_USED}" == *x86_64-pc-windows-gnu* ]]; then
    MINGW_BIN=""
    if [[ -n "${MINGW_PREFIX:-}" ]] && [[ -d "${MINGW_PREFIX}/bin" ]]; then
      MINGW_BIN="${MINGW_PREFIX}/bin"
    elif [[ -d "/mingw64/bin" ]]; then
      MINGW_BIN="/mingw64/bin"
    fi
    if [[ -d "${MINGW_BIN}" ]]; then
      for rt in libgcc_s_seh-1.dll libstdc++-6.dll libwinpthread-1.dll; do
        if [[ -f "${MINGW_BIN}/${rt}" ]]; then
          cp -f "${MINGW_BIN}/${rt}" "${FFI_DEST}/"
          echo "copied ${rt} -> ${FFI_DEST}/ (MinGW runtime for GNU FFI)"
        fi
      done
    fi
  fi
fi
