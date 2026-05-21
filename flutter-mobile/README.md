# Arqma Wallet — Mobile (Flutter)

Flutter shell for **iOS** and **Android**, adapted from `flutter/arqma_wallet_gui` (desktop stays unchanged).

## Layout

```
flutter-mobile/
  README.md
  arqma_wallet_mobile/     # Flutter app (lib/, ios/, android/, assets/)
```

## Remote nodes only

- No local `arqmad`, no solo pool sidecar.
- Mainnet uses public RPC nodes on port **19994**:
  - Default: `node1.arqma.com`
  - Picker: `node1` … `node4.arqma.com`
- Config and `remotes.json` live under the app documents directory (`MobileArqmaPaths`).

Wallet operations use in-process **`arqma-wallet-flutter-ffi`** (same C ABI as desktop), talking to the selected remote daemon for chain sync.

## Prerequisites

- Flutter SDK ≥ 3.41.9 (see desktop `build/ci/flutter-version`)
- Xcode (iOS device builds)
- Rust toolchain + Arqma `wallet_merged` for iOS (see `rust/docs/NATIVE_WALLET2.md`)

## Build wallet FFI for iOS

From the repository root:

```bash
chmod +x rust/tool/build_mobile_wallet_ffi_ios.sh
bash rust/tool/build_mobile_wallet_ffi_ios.sh
```

This produces:

- `rust/target/aarch64-apple-ios/release/libarqma_wallet_flutter_ffi.dylib` (device)
- `rust/target/aarch64-apple-ios-sim/release/libarqma_wallet_flutter_ffi.dylib` (simulator)

The Xcode target **Copy Arqma Wallet FFI** (`ios/copy_wallet_ffi.sh`) copies the dylib into `Runner.app/Frameworks/` when present.

Override discovery: `ARQMA_FLUTTER_WALLET_FFI=/absolute/path/to/libarqma_wallet_flutter_ffi.dylib`

UI-only without FFI: `ARQMA_FLUTTER_USE_STUB=1 flutter run`

## iOS app build

Use Homebrew CocoaPods (system `/usr/local/bin/pod` 1.11.x often fails with `LoadError: ffi`):

```bash
export PATH="/opt/homebrew/bin:$PATH"
```

Requires the **iOS platform** matching your Xcode (install via **Xcode → Settings → Components** if `flutter build ios` reports e.g. `iOS 26.5 is not installed`).

```bash
cd flutter-mobile/arqma_wallet_mobile
flutter pub get
flutter build ios --release --no-codesign
# or install on a connected device:
flutter run -d <device-id>
```

Open `ios/Runner.xcworkspace` in Xcode for signing, entitlements, and Archive.

`Info.plist` allows HTTP JSON-RPC to remote nodes (`NSAppTransportSecurity`).

## Android

Project structure is ready (`android/`). Remaining work:

- Build or package `libarqma_wallet_flutter_ffi.so` for `aarch64-linux-android` (and armeabi-v7a if needed)
- Load via `jniLibs` or Flutter FFI + `System.loadLibrary`
- Same remote-node defaults and `MobileNativeBridge` (already used on Android)

## Desktop parity (included)

Wallet select/create/restore, send/receive, history, address book, staking pools, swap, settings, i18n — same UI code as desktop where applicable.

## Removed vs desktop

| Feature | Desktop | Mobile |
|--------|---------|--------|
| Local `arqmad` | Yes | No |
| Solo pool | Yes | No |
| Daemon type local / local_remote | Yes | Remote only |
| Custom remote list (add/remove) | Yes | Fixed node1–4 |
| macOS / Windows / Linux bundles | Yes | N/A |
