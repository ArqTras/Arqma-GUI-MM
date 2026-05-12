#!/usr/bin/env bash
# Reconfigure + build libwallet_merged.a on macOS (Homebrew deps expected).
# Delegates to build-arqma-wallet-ffi-deps.sh (minimal CMake targets for FFI only).
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec env ARQMA_WALLET_FFI_PLATFORM=macos bash "$ROOT/build/ci/build-arqma-wallet-ffi-deps.sh"
