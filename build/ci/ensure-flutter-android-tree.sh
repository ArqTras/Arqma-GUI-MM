#!/usr/bin/env bash
# Restore flutter-android/ when the checked-out ref predates the Android app (e.g. tag 5.1.0).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="${ROOT}/flutter-android/arqma_wallet_android"
PUBSPEC="${APP}/pubspec.yaml"

if [[ -f "${PUBSPEC}" ]]; then
  echo "[ensure-android] OK: ${PUBSPEC}"
  exit 0
fi

echo "[ensure-android] missing at current ref; importing from origin/main"
git -C "${ROOT}" fetch origin main --depth=1
git -C "${ROOT}" checkout origin/main -- \
  flutter-android \
  build/ci/package-flutter-android-release.sh \
  build/ci/fetch-arqma-wallet-ffi-release-linux.sh \
  build/ci/ensure-flutter-android-tree.sh

if [[ ! -f "${PUBSPEC}" ]]; then
  echo "::error::flutter-android/arqma_wallet_android still missing after checkout from main" >&2
  exit 1
fi
echo "[ensure-android] restored $(grep -m1 '^version:' "${PUBSPEC}")"
