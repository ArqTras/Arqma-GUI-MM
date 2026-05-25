## Arqma Wallet 5.1.0

Desktop and mobile bundles built from tag **5.1.0** / `main` with **[ArqTras/FFI 1.0.3](https://github.com/ArqTras/FFI/releases/tag/1.0.3)** prebuilt wallet FFI.

### Native wallet (FFI 1.0.3 + GUI fixes)

- **Windows sync:** FFI **1.0.3** fixes wallet scan stalls near checkpoint height (`pauseRefresh` + `refreshAsync` fallback). GUI heartbeat defers heavy RPC during scan and kicks `refresh_from_height` on stall.
- **UI:** Fix nested `Scrollbar` / `PrimaryScrollController` errors on wallet list and daemon settings.
- **Daemon RPC:** Quieter probe logging during remote node scan and optional `get_txpool_backlog` JSON quirks.
- **Solo pool (desktop only):** Windows, Linux, and macOS bundles include **`arqma_flutter_solo_pool`** under `bin/` — Stratum solo mining sidecar. **Android and iOS do not include solo pool** (mobile uses wallet FFI only; no sidecar binary).

### CI

- `ARQMA_FFI_RELEASE_VERSION=1.0.3` in desktop and Android release workflows and fetch scripts.
- **Desktop release (Flutter)** builds and verifies solo pool on Windows, Linux, and macOS.
- **Android release (Flutter)** and iOS builds do **not** bundle solo pool.

### macOS — Gatekeeper

If macOS blocks the app after download, run once in Terminal:

```bash
xattr -cr "/Applications/Arqma-Wallet.app"
```

**FFI artifacts:** https://github.com/ArqTras/FFI/releases/tag/1.0.3

**Full changelog:** https://github.com/ArqTras/Arqma-GUI-MM/compare/daad9e2...HEAD
