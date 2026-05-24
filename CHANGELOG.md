# Changelog

## 5.1.0 — 2026-05-11

- Bump app / workspace version to **5.1.0** (from 5.0.5).
- CI / Flutter desktop release: **`flutter-linux`** and **`flutter-windows`** share **`ARQMA_UPSTREAM_REPO` / `ARQMA_UPSTREAM_REF`** for **`wallet_merged`** (fork **`arqtras/arqma`**, **`pospow`**). **`arqmad`** on **Linux** is fetched from **`arqma/arqma` Releases** via **`fetch-arqmad-github-release.sh`** (same source as Windows **`flutter-windows-fetch-arqma-binaries.ps1`**); no local CMake **`daemon`** build on Linux CI.
- Flutter Windows FFI bundle: DLLs and optional **`libwallet_merged.a`** under **`Release/`** (flat next to exe); release naming guide: `flutter/arqma_wallet_gui/tool/RELEASE_NAMING.md`.
- CI: replaced **`flutter-github-release.yml`** + **`tauri-app.yml`** with unified **`desktop-release.yml`** — Flutter (instalatory / archiwa) + Tauri (bundlery) → jeden GitHub Release; tagi **`v*`** oraz semver **`X.Y.Z`** (np. **`5.1.0`**); po push tagu opcjonalnie **`repo-private-after-release`** przy secrecie **`ARQMA_REPO_VISIBILITY_PAT`**.

## 5.0.5 — 2026-05-11

- Bump app / workspace version to 5.0.5.
- CI: **`arqmad`** for Flutter macOS / Linux — from **`arqma/arqma` latest GitHub Release** (`fetch-arqmad-github-release.sh` + `download-binaries.js`), not a local CMake `daemon` target; **`wallet_merged`** still built from **`arqtras/arqma`**.
- CI: Flutter Windows — unchanged: `arqmad.exe` from `arqma/arqma` release (`flutter-windows-fetch-arqma-binaries.ps1` / `download-binaries.js`).
- CI: Windows Tauri bundle — `cargo-runner-gnu-flat-sync.mjs` also syncs `arqma_flutter_solo_pool.exe` into flat `target/release/` for NSIS.
- Flutter GitHub Release: release assets use the **`Arqma-Wallet-Flutter-`** prefix (zip / tar.gz / DMG / AppImage / Inno **`Arqma-Wallet-Flutter-windows-x64-Setup.exe`**) so Flutter installers are distinct from Tauri bundles; `workflow_dispatch` to rebuild a tag; Tauri workflow tag-only + dispatch (no PR matrix).

## 5.0.4 — 2026-05-11

- Bump app / workspace version to 5.0.4.
- GitHub Actions: Flutter desktop bundles (macOS zip, Linux tar.gz, Windows zip) attach to `v*` releases via *Flutter GitHub Release* workflow.

## 5.0.3 — 2026-05-07

### Highlights

- **CI / MinGW patch bundle** (`build/ci/patch-arqma-mingw-gui.js`): after cloning Arqma core, applies RandomX `ARCH_ID` normalization, `wallet_merged` + `daemonizer` on MinGW, and MinGW `ARQMA_SKIP_CXA_THROW_HOOK` for `stack_trace.cpp` (same fixes as a manual upstream checkout; idempotent).
- **Native wallet API (`wallet2_api`)** is the only supported build path: the Tauri app always links Arqma core’s merged wallet library (`libwallet_merged`) via `arqma-wallet2-api`, given an [Arqma core checkout](rust/docs/NATIVE_WALLET2.md) and a successful CMake build.
- **CI builds Arqma from source** on Linux, macOS, and Windows (MinGW + `x86_64-pc-windows-gnu` on Windows) so installers use native wallet2. The **`stub-wallet2`** / **`native-wallet2`** Cargo feature split has been removed.
- Documentation: see [`rust/docs/NATIVE_WALLET2.md`](rust/docs/NATIVE_WALLET2.md) for upstream clone, `BUILD_GUI_DEPS`, and linker notes per platform.

### Migration notes

- **`npm run tauri:build`** and related scripts require the native Arqma prerequisites described in `rust/docs/NATIVE_WALLET2.md`.
- **GitHub Actions** full Tauri workflow clones **`arqtras/arqma`** (branch **`pospow`**) and builds the **`wallet_merged`** target before bundling the app.
