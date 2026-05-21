#!/bin/sh
# Copy `libarqma_wallet_flutter_ffi.dylib` (iOS platform only) into the app Frameworks folder.
set -e
FW="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Frameworks"
mkdir -p "${FW}"
LIB=libarqma_wallet_flutter_ffi.dylib
ROOT="${SRCROOT}/../../.."
DEVICE="${ROOT}/rust/target/aarch64-apple-ios/release/${LIB}"
SIM="${ROOT}/rust/target/aarch64-apple-ios-sim/release/${LIB}"
STAGED="${SRCROOT}/Frameworks/${LIB}"

ios_platform_ok() {
  # Rust/cargo iOS artifacts often use LC_VERSION_MIN_IPHONEOS; CMake/Xcode may use
  # LC_BUILD_VERSION (platform 2 = iOS, 1 = macOS — must never ship on iPhone).
  if otool -l "$1" 2>/dev/null | grep -q 'LC_VERSION_MIN_IPHONEOS'; then
    return 0
  fi
  if otool -l "$1" 2>/dev/null | grep -q 'LC_VERSION_MIN_MACOSX'; then
    return 1
  fi
  otool -l "$1" 2>/dev/null | awk '/platform / { print $2; exit }' | grep -qx 2
}

sign_embedded_dylib() {
  dest="$1"
  # Simulator / unsigned builds may use "-"; physical devices need the app team identity.
  identity="${EXPANDED_CODE_SIGN_IDENTITY:-}"
  if [ -z "${identity}" ] || [ "${identity}" = "-" ]; then
    if [ "${PLATFORM_NAME}" = "iphoneos" ]; then
      echo "error: EXPANDED_CODE_SIGN_IDENTITY is required to embed ${LIB} on device" >&2
      exit 1
    fi
    codesign --force --sign - "${dest}" 2>/dev/null || true
    return 0
  fi
  codesign --force --sign "${identity}" --timestamp=none "${dest}"
}

try_copy() {
  src="$1"
  if [ ! -f "${src}" ]; then
    return 1
  fi
  if ! ios_platform_ok "${src}"; then
    echo "warning: skip ${src} (not iOS Mach-O — likely macOS arm64)"
    return 1
  fi
  cp -f "${src}" "${FW}/"
  echo "[Arqma mobile] ${LIB} <- ${src} (iOS)"
  install_name_tool -id "@rpath/${LIB}" "${FW}/${LIB}" 2>/dev/null || true
  sign_embedded_dylib "${FW}/${LIB}"
  return 0
}

for rel in "${DEVICE}" "${SIM}" "${STAGED}"; do
  if try_copy "${rel}"; then
    exit 0
  fi
done

echo "warning: ${LIB} not found for iOS — build with:"
echo "  bash rust/tool/build_mobile_wallet_ffi_ios.sh"
echo "Wallet create/restore will not work until an iOS dylib is bundled."
