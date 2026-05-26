#!/usr/bin/env bash
# Install repo-pinned Flutter on GitHub Actions without marketplace actions.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VER="$(grep -v '^[[:space:]]*#' "${ROOT}/build/ci/flutter-version" | grep -v '^[[:space:]]*$' | head -1 | tr -d '[:space:]')"
if [[ -z "${VER}" ]]; then
  echo "::error::empty Flutter version in build/ci/flutter-version"
  exit 1
fi
DEST="${RUNNER_TEMP:-/tmp}/flutter"
if [[ -d "${DEST}/.git" ]]; then
  git -C "${DEST}" fetch --depth 1 origin "refs/tags/${VER}" || git -C "${DEST}" fetch --depth 1 origin "${VER}"
  git -C "${DEST}" checkout -f "${VER}"
else
  git clone https://github.com/flutter/flutter.git --depth 1 --branch "${VER}" "${DEST}"
fi
echo "${DEST}/bin" >> "${GITHUB_PATH}"
"${DEST}/bin/flutter" config --no-analytics
"${DEST}/bin/flutter" --version
"${DEST}/bin/flutter" precache
