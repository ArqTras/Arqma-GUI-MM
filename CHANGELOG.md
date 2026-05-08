# Changelog

## 5.0.3 — 2026-05-07

### Highlights

- **Native wallet API (`wallet2_api`) is now the default build.** The Tauri app links against Arqma core’s merged wallet library (`libwallet_merged`) when built with default Cargo features (`native-wallet2`). This removes the previous “stub only” behaviour for standard local and release builds, provided an [Arqma core checkout](rust/docs/NATIVE_WALLET2.md) and successful CMake build are available.
- **CI builds Arqma from source** on Linux, macOS, and Windows (MinGW + `x86_64-pc-windows-gnu` on Windows) so installers use native wallet2. **`npm` scripts pass `--features native-wallet2`**; stub is only via explicit Cargo (`--no-default-features --features stub-wallet2`) or the Rust workflow’s fast `cargo check`.
- Documentation: see [`rust/docs/NATIVE_WALLET2.md`](rust/docs/NATIVE_WALLET2.md) for upstream clone, `BUILD_GUI_DEPS`, and linker notes per platform.

### Migration notes

- If you **do not** compile Arqma core locally, use Cargo **`--no-default-features --features stub-wallet2`** (or `npx tauri build -- …`) for a stub UI build; **`npm run tauri:build`** expects native prerequisites.
- **GitHub Actions** full Tauri workflow clones **`arqtras/arqma`** (branch **`pospow`**) and builds the **`wallet_merged`** target before bundling the app.
