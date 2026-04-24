Tauri bundle folder "bin" (served as resource_dir/bin).

Before building a **release** installer, place official Arqma binaries here so the backend can spawn them:
  - Windows: arqmad.exe, arqma-wallet-rpc.exe
  - Linux / macOS: arqmad, arqma-wallet-rpc (chmod +x)

Do not commit executables to git (they are listed in .gitignore).
Source: official Arqma repository builds / project CI artifacts.

---

Prepare this folder from repo ./bin (CI / manual download)

- From repository root: **`node build/copy-to-tauri-bins.js`** copies every file from `./bin` into this directory.
- Or run **`scripts/prepare-release-bins.ps1`** (Windows) / **`scripts/prepare-release-bins.sh`** (Linux/macOS).

If you do **not** bundle exes here, the app can still find them via environment (see docs/WALLET_RUST_PORT.md):

  - ARQMA_BUILD_DIR = path to upstream `build/release` (contains `bin/arqmad`, `bin/arqma-wallet-rpc`)
  - ARQMA_WALLET_RPC / ARQMA_DAEMON = full paths to each executable
  - PATH

---

Windows — UI / exe name

- The crate enables Tauri **`custom-protocol`** so release binaries load embedded UI (not `http://localhost:1420`). You still need **`npm run build`** before `cargo build --release` so `../dist/index.html` exists at compile time.
- From `rust/tauri-app`: **`npm run release:win`** → `npm run build`, then `cargo build --release`, then copies **`Arqma-Wallet.exe`** next to `arqma-wallet.exe` in `rust/target/release/`.
- Full installer (NSIS, etc.): **`npm run ci:tauri`** or **`npm run tauri:build`** (uses `mainBinaryName` in `tauri.conf.json`). Run **`node build/copy-to-tauri-bins.js`** first if you bundle Arqma binaries.
