#!/bin/sh
# Copy ArqmaRescanWidget.appex into Runner.app/PlugIns (avoids Xcode copy-phase dependency cycles).
set -e
APPEX="${BUILT_PRODUCTS_DIR}/ArqmaRescanWidget.appex"
DEST="${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}/PlugIns"
if [ ! -d "${APPEX}" ]; then
  echo "warning: ${APPEX} not built; Live Activity extension will be missing" >&2
  exit 0
fi
mkdir -p "${DEST}"
rm -rf "${DEST}/ArqmaRescanWidget.appex"
ditto "${APPEX}" "${DEST}/ArqmaRescanWidget.appex"
