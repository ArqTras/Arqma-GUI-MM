# Arqma Wallet Desktop (Flutter)

Flutter desktop shell for **Windows, Linux, and macOS**.

## Build

```bash
flutter pub get
flutter run -d macos   # or linux / windows
```

## Bundled binaries

Release bundles need **`arqmad`** and (optional) **`arqma_flutter_solo_pool`** in [`../../build/flutter-desktop-bin/`](../../build/flutter-desktop-bin/):

1. Put upstream **`arqmad`** in repo [`bin/`](../../bin/), then: `node ../../build/copy-to-flutter-desktop-bins.js`
2. Solo pool: `bash ../../build/ci/fetch-arqma-wallet-solo-pool-release-linux.sh` or `build-flutter-solo-pool-for-desktop.sh`
3. Wallet FFI: fetch [ArqTras/FFI](https://github.com/ArqTras/FFI) or build — [`../../rust/docs/NATIVE_WALLET2.md`](../../rust/docs/NATIVE_WALLET2.md)

After `flutter build`, copy bins into the bundle:

```bash
tool/copy_arqma_desktop_bins.sh build/macos/Build/Products/Release/Arqma-Wallet.app
```

## Release packages

```bash
tool/package_flutter_release.sh
```

See [`tool/RELEASE_NAMING.md`](tool/RELEASE_NAMING.md).

Legacy Vue/Tauri/Electron UI: branch **`outdated`**.
