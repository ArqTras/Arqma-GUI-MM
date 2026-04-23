//! Loose parsing of JSON-RPC numeric fields (often `i64` or string in `serde_json::Value`).
use serde_json::Value;

#[inline]
pub fn value_as_u64 (v: &Value) -> Option<u64> {
  v.as_u64()
    .or_else(|| v.as_i64().filter(|&i| i >= 0).map(|i| i as u64))
    .or_else(|| v.as_str().and_then(|s| s.parse::<u64>().ok()))
    .or_else(|| v.as_f64().map(|f| f.max(0.0) as u64))
}
