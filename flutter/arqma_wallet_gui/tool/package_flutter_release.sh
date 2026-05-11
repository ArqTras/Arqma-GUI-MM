#!/usr/bin/env bash
# Build Flutter desktop release and write distributable archives under ./dist/.
# Requires: flutter SDK, platform desktop toolchain (Xcode on macOS, etc.).
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
  (cd "$(dirname "${app}")" && ditto -c -k --sequesterRsrc --keepParent "$(basename "${app}")" "${zip_out}")
  hdiutil create -quiet -volname "Arqma Wallet (Flutter)" -srcfolder "${app}" -format UDZO -imagekey zlib-level=9 -ov "${dmg_out}"
  echo "Packaged: ${zip_out}"
  echo "Packaged: ${dmg_out}"
}

package_linux() {
  if [[ "$(uname -s)" != Linux ]]; then
    echo "error: Linux packaging requires Linux host" >&2
    exit 1
  fi
  flutter build linux --release
  local arch
  arch="$(linux_arch_dir)"
  local bundle="build/linux/${arch}/release/bundle"
  if [[ ! -d "${bundle}" ]]; then
    echo "error: missing ${bundle} after build" >&2
    exit 1
  fi
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
