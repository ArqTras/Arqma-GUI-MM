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
tool/package_flutter_release.sh          # macOS / Linux
```

**Windows** (MSYS2 MinGW64 + Inno Setup for installer):

```powershell
cd flutter\arqma_wallet_gui
.\tool\package_flutter_release.ps1 -BuildInstaller
```

Uses `build/ci/package-flutter-windows-release.ps1`: bundles **`arqma_wallet_flutter_ffi.dll`** + MinGW deps into `runner/Release/`, verifies, then writes **`dist/*.zip`** and **`dist/*-Setup.exe`** (same layout as CI).

### macOS code signing and notarization (local distribution)

`tool/package_flutter_release.sh macos` signs with **Developer ID** and **notarizes automatically** when repo-root **`.notenv`** exists (same keys as legacy Electron: `SIGNING_APPLE_ID`, `SIGNING_APP_PASSWORD`, `SIGNING_TEAM_ID`) or when `APPLE_ID` + `APPLE_APP_SPECIFIC_PASSWORD` / `ARQMA_NOTARY_KEYCHAIN_PROFILE` are set.

Manual sign + notarize on an existing `.app`:

```bash
tool/sign_macos_app.sh build/macos/Build/Products/Release/Arqma-Wallet.app
tool/sign_macos_app.sh build/macos/Build/Products/Release/Arqma-Wallet.app \
  --dmg dist/Arqma-Wallet-Flutter-5.1.2-macos-signed.dmg --skip-sign
```

Disable notarization: `ARQMA_MACOS_NOTARIZE=0 ./tool/package_flutter_release.sh macos`

Signed release files use the **`…-macos-signed`** suffix; CI builds use **`…-macos-unsigned`**.

See [`tool/RELEASE_NAMING.md`](tool/RELEASE_NAMING.md).

Legacy Vue/Tauri/Electron UI: branch **`outdated`**.
