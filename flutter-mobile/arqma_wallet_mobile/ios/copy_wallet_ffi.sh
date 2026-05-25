#!/bin/sh
# Embed wallet FFI as a proper iOS framework (App Store rejects loose .dylib in Frameworks/).
set -e
FW="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Frameworks"
FRAMEWORK_NAME=libarqma_wallet_flutter_ffi.framework
FRAMEWORK_DIR="${FW}/${FRAMEWORK_NAME}"
EXEC_NAME=libarqma_wallet_flutter_ffi
ROOT="${SRCROOT}/../../.."
if [ -z "${ARQMA_FFI_RELEASE_VERSION:-}" ] || [ "${ARQMA_FFI_RELEASE_VERSION}" = "latest" ]; then
  VERSION="$(bash "${ROOT}/build/ci/resolve-arqma-ffi-release-version.sh")"
else
  VERSION="${ARQMA_FFI_RELEASE_VERSION#v}"
fi
PREBUILT="${ROOT}/.prebuilt/arqma-wallet-ffi/${VERSION}/ios/device/${EXEC_NAME}.dylib"
DEVICE="${ROOT}/rust/target/aarch64-apple-ios/release/${EXEC_NAME}.dylib"
SIM="${ROOT}/rust/target/aarch64-apple-ios-sim/release/${EXEC_NAME}.dylib"
STAGED="${SRCROOT}/Frameworks/${EXEC_NAME}.dylib"
INFO_PLIST="${SRCROOT}/${FRAMEWORK_NAME}/Info.plist"

ios_platform_ok() {
  if otool -l "$1" 2>/dev/null | grep -q 'LC_VERSION_MIN_IPHONEOS'; then
    return 0
  fi
  if otool -l "$1" 2>/dev/null | grep -q 'LC_VERSION_MIN_MACOSX'; then
    return 1
  fi
  otool -l "$1" 2>/dev/null | awk '/platform / { print $2; exit }' | grep -qx 2
}

sign_embedded_framework() {
  identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
  if [ -z "${identity}" ] || [ "${identity}" = "-" ]; then
    if [ "${PLATFORM_NAME}" = "iphoneos" ]; then
      echo "error: EXPANDED_CODE_SIGN_IDENTITY is required to embed ${FRAMEWORK_NAME} on device" >&2
      exit 1
    fi
    codesign --force --sign - "${FRAMEWORK_DIR}" 2>/dev/null || true
    return 0
  fi
  codesign --force --sign "${identity}" --timestamp=none "${FRAMEWORK_DIR}"
}

install_framework() {
  src="$1"
  if [ ! -f "${src}" ]; then
    return 1
  fi
  if ! ios_platform_ok "${src}"; then
    echo "warning: skip ${src} (not iOS Mach-O — likely macOS arm64)"
    return 1
  fi
  rm -rf "${FRAMEWORK_DIR}"
  rm -f "${FW}/${EXEC_NAME}.dylib"
  mkdir -p "${FRAMEWORK_DIR}"
  cp -f "${src}" "${FRAMEWORK_DIR}/${EXEC_NAME}"
  if [ -f "${INFO_PLIST}" ]; then
    cp -f "${INFO_PLIST}" "${FRAMEWORK_DIR}/Info.plist"
  fi
  echo "[Arqma mobile] ${FRAMEWORK_NAME} <- ${src} (iOS)"
  install_name_tool -id "@rpath/${FRAMEWORK_NAME}/${EXEC_NAME}" "${FRAMEWORK_DIR}/${EXEC_NAME}" 2>/dev/null || true
  sign_embedded_framework
  return 0
}

for rel in "${PREBUILT}" "${STAGED}" "${DEVICE}" "${SIM}"; do
  if install_framework "${rel}"; then
    exit 0
  fi
done

echo "warning: ${EXEC_NAME}.dylib not found for iOS — run:"
echo "  bash flutter-mobile/arqma_wallet_mobile/tool/prepare_ios_wallet_ffi.sh"
echo "  (ArqTras/FFI release ARQMA_FFI_RELEASE_VERSION=${VERSION})"
echo "Wallet create/restore will not work until an iOS dylib is bundled."
