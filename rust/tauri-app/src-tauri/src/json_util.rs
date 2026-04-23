//! Loose parsing of JSON-RPC numeric fields (often `i64` or string in `serde_json::Value`).
use serde_json::Value;

/// Many JSON-RPC stacks include `"error": null` on success. `Value::get("error").is_some()` is then
/// **true**, and treating that as an error drops `result` (no footer height / wallet sync %).
#[inline]
pub fn json_rpc_no_error (v: &Value) -> bool {
  match v.get("error") {
    None => true,
    Some(Value::Null) => true,
    Some(Value::Object(o)) if o.is_empty() => true,
    Some(_) => false
  }
}

#[inline]
pub fn value_as_u64 (v: &Value) -> Option<u64> {
  v.as_u64()
    .or_else(|| v.as_i64().filter(|&i| i >= 0).map(|i| i as u64))
    .or_else(|| v.as_str().and_then(|s| s.parse::<u64>().ok()))
    .or_else(|| v.as_f64().map(|f| f.max(0.0) as u64))
}

/// `getheight` JSON-RPC — same field resolution as `open_wallet` (`result.height` or `/result/height`, scalar `result` if ever used).
pub fn wallet_height_from_getheight (v: &Value) -> Option<u64> {
  if !json_rpc_no_error(v) {
    return None;
  }
  if let Some(h) = v.pointer("/result/height").and_then(value_as_u64) {
    return Some(h);
  }
  let r = v.get("result")?;
  if r.is_object() {
    r.get("height").and_then(value_as_u64)
  } else {
    value_as_u64(r)
  }
}
