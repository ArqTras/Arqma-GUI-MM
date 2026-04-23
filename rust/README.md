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

## Tauri application (release build)

The UI lives under `rust/tauri-app`. The Tauri project is `rust/tauri-app/src-tauri/`.

1. Install **Node.js** (see root `README.md` for version).
2. Optional but recommended for a full app: download official Arqma `arqmad` / `arqma-wallet-rpc` into `./bin` at repo root, then:

   ```bash
   node build/copy-to-tauri-bins.js
   ```

   See `rust/tauri-app/src-tauri/bin/README.txt`.

3. Build frontend + Tauri bundles:

   ```bash
   cd rust/tauri-app
   npm install
   npm run ci:tauri
   ```

Artifacts are written under `rust/target/release/` (binary, `resources/`, and `rust/target/release/bundle/` for installers).

On **Linux** CI, an extra `.tar.gz` of the release binary and `resources/` is produced by `scripts/pack-linux-tarball.sh` after `tauri build`.

## Release profile

Workspace `rust/Cargo.toml` sets `[profile.release]` (e.g. LTO, `strip`) for smaller, optimized binaries. Clean rebuilds after profile changes: `cargo clean` then build again.
