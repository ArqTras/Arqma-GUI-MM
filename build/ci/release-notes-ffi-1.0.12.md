# Arqma Wallet FFI 1.0.12

## Highlights

- **User-facing OOM on wallet open:** `wallet2_api_wrapper.cpp` maps `std::bad_alloc` during open to a clear error message instead of an opaque failure.
- **Deferred background refresh on open:** Wallet open no longer starts `startRefresh()` immediately; refresh is deferred until the refresh RPC path runs, reducing peak RAM on iOS during open.
- **`refresh_async_start` after open:** `wallet2_client.rs` calls `refresh_async_start` after a successful `open_wallet` so sync can start when the UI is ready.
- **Session hygiene on open:** `wallet2_client.rs` closes any existing session before `open_wallet` to avoid stale RPC state when switching wallets.

## Artifacts

- `arqma-wallet-ffi-ios-1.0.12.zip` — iOS device `libarqma_wallet_flutter_ffi.dylib` (`aarch64-apple-ios`)
- `arqma-wallet-ffi-macos-arm64-1.0.12.zip` — macOS Apple Silicon desktop FFI

## Build notes

Built from local workspace sources (uncommitted changes in `wallet2_api_wrapper.cpp` and `wallet2_client.rs`).
