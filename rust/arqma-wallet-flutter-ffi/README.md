# `arqma-wallet-flutter-ffi`

C ABI (`cdylib`) around [`Wallet2ApiClient`](https://github.com/ArqTras/Arqma-GUI-MM/blob/main/rust/arqma-wallet-rpc/src/wallet2_client.rs) so the **Flutter** shell can call the same **linked `wallet2_api`** stack as **Tauri** (no `arqma-wallet-rpc` subprocess when the library is bundled).

## Build

Requires an Arqma core checkout and `libwallet_merged` (or equivalent) per [`rust/docs/NATIVE_WALLET2.md`](../docs/NATIVE_WALLET2.md).

From the repository `rust/` directory:

```bash
bash tool/build_wallet_flutter_ffi.sh
```

Artifacts (host triple):

- macOS: `target/release/libarqma_wallet_flutter_ffi.dylib`
- Linux: `target/release/libarqma_wallet_flutter_ffi.so`
- Windows: `target/release/arqma_wallet_flutter_ffi.dll`

## C symbols

- `arqma_wallet_ffi_configure(wallet_dir, daemon_address, network)` — `network`: `0` mainnet, `1` testnet, `2` stagenet; UTF-8 C strings.
- `arqma_wallet_ffi_call_json(method, params_json, out_json)` — `out_json` receives an allocated JSON document; free with `arqma_wallet_ffi_string_free`.
- `arqma_wallet_ffi_reset` — drop the client.
- `arqma_wallet_ffi_string_free`

## Flutter packaging

- **macOS:** Xcode “Copy Arqma Tauri bins” copies the dylib into `Contents/Frameworks/` when present under `rust/target/…`.
- **Linux / Windows:** `flutter/arqma_wallet_gui/linux|windows/CMakeLists.txt` installs the library into the Flutter bundle (`lib/` on Linux, next to the `.exe` on Windows).
- **Manual:** `flutter/arqma_wallet_gui/tool/copy_arqma_tauri_bins.sh` supports `.app`, Linux `bundle/`, and Windows `runner/Release`.

Dart discovery and env vars: `flutter/arqma_wallet_gui/lib/core/desktop/wallet_native_ffi.dart`.

## CI

GitHub Actions **`.github/workflows/wallet-flutter-ffi.yml`** runs a **matrix** (`macos-latest`, `ubuntu-latest`, `windows-latest`): `clone-arqma.sh`, then `build-arqma-{macos,linux,mingw}.sh`, then `cargo build -p arqma-wallet-flutter-ffi --release` (Windows uses `--target x86_64-pc-windows-gnu` and `CARGO_PROFILE_RELEASE_LTO=thin`, same idea as the Tauri Windows job).
