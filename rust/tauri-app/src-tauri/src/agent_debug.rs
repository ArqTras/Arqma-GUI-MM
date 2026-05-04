//! NDJSON agent logs for debug sessions (repo `.cursor/debug-<session>.log`).
use serde_json::{json, Value};
use std::io::Write;

/// Session `6d616b` — debug ingest file under workspace `.cursor/`.
pub(crate) fn log (hypothesis_id: &str, location: &str, message: &str, data: Value) {
  // #region agent log
  let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
    .join("../../..")
    .join(".cursor")
    .join("debug-6d616b.log");
  let payload = json!({
    "sessionId": "6d616b",
    "runId": "pre-fix",
    "hypothesisId": hypothesis_id,
    "location": location,
    "message": message,
    "data": data,
    "timestamp": chrono::Utc::now().timestamp_millis()
  });
  if let Ok(mut f) = std::fs::OpenOptions::new()
    .create(true)
    .append(true)
    .open(&path)
  {
    let _ = writeln!(f, "{payload}");
    let _ = f.flush();
  }
  // #endregion
}
