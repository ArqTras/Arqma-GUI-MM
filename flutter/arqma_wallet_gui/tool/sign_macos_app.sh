#!/usr/bin/env bash
# Sign a Flutter macOS .app (and optional .dmg) for distribution outside the Mac App Store.
#
# Requires a "Developer ID Application" certificate in the login keychain.
# Optional notarization (recommended for other users' Macs):
#   ARQMA_MACOS_NOTARIZE=1 ARQMA_NOTARY_KEYCHAIN_PROFILE=your-profile ./tool/sign_macos_app.sh path/to/Arqma-Wallet.app
#
# Usage:
#   tool/sign_macos_app.sh build/macos/Build/Products/Release/Arqma-Wallet.app
#   tool/sign_macos_app.sh Arqma-Wallet.app --dmg dist/Arqma-Wallet-Flutter-5.1.2-macos-signed.dmg
#
# Env:
#   ARQMA_MACOS_SIGN_IDENTITY   explicit codesign identity (default: auto Developer ID Application)
#   ARQMA_MACOS_SIGN_SKIP=1     skip signing (adhoc build)
#   ARQMA_MACOS_SIGN_REQUIRED=1 fail when no Developer ID identity is found
#   ARQMA_MACOS_NOTARIZE=1      submit to Apple notary service and staple ticket
#   ARQMA_NOTARY_KEYCHAIN_PROFILE  notarytool keychain profile name
#   APPLE_ID / APPLE_APP_SPECIFIC_PASSWORD / DEVELOPMENT_TEAM  notarytool credentials
#   ARQMA_MACOS_SIGN_STATUS_FILE  write "signed" or "unsigned" (for package_flutter_release.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENTITLEMENTS="${GUI_ROOT}/macos/Runner/Release.entitlements"
DMG_PATH=""
NOTARIZE="${ARQMA_MACOS_NOTARIZE:-0}"

write_sign_status() {
  if [[ -n "${ARQMA_MACOS_SIGN_STATUS_FILE:-}" ]]; then
    printf '%s\n' "$1" > "${ARQMA_MACOS_SIGN_STATUS_FILE}"
  fi
}

usage() {
  echo "usage: $0 path/to/Arqma-Wallet.app [--dmg path/to/file.dmg]" >&2
  exit 2
}

APP="${1:-}"
shift || usage
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dmg)
      DMG_PATH="${2:-}"
      shift 2
      ;;
    --notarize)
      NOTARIZE=1
      shift
      ;;
    -h | --help)
      usage
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ -z "${APP}" ]] || [[ ! -d "${APP}" ]]; then
  echo "error: app bundle not found: ${APP:-<missing>}" >&2
  exit 1
fi
APP="$(cd "$(dirname "${APP}")" && pwd)/$(basename "${APP}")"

if [[ "${ARQMA_MACOS_SIGN_SKIP:-0}" == "1" ]]; then
  echo "[sign-macos] skip (ARQMA_MACOS_SIGN_SKIP=1)"
  write_sign_status unsigned
  exit 0
fi

resolve_sign_identity() {
  if [[ -n "${ARQMA_MACOS_SIGN_IDENTITY:-}" ]]; then
    echo "${ARQMA_MACOS_SIGN_IDENTITY}"
    return 0
  fi
  if [[ -n "${CODE_SIGN_IDENTITY:-}" && "${CODE_SIGN_IDENTITY}" != "-" ]]; then
    echo "${CODE_SIGN_IDENTITY}"
    return 0
  fi
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ { print $2; exit }'
}

IDENTITY="$(resolve_sign_identity)"
if [[ -z "${IDENTITY}" ]]; then
  msg="[sign-macos] no Developer ID Application identity in keychain"
  if [[ "${ARQMA_MACOS_SIGN_REQUIRED:-0}" == "1" ]]; then
    echo "error: ${msg}" >&2
    exit 1
  fi
  echo "${msg}; leaving adhoc signature"
  write_sign_status unsigned
  exit 0
fi

if [[ ! -f "${ENTITLEMENTS}" ]]; then
  echo "error: missing entitlements: ${ENTITLEMENTS}" >&2
  exit 1
fi

sign_mach_o() {
  local target="$1"
  codesign --force --sign "${IDENTITY}" --options runtime --timestamp "${target}"
  echo "[sign-macos] ${target}"
}

echo "[sign-macos] identity: ${IDENTITY}"

xattr -cr "${APP}" 2>/dev/null || true

if [[ -d "${APP}/Contents/Frameworks" ]]; then
  while IFS= read -r -d '' item; do
    base="$(basename "${item}")"
    if [[ -d "${item}" && "${base}" == *.framework ]]; then
      sign_mach_o "${item}"
    elif [[ -f "${item}" ]] && file -b "${item}" | grep -q 'Mach-O'; then
      sign_mach_o "${item}"
    fi
  done < <(find "${APP}/Contents/Frameworks" -depth -print0)
fi

if [[ -d "${APP}/Contents/Resources/bin" ]]; then
  shopt -s nullglob
  for bin in "${APP}/Contents/Resources/bin/"*; do
    [[ -f "${bin}" ]] || continue
    if file -b "${bin}" | grep -q 'Mach-O'; then
      sign_mach_o "${bin}"
    fi
  done
  shopt -u nullglob
fi

MAIN_EXE="${APP}/Contents/MacOS/Arqma-Wallet"
if [[ ! -f "${MAIN_EXE}" ]]; then
  echo "error: missing main executable: ${MAIN_EXE}" >&2
  exit 1
fi
sign_mach_o "${MAIN_EXE}"

codesign --force --sign "${IDENTITY}" --options runtime --timestamp \
  --entitlements "${ENTITLEMENTS}" "${APP}"
echo "[sign-macos] app bundle: ${APP}"

codesign --verify --deep --strict --verbose=2 "${APP}"
echo "[sign-macos] codesign verify: OK"

if [[ -n "${DMG_PATH}" && -f "${DMG_PATH}" ]]; then
  codesign --force --sign "${IDENTITY}" --timestamp "${DMG_PATH}"
  codesign --verify --verbose=2 "${DMG_PATH}"
  echo "[sign-macos] dmg: ${DMG_PATH}"
fi

if [[ "${NOTARIZE}" != "1" ]]; then
  echo "[sign-macos] notarization skipped (set ARQMA_MACOS_NOTARIZE=1 to enable)"
  spctl -a -vv "${APP}" 2>&1 || true
  write_sign_status signed
  exit 0
fi

TEAM_ID="${DEVELOPMENT_TEAM:-75L2UT4BNN}"
NOTARY_ZIP="$(mktemp -t arqma-notarize.XXXXXX).zip"
ditto -c -k --keepParent "${APP}" "${NOTARY_ZIP}"
echo "[sign-macos] notary submit: ${NOTARY_ZIP}"

if [[ -n "${ARQMA_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  xcrun notarytool submit "${NOTARY_ZIP}" \
    --keychain-profile "${ARQMA_NOTARY_KEYCHAIN_PROFILE}" \
    --wait
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  xcrun notarytool submit "${NOTARY_ZIP}" \
    --apple-id "${APPLE_ID}" \
    --password "${APPLE_APP_SPECIFIC_PASSWORD}" \
    --team-id "${TEAM_ID}" \
    --wait
else
  rm -f "${NOTARY_ZIP}"
  echo "error: notarization requested but no credentials (ARQMA_NOTARY_KEYCHAIN_PROFILE or APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD)" >&2
  exit 1
fi

xcrun stapler staple "${APP}"
echo "[sign-macos] stapled: ${APP}"
rm -f "${NOTARY_ZIP}"

if [[ -n "${DMG_PATH}" && -f "${DMG_PATH}" ]]; then
  codesign --force --sign "${IDENTITY}" --timestamp "${DMG_PATH}"
  echo "[sign-macos] re-signed dmg after staple"
fi

spctl -a -vv "${APP}" 2>&1 || true
write_sign_status signed
echo "[sign-macos] done"
