#!/usr/bin/env bash
# Regenerate App Store screenshot PNGs (see store_assets/app_store/README.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV="${ROOT}/tool/.venv-screenshots"
if [[ ! -x "${VENV}/bin/python3" ]]; then
  python3 -m venv "${VENV}"
  "${VENV}/bin/pip" install -q Pillow
fi
exec "${VENV}/bin/python3" "${ROOT}/tool/generate_app_store_screenshots.py"
