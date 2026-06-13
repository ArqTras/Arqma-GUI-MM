# Flutter desktop release file naming

## Version embedded in filenames

- Source: the **`version`** field in `pubspec.yaml` (e.g. `5.1.1+1`).
- **Filename slug:** semver **before** the first `+` (build metadata is not in filenames), e.g. `5.1.1` — same as the Git release tag. Same rule as `package_flutter_release.ps1` / `.sh` and CI.

## Distribution artifacts (`Arqma-Wallet-Flutter-` prefix)

| Platform | Filename pattern |
|----------|------------------|
| Windows (portable zip) | `Arqma-Wallet-Flutter-{slug}-windows-x64.zip` |
| Windows (Inno Setup) | `Arqma-Wallet-Flutter-{slug}-windows-x64-Setup.exe` |
| macOS (zip, CI) | `Arqma-Wallet-Flutter-{slug}-macos-unsigned.zip` |
| macOS (DMG, CI) | `Arqma-Wallet-Flutter-{slug}-macos-unsigned.dmg` |
| macOS (zip, local signed) | `Arqma-Wallet-Flutter-{slug}-macos-signed.zip` |
| macOS (DMG, local signed) | `Arqma-Wallet-Flutter-{slug}-macos-signed.dmg` |
| Linux (tar.gz) | `Arqma-Wallet-Flutter-{slug}-linux-x64.tar.gz` |
| Linux (AppImage) | `Arqma-Wallet-Flutter-{slug}-x86_64.AppImage` |

`{slug}` is the same string as above (e.g. `5.1.1`).

## Installed application name (unchanged)

- **Windows:** executable `Arqma-Wallet.exe` — `BINARY_NAME` in `windows/CMakeLists.txt`.
- **Linux:** binary `Arqma-Wallet` inside the bundle.
- **macOS:** `Arqma-Wallet.app`.

The **`Arqma-Wallet-Flutter-`** prefix applies to **installers and archives**, not to the process name or Start Menu shortcut target binary name.

## Wallet FFI (desktop GUI)

Desktop **Windows / Linux / macOS** always use the **Latest** [ArqTras/FFI](https://github.com/ArqTras/FFI/releases/latest) prebuilt **`arqma-wallet-flutter-ffi`** (resolved by `build/ci/ensure-desktop-latest-ffi.sh` → `resolve-arqma-ffi-release-version.sh`).

| OS | Artifact pattern (version = Latest tag) |
|----|----------------------------------------|
| macOS (arm64) | `arqma-wallet-ffi-macos-arm64-<version>.zip` |
| Windows (x64 GNU) | `arqma-wallet-ffi-windows-x86_64-gnu-<version>.zip` |
| Linux (x64) | `arqma-wallet-ffi-linux-x86_64-<version>.zip` |

Fetched by `build/ci/fetch-arqma-desktop-prebuilts.sh` (local: `tool/fetch_latest_wallet_ffi.sh` / `.ps1`, or via `package_flutter_release.*`). Solo pool sidecars use the **same Latest** FFI release tag.

**Pinning** (`ARQMA_FFI_RELEASE_VERSION=1.0.x`) is ignored for desktop unless `ARQMA_FFI_DESKTOP_ALLOW_PIN=1` (CI/debug). Mobile/Android may pin independently.

## Where this is implemented

- CI: `.github/workflows/desktop-release.yml` (**Pubspec semver for release filenames** step, artifact uploads).
- Inno Setup: `build/ci/flutter-windows-installer.iss` — `OutputBaseFilename=Arqma-Wallet-Flutter-{#VersionSafe}-windows-x64-Setup`, with `/DMyAppVersion` (semver for Windows metadata) and `/DVersionSafe` (filename slug).
- Local Windows: `tool/package_flutter_release.ps1` (zip under `dist/`, optional `-BuildInstaller`).
- Local macOS: `tool/package_flutter_release.sh` — `Arqma-Wallet-Flutter-${VERSION_SAFE}-macos-signed.*` when Developer ID signing succeeds, `-macos-unsigned.*` otherwise.
- CI macOS: `.github/workflows/desktop-release.yml` — always `-macos-unsigned.*` (no codesign in CI).
