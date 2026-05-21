#!/bin/sh
# Copy `libarqma_wallet_flutter_ffi.dylib` into the app Frameworks folder when built for iOS.
set -e
FW="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Frameworks"
mkdir -p "${FW}"
LIB=libarqma_wallet_flutter_ffi.dylib
ROOT="${SRCROOT}/../../.."
for rel in \
  "${ROOT}/rust/target/aarch64-apple-ios/release/${LIB}" \
  "${ROOT}/rust/target/aarch64-apple-ios-sim/release/${LIB}" \
  "${ROOT}/rust/target/release/${LIB}"; do
  if [ -f "${rel}" ]; then
    cp -f "${rel}" "${FW}/"
    echo "[Arqma mobile] ${LIB} <- ${rel}"
    install_name_tool -id "@rpath/${LIB}" "${FW}/${LIB}" 2>/dev/null || true
    exit 0
  fi
done
echo "warning: ${LIB} not found — build with rust/tool/build_mobile_wallet_ffi_ios.sh"
