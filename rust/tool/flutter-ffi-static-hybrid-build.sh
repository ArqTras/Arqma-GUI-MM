#!/usr/bin/env bash
# Release-build `arqma-wallet-flutter-ffi` with the same static-hybrid native linking as Windows
# (`ARQMA_WALLET_FFI_STATIC_HYBRID=1`). Requires upstream `wallet_merged` + Homebrew/Linux deps on PATH.
set -euo pipefail
export ARQMA_WALLET_FFI_STATIC_HYBRID=1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUST_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${RUST_ROOT}"
cargo build -p arqma-wallet-flutter-ffi --release "$@"
