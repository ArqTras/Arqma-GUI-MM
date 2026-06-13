#!/usr/bin/env bash
# Sign and optionally notarize a Flutter macOS .app (and optional .dmg).
#
# Usage:
#   tool/sign_macos_app.sh build/macos/Build/Products/Release/Arqma-Wallet.app
#   tool/sign_macos_app.sh Arqma-Wallet.app --dmg dist/Arqma-Wallet-Flutter-5.1.2-macos-signed.dmg
#   tool/sign_macos_app.sh Arqma-Wallet.app --dmg path.dmg --skip-sign
#
# Env:
#   ARQMA_MACOS_SIGN_IDENTITY / CODE_SIGN_IDENTITY
#   ARQMA_MACOS_SIGN_SKIP=1
#   ARQMA_MACOS_SIGN_REQUIRED=1
#   ARQMA_MACOS_NOTARIZE=auto|1|0   (default auto: on when credentials exist)
#   ARQMA_NOTARY_KEYCHAIN_PROFILE   notarytool keychain profile
#   APPLE_ID / APPLE_APP_SPECIFIC_PASSWORD / DEVELOPMENT_TEAM
#   Repo-root .notenv: SIGNING_APPLE_ID, SIGNING_APP_PASSWORD, SIGNING_TEAM_ID
#   ARQMA_MACOS_SIGN_STATUS_FILE    writes signed|unsigned
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${GUI_ROOT}/../.." && pwd)"
ENTITLEMENTS="${GUI_ROOT}/macos/Runner/Release.entitlements"
DMG_PATH=""
SKIP_SIGN=0
NOTARIZE="${ARQMA_MACOS_NOTARIZE:-auto}"

write_sign_status() {
  if [[ -n "${ARQMA_MACOS_SIGN_STATUS_FILE:-}" ]]; then
    printf '%s\n' "$1" > "${ARQMA_MACOS_SIGN_STATUS_FILE}"
  fi
}

load_notary_env() {
  if [[ -f "${REPO_ROOT}/.notenv" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/.notenv"
    set +a
  fi
  : "${APPLE_ID:=${SIGNING_APPLE_ID:-}}"
  : "${APPLE_APP_SPECIFIC_PASSWORD:=${SIGNING_APP_PASSWORD:-}}"
  : "${DEVELOPMENT_TEAM:=${SIGNING_TEAM_ID:-75L2UT4BNN}}"
}

notary_credentials_ok() {
  load_notary_env
  if [[ -n "${ARQMA_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    return 0
  fi
  [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]
}

should_notarize() {
  case "${NOTARIZE}" in
    1 | true | yes | YES)
      return 0
      ;;
    0 | false | no | NO)
      return 1
      ;;
    auto | AUTO | "")
      notary_credentials_ok
      ;;
    *)
      return 1
      ;;
  esac
}

notarize_submit_path() {
  local artifact="$1"
  load_notary_env
  echo "[sign-macos] notary submit: ${artifact}"
  if [[ -n "${ARQMA_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    xcrun notarytool submit "${artifact}" \
      --keychain-profile "${ARQMA_NOTARY_KEYCHAIN_PROFILE}" \
      --wait
  else
    xcrun notarytool submit "${artifact}" \
      --apple-id "${APPLE_ID}" \
      --password "${APPLE_APP_SPECIFIC_PASSWORD}" \
      --team-id "${DEVELOPMENT_TEAM}" \
      --wait
  fi
}

staple_path() {
  echo "[sign-macos] staple: $1"
  xcrun stapler staple "$1"
  xcrun stapler validate "$1" 2>&1 || true
}

notarize_app_bundle() {
  local zip
  zip="$(mktemp -t arqma-notarize-app.XXXXXX).zip"
  ditto -c -k --keepParent "${APP}" "${zip}"
  notarize_submit_path "${zip}"
  rm -f "${zip}"
  staple_path "${APP}"
}

notarize_dmg_file() {
  notarize_submit_path "${DMG_PATH}"
  staple_path "${DMG_PATH}"
}

usage() {
  echo "usage: $0 path/to/Arqma-Wallet.app [--dmg path] [--skip-sign] [--notarize|--no-notarize]" >&2
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
    --skip-sign)
      SKIP_SIGN=1
      shift
      ;;
    --notarize)
      NOTARIZE=1
      shift
      ;;
    --no-notarize)
      NOTARIZE=0
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
if [[ -n "${DMG_PATH}" ]]; then
  DMG_PATH="$(cd "$(dirname "${DMG_PATH}")" && pwd)/$(basename "${DMG_PATH}")"
fi

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

sign_mach_o() {
  local target="$1"
  codesign --force --sign "${IDENTITY}" --options runtime --timestamp "${target}"
  echo "[sign-macos] ${target}"
}

if [[ "${SKIP_SIGN}" -eq 0 ]]; then
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

  if should_notarize; then
    notarize_app_bundle
  else
    echo "[sign-macos] notarization skipped (set ARQMA_MACOS_NOTARIZE=1 or add .notenv / notary profile)"
  fi
else
  IDENTITY="$(resolve_sign_identity)"
  if [[ -z "${IDENTITY}" ]]; then
    echo "error: --skip-sign with --dmg requires Developer ID identity for DMG signing" >&2
    exit 1
  fi
fi

if [[ -n "${DMG_PATH}" && -f "${DMG_PATH}" ]]; then
  codesign --force --sign "${IDENTITY}" --timestamp "${DMG_PATH}"
  codesign --verify --verbose=2 "${DMG_PATH}"
  echo "[sign-macos] dmg signed: ${DMG_PATH}"
  if should_notarize; then
    notarize_dmg_file
  fi
fi

spctl -a -vv "${APP}" 2>&1 || true
if [[ -n "${DMG_PATH}" && -f "${DMG_PATH}" ]]; then
  spctl -a -vv --type open --context context:primary-signature "${DMG_PATH}" 2>&1 || true
fi

write_sign_status signed
echo "[sign-macos] done"
