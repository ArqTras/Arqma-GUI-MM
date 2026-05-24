#!/usr/bin/env bash
# Full iOS device pipeline with live, line-buffered progress in the terminal.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
UPSTREAM="${ARQMA_WALLET2_UPSTREAM_DIR:-${ROOT}/rust/arqma-rpc-upstream}"
DEPENDS_HOST="${ARQMA_IOS_DEPENDS_HOST:-aarch64-apple-ios}"
DEVICE_ID="${ARQMA_IOS_DEVICE_ID:-00008140-001049043A60801C}"
J="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

export PATH="/usr/bin:/bin:${HOME}/.cargo/bin:/opt/homebrew/bin:${PATH}"
export PS4='+ [$(date "+%H:%M:%S")] '
set -x

phase() {
  echo ""
  echo "======================================================================"
  echo ">>> $*"
  echo "======================================================================"
  echo ""
}

phase "1/6 — contrib/depends (HOST=${DEPENDS_HOST}, -j1)"
make -C "${UPSTREAM}/contrib/depends" "HOST=${DEPENDS_HOST}" -j1

phase "2/6 — ICU static into depends"
bash "${ROOT}/build/ci/build-icu-static-into-depends.sh" "${UPSTREAM}" "${DEPENDS_HOST}"

phase "3/6 — wallet_merged (CMake + depends toolchain)"
ARQMA_SKIP_IOS_DEPENDS=1 bash "${ROOT}/rust/tool/build_ios_wallet_merged.sh"

phase "4/6 — Flutter FFI for iOS device"
bash "${ROOT}/rust/tool/build_mobile_wallet_ffi_ios.sh"

FFI="${ROOT}/rust/target/aarch64-apple-ios/release/libarqma_wallet_flutter_ffi.dylib"
phase "5/6 — verify FFI platform (expect PLATFORM 2 = iOS)"
otool -l "${FFI}" | rg -n "LC_BUILD_VERSION|platform|LC_VERSION_MIN" || otool -l "${FFI}" | head -40

phase "6/6 — Flutter release + install on ${DEVICE_ID}"
cd "${ROOT}/flutter-mobile/arqma_wallet_mobile"
flutter clean
flutter pub get
flutter build ios --release --no-pub
flutter install -d "${DEVICE_ID}"

echo ""
echo "======================================================================"
echo ">>> DONE — open the app from the home screen (release build)."
echo "======================================================================"
