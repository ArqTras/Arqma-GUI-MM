#!/usr/bin/env bash
# Download prebuilt arqma-wallet-flutter-ffi from GitHub Releases (Linux/macOS, no PowerShell).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${ARQMA_FFI_RELEASE_VERSION:-1.0.0}"
REPO="${ARQMA_FFI_REPO:-ArqTras/FFI}"
PLATFORMS="${ARQMA_FFI_PLATFORMS:-android-arm64,android-x86_64}"
CACHE_ROOT="${ROOT}/.prebuilt/arqma-wallet-ffi"
VER_DIR="${CACHE_ROOT}/${VERSION}"
BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"
FORCE="${ARQMA_FFI_FORCE:-0}"

mkdir -p "${VER_DIR}"

fetch_platform() {
  local platform="$1"
  local dest="${VER_DIR}/${platform}"
  local stamp="${dest}/.extracted"
  if [[ -f "${stamp}" && "${FORCE}" != "1" ]]; then
    echo "[fetch-ffi] ${platform} already at ${dest}"
    return 0
  fi
  local zip="arqma-wallet-ffi-${platform}-${VERSION}.zip"
  local url="${BASE_URL}/${zip}"
  local tmp
  tmp="$(mktemp -t arqma-ffi-XXXXXX.zip)"
  echo "[fetch-ffi] downloading ${url}"
  curl -fsSL -o "${tmp}" "${url}"
  rm -rf "${dest}"
  mkdir -p "${dest}"
  unzip -q -o "${tmp}" -d "${dest}"
  local inner="${dest}/${platform}"
  if [[ -d "${inner}" ]]; then
    shopt -s dotglob
    mv -f "${inner}"/* "${dest}/" 2>/dev/null || true
    shopt -u dotglob
    rmdir "${inner}" 2>/dev/null || true
  fi
  touch "${stamp}"
  rm -f "${tmp}"
  echo "[fetch-ffi] extracted -> ${dest}"
}

mirror_jni() {
  local platform="$1"
  local dir="${VER_DIR}/${platform}"
  local app="${ROOT}/flutter-android/arqma_wallet_android"
  [[ -d "${app}" ]] || return 0
  local jni_src="${dir}/jniLibs"
  [[ -d "${jni_src}" ]] || return 0
  local base="${app}/android/app/src/main/jniLibs"
  local ndk_triple=""
  case "${platform}" in
    android-arm64) ndk_triple="aarch64-linux-android" ;;
    android-x86_64) ndk_triple="x86_64-linux-android" ;;
  esac
  local ndk_root=""
  for c in "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}"; do
    [[ -n "${c}" && -d "${c}" ]] && ndk_root="${c}" && break
  done
  if [[ -z "${ndk_root}" && -n "${ANDROID_HOME:-}" && -d "${ANDROID_HOME}/ndk" ]]; then
    ndk_root="$(find "${ANDROID_HOME}/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
  fi
  for abi_dir in "${jni_src}"/*; do
    [[ -d "${abi_dir}" ]] || continue
    local abi
    abi="$(basename "${abi_dir}")"
    local dest_abi="${base}/${abi}"
    mkdir -p "${dest_abi}"
    cp -f "${abi_dir}/libarqma_wallet_flutter_ffi.so" "${dest_abi}/"
    echo "[fetch-ffi] jniLibs/${abi} <- ${abi_dir}/libarqma_wallet_flutter_ffi.so"
    if [[ -n "${ndk_root}" && -n "${ndk_triple}" ]]; then
      local cpp="${ndk_root}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/${ndk_triple}/libc++_shared.so"
      if [[ -f "${cpp}" ]]; then
        cp -f "${cpp}" "${dest_abi}/"
        echo "[fetch-ffi] jniLibs/${abi}/libc++_shared.so"
      fi
    fi
  done
}

IFS=',' read -r -a _platforms <<< "${PLATFORMS}"
for p in "${_platforms[@]}"; do
  p="${p// /}"
  [[ -n "${p}" ]] || continue
  fetch_platform "${p}"
  if [[ "${p}" == android-* ]]; then
    mirror_jni "${p}"
  fi
done

echo "[fetch-ffi] done (version=${VERSION}, cache=${VER_DIR})"
