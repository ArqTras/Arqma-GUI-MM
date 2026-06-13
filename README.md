# Arqma Wallet — Flutter

Monorepo for **Arqma Wallet** on **desktop** (Windows, Linux, macOS), **iOS**, and **Android**. All active UI and release CI live in Flutter; legacy **Electron (Quasar)** and **Tauri (Vue)** stacks are preserved on branch [`outdated`](https://github.com/ArqTras/Arqma-GUI-MM/tree/outdated).

**Version:** 5.1.2 · Wallet FFI prebuilts: [ArqTras/FFI](https://github.com/ArqTras/FFI/releases/latest)

## Layout

| Path | Platform |
|------|----------|
| [`flutter/arqma_wallet_gui/`](flutter/arqma_wallet_gui/) | Desktop — Windows, Linux, macOS |
| [`flutter-mobile/arqma_wallet_mobile/`](flutter-mobile/arqma_wallet_mobile/) | iOS (remote node; TestFlight built locally on macOS) |
| [`flutter-android/arqma_wallet_android/`](flutter-android/arqma_wallet_android/) | Android |
| [`build/ci/`](build/ci/) | Release scripts, GitHub Actions helpers |
| [`build/flutter-desktop-bin/`](build/flutter-desktop-bin/) | `arqmad` + `arqma_flutter_solo_pool` staged for desktop bundles |
| [`rust/`](rust/) | Optional local build of `arqma-wallet-flutter-ffi` (CI uses FFI releases) |

## Prerequisites

- **Flutter** ≥ 3.41.9 ([`build/ci/flutter-version`](build/ci/flutter-version))
- **Desktop:** local `arqmad` in [`bin/`](bin/) then `node build/copy-to-flutter-desktop-bins.js`, or CI fetch from [arqma/arqma](https://github.com/arqma/arqma/releases)
- **Wallet FFI:** prebuilt from [ArqTras/FFI](https://github.com/ArqTras/FFI) (`build/ci/fetch-arqma-wallet-ffi-release*.sh`) or build locally — [`rust/docs/NATIVE_WALLET2.md`](rust/docs/NATIVE_WALLET2.md)
- **iOS:** Xcode, Apple Developer org account — [`flutter-mobile/README.md`](flutter-mobile/README.md)

## Quick start

### Desktop

```bash
cd flutter/arqma_wallet_gui
flutter pub get
flutter run -d macos   # or linux / windows
```

Populate [`build/flutter-desktop-bin/`](build/flutter-desktop-bin/) before release builds — see [`build/flutter-desktop-bin/README.txt`](build/flutter-desktop-bin/README.txt).

### iOS

```bash
cd flutter-mobile/arqma_wallet_mobile
bash tool/prepare_ios_wallet_ffi.sh
flutter run -d <device-id>
```

### Android

```bash
cd flutter-android/arqma_wallet_android
flutter pub get
flutter run
```

## Releases & CI

| Workflow | Purpose |
|----------|---------|
| [`.github/workflows/desktop-release.yml`](.github/workflows/desktop-release.yml) | Desktop Flutter zip/tar.gz/DMG/AppImage/Setup → GitHub Release on tags |
| [`.github/workflows/android-release.yml`](.github/workflows/android-release.yml) | Android APK/AAB |
| [`.github/workflows/flutter-test.yml`](.github/workflows/flutter-test.yml) | Flutter analyze/tests |
| [`.github/workflows/flutter-wallet-mirror.yml`](.github/workflows/flutter-wallet-mirror.yml) | Mirror assets to [arqma/Flutter-Wallet](https://github.com/arqma/Flutter-Wallet) |

Release notes: [`build/ci/release-notes-gui-*.md`](build/ci/). iOS IPA: build on macOS with [`flutter-mobile/.../tool/package_mobile_release.sh`](flutter-mobile/arqma_wallet_mobile/tool/package_mobile_release.sh) (not in CI).

## Legacy stacks (branch `outdated`)

Electron + Quasar (`src/`, `src-electron/`, root `package.json`) and Tauri + Vue (`rust/tauri-app/`) were removed from **`main`** to keep this repository focused on Flutter builds. Full history and sources remain on **`outdated`**.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Commit messages and PR text in **English**.

## Changelog

[`CHANGELOG.md`](CHANGELOG.md)
