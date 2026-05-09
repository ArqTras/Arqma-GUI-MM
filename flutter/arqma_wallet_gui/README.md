# Arqma Wallet — Flutter shell

This directory is a **Flutter desktop/mobile shell** that mirrors the **Vue + Quasar + Tauri** wallet in `rust/tauri-app`: routing, **Arqma color palette**, `GatewayStore` (Vuex parity), and `AppReceiver` (same `backend-receive` event names as `src/receiver/receiver.js`).

## Run

```bash
cd flutter/arqma_wallet_gui
flutter pub get
flutter run -d macos   # or linux / windows / chrome
```

## Native bridge

Real wallet behaviour still lives in **Rust** (`rust/tauri-app/src-tauri`) behind Tauri `invoke("backend_send", …)` and `listen("backend-receive", …)`.

- **Debug builds** use `StubNativeBridge` (see `lib/main.dart`) so the UI can be exercised without the embedder.
- **Release path**: implement `MethodChannelNativeBridge` on each platform (or use **flutter_rust_bridge** / a small C ABI around the existing handlers) and forward:

  - `backend_send` → same JSON envelope as today’s `IpcMessage`.
  - Native → Dart: JSON maps shaped like `{ "event": "<name>", "data": … }` (see `gateway_emit.rs`).

## What is not done yet

Individual **Vue pages** (forms, validation, swap, staking tables, settings modals, i18n ARB files) are mostly **stubs** or simplified layouts. Porting them 1:1 is incremental work on top of this scaffold.
