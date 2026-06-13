#!/usr/bin/env bash
# Build Flutter desktop release and write distributable archives under ./dist/.
# Fetches GitHub Latest ArqTras/FFI before build (see tool/fetch_latest_wallet_ffi.sh).
#
# Usage:
#   cd flutter/arqma_wallet_gui && ./tool/package_flutter_release.sh
#   ./tool/package_flutter_release.sh macos
#   ./tool/package_flutter_release.sh linux
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${GUI_ROOT}"

if [[ ! -f pubspec.yaml ]]; then
  echo "error: run from flutter/arqma_wallet_gui (pubspec.yaml missing)" >&2
  exit 1
fi

VERSION_LINE="$(grep -m1 '^version:' pubspec.yaml | sed 's/^version:[[:space:]]*//;s/[[:space:]]*$//')"
VERSION_SAFE="${VERSION_LINE%%+*}"
DIST="${GUI_ROOT}/dist"
mkdir -p "${DIST}"

detect_platform() {
  case "$(uname -s)" in
    Darwin) echo macos ;;
    Linux) echo linux ;;
    MINGW* | MSYS* | CYGWIN*) echo windows ;;
    *) echo unknown ;;
  esac
}

PLATFORM="${1:-$(detect_platform)}"
if [[ "${PLATFORM}" == unknown ]]; then
  echo "error: unsupported host OS; pass macos|linux|windows explicitly" >&2
  exit 1
fi

REPO_ROOT="$(cd "${GUI_ROOT}/../.." && pwd)"

ensure_desktop_prebuilts() {
  local host=""
  case "$(uname -s)" in
    Darwin) host="macos" ;;
    Linux) host="linux" ;;
    MINGW* | MSYS* | CYGWIN*) host="mingw" ;;
    *)
      echo "error: unsupported host for desktop prebuilts" >&2
      return 1
      ;;
  esac
  bash "${REPO_ROOT}/build/ci/fetch-arqma-desktop-prebuilts.sh" "${host}"
}

linux_arch_dir() {
  case "$(uname -m)" in
    aarch64 | arm64) echo arm64 ;;
    *) echo x64 ;;
  esac
}

package_macos() {
  if [[ "$(uname -s)" != Darwin ]]; then
    echo "error: macOS packaging requires Darwin host" >&2
    exit 1
  fi
  ensure_desktop_prebuilts
  flutter build macos --release
  local app="build/macos/Build/Products/Release/Arqma-Wallet.app"
  if [[ ! -d "${app}" ]]; then
    echo "error: missing ${app} after build" >&2
    exit 1
  fi
  local base="Arqma-Wallet-Flutter-${VERSION_SAFE}-macos"
  local zip_out="${DIST}/${base}.zip"
  local dmg_out="${DIST}/${base}.dmg"
  rm -f "${zip_out}" "${dmg_out}"
  bash "${GUI_ROOT}/tool/copy_arqma_desktop_bins.sh" "${app}"
  bash "${REPO_ROOT}/build/ci/verify-macos-bundle.sh" "${app}"
  bash "${GUI_ROOT}/tool/sign_macos_app.sh" "${app}"
  (cd "$(dirname "${app}")" && ditto -c -k --sequesterRsrc --keepParent "$(basename "${app}")" "${zip_out}")
  # DMG must contain both the app and a symlink to /Applications for the standard drag-to-install layout.
  local staging
  staging="$(mktemp -d "${TMPDIR:-/tmp}/arqma-wallet-dmg-staging.XXXXXX")"
  ditto "${app}" "${staging}/$(basename "${app}")"
  ln -sf /Applications "${staging}/Applications"
  hdiutil create -quiet -volname "Arqma Wallet (Flutter)" -srcfolder "${staging}" -format UDZO -imagekey zlib-level=9 -ov "${dmg_out}"
  rm -rf "${staging}"
  bash "${GUI_ROOT}/tool/sign_macos_app.sh" "${app}" --dmg "${dmg_out}"
  echo "Packaged: ${zip_out}"
  echo "Packaged: ${dmg_out}"
}

package_linux() {
  if [[ "$(uname -s)" != Linux ]]; then
    echo "error: Linux packaging requires Linux host" >&2
    exit 1
  fi
  ensure_desktop_prebuilts
  flutter build linux --release
  local arch
  arch="$(linux_arch_dir)"
  local bundle="build/linux/${arch}/release/bundle"
  if [[ ! -d "${bundle}" ]]; then
    echo "error: missing ${bundle} after build" >&2
    exit 1
  fi
  chmod +x "${GUI_ROOT}/tool/bundle_linux_ffi_runtime_libs.sh"
  bash "${GUI_ROOT}/tool/bundle_linux_ffi_runtime_libs.sh" "${bundle}"
  FAIL_IF_NO_SOLO_POOL=1 bash "${GUI_ROOT}/tool/verify_linux_bundle.sh" "${bundle}"
  local base="Arqma-Wallet-Flutter-${VERSION_SAFE}-linux-${arch}"
  local tgz="${DIST}/${base}.tar.gz"
  rm -f "${tgz}"
  tar -C "${bundle}" -czf "${tgz}" .
  echo "Packaged: ${tgz}"
}

case "${PLATFORM}" in
  macos) package_macos ;;
  linux) package_linux ;;
  windows)
    echo "error: use PowerShell on Windows: .\\tool\\package_flutter_release.ps1" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [macos|linux]" >&2
    exit 2
    ;;
esac
