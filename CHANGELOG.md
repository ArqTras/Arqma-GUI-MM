# Changelog

## 5.0.5 — 2026-05-11

- Bump app / workspace version to 5.0.5.
- CI: build upstream `daemon` + `wallet_rpc_server` and copy `arqmad` / `arqma-wallet-rpc` into `rust/tauri-app/src-tauri/bin/` before Flutter desktop builds so release zips include bundled daemons (Windows / Linux / macOS).
- CI: MinGW — build `daemon` with `LDFLAGS=-Wl,--allow-multiple-definition`, then `wallet_rpc_server` without it (libunwind vs libgcc_eh vs full RPC link).
- CI: Windows Tauri bundle — `cargo-runner-gnu-flat-sync.mjs` also syncs `arqma_flutter_solo_pool.exe` into flat `target/release/` for NSIS.
- Flutter GitHub Release: attach **DMG** (macOS), **AppImage** (Linux), **Inno Setup** `Arqma-Wallet-windows-x64-Setup.exe` plus existing zip/tar.gz; `workflow_dispatch` to rebuild a tag; Tauri workflow tag-only + dispatch (no PR matrix).

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
