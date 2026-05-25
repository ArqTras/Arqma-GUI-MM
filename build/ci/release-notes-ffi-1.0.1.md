## Arqma Wallet FFI 1.0.1

Prebuilt **arqma-wallet-flutter-ffi** libraries for desktop and mobile builds.

### Changes from 1.0.0

- **Windows scan stall:** `refresh` RPC accepts optional `start_height`; uses `setRefreshFromBlockHeight` + `refresh` for upstream compatibility.
- **iOS:** Link **liblmdb** alongside `wallet_merged` (fixes undefined `mdb_*` symbols at link time).
- Bare `refresh` returning `false` while `startRefresh` is active is treated as non-fatal.

### Platforms

| Platform | Asset |
|----------|--------|
| Linux x86_64 | `arqma-wallet-ffi-linux-x86_64-1.0.1.zip` |
| macOS arm64 | `arqma-wallet-ffi-macos-arm64-1.0.1.zip` |
| Windows x86_64 GNU | `arqma-wallet-ffi-windows-x86_64-gnu-1.0.1.zip` |
| Android arm64 | `arqma-wallet-ffi-android-arm64-1.0.1.zip` |
| Android x86_64 | `arqma-wallet-ffi-android-x86_64-1.0.1.zip` |
| iOS | `arqma-wallet-ffi-ios-1.0.1.zip` |

### Consumers

- [Arqma-GUI-MM](https://github.com/ArqTras/Arqma-GUI-MM) desktop CI (`ARQMA_FFI_RELEASE_VERSION=1.0.1`) and release **5.1.0**.
- Set `ARQMA_FFI_RELEASE_VERSION=1.0.1` when running `build/ci/fetch-arqma-wallet-ffi-release.ps1` locally.

**Full changelog:** https://github.com/ArqTras/FFI/compare/1.0.0...1.0.1
