#!/usr/bin/env bash
# Configure + build libwallet_merged.a on Linux (Debian/Ubuntu-style CI).
# Delegates to build-arqma-wallet-ffi-deps.sh (minimal CMake targets for FFI only).
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec env ARQMA_WALLET_FFI_PLATFORM=linux bash "$ROOT/build/ci/build-arqma-wallet-ffi-deps.sh"
