#!/usr/bin/env bash
# Copy libarqma_wallet_flutter_ffi.so into jniLibs (arm64-v8a / x86_64 / armeabi-v7a).
# Prefers ArqTras/FFI prebuilts under .prebuilt/arqma-wallet-ffi unless ARQMA_BUILD_FFI_FROM_SOURCE=1.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
APP="$(cd "$(dirname "$0")/.." && pwd)"
JNILIBS="${APP}/android/app/src/main/jniLibs"
LIB="libarqma_wallet_flutter_ffi.so"
VERSION="${ARQMA_FFI_RELEASE_VERSION:-1.0.3}"
PREBUILT_ROOT="${ROOT}/.prebuilt/arqma-wallet-ffi/${VERSION}"
CPP_SHARED="libc++_shared.so"

ndk_host_prebuilt() {
  case "$(uname -s)" in
    Darwin)
      if [[ "$(uname -m)" == "arm64" ]]; then
        echo "darwin-arm64"
      else
        echo "darwin-x86_64"
      fi
      ;;
    Linux) echo "linux-x86_64" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows-x86_64" ;;
    *) echo "linux-x86_64" ;;
  esac
}

resolve_ndk_root() {
  local c
  for c in "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}"; do
    [[ -n "${c}" && -d "${c}" ]] && echo "${c}" && return 0
  done
  local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [[ -n "${sdk}" && -d "${sdk}/ndk" ]]; then
    find "${sdk}/ndk" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -1
    return 0
  fi
  return 1
}

copy_cpp_shared() {
  local abi="$1"
  local ndk_triple="$2"
  local ndk host_prebuilt_dir src dest_dir
  ndk="$(resolve_ndk_root)" || return 1
  host_prebuilt_dir="$(ndk_host_prebuilt)"
  src="${ndk}/toolchains/llvm/prebuilt/${host_prebuilt_dir}/sysroot/usr/lib/${ndk_triple}/${CPP_SHARED}"
  if [[ ! -f "${src}" ]]; then
    echo "warn: missing NDK runtime ${src}" >&2
    return 1
  fi
  dest_dir="${JNILIBS}/${abi}"
  mkdir -p "${dest_dir}"
  cp -f "${src}" "${dest_dir}/${CPP_SHARED}"
  echo "copied ${abi} ${CPP_SHARED} <- ${src}"
}

copy_prebuilt_jni() {
  local platform="$1"
  local abi="$2"
  local src="${PREBUILT_ROOT}/${platform}/jniLibs/${abi}/${LIB}"
  if [[ ! -f "${src}" ]]; then
    return 1
  fi
  mkdir -p "${JNILIBS}/${abi}"
  cp -f "${src}" "${JNILIBS}/${abi}/${LIB}"
  echo "copied ${abi} (FFI ${VERSION}) <- ${src}"
  return 0
}

ensure_release_fetched() {
  if [[ "${ARQMA_BUILD_FFI_FROM_SOURCE:-0}" == "1" ]]; then
    return 0
  fi
  local missing=0
  for pair in "android-arm64:arm64-v8a" "android-x86_64:x86_64"; do
    local platform="${pair%%:*}"
    local abi="${pair##*:}"
    if [[ ! -f "${PREBUILT_ROOT}/${platform}/jniLibs/${abi}/${LIB}" ]]; then
      missing=1
    fi
  done
  if [[ "${missing}" -eq 1 ]]; then
    if [[ -x "${ROOT}/build/ci/fetch-arqma-wallet-ffi-release-linux.sh" ]]; then
      bash "${ROOT}/build/ci/fetch-arqma-wallet-ffi-release-linux.sh"
    elif command -v pwsh >/dev/null 2>&1; then
      pwsh -NoProfile -File "${ROOT}/build/ci/fetch-arqma-wallet-ffi-release.ps1" \
        -Platforms android-arm64,android-x86_64
    else
      echo "error: missing prebuilt FFI; run fetch-arqma-wallet-ffi-release-linux.sh" >&2
      exit 1
    fi
  fi
}

mkdir -p "${JNILIBS}"

if [[ "${ARQMA_BUILD_FFI_FROM_SOURCE:-0}" != "1" ]]; then
  ensure_release_fetched
  copied=0
  while IFS=: read -r platform abi ndk_triple; do
    [[ -n "${platform}" ]] || continue
    if copy_prebuilt_jni "${platform}" "${abi}"; then
      copy_cpp_shared "${abi}" "${ndk_triple}" || true
      copied=1
    fi
  done <<'EOF'
android-arm64:arm64-v8a:aarch64-linux-android
android-x86_64:x86_64:x86_64-linux-android
EOF
  if [[ "${copied}" -eq 1 ]]; then
    exit 0
  fi
  echo "warn: prebuilt FFI missing; falling back to rust/target" >&2
fi

copied=0
while IFS=: read -r triple abi ndk_triple; do
  [[ -n "${triple}" ]] || continue
  src="${ROOT}/rust/target/${triple}/release/${LIB}"
  if [[ ! -f "${src}" ]]; then
    echo "skip ${abi}: missing ${src}"
    continue
  fi
  mkdir -p "${JNILIBS}/${abi}"
  cp -f "${src}" "${JNILIBS}/${abi}/${LIB}"
  copy_cpp_shared "${abi}" "${ndk_triple}" || true
  echo "copied ${abi} <- ${src}"
  copied=1
done <<'EOF'
aarch64-linux-android:arm64-v8a:aarch64-linux-android
x86_64-linux-android:x86_64:x86_64-linux-android
armv7-linux-androideabi:armeabi-v7a:arm-linux-androideabi
EOF

if [[ "${copied}" -eq 0 ]]; then
  echo "error: no ${LIB} found (fetch ArqTras/FFI or build rust FFI)" >&2
  exit 1
fi
