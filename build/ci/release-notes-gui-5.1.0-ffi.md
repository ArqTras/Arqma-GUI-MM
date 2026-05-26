## Arqma Wallet 5.1.0

Desktop and mobile bundles built from tag **5.1.0** with prebuilt wallet FFI from [ArqTras/FFI](https://github.com/ArqTras/FFI/releases/tag/1.0.5) release **1.0.5**.

### Native wallet (FFI + GUI)

- **FFI:** Desktop and mobile use ArqTras/FFI **1.0.5** by default (`resolve-arqma-ffi-release-version.*`). Set `ARQMA_FFI_RELEASE_VERSION=latest` to follow GitHub Latest.
- **Windows sync:** FFI stall recovery (`pauseRefresh` + `refreshAsync` fallback). GUI heartbeat defers heavy RPC during scan.
- **UI:** Fix nested `Scrollbar` / `PrimaryScrollController` errors on wallet list and daemon settings.
- **Daemon RPC:** Quieter probe logging during remote node scan.

### Solo pool (desktop only)

- **Windows, Linux, macOS:** Bundles include **`arqma_flutter_solo_pool`** from `arqma-wallet-solo-pool-*` zips on the same FFI release (`fetch-arqma-desktop-prebuilts.*`).
- **Android and iOS:** Wallet FFI only — **no** solo pool sidecar binary.

### CI / fetch

- **Desktop release (Flutter):** `fetch-arqma-wallet-ffi-release*` + `fetch-arqma-wallet-solo-pool-release*` (FFI **1.0.5**).
- **Android release (Flutter):** `fetch-arqma-wallet-ffi-release*` for `android-arm64` / `android-x86_64` only.
- **iOS:** `prepare_ios_wallet_ffi.sh` fetches FFI `ios` artifact only.

### macOS — Gatekeeper

```bash
xattr -cr "/Applications/Arqma-Wallet.app"
```

**FFI releases:** https://github.com/ArqTras/FFI/releases

**Full changelog:** https://github.com/ArqTras/Arqma-GUI-MM/compare/daad9e2...HEAD
