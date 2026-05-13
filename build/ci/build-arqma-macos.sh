#!/usr/bin/env bash
# Reconfigure + build libwallet_merged.a on macOS (Homebrew deps expected).
# Delegates to build-arqma-wallet-ffi-deps.sh — CMake targets for FFI static libs + wallet_merged only (no daemon / no arqmad).
# Default daemon binary: fetch from arqma/arqma GitHub Releases — build/ci/fetch-arqmad-github-release.sh (see desktop-release CI).
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec env ARQMA_WALLET_FFI_PLATFORM=macos bash "$ROOT/build/ci/build-arqma-wallet-ffi-deps.sh"
