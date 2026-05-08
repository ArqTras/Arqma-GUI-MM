# Changelog

## 5.0.3 — 2026-05-07

### Highlights

- **Native wallet API (`wallet2_api`) is now the default build.** The Tauri app links against Arqma core’s merged wallet library (`libwallet_merged`) when built with default Cargo features (`native-wallet2`). This removes the previous “stub only” behaviour for standard local and release builds, provided an [Arqma core checkout](rust/docs/NATIVE_WALLET2.md) and successful CMake build are available.
- **CI builds Arqma from source** on Linux, macOS, and Windows (MinGW + `x86_64-pc-windows-gnu` on Windows) so installers are produced with the same native wallet stack where the pipeline succeeds. A **stub** build path remains for fast checks: `npm run ci:tauri:stub` / Cargo `--no-default-features --features stub-wallet2`.
- Documentation: see [`rust/docs/NATIVE_WALLET2.md`](rust/docs/NATIVE_WALLET2.md) for upstream clone, `BUILD_GUI_DEPS`, and linker notes per platform.

### Migration notes

- If you **do not** compile Arqma core locally, use **`npm run tauri:build:stub`** / **`tauri:dev:stub`** or pass **`--no-default-features --features stub-wallet2`** to Cargo.
- **GitHub Actions** full Tauri workflow clones **`arqtras/arqma`** (branch **`pospow`**) and builds the **`wallet_merged`** target before bundling the app.
