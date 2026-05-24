#!/usr/bin/env bash
# CI/local: fetch ArqTras/FFI prebuilts, build Android APK + AAB, stage dist/ for GitHub Release.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="${ROOT}/flutter-android/arqma_wallet_android"
cd "${APP}"

VERSION_LINE="$(grep -E '^version:' pubspec.yaml | head -1)"
VERSION="${VERSION_LINE#version:}"
VERSION="${VERSION// /}"
SLUG="${VERSION%%+*}"

export ARQMA_FFI_RELEASE_VERSION="${ARQMA_FFI_RELEASE_VERSION:-1.0.0}"
export ARQMA_SKIP_ANDROID_FFI_COPY=1

echo "==> Fetch wallet FFI (${ARQMA_FFI_RELEASE_VERSION}) from ArqTras/FFI"
bash "${ROOT}/build/ci/fetch-arqma-wallet-ffi-release-linux.sh"

echo "==> jniLibs (prebuilt + libc++_shared)"
bash "${APP}/tool/copy_android_wallet_ffi.sh"

flutter pub get
flutter build apk --release
flutter build appbundle --release

APK="${APP}/build/app/outputs/flutter-apk/app-release.apk"
AAB="${APP}/build/app/outputs/bundle/release/app-release.aab"
[[ -f "${APK}" ]] || { echo "missing ${APK}" >&2; exit 1; }
[[ -f "${AAB}" ]] || { echo "missing ${AAB}" >&2; exit 1; }

DIST="${APP}/dist"
mkdir -p "${DIST}"
OUT_APK="${DIST}/Arqma-Wallet-Android-${SLUG}.apk"
OUT_AAB="${DIST}/Arqma-Wallet-Android-${SLUG}.aab"
cp -f "${APK}" "${OUT_APK}"
cp -f "${AAB}" "${OUT_AAB}"

MANIFEST="${DIST}/Arqma-Wallet-Android-${SLUG}-manifest.txt"
{
  echo "Arqma Wallet Android ${SLUG}"
  echo "version: ${VERSION}"
  echo "ffi: ArqTras/FFI ${ARQMA_FFI_RELEASE_VERSION}"
  echo "apk: $(basename "${OUT_APK}") ($(wc -c < "${OUT_APK}" | tr -d ' ') bytes)"
  echo "aab: $(basename "${OUT_AAB}") ($(wc -c < "${OUT_AAB}" | tr -d ' ') bytes)"
  echo "applicationId: com.arqma.arqma_wallet_android"
} > "${MANIFEST}"

(
  cd "${DIST}"
  sha256sum "$(basename "${OUT_APK}")" "$(basename "${OUT_AAB}")" > "SHA256SUMS-android-${SLUG}.txt"
)

echo "==> Android release artifacts:"
ls -la "${DIST}/Arqma-Wallet-Android-${SLUG}"* "${DIST}/SHA256SUMS-android-${SLUG}.txt" "${MANIFEST}"
