## Arqma Wallet 5.1.2

Desktop and mobile bundles for tag **5.1.2**. Wallet FFI **[1.0.15](https://github.com/ArqTras/FFI/releases/tag/1.0.15)** (unchanged). Desktop solo pool sidecar **republished on FFI 1.0.15** with block submit fix (miner nonce in block header, full 256-bit block candidate check).

### Highlights

- **Solo pool (desktop):** Fixed `submit_block` — Stratum miner nonce is patched into the **block-header nonce field** (not `reserved_offset` in coinbase `tx_extra`), matching `construct_block_blob` in arqma-electron-wallet and MoneroOcean. Solo-found blocks are accepted by `arqmad` and pay the configured mining address.
- **Desktop Flutter:** **5.1.2+6** — bundles include updated `arqma_flutter_solo_pool` from [ArqTras/FFI](https://github.com/ArqTras/FFI/releases/tag/1.0.15). Windows CI: MSVC coroutine fix (`local_auth_windows`); Inno Setup includes wallet FFI flat + `lib/` mirror.
- **iOS / mobile:** **5.1.2+51** — semver bump; same wallet stack as 5.1.1 (FFI **1.0.15**, no solo pool on mobile).
- **Android:** **5.1.2+14** — release APK/AAB filenames use slug `5.1.2`.

### Desktop install (artifact names use slug `5.1.2`)

| OS | File | Notes |
|----|------|--------|
| **Windows** | `Arqma-Wallet-Flutter-5.1.2-windows-x64.zip` or `…-Setup.exe` | Portable ZIP or installer |
| **Linux** | `Arqma-Wallet-Flutter-5.1.2-linux-x64.tar.gz` and/or `…-x86_64.AppImage` | tar.gz or AppImage |
| **macOS** | `Arqma-Wallet-Flutter-5.1.2-macos.zip` and/or `…-macos.dmg` | Drag app to Applications |
