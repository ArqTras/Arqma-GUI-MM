# Flutter desktop release file naming

## Version embedded in filenames

- Source: the **`version`** field in `pubspec.yaml` (e.g. `5.1.0+1`).
- **Filename slug:** replace `+` with `-` (e.g. `5.1.0-1`). Same rule as `package_flutter_release.ps1` and CI.

## Distribution artifacts (`Arqma-Wallet-Flutter-` prefix)

| Platform | Filename pattern |
|----------|------------------|
| Windows (portable zip) | `Arqma-Wallet-Flutter-{slug}-windows-x64.zip` |
| Windows (Inno Setup) | `Arqma-Wallet-Flutter-{slug}-windows-x64-Setup.exe` |
| macOS (zip) | `Arqma-Wallet-Flutter-{slug}-macos.zip` |
| macOS (DMG) | `Arqma-Wallet-Flutter-{slug}-macos.dmg` |
| Linux (tar.gz) | `Arqma-Wallet-Flutter-{slug}-linux-x64.tar.gz` |
| Linux (AppImage) | `Arqma-Wallet-Flutter-{slug}-x86_64.AppImage` |

`{slug}` is the same string as above (e.g. `5.1.0-1`).

## Installed application name (unchanged)

- **Windows:** executable `Arqma-Wallet.exe` — `BINARY_NAME` in `windows/CMakeLists.txt`.
- **Linux:** binary `Arqma-Wallet` inside the bundle.
- **macOS:** `Arqma-Wallet.app`.

The **`Arqma-Wallet-Flutter-`** prefix applies to **installers and archives**, not to the process name or Start Menu shortcut target binary name.

## Where this is implemented

- CI: `.github/workflows/desktop-release.yml` (**Pubspec version slug** step, artifact uploads).
- Inno Setup: `build/ci/flutter-windows-installer.iss` — `OutputBaseFilename=Arqma-Wallet-Flutter-{#VersionSafe}-windows-x64-Setup`, with `/DMyAppVersion` (semver for Windows metadata) and `/DVersionSafe` (filename slug).
- Local Windows: `tool/package_flutter_release.ps1` (zip under `dist/`, optional `-BuildInstaller`).
- Local macOS/Linux: `tool/package_flutter_release.sh` — uses `Arqma-Wallet-Flutter-${VERSION_SAFE}-…`.
