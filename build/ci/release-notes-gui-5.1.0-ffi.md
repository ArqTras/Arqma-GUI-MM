## Arqma Wallet 5.1.0

Desktop and mobile bundles built from tag **5.1.0** / `main` with **[ArqTras/FFI 1.0.1](https://github.com/ArqTras/FFI/releases/tag/1.0.1)** prebuilt wallet FFI.

### Native wallet (FFI 1.0.1 + GUI fixes)

- **Windows:** Scan heartbeat defers heavy RPC during sync; detects stall and calls `refresh` with `start_height`; periodic `get_transfers` during long scan.
- **FFI:** `refresh_from_height` (`setRefreshFromBlockHeight` + `refresh`); iOS links **liblmdb** with `wallet_merged`.
- **Daemon:** Quieter handling of invalid JSON from optional `get_txpool_backlog`.

### CI

- `ARQMA_FFI_RELEASE_VERSION=1.0.1` in desktop and Android release workflows.
- Rebuild installers/archives via **Desktop release (Flutter)** and **Android release (Flutter)**.

**FFI artifacts:** https://github.com/ArqTras/FFI/releases/tag/1.0.1

**Full changelog:** https://github.com/ArqTras/Arqma-GUI-MM/compare/2641a6b...daad9e2
