#!/usr/bin/env bash
# After `tauri build` on Linux: produce a .tar.gz with the main binary, any .so next to it, and resources/.
# Tauri has no built-in "tar.gz" bundle target; AppImage is built via bundle.targets.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
# Cargo workspace root is `rust/` (see rust/Cargo.toml), so artifacts are under rust/target/release — not <repo>/target/release.
RUST_ROOT="$(cd "${APP_DIR}/.." && pwd)"
TARGET_DIR="${RUST_ROOT}/target/release"
VERSION="$(node -p "require('${APP_DIR}/package.json').version")"
ARCH="$(uname -m)"
OUT_SUBDIR="bundle/tgz"
OUT_DIR="${TARGET_DIR}/${OUT_SUBDIR}"
STAGE_ROOT="${OUT_DIR}/_stage"
STAGE_NAME="Arqma-Wallet_${VERSION}_linux_${ARCH}"
STAGE="${STAGE_ROOT}/${STAGE_NAME}"

BIN=""
for c in \
  "${TARGET_DIR}/Arqma Wallet" \
  "${TARGET_DIR}/arqma-wallet" \
  "${TARGET_DIR}/arqma-tauri"
do
  if [[ -f "${c}" ]]; then
    BIN="${c}"
    break
  fi
done
if [[ -z "${BIN}" ]]; then
  echo "pack-linux-tarball: no main binary in ${TARGET_DIR} (expected 'Arqma Wallet', arqma-wallet, or arqma-tauri)." >&2
  echo "pack-linux-tarball: listing ${TARGET_DIR} (first 40 entries):" >&2
  ls -la "${TARGET_DIR}" 2>&1 | head -n 40 >&2 || true
  exit 1
fi

mkdir -p "${OUT_DIR}"
rm -rf "${STAGE_ROOT}"
mkdir -p "${STAGE}"

cp -a "${BIN}" "${STAGE}/"
if [[ -d "${TARGET_DIR}/resources" ]]; then
  cp -a "${TARGET_DIR}/resources" "${STAGE}/"
fi

shopt -s nullglob
for so in "${TARGET_DIR}"/*.so; do
  cp -a "${so}" "${STAGE}/"
done
shopt -u nullglob

ARCHIVE="${OUT_DIR}/${STAGE_NAME}.tar.gz"
tar -czf "${ARCHIVE}" -C "${STAGE_ROOT}" "${STAGE_NAME}"
rm -rf "${STAGE_ROOT}"

echo "pack-linux-tarball: ${ARCHIVE}"
