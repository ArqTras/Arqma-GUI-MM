//! Abstraction for `solo_pool` gateway events — Tauri IPC vs Flutter sidecar (JSON lines on stdout).

use serde_json::Value;
use tauri::AppHandle;

use crate::gateway_emit::BackendReceiveSink;

/// Same payload shape as Electron `webContents.send("receive", { event, data })` / Tauri `backend-receive`.
pub trait SoloPoolSink: Send + Sync + 'static {
  fn emit_receive (&self, event: &str, data: Value);
}

#[derive(Clone)]
pub struct TauriSoloPoolSink (pub AppHandle);

impl SoloPoolSink for TauriSoloPoolSink {
  fn emit_receive (&self, event: &str, data: Value) {
    let _ = BackendReceiveSink::emit_receive(&self.0, event, data);
  }
}

/// Flutter spawns `arqma_flutter_solo_pool`; each line is one JSON object `{ "event", "data" }`.
#[derive(Clone, Copy)]
pub struct JsonlStdoutSoloPoolSink;

impl SoloPoolSink for JsonlStdoutSoloPoolSink {
  fn emit_receive (&self, event: &str, data: Value) {
    use std::io::Write;
    let line = serde_json::json!({ "event": event, "data": data }).to_string();
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "{line}");
    let _ = out.flush();
  }
}
