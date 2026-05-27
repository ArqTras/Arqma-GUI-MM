# Arqma Wallet — Flutter shell

This directory is a **Flutter desktop/mobile shell** that mirrors the **Vue + Quasar + Tauri** wallet in `rust/tauri-app`: routing, **Arqma color palette**, `GatewayStore` (Vuex parity), and `AppReceiver` (same `backend-receive` event names as `src/receiver/receiver.js`).

## Run

```bash
cd flutter/arqma_wallet_gui
flutter pub get
flutter run -d macos   # or linux / windows / chrome
```

## App name and icons (matches Tauri)

- **Display name:** `Arqma-Wallet` (same as `rust/tauri-app/src-tauri/tauri.conf.json` `productName`).
- **macOS:** `macos/Runner/Configs/AppInfo.xcconfig`, `AppIcon.appiconset` (generated from `rust/tauri-app/public/icon_512x512.png`).
- **Windows:** `BINARY_NAME` + `Runner.rc` metadata; `windows/runner/resources/app_icon.ico` ← `rust/tauri-app/public/icon.ico`.
- **Linux:** `BINARY_NAME` + `APPLICATION_ID` in `linux/CMakeLists.txt`; GTK title in `linux/runner/my_application.cc`; window icon loads `assets/branding/app_icon.png` (copy of Tauri `icon_512x512.png`) from the bundled `flutter_assets` tree.

## Bundled `arqmad` / `arqma-wallet-rpc` (same as Tauri)

Tauri packs `rust/tauri-app/src-tauri/bin/` via `tauri.conf.json` → `bundle.resources`. Flutter desktop does the same sources:

| Platform | Mechanism | On-disk layout (resolved by `lib/core/desktop/arqma_executable_resolve.dart`) |
|----------|-----------|-----------------------------------------------------------------------------------|
| **macOS** | Xcode **Run Script** phase *Copy Arqma Tauri bins* (after Flutter embed) | `Arqma-Wallet.app/Contents/Resources/bin/` |

**macOS App Sandbox:** disabled (`Runner/*entitlements`) so the GUI can spawn bundled **`arqmad`** from the app bundle (`arqma-wallet-rpc` is not shipped in `src-tauri/bin/`; use native FFI or `ARQMA_WALLET_RPC`). Enabling sandbox would require a separate signed helper/XPC design. Mac App Store builds would need a different packaging story.
| **Linux** | `linux/CMakeLists.txt` `install(PROGRAMS …)` | `<bundle>/bin/` next to the app executable |
| **Linux** | same file — optional `install(FILES …)` | `<bundle>/lib/libarqma_wallet_flutter_ffi.so` when built under `rust/target/…` (native wallet2 FFI) |
| **Windows** | `windows/CMakeLists.txt` `install(FILES …)` | `<install prefix>/bin/` next to `Arqma-Wallet.exe` |
| **Windows** | same file — optional `install(SCRIPT …)` | `arqma_wallet_flutter_ffi.dll` + MinGW deps flat under `<runner Release>/` (legacy `lib/` mirror supported) |

**Before building Flutter:** place **`arqmad`** in `rust/tauri-app/src-tauri/bin/` — see `rust/tauri-app/src-tauri/bin/README.txt`. From repo root: `node build/copy-to-tauri-bins.js` when `./bin` already has upstream **arqmad**.

**Solo pool (desktop only — not Android/iOS):** install **`arqma_flutter_solo_pool`** into the same `src-tauri/bin/` folder (CMake / Xcode install it into each bundle’s `bin/`). **desktop-release** CI and release packagers fetch it from [ArqTras/FFI](https://github.com/ArqTras/FFI/releases) (`arqma-wallet-solo-pool-*` zips); local dev:

| Platform | Fetch prebuilt (recommended) | Build from source |
|----------|------------------------------|-------------------|
| **Linux / macOS** | `ARQMA_SOLO_POOL_PLATFORMS=linux-x86_64 bash build/ci/fetch-arqma-wallet-solo-pool-release-linux.sh` (or `macos-arm64`) | `bash rust/tool/build_flutter_solo_pool.sh` |
| **Windows** | `.\build\ci\fetch-arqma-wallet-solo-pool-release.ps1 -Platforms windows-x86_64-gnu` | `.\build\ci\fetch-or-build-solo-pool-desktop.ps1` or `.\rust\tool\build_flutter_solo_pool.ps1` |

Set `ARQMA_SOLO_POOL_RELEASE_VERSION` only to pin a tag; otherwise the **Latest** [ArqTras/FFI](https://github.com/ArqTras/FFI/releases/latest) release is used (same as wallet FFI). Force local build: `ARQMA_SOLO_POOL_BUILD_FROM_SOURCE=1`.

If the binary is missing at runtime, the GUI shows an error notification and XMRig cannot connect to the Stratum port.

**Manual copy** (after `flutter build`, if you did not use Xcode / CMake install): `bash tool/copy_arqma_tauri_bins.sh <bundle>` — e.g. macOS `.app`, Linux `build/linux/x64/release/bundle`, Windows `build/windows/x64/runner/Release` (Git Bash).

## Release install packages (Flutter desktop)

From `flutter/arqma_wallet_gui`, after `flutter pub get` and with **`rust/tauri-app/src-tauri/bin/`** populated (see above):

| Host | Command | Output under `dist/` |
|------|---------|------------------------|
| **macOS** | `./tool/package_flutter_release.sh` or `./tool/package_flutter_release.sh macos` | `Arqma-Wallet-Flutter-<version>-macos.zip`, `.dmg` (UDZO; disk volume **Arqma Wallet (Flutter)**) |
| **Linux** | `./tool/package_flutter_release.sh linux` | `Arqma-Wallet-Flutter-<version>-linux-x64.tar.gz` or `…-linux-arm64.tar.gz` (flattened `bundle/` tree) |
| **Windows** | `.\tool\package_flutter_release.ps1` | `Arqma-Wallet-Flutter-<version>-windows-x64.zip` (`build/windows/x64/runner/Release`) |

`dist/` is gitignored. These archives are drag-and-drop / extract installs (no root installer). Codesigning / notarization for macOS distribution is outside this script.

### Windows: self-contained portable folder

The PowerShell packager aims for a **single extract-and-run** tree (no MSYS2 / MinGW on `PATH`):

1. **Daemon:** put **`arqmad.exe`** in the repo **`bin/`** directory (or manually under `rust/tauri-app/src-tauri/bin/`). The script runs **`build/copy-to-tauri-bins.js`** (needs Node on `PATH`) so Tauri’s bin folder matches Tauri/CMake, then copies **`bin/arqmad.exe`** into `build/windows/x64/runner/Release/bin/` for Flutter.
2. **Native wallet FFI:** `arqma_wallet_flutter_ffi.dll` plus the **MinGW dependency DLLs** are synced into **`Release/`** next to `Arqma-Wallet.exe` (same globs as `windows/cmake/install_arqma_wallet_ffi.cmake.in`; optional `libwallet_merged.a` if built). Legacy `Release/lib/` is still supported by the loader.
3. **Solo pool:** `package_flutter_release.ps1` fetches `arqma_flutter_solo_pool.exe` from ArqTras/FFI when missing (`-BuildSoloPool` forces rebuild from source). Bundled under `Release/bin/`.
4. **Checks:** `tool/verify_windows_bundle.ps1` validates the Release folder (exe, FFI, assets, **`bin/arqmad.exe`**, **`bin/arqma_flutter_solo_pool.exe`**). CI uses `-FailIfNoArqmad -FailIfNoSoloPool`. Linux: `tool/verify_linux_bundle.sh` with `FAIL_IF_NO_SOLO_POOL=1`.

Installer equivalent: **`build/ci/flutter-windows-installer.iss`** packs the same `Release` folder into a Setup.exe (CI uses Inno Setup).

## Native bridge

`lib/main.dart` calls **`resolveAppNativeBridge()`** (see `lib/core/services/native_bridge_resolver.dart`):

| Condition | Bridge |
|-----------|--------|
| `ARQMA_FLUTTER_USE_STUB=1` or **web** | `StubNativeBridge` — UI / tests without disk or binaries |
| Desktop + `MethodChannel('com.arqma.wallet/native')` answers **`native_ping`** | `MethodChannelNativeBridge` — embedder owns `backend_send` + pushes `backend_receive` |
| Otherwise **macOS / Linux / Windows** | **`DesktopNativeBridge`** — full Dart-side parity with the Tauri wallet/daemon surface (config, processes, JSON-RPC, emits) |

Optional **release** embedder path: implement the same MethodChannel contract (or **flutter_rust_bridge** / C ABI around the Rust handlers) and forward:

- `backend_send` → same JSON envelope as Tauri `IpcMessage`.
- Native → Dart: `{ "event": "<name>", "data": … }` (same shape as `gateway_emit.rs` / `backend-receive`).

### Desktop (macOS / Linux / Windows): `DesktopNativeBridge`

When you run `flutter run -d macos` (or `linux` / `windows`) without a native embedder, **`DesktopNativeBridge`** drives config files, local `arqmad`, wallet RPC, daemon heartbeat, and the **solo Stratum pool** like the Tauri backend.

**Invoke parity (shell commands, not `backend_send`):** `app_version_str`, `daemon_version_probe`, `app_is_dev`, `app_log_*`, **`clip_write_text`**, **`app_save_log_level`** (writes `LOG_LEVEL=` under `ArqmaPaths.configDir/.env`), `dialog_open_dir` (via **file_picker**), **`confirm_close`** (stops pool / heartbeat / wallet RPC / daemon, then **`exit(0)`** like Tauri `app.exit(0)`).

**Wallet (native FFI only):** On desktop, **`ArqmaWalletRpcSession`** loads **`arqma-wallet-flutter-ffi`** (same **`Wallet2ApiClient`** / `wallet2_api` stack as Tauri native mode). Build with **`rust/tool/build_wallet_flutter_ffi.sh`** (Arqma upstream per **`rust/docs/NATIVE_WALLET2.md`**). Set **`ARQMA_FLUTTER_WALLET_FFI`** to override the library path, or rely on **`macos/Runner.xcodeproj`** phase **“Copy Arqma Tauri bins”** / **`tool/package_flutter_release.ps1`**, which place **`libarqma_wallet_flutter_ffi`** next to the app. There is **no** `arqma-wallet-rpc` subprocess on desktop. If the library is missing, wallet features stay offline until you rebuild or bundle the FFI. Optional **`MethodChannel('com.arqma.wallet/native')`** with `native_ping` remains a separate full-bridge path.

**Sharing the Tauri Rust backend with Flutter (roadmap):** see **`docs/FLUTTER_NATIVE_FROM_TAURI.md`** — phased plan (`BackendReceiveSink` in `gateway_emit.rs` started; then `cdylib` + MethodChannel, retiring duplicate Dart logic).

**Solo pool sidecar** (`arqma_flutter_solo_pool`) — bundled on **Windows, Linux, and macOS** next to `arqmad` under each app’s `bin/` (or `Contents/Resources/bin` on macOS). Build via **`rust/tool/build_flutter_solo_pool.sh`** / **`.ps1`** (see table above) or from `rust/tauri-app`:

```bash
npm run build:flutter-solo-pool:release   # installs to rust/target/…; copy into src-tauri/bin/ if needed
```

**Runtime overrides:**

- **`ARQMA_FLUTTER_SOLO_POOL`** — absolute path to the executable.
- **`ARQMA_FLUTTER_NO_SOLO_POOL=1`** — do not spawn the sidecar.

The sidecar reads the GUI config directory as its first CLI argument (`ArqmaPaths.configDir`) and runs the same Stratum solo pool logic as Tauri.

## What is not done yet

- **In-process wallet:** **`arqma-wallet-flutter-ffi`** on desktop (see above); Tauri may still use subprocess RPC in some modes — see `docs/WALLET_RUST_PORT.md`.
- **MethodChannel Rust engine:** optional; see `docs/FLUTTER_NATIVE_FROM_TAURI.md` — today the **authoritative desktop behaviour** for this repo is **`DesktopNativeBridge`** + bundled binaries, without calling into the Tauri crate at runtime.
