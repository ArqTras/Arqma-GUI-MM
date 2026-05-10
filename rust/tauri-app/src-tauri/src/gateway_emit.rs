use serde_json::{json, Value};
use tauri::AppHandle;
use tauri::Emitter;

/// Delivers `{ event, data }` to the UI shell (Tauri `backend-receive` today; Flutter
/// `MethodChannel` / FFI later). See `docs/FLUTTER_NATIVE_FROM_TAURI.md` Phase 1.
pub trait BackendReceiveSink: Send + Sync {
  fn emit_receive (&self, event: &str, data: Value) -> Result<(), String>;
}

impl BackendReceiveSink for AppHandle {
  fn emit_receive (&self, event: &str, data: Value) -> Result<(), String> {
    self
      .emit(
        "backend-receive",
        json!({ "event": event, "data": data }),
      )
      .map_err(|e| e.to_string())
  }
}

/// Same as `Backend.send` — `webContents.send("receive", { event, data })` in Electron.
/// Kept as a stable name for future FFI / embedders; in-crate call sites use [`BackendReceiveSink`] directly.
#[allow(dead_code)]
#[inline]
pub fn emit_receive (app: &AppHandle, event: &str, data: Value) -> Result<(), String> {
  BackendReceiveSink::emit_receive(app, event, data)
}
