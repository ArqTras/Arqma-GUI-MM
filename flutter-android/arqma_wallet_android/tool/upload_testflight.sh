#!/usr/bin/env bash
# Build IPA (with SwiftSupport) and upload to App Store Connect / TestFlight.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "${ROOT}/../.." && pwd)"
export PATH="${HOME}/.cargo/bin:/Applications/Xcode.app/Contents/Developer/usr/bin:/opt/homebrew/bin:/usr/bin:/bin:${PATH}"

VERSION_LINE="$(grep -m1 '^version:' "${ROOT}/pubspec.yaml" | sed 's/^version:[[:space:]]*//;s/[[:space:]]*$//')"
VERSION_NAME="${VERSION_LINE%%+*}"
BUILD_NUMBER="${VERSION_LINE#*+}"
[[ "${BUILD_NUMBER}" == "${VERSION_LINE}" ]] && BUILD_NUMBER="1"

FFI="${REPO}/rust/target/aarch64-apple-ios/release/libarqma_wallet_flutter_ffi.dylib"
if [[ ! -f "${FFI}" ]]; then
  echo "error: missing ${FFI} — run rust/tool/build_mobile_wallet_ffi_ios.sh" >&2
  exit 1
fi

mkdir -p "${ROOT}/ios/Frameworks"
cp -f "${FFI}" "${ROOT}/ios/Frameworks/"

echo "==> flutter build ipa ${VERSION_NAME} (${BUILD_NUMBER})"
cd "${ROOT}"
flutter pub get
flutter build ipa --release --no-pub \
  --build-name="${VERSION_NAME}" \
  --build-number="${BUILD_NUMBER}" \
  --export-options-plist="${ROOT}/ios/ExportOptions-appstore-export.plist"

ARCHIVE="${ROOT}/build/ios/archive/Runner.xcarchive"
IPA="$(find "${ROOT}/build/ios/ipa" -maxdepth 1 -name '*.ipa' -print -quit)"
if [[ -z "${IPA}" || ! -f "${IPA}" ]]; then
  echo "error: no IPA under build/ios/ipa" >&2
  exit 1
fi

bash "${ROOT}/tool/attach_ios_archive_dsyms.sh" "${ARCHIVE}"

IPA_LIST="$(mktemp)"
unzip -l "${IPA}" >"${IPA_LIST}" 2>/dev/null || true
if grep -Fq 'Frameworks/libarqma_wallet_flutter_ffi.dylib' "${IPA_LIST}"; then
  echo "error: ${IPA} has loose FFI dylib in Frameworks/ (ITMS-90426) — rebuild after copy_wallet_ffi.sh framework fix" >&2
  rm -f "${IPA_LIST}"
  exit 1
fi
if ! grep -Fq 'libarqma_wallet_flutter_ffi.framework/libarqma_wallet_flutter_ffi' "${IPA_LIST}"; then
  echo "error: ${IPA} missing libarqma_wallet_flutter_ffi.framework" >&2
  rm -f "${IPA_LIST}"
  exit 1
fi
rm -f "${IPA_LIST}"
echo "OK: wallet FFI packaged as framework (no loose dylib)"

echo "==> Upload to App Store Connect…"
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE}" \
  -exportOptionsPlist "${ROOT}/ios/ExportOptions-appstore.plist" \
  -exportPath "${ROOT}/build/ios/app-store-upload" \
  -allowProvisioningUpdates

echo "Upload finished. TestFlight: App Store Connect → build ${VERSION_NAME} (${BUILD_NUMBER})."
