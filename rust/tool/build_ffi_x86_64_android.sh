#!/usr/bin/env bash
set -euo pipefail
export ARQMA_USE_SDK_ANDROID_NDK=1
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${HOME}/arqma-android-build/android-ndk-r28c}"
export PATH="${HOME}/.cargo/bin:${PATH}"
cd "${HOME}/arqma-android-build/GUI-Rust/rust"
export ARQMA_WALLET2_UPSTREAM_DIR="${PWD}/arqma-rpc-upstream"
export CARGO_TARGET_DIR="${PWD}/target"
export ARQMA_WALLET_FFI_STATIC_HYBRID=1
export ARQMA_WALLET_FFI_USE_DEPENDS=1
export ARQMA_WALLET2_LIB_DIR="${PWD}/arqma-rpc-upstream/build-android-depends-x86_64-linux-android/src/wallet"
export ARQMA_WALLET_FFI_DEPENDS_LIB_DIR="${PWD}/arqma-rpc-upstream/contrib/depends/x86_64-linux-android/lib"
P="${ANDROID_NDK_HOME}/toolchains/llvm/prebuilt/linux-x86_64/bin"
export CC_x86_64_linux_android="${P}/x86_64-linux-android21-clang"
export CXX_x86_64_linux_android="${P}/x86_64-linux-android21-clang++"
export AR_x86_64_linux_android="${P}/llvm-ar"
export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="${P}/x86_64-linux-android21-clang"
cargo build -p arqma-wallet-flutter-ffi --release --target x86_64-linux-android
ls -la "${CARGO_TARGET_DIR}/x86_64-linux-android/release/libarqma_wallet_flutter_ffi.so"
