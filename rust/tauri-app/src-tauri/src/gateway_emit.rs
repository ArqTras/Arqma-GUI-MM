use serde_json::{json, Value};
use tauri::AppHandle;
use tauri::Emitter;

/// Odpowiednik `Backend.send` — `webContents.send("receive", { event, data })`.
pub fn emit_receive (app: &AppHandle, event: &str, data: Value) -> Result<(), String> {
  app
    .emit(
      "backend-receive",
      json!({ "event": event, "data": data }),
    )
    .map_err(|e| e.to_string())
}
