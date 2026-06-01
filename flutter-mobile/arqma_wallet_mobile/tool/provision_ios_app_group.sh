#!/usr/bin/env bash
# Registers App Group + extension App ID via Xcode automatic signing, then builds Runner.
# Requires Apple Developer team 75L2UT4BNN and a logged-in Xcode account.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IOS="${MOBILE_ROOT}/ios"
TEAM_ID="${DEVELOPMENT_TEAM:-75L2UT4BNN}"
APP_GROUP="group.com.arqma.arqmaWalletMobile"
MAIN_BUNDLE="com.arqma.arqmaWalletMobile"
EXT_BUNDLE="com.arqma.arqmaWalletMobile.RescanLiveActivity"

export PATH="/Applications/Xcode.app/Contents/Developer/usr/bin:${PATH}"

echo "==> Embed Live Activity widget target (if missing)"
ruby "${SCRIPT_DIR}/embed_ios_live_activity_target.rb"

echo "==> Pod install"
(cd "${IOS}" && pod install)

echo "==> Provision App Group + extension with Xcode (-allowProvisioningUpdates)"
echo "    Main: ${MAIN_BUNDLE}"
echo "    Extension: ${EXT_BUNDLE}"
echo "    App Group: ${APP_GROUP}"

xcodebuild \
  -workspace "${IOS}/Runner.xcworkspace" \
  -scheme Runner \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  CODE_SIGN_STYLE=Automatic \
  build

echo "==> Done. Open ios/Runner.xcworkspace → Runner + ${EXT_BUNDLE##*.} target → Signing if warnings remain."
