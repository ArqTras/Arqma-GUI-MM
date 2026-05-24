#!/usr/bin/env bash
# Build release APK for Arqma Wallet Android.
set -euo pipefail
APP="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "${APP}/../.." && pwd)"
cd "${APP}"

if [[ "${ARQMA_SKIP_ANDROID_FFI_COPY:-0}" != "1" ]]; then
  bash "${APP}/tool/copy_android_wallet_ffi.sh"
fi

VERSION_LINE="$(grep -E '^version:' pubspec.yaml | head -1)"
VERSION="${VERSION_LINE#version:}"
VERSION="${VERSION// /}"
SLUG="${VERSION%%+*}"

flutter pub get
flutter build apk --release
flutter build appbundle --release

APK="${APP}/build/app/outputs/flutter-apk/app-release.apk"
AAB="${APP}/build/app/outputs/bundle/release/app-release.aab"
mkdir -p "${APP}/dist"
if [[ -f "${APK}" ]]; then
  cp -f "${APK}" "${APP}/dist/Arqma-Wallet-Android-${SLUG}.apk"
  echo "APK: ${APP}/dist/Arqma-Wallet-Android-${SLUG}.apk"
fi
if [[ -f "${AAB}" ]]; then
  cp -f "${AAB}" "${APP}/dist/Arqma-Wallet-Android-${SLUG}.aab"
  echo "AAB: ${APP}/dist/Arqma-Wallet-Android-${SLUG}.aab"
fi
