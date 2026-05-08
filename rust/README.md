# Rust workspace

This directory contains the **Rust workspace** used by the Tauri desktop shell and shared libraries.

## Layout

| Path | Role |
|------|------|
| `core/` | Shared wallet logic (`arqma-wallet-core`) |
| `daemon/` | Daemon-related crate (if present in workspace) |
| `tauri-app/` | Vue + Quasar UI and `src-tauri/` Tauri backend |

The workspace manifest is `rust/Cargo.toml`.

## Prerequisites

- **Rust**: stable toolchain (`rustup` recommended), edition and MSRV as defined in the workspace `Cargo.toml`.
- **Linux (Tauri / `cargo check` on Ubuntu CI)**: WebKit and related dev packages, e.g. `libwebkit2gtk-4.1-dev`, `libappindicator3-dev`, `librsvg2-dev`, `patchelf` (see `.github/workflows/rust.yml` and `tauri-app.yml` for the exact `apt` list).

## Commands (from repository root)

Check and lint the whole workspace (no installer produced):

```bash
cd rust
cargo check --workspace --all-targets
cargo clippy --workspace --all-targets
```

## Native `wallet2` (FFI)

The Tauri crate defaults to **`native-wallet2`** (real `wallet2_api`). You need an Arqma core checkout and a successful link; see [`docs/NATIVE_WALLET2.md`](docs/NATIVE_WALLET2.md).

**GitHub Actions** [`tauri-app.yml`](../.github/workflows/tauri-app.yml) builds **native** `wallet2` (clone + CMake Arqma, then `npm run ci:tauri`). The [**Rust**](../.github/workflows/rust.yml) workflow uses **`cargo check -p arqma-wallet --no-default-features --features stub-wallet2`** only so PRs can compile without C++; **`npm` scripts always pass `--features native-wallet2`** for real installs.

## Tauri application (release build)

The UI lives under `rust/tauri-app`. The Tauri project is `rust/tauri-app/src-tauri/`.

1. Install **Node.js** (see root `README.md` for version).
2. Optional but recommended for a **bundled** app: put official Arqma `arqmad` / `arqma-wallet-rpc` in `./bin` at repo root, then from repo root run `node build/copy-to-tauri-bins.js`, or `scripts/prepare-release-bins.ps1` / `scripts/prepare-release-bins.sh`. Without bundled binaries, set `ARQMA_BUILD_DIR` (upstream `build/release`) or `ARQMA_WALLET_RPC` / `ARQMA_DAEMON` — see `docs/WALLET_RUST_PORT.md` and `rust/tauri-app/src-tauri/bin/README.txt`.

3. Build frontend, then the app (Tauri **`custom-protocol`** embeds `dist/`). All **`npm run tauri:*`** / **`ci:tauri*`** scripts enable **`native-wallet2`** (needs Arqma core per `docs/NATIVE_WALLET2.md`). For UI-only experiments without C++, use Cargo manually: `--no-default-features --features stub-wallet2`.

   ```bash
   cd rust/tauri-app
   npm install
   npm run tauri:build
   ```

   **`npm run ci:tauri`** and **`npm run tauri:build`** both build **native** wallet2. On Windows GNU (CI-style), use **`npm run ci:tauri:native:windows-gnu`**. **`npm run release:win`** builds the MSVC release binary and runs `scripts/postbuild-rename-windows.mjs`.

Artifacts are written under `rust/target/release/` (e.g. `arqma-wallet.exe`, `resources/`, and `rust/target/release/bundle/` for installers).

On **Linux** CI, an extra `.tar.gz` of the release binary and `resources/` is produced by `scripts/pack-linux-tarball.sh` after `tauri build`.

## Release profile

Workspace `rust/Cargo.toml` sets `[profile.release]` (e.g. LTO, `strip`) for smaller, optimized binaries. Clean rebuilds after profile changes: `cargo clean` then build again.
