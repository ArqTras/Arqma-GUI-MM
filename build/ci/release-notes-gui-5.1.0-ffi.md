## Arqma Wallet 5.1.0 (rebuild)

Desktop and Android bundles rebuilt against **[ArqTras/FFI 1.0.1](https://github.com/ArqTras/FFI/releases/tag/1.0.1)** prebuilt wallet FFI.

### Native wallet (FFI 1.0.1)

- Windows: `refresh_from_height` for stalled blockchain scan; improved compatibility with background `startRefresh`.
- iOS / mobile: LMDB link fix in FFI (see FFI release notes).

### How to verify

- Desktop installers and archives in this release were produced by **Desktop release (Flutter)** CI with `ARQMA_FFI_RELEASE_VERSION=1.0.1`.
- Android APK/AAB: **Android release (Flutter)** with `ffi_version=1.0.1`.

**FFI artifacts:** https://github.com/ArqTras/FFI/releases/tag/1.0.1
