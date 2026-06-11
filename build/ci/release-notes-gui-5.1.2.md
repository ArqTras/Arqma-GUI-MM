## Arqma Wallet 5.1.2

Desktop and mobile bundles for tag **5.1.2**. Wallet FFI **[1.0.15](https://github.com/ArqTras/FFI/releases/tag/1.0.15)** **republished** (Windows LMDB link + scan crash fix). Desktop solo pool sidecar from FFI 1.0.15 (block submit fix: miner nonce in block header, full 256-bit block candidate check).

### Highlights

- **Solo pool (desktop):** Fixed `submit_block` — Stratum miner nonce is patched into the **block-header nonce field** (not `reserved_offset` in coinbase `tx_extra`), matching `construct_block_blob` in arqma-electron-wallet and MoneroOcean. Solo-found blocks are accepted by `arqmad` and pay the configured mining address.
- **Desktop Flutter:** **5.1.2+6** — republished with FFI **1.0.15** (Windows LMDB link + scan crash fix). Windows CI builds wallet FFI from source; Inno Setup includes wallet FFI flat + `lib/` mirror; GUI footer reads version from `pubspec.yaml`; improved MinGW DLL preload for Inno installs (Win32 1114).
- **iOS / mobile:** **5.1.2+51** — semver bump; same wallet stack as 5.1.1 (FFI **1.0.15**, no solo pool on mobile).
- **Android:** **5.1.2+14** — release APK/AAB filenames use slug `5.1.2`.

### Desktop install (artifact names use slug `5.1.2`)

| OS | File | Notes |
|----|------|--------|
| **Windows** | `Arqma-Wallet-Flutter-5.1.2-windows-x64.zip` or `…-Setup.exe` | Portable ZIP or installer |
| **Linux** | `Arqma-Wallet-Flutter-5.1.2-linux-x64.tar.gz` and/or `…-x86_64.AppImage` | tar.gz or AppImage |
| **macOS** | `Arqma-Wallet-Flutter-5.1.2-macos.zip` and/or `…-macos.dmg` | Drag app to Applications |
