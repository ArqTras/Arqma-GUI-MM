#!/usr/bin/env bash
# Fetch GitHub Latest ArqTras/FFI wallet library + solo pool for desktop GUI dev/build.
set -euo pipefail
GUI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="$(cd "${GUI_ROOT}/../.." && pwd)"
case "$(uname -s)" in
  Darwin) HOST=macos ;;
  Linux) HOST=linux ;;
  MINGW* | MSYS* | CYGWIN*) HOST=mingw ;;
  *)
    echo "error: unsupported host; run from macOS, Linux, or Git Bash on Windows" >&2
    exit 1
    ;;
esac
bash "${REPO_ROOT}/build/ci/fetch-arqma-desktop-prebuilts.sh" "${HOST}"
