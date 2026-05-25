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

## Wallet FFI (desktop CI)

Prebuilt **`arqma-wallet-flutter-ffi`** from [ArqTras/FFI](https://github.com/ArqTras/FFI/releases/tag/1.0.1) tag **`1.0.1`** (see `ARQMA_FFI_RELEASE_VERSION` in workflow):

| OS | Download |
|----|----------|
| macOS (arm64) | https://github.com/ArqTras/FFI/releases/download/1.0.1/arqma-wallet-ffi-macos-arm64-1.0.1.zip |
| Windows (x64 GNU) | https://github.com/ArqTras/FFI/releases/download/1.0.1/arqma-wallet-ffi-windows-x86_64-gnu-1.0.1.zip |
| Linux (x64) | https://github.com/ArqTras/FFI/releases/download/1.0.1/arqma-wallet-ffi-linux-x86_64-1.0.1.zip |

Fetched by `build/ci/fetch-arqma-wallet-ffi-release-linux.sh` (macOS/Linux) and `fetch-arqma-wallet-ffi-release.ps1` (Windows).

## Where this is implemented

- CI: `.github/workflows/desktop-release.yml` (**Pubspec semver for release filenames** step, artifact uploads).
- Inno Setup: `build/ci/flutter-windows-installer.iss` — `OutputBaseFilename=Arqma-Wallet-Flutter-{#VersionSafe}-windows-x64-Setup`, with `/DMyAppVersion` (semver for Windows metadata) and `/DVersionSafe` (filename slug).
- Local Windows: `tool/package_flutter_release.ps1` (zip under `dist/`, optional `-BuildInstaller`).
- Local macOS/Linux: `tool/package_flutter_release.sh` — uses `Arqma-Wallet-Flutter-${VERSION_SAFE}-…`.
