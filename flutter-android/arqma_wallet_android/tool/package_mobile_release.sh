#!/usr/bin/env bash
# Build iOS release artifacts for GitHub Releases and TestFlight (App Store Connect).
#
# Prerequisites (once per machine / after Rust changes):
#   bash rust/tool/build_ios_wallet_merged.sh    # or ARQMA_SKIP_IOS_WALLET_MERGED=1 if already built
#   bash rust/tool/build_mobile_wallet_ffi_ios.sh
#
# Usage (from repo root or flutter-mobile/arqma_wallet_mobile):
#   ./tool/package_mobile_release.sh
#   ./tool/package_mobile_release.sh --skip-ffi
#   ARQMA_IOS_EXPORT_METHOD=development ./tool/package_mobile_release.sh   # ad-hoc / dev IPA
#
# Outputs under flutter-mobile/arqma_wallet_mobile/dist/:
#   Arqma-Wallet-Mobile-{semver}-ios.ipa
#   Arqma-Wallet-Mobile-{semver}-ios-manifest.txt
#   SHA256SUMS.txt
#   TESTFLIGHT.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${MOBILE_ROOT}/../.." && pwd)"
cd "${MOBILE_ROOT}"

SKIP_FFI=0
for arg in "$@"; do
  case "${arg}" in
    --skip-ffi) SKIP_FFI=1 ;;
    -h | --help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: ${arg}" >&2
      exit 2
      ;;
  esac
done

export PATH="${HOME}/.cargo/bin:/opt/homebrew/bin:/usr/bin:/bin:${PATH}"

VERSION_LINE="$(grep -m1 '^version:' pubspec.yaml | sed 's/^version:[[:space:]]*//;s/[[:space:]]*$//')"
VERSION_NAME="${VERSION_LINE%%+*}"
BUILD_NUMBER="${VERSION_LINE#*+}"
if [[ "${BUILD_NUMBER}" == "${VERSION_LINE}" ]]; then
  BUILD_NUMBER="1"
fi
VERSION_SAFE="${VERSION_NAME}"

DIST="${MOBILE_ROOT}/dist"
mkdir -p "${DIST}"

BASE="Arqma-Wallet-Mobile-${VERSION_SAFE}"
MANIFEST="${DIST}/${BASE}-ios-manifest.txt"
CHECKSUMS="${DIST}/SHA256SUMS.txt"
TESTFLIGHT_DOC="${DIST}/TESTFLIGHT.md"

echo "==> Arqma Wallet Mobile release ${VERSION_LINE} (ios)"

if [[ "${SKIP_FFI}" != "1" ]]; then
  echo "==> Native wallet FFI (iOS device)"
  export ARQMA_SKIP_IOS_DEPENDS="${ARQMA_SKIP_IOS_DEPENDS:-1}"
  export ARQMA_SKIP_IOS_WALLET_MERGED="${ARQMA_SKIP_IOS_WALLET_MERGED:-1}"
  bash "${REPO_ROOT}/rust/tool/build_mobile_wallet_ffi_ios.sh"
fi

DEVICE_DYLIB="${REPO_ROOT}/rust/target/aarch64-apple-ios/release/libarqma_wallet_flutter_ffi.dylib"
if [[ ! -f "${DEVICE_DYLIB}" ]]; then
  echo "error: missing ${DEVICE_DYLIB} — run rust/tool/build_mobile_wallet_ffi_ios.sh" >&2
  exit 1
fi

mkdir -p "${MOBILE_ROOT}/ios/Frameworks"
cp -f "${DEVICE_DYLIB}" "${MOBILE_ROOT}/ios/Frameworks/"

echo "==> Flutter pub get"
flutter pub get

EXPORT_METHOD="${ARQMA_IOS_EXPORT_METHOD:-app-store}"
EXPORT_PLIST="${MOBILE_ROOT}/ios/ExportOptions-appstore-export.plist"
IPA_SUFFIX="testflight"
if [[ "${EXPORT_METHOD}" == "development" ]]; then
  EXPORT_PLIST="${MOBILE_ROOT}/ios/ExportOptions-development.plist"
  IPA_SUFFIX="development"
fi

echo "==> flutter build ipa (export=${EXPORT_METHOD}, build-number=${BUILD_NUMBER})"
set +e
flutter build ipa --release --no-pub \
  --build-name="${VERSION_NAME}" \
  --build-number="${BUILD_NUMBER}" \
  --export-options-plist="${EXPORT_PLIST}"
IPA_BUILD_RC=$?
set -e

ARCHIVE_DIR="${MOBILE_ROOT}/build/ios/archive"
XCARCHIVE="$(find "${ARCHIVE_DIR}" -maxdepth 1 -name '*.xcarchive' -print -quit 2>/dev/null || true)"
XCARCHIVE_ZIP="${DIST}/${BASE}-ios.xcarchive.zip"

if [[ -n "${XCARCHIVE}" && -d "${XCARCHIVE}" ]]; then
  echo "==> Attach dSYMs for embedded FFI + objective_c.framework"
  bash "${MOBILE_ROOT}/tool/attach_ios_archive_dsyms.sh" "${XCARCHIVE}"
  echo "==> Zip xcarchive (manual TestFlight export in Xcode if IPA export failed)"
  rm -f "${XCARCHIVE_ZIP}"
  (cd "$(dirname "${XCARCHIVE}")" && ditto -c -k --sequesterRsrc --keepParent "$(basename "${XCARCHIVE}")" "${XCARCHIVE_ZIP}")
fi

BUILT_IPA="$(find "${MOBILE_ROOT}/build/ios/ipa" -maxdepth 1 -name '*.ipa' -print -quit 2>/dev/null || true)"
if [[ -z "${BUILT_IPA}" || ! -f "${BUILT_IPA}" ]]; then
  if [[ "${EXPORT_METHOD}" == "app-store" && -n "${XCARCHIVE}" ]]; then
    echo "warning: App Store IPA export failed (need iOS Distribution certificate)."
    echo "         Falling back to development IPA for GitHub / device testing."
    EXPORT_METHOD="development"
    EXPORT_PLIST="${MOBILE_ROOT}/ios/ExportOptions-development.plist"
    IPA_SUFFIX="development"
    IPA_OUT="${DIST}/${BASE}-ios-${IPA_SUFFIX}.ipa"
    flutter build ipa --release --no-pub \
      --build-name="${VERSION_NAME}" \
      --build-number="${BUILD_NUMBER}" \
      --export-options-plist="${EXPORT_PLIST}"
    BUILT_IPA="$(find "${MOBILE_ROOT}/build/ios/ipa" -maxdepth 1 -name '*.ipa' -print -quit 2>/dev/null || true)"
  fi
fi

if [[ -z "${BUILT_IPA}" || ! -f "${BUILT_IPA}" ]]; then
  echo "error: no IPA — open ${XCARCHIVE:-Runner.xcarchive} in Xcode → Distribute App" >&2
  echo "       TestFlight needs Apple Distribution cert + App Store provisioning profile." >&2
  exit 1
fi

IPA_OUT="${DIST}/${BASE}-ios-${IPA_SUFFIX}.ipa"
rm -f "${DIST}/${BASE}"-ios-*.ipa 2>/dev/null || true
cp -f "${BUILT_IPA}" "${IPA_OUT}"

# Verify embedded FFI + signature (device builds only).
FFI_CHECK="$(mktemp -d)"
unzip -q -o "${IPA_OUT}" -d "${FFI_CHECK}"
PAYLOAD="$(find "${FFI_CHECK}/Payload" -maxdepth 1 -name '*.app' -print -quit)"
FFI_FRAMEWORK="${PAYLOAD}/Frameworks/libarqma_wallet_flutter_ffi.framework/libarqma_wallet_flutter_ffi"
FFI_LOOSE="${PAYLOAD}/Frameworks/libarqma_wallet_flutter_ffi.dylib"
if [[ -f "${FFI_LOOSE}" ]]; then
  echo "error: IPA has loose libarqma_wallet_flutter_ffi.dylib in Frameworks/ (ITMS-90426) — must be a .framework bundle" >&2
  rm -rf "${FFI_CHECK}"
  exit 1
fi
if [[ ! -f "${FFI_FRAMEWORK}" ]]; then
  echo "error: IPA missing libarqma_wallet_flutter_ffi.framework — wallet will not work on device" >&2
  rm -rf "${FFI_CHECK}"
  exit 1
fi
codesign --verify --verbose=2 "${PAYLOAD}/Frameworks/libarqma_wallet_flutter_ffi.framework" >/dev/null 2>&1 || {
  echo "error: FFI framework in IPA is not validly signed" >&2
  rm -rf "${FFI_CHECK}"
  exit 1
}
rm -rf "${FFI_CHECK}"

(
  cd "${DIST}"
  shasum -a 256 "$(basename "${IPA_OUT}")" > "${CHECKSUMS}.tmp"
  mv -f "${CHECKSUMS}.tmp" "${CHECKSUMS}"
)

GIT_SHA="$(git -C "${REPO_ROOT}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
GIT_TAG="$(git -C "${REPO_ROOT}" describe --tags --always 2>/dev/null || echo none)"

cat > "${MANIFEST}" <<EOF
Arqma Wallet Mobile — iOS release manifest
==========================================
Version:     ${VERSION_LINE}
Bundle ID:   com.arqma.arqmaWalletMobile
Team ID:     75L2UT4BNN
Export:      ${EXPORT_METHOD}
Git:         ${GIT_SHA} (${GIT_TAG})
Built:       $(date -u +"%Y-%m-%dT%H:%M:%SZ") UTC
Host:        $(uname -srm)

Artifacts:
  $(basename "${IPA_OUT}")  — export: ${EXPORT_METHOD} (${IPA_SUFFIX})
  $(basename "${XCARCHIVE_ZIP:-none}") — Xcode archive (manual Distribute App)
  SHA256SUMS.txt            — checksum

FFI: libarqma_wallet_flutter_ffi.dylib (aarch64-apple-ios, static-hybrid)
Remote nodes only (no local arqmad).
EOF

cat > "${TESTFLIGHT_DOC}" <<EOF
# TestFlight upload (Arqma Wallet Mobile)

## Prerequisites

- Apple Developer **Program** membership (team **75L2UT4BNN**)
- **Apple Distribution** certificate (Xcode → Settings → Accounts → Manage Certificates → **+** → Apple Distribution)
- App Store provisioning profile for **com.arqma.arqmaWalletMobile**
- App record in [App Store Connect](https://appstoreconnect.apple.com/)

If \`package_mobile_release.sh\` only produced \`*-ios-development.ipa\`, Distribution cert was missing.
Re-run after creating the certificate:

\`\`\`bash
./tool/package_mobile_release.sh --skip-ffi
# or force App Store export:
ARQMA_IOS_EXPORT_METHOD=app-store ./tool/package_mobile_release.sh --skip-ffi
\`\`\`

Or open \`*-ios.xcarchive.zip\` (unzip), then Xcode → **Distribute App** → App Store Connect.

**Icons:** App Store requires opaque 1024×1024 icon (no alpha). Regenerate: \`./tool/generate_app_icons.sh\`.

**dSYM warnings** for \`libarqma_wallet_flutter_ffi.dylib\` / \`objective_c.framework\`: export uses \`uploadSymbols=false\` (embedded Rust/Flutter binaries without Apple dSYMs).

## Upload IPA (TestFlight)

Use \`**-ios-testflight.ipa\`** (App Store export), not \`*-development.ipa\`.

1. Open **Transporter** (or Xcode → Organizer → Distribute App).
2. Sign in with the Apple ID linked to the developer team.
3. Drag the **testflight** IPA from \`dist/\` into Transporter.
4. Click **Deliver**. Wait for processing (often 5–15 minutes).
5. App Store Connect → **TestFlight** → select the build → add testers / groups.

### CLI (optional)

\`\`\`bash
xcrun altool --upload-app -f dist/Arqma-Wallet-Mobile-VERSION-ios-testflight.ipa \
  -t ios --apiKey YOUR_KEY_ID --apiIssuer YOUR_ISSUER_ID
\`\`\`

## GitHub Release

Attach to a release tag matching pubspec semver (e.g. \`5.1.1\` or \`v5.1.1\`):

- \`Arqma-Wallet-Mobile-5.1.1-ios-testflight.ipa\` (or \`*-development.ipa\` for dev testers)
- \`Arqma-Wallet-Mobile-5.1.1-ios.xcarchive.zip\`
- \`SHA256SUMS.txt\`, \`*-ios-manifest.txt\`

## Bump build for re-upload

Edit \`pubspec.yaml\` build number after \`+\` (e.g. \`5.1.1+2\`) and re-run \`./tool/package_mobile_release.sh\`.
EOF

echo ""
echo "Packaged:"
echo "  ${IPA_OUT}"
echo "  ${MANIFEST}"
echo "  ${CHECKSUMS}"
echo "  ${TESTFLIGHT_DOC}"
ls -lh "${IPA_OUT}"
