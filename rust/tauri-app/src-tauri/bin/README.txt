Tauri bundle folder "bin" (served as resource_dir/bin).

Before building a **release** installer, place official Arqma binaries here so the backend can spawn them:
  - Windows: arqmad.exe, arqma-wallet-rpc.exe
  - Linux / macOS: arqmad, arqma-wallet-rpc (chmod +x)

Do not commit executables to git (they are listed in .gitignore).
Source: official Arqma repository builds / project CI artifacts.

---

Windows — UI / exe name

- Do **not** run only `cargo build --release` without the Vite app: the WebView needs `rust/tauri-app/dist/` built first (`npm run build`), or you get **localhost:1420 / ERR_CONNECTION_REFUSED**.
- From `rust/tauri-app`: **`npm run release:win`** → `npm run build`, then `cargo build --release`, then copies **`Arqma Wallet.exe`** next to `arqma-wallet.exe` in `rust/target/release/`.
- Full installer (NSIS, etc.): **`npm run tauri:build`** (uses `mainBinaryName` in `tauri.conf.json`).
