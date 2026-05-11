#!/usr/bin/env bash
# Build Arqma libwallet_merged + arqma-wallet-flutter-ffi (no arqma-wallet-rpc subprocess).
# Run on Linux or macOS from anywhere; requires CMake, toolchain deps per rust/docs/NATIVE_WALLET2.md.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
UP="${ARQMA_WALLET2_UPSTREAM_DIR:-$ROOT/arqma-rpc-upstream}"
export ARQMA_WALLET2_UPSTREAM_DIR="$UP"

if [[ ! -f "$UP/src/wallet/api/wallet2_api.h" ]]; then
  echo "Missing upstream; run from repo root: bash build/ci/clone-arqma.sh" >&2
  exit 1
fi

case "$(uname -s)" in
  Darwin)
    bash "$ROOT/../build/ci/build-arqma-macos.sh"
    ;;
  Linux)
    bash "$ROOT/../build/ci/build-arqma-linux.sh"
    ;;
  *)
    echo "Use Windows: rust\\tool\\build_native_wallet_flutter_ffi_windows.ps1" >&2
    exit 2
    ;;
esac

cargo build -p arqma-wallet-flutter-ffi --release
echo "OK: native wallet FFI library under target/release/"
