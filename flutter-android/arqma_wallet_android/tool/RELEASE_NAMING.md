# Flutter release file naming (desktop + mobile)

## Mobile (iOS — `flutter-mobile/arqma_wallet_mobile`)

| Artifact | Filename pattern |
|----------|------------------|
| TestFlight / App Store IPA | `Arqma-Wallet-Mobile-{slug}-ios.ipa` |
| Checksums | `SHA256SUMS.txt` |
| Build manifest | `Arqma-Wallet-Mobile-{slug}-ios-manifest.txt` |
| Upload guide | `TESTFLIGHT.md` |

`{slug}` = semver before `+` in `pubspec.yaml` (e.g. `5.1.0` from `5.1.0+1`).

**Build:** `./tool/package_mobile_release.sh` (macOS + Xcode + Apple Developer signing).

**Bundle ID:** `com.arqma.arqmaWalletMobile` — display name **Arqma Wallet Mobile**.

## Android (`flutter-android/arqma_wallet_android`)

| Artifact | Filename pattern |
|----------|------------------|
| Sideload APK | `Arqma-Wallet-Android-{slug}.apk` (under `dist/`) |
| Play Store AAB | `Arqma-Wallet-Android-{slug}.aab` |
| Checksums | `SHA256SUMS-android-{slug}.txt` |
| Manifest | `Arqma-Wallet-Android-{slug}-manifest.txt` |

`{slug}` = semver before `+` in `pubspec.yaml` (e.g. `5.1.0`).

**Build (local):** `./tool/package_android_release.sh` — uses prebuilt FFI from [ArqTras/FFI](https://github.com/ArqTras/FFI/releases/tag/1.0.1) (`ARQMA_FFI_RELEASE_VERSION`, default `1.0.1`).

**CI:** `.github/workflows/android-release.yml` — `build/ci/package-flutter-android-release.sh`, attaches to GitHub Release `5.1.0` / `v5.1.0`.

**Application ID:** `com.arqma.arqma_wallet_android` — display name **Arqma Wallet**.

---

# Flutter desktop release file naming

## Version embedded in filenames

- Source: the **`version`** field in `pubspec.yaml` (e.g. `5.1.0+1`).
- **Filename slug:** semver **before** the first `+` (build metadata is not in filenames), e.g. `5.1.0` — same as the Git release tag. Same rule as `package_flutter_release.ps1` / `.sh` and CI.

## Distribution artifacts (`Arqma-Wallet-Flutter-` prefix)

| Platform | Filename pattern |
|----------|------------------|
| Windows (portable zip) | `Arqma-Wallet-Flutter-{slug}-windows-x64.zip` |
| Windows (Inno Setup) | `Arqma-Wallet-Flutter-{slug}-windows-x64-Setup.exe` |
| macOS (zip) | `Arqma-Wallet-Flutter-{slug}-macos.zip` |
| macOS (DMG) | `Arqma-Wallet-Flutter-{slug}-macos.dmg` |
| Linux (tar.gz) | `Arqma-Wallet-Flutter-{slug}-linux-x64.tar.gz` |
| Linux (AppImage) | `Arqma-Wallet-Flutter-{slug}-x86_64.AppImage` |

`{slug}` is the same string as above (e.g. `5.1.0`).

## Installed application name (unchanged)

- **Windows:** executable `Arqma-Wallet.exe` — `BINARY_NAME` in `windows/CMakeLists.txt`.
- **Linux:** binary `Arqma-Wallet` inside the bundle.
- **macOS:** `Arqma-Wallet.app`.

The **`Arqma-Wallet-Flutter-`** prefix applies to **installers and archives**, not to the process name or Start Menu shortcut target binary name.

## Where this is implemented

- CI: `.github/workflows/desktop-release.yml` (**Pubspec semver for release filenames** step, artifact uploads).
- Inno Setup: `build/ci/flutter-windows-installer.iss` — `OutputBaseFilename=Arqma-Wallet-Flutter-{#VersionSafe}-windows-x64-Setup`, with `/DMyAppVersion` (semver for Windows metadata) and `/DVersionSafe` (filename slug).
- Local Windows: `tool/package_flutter_release.ps1` (zip under `dist/`, optional `-BuildInstaller`).
- Local macOS/Linux: `tool/package_flutter_release.sh` — uses `Arqma-Wallet-Flutter-${VERSION_SAFE}-…`.
