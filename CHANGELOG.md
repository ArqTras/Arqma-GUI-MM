# Changelog

## 5.1.2 — 2026-06-10

- Bump Flutter desktop to **5.1.2+6**, mobile to **5.1.2+51**, and Android tree to **5.1.2+14** (workspace **5.1.2**).
- **Repo layout:** **`main`** is Flutter-only (desktop, iOS, Android). Legacy **Electron** and **Tauri** stacks moved to branch **`outdated`**. Desktop binaries staged under **`build/flutter-desktop-bin/`** (replaces `rust/tauri-app/src-tauri/bin/`).
- **Solo pool (desktop):** Fix block submission — miner nonce written to block header on `submit_block` (sidecar `arqma_flutter_solo_pool` republished on [FFI 1.0.15](https://github.com/ArqTras/FFI/releases/tag/1.0.15)); desktop bundles rebuilt with fixed solo pool binary.
- **Solo pool (desktop, republish):** Block reward from template/`get_block`, `solo_pool_block_found` event + tx refresh, submit success/failure notifications; stop sidecar on `close_wallet` and app exit (SIGTERM/SIGKILL, fixes orphaned process on Linux).
- **Wallet sync (desktop + mobile + Android, republish FFI 1.0.15):** `TIP_BAND` 1 block near daemon tip; stall refresh near tip; footer progress ≠ 100% when gap > 1; transaction refresh on balance change during catch-up.
- **Desktop + mobile:** Wallet FFI **1.0.15** republished with the above native + Flutter bridge changes.

## 5.1.1 — 2026-05-27

- Bump app / workspace version to **5.1.1** (patch after 5.1.0).
- **Solo pool (desktop):** network block detection aligned with nodejs-pool (`hashDiff` / full 256-bit check); `enableBlockRefreshInterval` and `blockRefreshInterval` honored by the Rust sidecar; tuned VarDiff defaults for RandomARQ (see release notes).
- **Windows / Linux / macOS:** Rebuild bundles with latest wallet FFI and `arqma_flutter_solo_pool` from source or [ArqTras/FFI](https://github.com/ArqTras/FFI/releases/latest).
- **Android / iOS:** Wallet FFI only (no solo pool binary); version and build numbers bumped in `pubspec.yaml`.
- **Android / iOS:** Transaction history refreshes every **5 s** at chain tip, on each new block, and immediately after sending a transaction (pending/outgoing visible without waiting for the 60 s remote heartbeat).
- **About:** Copyright **2018–2026, Arqma Project** only (removed Loki / Ryo lines) on desktop and mobile.
- **FFI 1.0.9:** Async wallet `refresh`/sync with live height polling (fixes frozen **0%** scan progress on desktop footer and iOS Live Activity); includes async full rescan from 1.0.8.
- **iOS (build 27):** Live Activity rescan extension restored (`RescanLiveActivity`, App Group); archive build fix for extension target.
- **Desktop + mobile:** Scan progress UI no longer masks tip height during catch-up after open or manual refresh.
- **Desktop (Flutter 5.1.1+3):** Full rescan progress ignores stale pre-rescan tip snapshots; inactivity logout paused while minimized/backgrounded or during full rescan (parity with mobile).
- **iOS (build 28):** Background wallet sync pulse; no inactivity logout on screen lock; rescan progress UI fixes when tapping Live Activity.
- **iOS (build 29) / desktop release rebuild:** Wallet FFI **1.0.10** (full rescan native progress; `getheight` during background rescan/refresh).
- **Desktop (Flutter 5.1.1+5):** Re-configure native wallet FFI after `closeWalletSession` / worker reset so `open_wallet` retry works without restarting the app (Dart fix; FFI **1.0.14** unchanged).
- **Desktop + mobile + Android (5.1.1+6):** FFI **1.0.15** — `getheight` reports `daemon_height` / `background_busy`; footer scan progress uses 1-block tip tolerance; transaction history refreshes on balance change during catch-up; `wallet_syncing` in UI; mobile post-open `refresh` and faster scan heartbeat.

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
