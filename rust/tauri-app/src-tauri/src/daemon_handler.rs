use crate::arqma_paths_config::daemon_rpc_host_port;
use crate::backend_state::WalletBackendState;
use crate::gateway_emit::emit_receive;
use crate::json_rpc_client::daemon_post;
use crate::native_bin::find_resource_bin;
use crate::subprocess::new_child_command;
use serde_json::{json, Value};
use tauri::AppHandle;

fn next_daemon_id (st: &mut WalletBackendState) -> u64 {
  let n = st.next_rpc_id;
  st.next_rpc_id = st.next_rpc_id.saturating_add(1);
  n
}

fn arqmad_version_string (app: &AppHandle) -> Option<String> {
  let exe = find_resource_bin(app, "arqmad.exe", "arqmad")?;
  let o = new_child_command(&exe).arg("--version").output().ok()?;
  if o.status.success() {
    return Some(String::from_utf8_lossy(&o.stdout).to_string());
  }
  None
}

/// Jedna linia wersji (stdout `arqmad --version`) albo `unknown` — m.in. dla `daemon_version_probe` w Tauri.
pub fn arqmad_version_probe_str (app: &AppHandle) -> String {
  arqmad_version_string(app)
    .map(|s| s.trim().to_string())
    .filter(|s| !s.is_empty())
    .unwrap_or_else(|| "unknown".to_string())
}

pub async fn handle_daemon (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &reqwest::Client,
  method: &str,
  data: &Value,
) -> Result<Value, String> {
  let params = data;
  match method {
    "check_version" => {
      if let Some(ver) = arqmad_version_string(app) {
        emit_receive(
          app,
          "daemon_version",
          json!({ "version": ver.trim() }),
        )?;
      } else {
        emit_receive(
          app,
          "daemon_version",
          json!({ "version": false }),
        )?;
      }
    }
    "ban_peer" => {
      let host = params
        .get("host")
        .and_then(|h| h.as_str())
        .ok_or_else(|| "ban_peer: missing host".to_string())?;
      let mut seconds = params
        .get("seconds")
        .and_then(|s| s.as_u64())
        .unwrap_or(3600);
      if seconds == 0 {
        seconds = 3600;
      }
      let Some((h, p)) = daemon_rpc_host_port(&st.config_data) else {
        return Err("daemon: missing host/port for RPC in configuration".to_string());
      };
      let id = next_daemon_id(st);
      let pban = json!({ "bans": [{ "host": host, "seconds": seconds, "ban": true }] });
      let r = daemon_post(http, &h, p, "set_bans", id, &pban).await?;
      if r.get("error").is_some() || r.get("result").is_none() {
        emit_receive(
          app,
          "show_notification",
          json!({ "type": "negative", "message": "Error banning peer", "timeout": 3000 }),
        )?;
        return Ok(Value::Null);
      }
      let msg = format!("Banned {host} for {seconds} s");
      emit_receive(
        app,
        "show_notification",
        json!({ "type": "positive", "message": msg, "timeout": 3000 }),
      )?;
    }
    _ => {
      eprintln!("[daemon] unsupported method: {method}");
    }
  }
  Ok(Value::Null)
}
