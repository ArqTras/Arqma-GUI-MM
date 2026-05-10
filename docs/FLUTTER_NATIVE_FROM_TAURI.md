# Moving Tauri “native” backend into Flutter

This document describes how to **reuse the Rust wallet/daemon logic** from `rust/tauri-app/src-tauri` inside the **Flutter desktop** shell, instead of maintaining a parallel **Dart** implementation (`DesktopNativeBridge`).

## Today (two shells)

| Shell | Backend | UI → backend |
|-------|---------|----------------|
| **Tauri** (`arqma-wallet` binary) | Rust in `src-tauri`, `AppData`, `backend_send` | Tauri `invoke("backend_send")` + `listen("backend-receive")` |
| **Flutter** (`Arqma-Wallet.app`) | Dart `DesktopNativeBridge` + subprocess `arqmad` / `arqma-wallet-rpc` | `NativeBridge.backendSend` + `backendReceive` stream |

The Flutter path **re-implements** startup, wallet list, JSON-RPC, and process control in Dart for parity. The Tauri path is the **authoritative** implementation.

## Target (single Rust backend, two UIs)

1. **Extract** a UI-agnostic “engine” from `arqma_wallet_lib` that does **not** depend on `tauri::AppHandle` for every emit.
2. **Expose** that engine to Flutter via **either**:
   - **macOS / iOS style:** `FlutterMethodChannel('com.arqma.wallet/native')` implemented in Swift, which calls into a **`cdylib`** built from Rust; or  
   - **`dart:ffi`:** load `libarqma_wallet_engine.dylib` / `.so` / `.dll` and call a small **C ABI** (`arqma_engine_*`).
3. Flutter **`resolveAppNativeBridge()`** already prefers **`MethodChannelNativeBridge`** when `native_ping` succeeds (`native_bridge_resolver.dart`). Once the embedder answers `native_ping`, **disable** `DesktopNativeBridge` for that build so all `backend_send` traffic goes through native code.

`arqma_wallet` already lists `crate-type = ["staticlib", "cdylib", "rlib"]` in `rust/tauri-app/src-tauri/Cargo.toml`, but **`pub fn run()`** is entirely **Tauri Builder** — there is **no stable C entrypoint** yet for Flutter.

## Why it is not a one-shot copy

`backend_send` in `lib.rs` takes `tauri::AppHandle` and passes it into:

- `core_handler::handle_core(&app, &app, …)` — first `&AppHandle` coerces to `&dyn BackendReceiveSink` for emits; second is for Tauri-only APIs (`rfd`, solo pool, …).
- `daemon_handler::handle_daemon(&app, …)`
- wallet paths that call `gateway_emit::emit_receive(&app, …)` and many `wallet_handler::*` helpers.

`AppHandle` is used for:

- Emitting JSON to the UI (`backend-receive` channel in Tauri; in Flutter this becomes `MethodChannel('…/native')` **from native → Dart** with method `backend_receive`).
- Opening dialogs (`rfd`), clipboard (`arboard`), logging, version strings, etc.

Flutter already has Dart equivalents for some invokes (`dialog_open_dir`, `clip_write_text` in `DesktopNativeBridge.invoke`). A shared engine should take **trait objects** instead of raw `AppHandle` where possible.

**Started in code:** `BackendReceiveSink` in `gateway_emit.rs` (emit-only). A future **`AppHostSink`** (or similar) can extend it with `pick_folder`, clipboard, `exit_app`, …

```rust
// Implemented today for AppHandle:
pub trait BackendReceiveSink: Send + Sync {
  fn emit_receive(&self, event: &str, data: Value) -> Result<(), String>;
}
```

Implement **`FlutterMethodChannelSink`** (or FFI callback table) for Flutter once the engine is decoupled from Tauri.

## Recommended phases

### Phase 1 — Emit boundary (substantially done)

1. **`BackendReceiveSink`** in `rust/tauri-app/src-tauri/src/gateway_emit.rs`: `emit_receive` → Tauri `backend-receive` (implemented for `AppHandle`). Public `emit_receive(app, …)` remains a thin wrapper (`#[allow(dead_code)]`) for future FFI / out-of-crate callers; in-crate sites use the trait explicitly.
2. **`solo_pool_sink::TauriSoloPoolSink`** now calls `BackendReceiveSink::emit_receive` (same behaviour; first consumer of the trait).
3. **Done:** `core_handler`, `startup_run`, `daemon_handler`, `daemon_heartbeat`, `wallet_handler`, `wallet_heartbeat`, `wallet_relay_ops`, `wallet_pools`, `wallet_process`, and `lib.rs` now call **`BackendReceiveSink::emit_receive`** explicitly (still passing `&AppHandle`, which implements the trait).
4. Next: change signatures to `sink: &dyn BackendReceiveSink` (plus `app: &AppHandle` only where `Manager` / `try_state` / dialogs are needed).

### Phase 2 — `handle_core` / `handle_daemon` signatures

5. **Done for core path:** `handle_core(sink: &dyn BackendReceiveSink, app: &AppHandle, …)` and `run_core_startup(sink, app, …)`; `backend_send` passes `&app` for both until a non-Tauri sink exists. **Next:** same pattern for `handle_daemon` and selected `wallet_handler` entrypoints (keep `app` where only `Manager` / `try_state` / subprocess / dialogs are needed).
6. Where Tauri-only APIs are required (`path_resolver`, window), keep `AppHandle` or extend the trait with optional hooks.

### Phase 3 — C ABI for Flutter (macOS first)

7. Add `#[no_mangle] pub unsafe extern "C" fn arqma_engine_create(...) -> *mut EngineHandle` that:
   - builds `reqwest::Client`, `AppData`-like struct **without** `tauri::Manager`;
   - stores an `Arc<Engine>` in a box.
8. Add `arqma_engine_backend_send_json(ptr, *const c_char, out_err) -> *mut c_char` returning serialized `serde_json::Value` or error string (caller frees with `arqma_engine_free_cstr`).
9. Add `arqma_engine_poll_events` **or** push model: native calls **into** Flutter via `binaryMessenger` `invokeMethod('backend_receive', …)` on a background thread (main-thread marshalling required on macOS).

### Phase 4 — Xcode / Flutter packaging

10. Build the `cdylib` for the same architectures as Flutter (`arm64` / `x86_64`), embed under `Frameworks/` or `Arqma-Wallet.app/Contents/MacOS/`, set **rpath**, **codesign** nested library.
11. Swift `AppDelegate` / `MainFlutterWindow`: after `FlutterViewController` is created, register `FlutterMethodChannel` and load the dylib with `dlopen` or static link.

### Phase 5 — Dart glue

12. When `native_ping` is true, **`resolveAppNativeBridge`** returns `MethodChannelNativeBridge` only (no `DesktopNativeBridge`).
13. Remove or feature-flag Dart subprocess wallet/daemon code for macOS builds that ship the dylib.

### Phase 6 — Linux / Windows

14. Repeat packaging for `.so` / `.dll` and adjust resolver + CI.

### Wallet-only FFI (implemented; subset of Phase D / packaging)

The Flutter **desktop** shell can use **`arqma-wallet-flutter-ffi`** (`rust/arqma-wallet-flutter-ffi`) instead of spawning **`arqma-wallet-rpc`**: Dart loads the `cdylib` / `.so` / `.dll` and calls the same JSON-RPC-shaped API as `Wallet2ApiClient`. Packaging hooks:

| Platform | Mechanism |
|----------|-----------|
| **macOS** | Xcode “Copy Arqma Tauri bins” → `Contents/Frameworks/libarqma_wallet_flutter_ffi.dylib` |
| **Linux** | `flutter/arqma_wallet_gui/linux/CMakeLists.txt` → `bundle/lib/libarqma_wallet_flutter_ffi.so` |
| **Windows** | `flutter/arqma_wallet_gui/windows/CMakeLists.txt` → `arqma_wallet_flutter_ffi.dll` next to `Arqma-Wallet.exe` |
| **Manual** | `flutter/arqma_wallet_gui/tool/copy_arqma_tauri_bins.sh` (`.app`, Linux `bundle/`, Windows `runner/Release`) |
| **CI** | `.github/workflows/wallet-flutter-ffi.yml` — matrix **macOS / Linux / Windows (GNU)** + `cargo build -p arqma-wallet-flutter-ffi --release` |

See **`rust/arqma-wallet-flutter-ffi/README.md`** and **`docs/WALLET_RUST_PORT.md`** (Phase D). A future **full** `arqma_engine_*` ABI for all `backend_send` modules remains separate from this wallet slice.

## Relation to `docs/WALLET_RUST_PORT.md`

- **Subprocess `arqma-wallet-rpc`**: both Tauri and Flutter today.  
- **Phase D (FFI wallet2)**: replaces the **wallet RPC subprocess** with linked native code — orthogonal but can share the same **`cdylib`** delivery pipeline as this document.  
- This document focuses on **moving the whole Tauri command surface** (`backend_send` + emits) behind one native boundary for Flutter.

## Flutter code already prepared

- `MethodChannelNativeBridge` + `resolveAppNativeBridge()` (`flutter/arqma_wallet_gui/lib/core/services/native_bridge.dart`, `native_bridge_resolver.dart`).
- Embedder must implement: `native_ping`, `backend_send` (same JSON envelope as Tauri `IpcMessage`), and call **`backend_receive`** on the Dart side with `{ event, data }` maps.

## Suggested ownership

| Area | Owner / notes |
|------|------------------|
| Rust `BackendReceiveSink` / host trait + C ABI | Rust / wallet team |
| Swift MethodChannel + threading | macOS Flutter maintainer |
| CI codesign + dylib | Release / CI |

## Out of scope for a single PR

- Duplicating all `wallet_handler` paths in Dart (already partially done in `DesktopNativeBridge` — treat as **temporary** once Rust engine is shared).
- Running **full** `tauri::Builder` inside Flutter (two compositors / two WebViews — not desired).

---

**Summary:** “Move native from Tauri to Flutter” means **share one Rust engine** and **plumb events through MethodChannel (or FFI)**, not re-copy business logic into Dart. Continue with **`BackendReceiveSink`** through handlers, then a **minimal `native_ping` + `backend_send` + `backend_receive`** loop on macOS; expand module-by-module until `DesktopNativeBridge` can be retired on desktop.
