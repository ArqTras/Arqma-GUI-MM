# Rust workspace (Flutter FFI support)

This workspace builds **`arqma-wallet-flutter-ffi`** — the C ABI used by all Flutter shells (desktop, iOS, Android). **CI release builds** download prebuilt FFI from [ArqTras/FFI](https://github.com/ArqTras/FFI/releases/latest); local builds are optional for development.

Legacy **Tauri** (`rust/tauri-app/`) and in-process Vue UI live on branch **`outdated`**.

## Crates

| Crate | Role |
|-------|------|
| `arqma-wallet-flutter-ffi` | `cdylib` / staticlib for Flutter (`libarqma_wallet_flutter_ffi.*`) |
| `arqma-wallet-rpc` | Wallet2 JSON-RPC client (linked into FFI) |
| `arqma-wallet2-api` | C++ `wallet2_api` wrapper |
| `core`, `daemon` | Shared helpers |

## Local FFI build

See [`docs/NATIVE_WALLET2.md`](docs/NATIVE_WALLET2.md).

```bash
# Desktop (example)
bash rust/tool/build_wallet_flutter_ffi.sh

# iOS device + simulator
bash rust/tool/build_mobile_wallet_ffi_ios.sh
```

Outputs under `rust/target/` (gitignored).

## Solo pool sidecar (desktop)

Desktop bundles **`arqma_flutter_solo_pool`** from [ArqTras/FFI](https://github.com/ArqTras/FFI) into [`build/flutter-desktop-bin/`](../build/flutter-desktop-bin/):

```bash
bash build/ci/fetch-arqma-wallet-solo-pool-release-linux.sh
# or build/ci/build-flutter-solo-pool-for-desktop.sh linux|macos|mingw
```

Source build of the sidecar (formerly in `rust/tauri-app/`) is on branch **`outdated`**.

## Check

```bash
cd rust && cargo check -p arqma-wallet-flutter-ffi
```
