#!/usr/bin/env bash
# Full iOS device chain: depends + wallet_merged + FFI + Flutter release + install.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEVICE_ID="${ARQMA_IOS_DEVICE_ID:-00008140-001049043A60801C}"
export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:${PATH}"

bash "${ROOT}/rust/tool/build_ios_wallet_merged.sh"
bash "${ROOT}/rust/tool/build_mobile_wallet_ffi_ios.sh"

cd "${ROOT}/flutter-mobile/arqma_wallet_mobile"
flutter clean
flutter pub get
flutter build ios --release --no-pub
flutter install -d "${DEVICE_ID}"

echo "Done. Open the app from the home screen (release build)."
