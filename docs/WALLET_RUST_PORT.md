# Arqma wallet in Rust (`solopoolrust`) — plan vs upstream

## Facts from `github.com/arqma/arqma`

The `arqma-wallet-rpc` **binary** is not a small standalone library: it is the HTTP JSON-RPC front-end over **C++ wallet2**, same family as Monero.

Authoritative upstream paths (default branch):

| Area | Path |
|------|------|
| JSON-RPC server | `src/wallet/wallet_rpc_server.cpp`, `wallet_rpc_server.h`, `wallet_rpc_server_commands_defs.h` |
| High-level wallet API | `src/wallet/api/wallet.cpp`, `wallet.h`, plus `pending_transaction`, `transaction_history`, … |
| CLI wallet | `src/simplewallet/simplewallet.cpp` |
| API tests | `tests/libwallet_api_tests/` |

There is **no** maintained “`arqma-wallet-rpc` as a Rust crate” in that repository. Options for this GUI are:

1. **Keep subprocess + HTTP** (current): spawn upstream-built `arqma-wallet-rpc`, talk JSON-RPC + digest (what Tauri does today).
2. **Static/dynamic link + FFI**: build `libwallet_api` (or a thin C ABI wrapper) from `arqma/arqma`, expose `extern "C"` entrypoints, bind with `cxx` / `bindgen` from Rust. Still ships native code; not “pure Rust”.
3. **Pure Rust reimplementation**: reimplement CryptoNote/Arqma wallet rules in Rust — far beyond a GUI port; not realistic as a single deliverable.

This branch introduces crate **`arqma-wallet-rpc`** as the **integration boundary**: a Rust API (`WalletJsonRpc`) plus **`upstream_paths`** — resolution of the **executables Arqma’s CMake build produces** (`build/release/bin/arqma-wallet-rpc`, `arqmad`, …). Those binaries are already the linked product of Arqma’s internal wallet/daemon libraries; the GUI runs them and uses HTTP JSON-RPC for the wallet RPC process.

Upstream CMake also offers **`BUILD_GUI_DEPS`** (install **`libwallet_merged`** into `lib/`) for **native GUI / JNI** style linking — not used by this Tauri app yet; a future FFI backend (Phase D) would target that.

## Phases (recommended)

- **Phase A (done here):** workspace crate + `WalletJsonRpc` + **`resolve_wallet_rpc_path` / `resolve_daemon_path`** (env + upstream `build/…/bin` + `PATH` + bundle); Tauri uses these for **`arqma-wallet-rpc`** and **`arqmad`**.
- **Phase B (script):** `scripts/checkout-arqma.ps1` / `scripts/checkout-arqma.sh` — shallow clone to `vendor/arqma/` (ignored by git). CI can keep using release archives; developers match upstream CMake output via `ARQMA_BUILD_DIR`.
- **Phase C (done):** feature **`http-digest`** on crate `arqma-wallet-rpc`: `WalletRpcClient` + digest + `WalletJsonRpc` impl live in the workspace crate; Tauri enables the feature and re-exports the client from `json_rpc_client.rs`. `WalletBackendState.wallet` is **`Option<Arc<WalletRpcClient>>`** with `wallet_json_rpc()` returning `Option<&dyn WalletJsonRpc>` for call-only sites.
- **Phase D:** FFI backend calling into compiled Arqma libraries; remove subprocess for supported platforms.
- **Phase E (optional):** embed HTTP server in-process (still C++ inside) vs true Rust wallet logic.

## Environment variables (upstream build / install vs bundle)

| Variable | Purpose |
|----------|---------|
| `ARQMA_WALLET_RPC` | Full path to `arqma-wallet-rpc` (or `.exe`). |
| `ARQMA_DAEMON` | Full path to `arqmad` (or `.exe`) for **local** daemon mode. |
| `ARQMA_BUILD_DIR` | Directory that contains `bin/` (e.g. clone’s `build/release` after `make release`). Both wallet-rpc and daemon are resolved as `$ARQMA_BUILD_DIR/bin/<name>`. |
| `ARQMA_INSTALL_PREFIX` | Prefix from `make install` (executables in `$prefix/bin/`). |
| `PATH` | Last-resort before bundle: names `arqma-wallet-rpc` / `arqmad` (with `.exe` on Windows). |

After `make release` in [arqma/arqma](https://github.com/arqma/arqma), executables live under **`build/release/bin/`** — set `ARQMA_BUILD_DIR` to the absolute path of **`build/release`** (not necessarily ending in `bin`; the resolver appends `bin` when needed).

## Branch

Development branch: **`solopoolrust`** (from `solopool`).
