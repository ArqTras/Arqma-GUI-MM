use crate::http_digest_arqma::{build_digest_header, inc_nc, generate_cnonce};
use serde_json::{json, Value};
use std::sync::atomic::{AtomicU64, Ordering};

const PATH_JSON_RPC: &str = "/json_rpc";

/// Custom `WalletRPC.sendRPC` (queue=1) with 401 retry (like `axiosDigest.js`).
pub struct WalletRpcClient {
  pub base: String, // "http://127.0.0.1:9999"
  pub user: String,
  pub pass: String,
  pub next_id: AtomicU64,
  pub nc: std::sync::Mutex<String>,
  pub cnonce: String,
  pub http: reqwest::Client
}

impl WalletRpcClient {
  pub fn new (http: &reqwest::Client, host: &str, port: u16, user: String, pass: String) -> Self {
    Self {
      base: format!("http://{host}:{port}"),
      user,
      pass,
      next_id: AtomicU64::new(0),
      nc: std::sync::Mutex::new("00000001".to_string()),
      cnonce: generate_cnonce(),
      http: http.clone()
    }
  }

  /// Separate JSON-RPC session (different `id` + digest) for heartbeat so it does not clash with UI calls.
  pub fn fork_for_heartbeat (&self) -> Self {
    Self {
      base: self.base.clone(),
      user: self.user.clone(),
      pass: self.pass.clone(),
      next_id: AtomicU64::new(50_000_000),
      nc: std::sync::Mutex::new("00000001".to_string()),
      cnonce: generate_cnonce(),
      http: self.http.clone()
    }
  }

  fn next_id (&self) -> u64 {
    self.next_id.fetch_add(1, Ordering::SeqCst)
  }

  /// POST JSON-RPC (digest); returns full JSON response (like `parseWalletResponse`, simplified to `Value`).
  pub async fn call (&self, method: &str, params: &Value) -> Result<Value, String> {
    let id = self.next_id();
    let mut body = json!({ "jsonrpc": "2.0", "id": id, "method": method });
    if !params.is_null() && !params.as_object().map(|o| o.is_empty()).unwrap_or(true) {
      body
        .as_object_mut()
        .unwrap()
        .insert("params".to_string(), params.clone());
    }
    let s = body.to_string();
    self.post_with_digest(&s).await
  }

  async fn post_with_digest (&self, body: &str) -> Result<Value, String> {
    let url = format!("{}{}", self.base, PATH_JSON_RPC);
    let first = self
      .http
      .post(&url)
      .header("Content-Type", "application/json")
      .body(body.to_string())
      .send()
      .await
      .map_err(|e| e.to_string())?;
    if first.status() == reqwest::StatusCode::UNAUTHORIZED {
      let www = first
        .headers()
        .get("www-authenticate")
        .and_then(|h| h.to_str().ok())
        .map(|s| s.to_string());
      let _ = first.text().await;
      let www = www.ok_or_else(|| "missing WWW-Authenticate".to_string())?;
      let nc = { self.nc.lock().map_err(|e| e.to_string())?.clone() };
      let path = PATH_JSON_RPC;
      let header = build_digest_header(
        "POST",
        path,
        &www,
        &self.user,
        &self.pass,
        &nc,
        &self.cnonce
      )?;
      {
        let mut g = self.nc.lock().map_err(|e| e.to_string())?;
        *g = inc_nc(&nc);
      }
      let r = self
        .http
        .post(&url)
        .header("Content-Type", "application/json")
        .header("Authorization", header)
        .body(body.to_string())
        .send()
        .await
        .map_err(|e| e.to_string())?;
      if !r.status().is_success() {
        return Err(format!("HTTP {} (digest)", r.status()));
      }
      let t = r.text().await.map_err(|e| e.to_string())?;
      return serde_json::from_str(&t).map_err(|e| e.to_string());
    }
    if !first.status().is_success() {
      return Err(format!("HTTP {}", first.status()));
    }
    let t = first
      .text()
      .await
      .map_err(|e| e.to_string())?;
    serde_json::from_str(&t).map_err(|e| e.to_string())
  }
}

/// `Daemon.sendRPC` — unauthenticated plain POST.
pub async fn daemon_post (
  client: &reqwest::Client,
  host: &str,
  port: u16,
  method: &str,
  id: u64,
  params: &Value
) -> Result<Value, String> {
  let url = format!("http://{host}:{port}{PATH_JSON_RPC}");
  let mut body = json!({ "jsonrpc": "2.0", "id": id, "method": method });
  if !params.is_null() && !params.as_object().map(|o| o.is_empty()).unwrap_or(true) {
    body
      .as_object_mut()
      .unwrap()
      .insert("params".to_string(), params.clone());
  }
  let r = client
    .post(&url)
    .json(&body)
    .send()
    .await
    .map_err(|e| e.to_string())?;
  if !r.status().is_success() {
    return Err(format!("HTTP {}", r.status()));
  }
  r.json().await.map_err(|e| e.to_string())
}
