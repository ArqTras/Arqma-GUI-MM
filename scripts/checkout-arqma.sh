#!/usr/bin/env bash
# Shallow clone of github.com/arqma/arqma into vendor/arqma (gitignored).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${ROOT}/vendor/arqma"
if [[ -d "${DEST}/.git" ]]; then
  echo "[checkout-arqma] vendor/arqma already exists — skipping."
  exit 0
fi
mkdir -p "$(dirname "${DEST}")"
git clone --depth 1 "https://github.com/arqma/arqma.git" "${DEST}"
echo "[checkout-arqma] cloned to ${DEST}"
echo "Build per upstream README; then: export ARQMA_BUILD_DIR=\"\${DEST}/build/release\""
