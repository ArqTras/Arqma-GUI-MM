#!/usr/bin/env bash
# Build release APK for Arqma Wallet Android.
set -euo pipefail
APP="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "${APP}/../.." && pwd)"
cd "${APP}"

if [[ "${ARQMA_SKIP_ANDROID_FFI_COPY:-0}" != "1" ]]; then
  if [[ -f "${ROOT}/rust/target/aarch64-linux-android/release/libarqma_wallet_flutter_ffi.so" ]]; then
    bash "${APP}/tool/copy_android_wallet_ffi.sh"
  else
    echo "warn: no aarch64 libarqma_wallet_flutter_ffi.so — APK will lack wallet FFI" >&2
  fi
fi

flutter pub get
flutter build apk --release
OUT="${APP}/build/app/outputs/flutter-apk/app-release.apk"
if [[ -f "${OUT}" ]]; then
  mkdir -p "${APP}/dist"
  cp -f "${OUT}" "${APP}/dist/arqma-wallet-android-$(date -u +%Y%m%d).apk"
  echo "APK: ${APP}/dist/"
fi
