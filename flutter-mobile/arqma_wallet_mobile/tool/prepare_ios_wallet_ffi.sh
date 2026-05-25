#!/usr/bin/env bash
# Stage iOS wallet FFI for Flutter/Xcode (default: ArqTras/FFI prebuilt, not local rust build).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
APP="$(cd "$(dirname "$0")/.." && pwd)"
LIB="libarqma_wallet_flutter_ffi.dylib"
VERSION="$(bash "${ROOT}/build/ci/resolve-arqma-ffi-release-version.sh")"
PREBUILT="${ROOT}/.prebuilt/arqma-wallet-ffi/${VERSION}/ios/device/${LIB}"
STAGED="${APP}/ios/Frameworks/${LIB}"
export PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:${PATH}"

ios_platform_ok() {
  otool -l "$1" 2>/dev/null | grep -q 'LC_VERSION_MIN_IPHONEOS' && return 0
  otool -l "$1" 2>/dev/null | grep -q 'LC_VERSION_MIN_MACOSX' && return 1
  otool -l "$1" 2>/dev/null | awk '/platform / { print $2; exit }' | grep -qx 2
}

resolve_codesign_identity() {
  if [[ -n "${CODE_SIGN_IDENTITY:-}" && "${CODE_SIGN_IDENTITY}" != "-" ]]; then
    echo "${CODE_SIGN_IDENTITY}"
    return 0
  fi
  security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Apple Distribution' \
    | head -1 \
    | sed -n 's/.*"\(.*\)".*/\1/p' || true
}

sign_ffi_binary() {
  local bin="$1"
  local id
  id="$(resolve_codesign_identity)"
  if [[ -z "${id}" ]]; then
    echo "[prepare-ios-ffi] skip codesign (no Apple Distribution identity in keychain)"
    return 0
  fi
  codesign --force --sign "${id}" --timestamp=none "${bin}"
  codesign --verify --verbose=2 "${bin}"
  echo "[prepare-ios-ffi] signed ${bin} (${id})"
}

if [[ "${ARQMA_BUILD_FFI_FROM_SOURCE:-0}" == "1" ]]; then
  echo "==> Building wallet FFI from source (ARQMA_BUILD_FFI_FROM_SOURCE=1)"
  export ARQMA_SKIP_IOS_DEPENDS="${ARQMA_SKIP_IOS_DEPENDS:-1}"
  export ARQMA_SKIP_IOS_WALLET_MERGED="${ARQMA_SKIP_IOS_WALLET_MERGED:-1}"
  bash "${ROOT}/rust/tool/build_mobile_wallet_ffi_ios.sh"
  src="${ROOT}/rust/target/aarch64-apple-ios/release/${LIB}"
else
  echo "==> Fetch wallet FFI ${VERSION} from ArqTras/FFI (ios)"
  export ARQMA_FFI_RELEASE_VERSION="${VERSION}"
  export ARQMA_FFI_PLATFORMS=ios
  bash "${ROOT}/build/ci/fetch-arqma-wallet-ffi-release-linux.sh"
  src="${PREBUILT}"
  if [[ ! -f "${src}" ]]; then
    src="$(find "${ROOT}/.prebuilt/arqma-wallet-ffi/${VERSION}/ios" -name "${LIB}" -type f 2>/dev/null | head -1)"
  fi
fi

if [[ ! -f "${src}" ]]; then
  echo "error: missing iOS ${LIB} (ArqTras/FFI ${VERSION} or rust build)" >&2
  exit 1
fi
if ! ios_platform_ok "${src}"; then
  echo "error: ${src} is not iOS arm64 (wrong platform — use ArqTras/FFI ios artifact)" >&2
  exit 1
fi

mkdir -p "${APP}/ios/Frameworks"
cp -f "${src}" "${STAGED}"
sign_ffi_binary "${STAGED}"
echo "[prepare-ios-ffi] staged ${STAGED} <- ${src}"
