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

### macOS code signing (local distribution)

After `flutter build macos --release` and `tool/copy_arqma_desktop_bins.sh`, sign with a **Developer ID Application** certificate (auto-detected from keychain):

```bash
tool/sign_macos_app.sh build/macos/Build/Products/Release/Arqma-Wallet.app
```

`package_flutter_release.sh macos` runs this automatically when a Developer ID identity is present.

For installation on **other users' Macs**, also notarize and staple (once per machine):

```bash
xcrun notarytool store-credentials "AC_PASSWORD" \
  --apple-id "you@example.com" \
  --team-id 75L2UT4BNN \
  --password "@keychain:AC_PASSWORD"

ARQMA_MACOS_NOTARIZE=1 ARQMA_NOTARY_KEYCHAIN_PROFILE=AC_PASSWORD \
  tool/sign_macos_app.sh build/macos/Build/Products/Release/Arqma-Wallet.app \
  --dmg dist/Arqma-Wallet-Flutter-5.1.2-macos-signed.dmg
```

Env: `ARQMA_MACOS_SIGN_IDENTITY`, `ARQMA_MACOS_SIGN_SKIP=1`, `ARQMA_MACOS_SIGN_REQUIRED=1`.

See [`tool/RELEASE_NAMING.md`](tool/RELEASE_NAMING.md).

Legacy Vue/Tauri/Electron UI: branch **`outdated`**.
