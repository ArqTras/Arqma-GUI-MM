#!/usr/bin/env bash
# Build arqma-wallet-flutter-ffi for iOS device + simulator (requires Xcode + wallet_merged for iOS).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${ROOT}/rust"

if ! rustup target list --installed | grep -q 'aarch64-apple-ios'; then
  rustup target add aarch64-apple-ios aarch64-apple-ios-sim
fi

# Upstream wallet_merged must exist for the iOS triple (see rust/docs/NATIVE_WALLET2.md).
export ARQMA_WALLET2_UPSTREAM_DIR="${ARQMA_WALLET2_UPSTREAM_DIR:-${ROOT}/../arqma-rpc-upstream}"

echo "Building arqma-wallet-flutter-ffi for aarch64-apple-ios (device)..."
cargo build -p arqma-wallet-flutter-ffi --release --target aarch64-apple-ios

echo "Building arqma-wallet-flutter-ffi for aarch64-apple-ios-sim..."
cargo build -p arqma-wallet-flutter-ffi --release --target aarch64-apple-ios-sim

echo "Artifacts:"
ls -la "${ROOT}/rust/target/aarch64-apple-ios/release/libarqma_wallet_flutter_ffi.dylib" 2>/dev/null || true
ls -la "${ROOT}/rust/target/aarch64-apple-ios-sim/release/libarqma_wallet_flutter_ffi.dylib" 2>/dev/null || true
