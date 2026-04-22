use crate::backend_state::WalletBackendState;
use crate::gateway_emit::emit_receive;
use crate::remote_scan::pick_fastest_remote;
use crate::wallet_list_fs::list_wallet_files;
use crate::wallet_process::try_start_wallet_rpc;
use arqma_wallet_core::{
  default_ethereum, ensure_datadir_layout, load_config_snapshot, required_dirs_exist, write_config_file
};
use reqwest::Client;
use serde_json::{json, Value};
use tauri::AppHandle;

/// Pełna sekwencja `Backend.startup()` (stub kroków 3–7, potem ewent. spawn `arqma-wallet-rpc` i lista plików).
pub async fn run_core_startup (app: &AppHandle, st: &mut WalletBackendState, http: &Client) -> Result<(), String> {
  let snap = load_config_snapshot(&st.paths).map_err(|e| e.to_string())?;
  st.defaults = snap.defaults.clone();
  st.config_data = snap.config_data.clone();
  st.remotes = snap.remotes.clone();
  st.ethereum = snap.ethereum.clone();

  emit_receive(
    app,
    "set_app_data",
    json!({ "remotes": snap.remotes, "defaults": snap.defaults }),
  )?;
  emit_receive(app, "set_ethereum_data", st.ethereum.clone())?;

  if !snap.had_config_file {
    emit_receive(
      app,
      "set_app_data",
      json!({
        "status": { "code": -1 },
        "config": st.config_data,
        "pending_config": st.config_data
      }),
    )?;
    st.startup_seq_done = true;
    return Ok(());
  }

  apply_scan_and_remote(&mut st.config_data, &st.remotes).await;
  st.ethereum = st
    .config_data
    .get("ethereum")
    .cloned()
    .unwrap_or_else(default_ethereum);
  write_config_file(&st.paths, &st.config_data).map_err(|e| e.to_string())?;

  let selected = selected_node_string(&st.config_data);
  emit_receive(
    app,
    "set_app_data",
    json!({
      "config": st.config_data,
      "pending_config": st.config_data,
      "selected_node": selected
    }),
  )?;
  emit_receive(app, "set_ethereum_data", st.ethereum.clone())?;

  if let Err(msg) = required_dirs_exist(&st.config_data) {
    emit_show_notification(app, "negative", &msg)?;
    emit_receive(app, "set_app_data", json!({ "status": { "code": -1 } }))?;
    st.startup_seq_done = true;
    return Ok(());
  }

  ensure_datadir_layout(&st.config_data).map_err(|e| e.to_string())?;

  // Stub (bez subprocessów): odtwarzanie kodów `status` z oryginalnego `startup`.
  emit_receive(app, "set_app_data", json!({ "status": { "code": 3 } }))?;
  emit_receive(
    app,
    "set_app_data",
    json!({ "status": { "code": 4, "message": "tauri-stub" } }),
  )?;
  emit_receive(
    app,
    "set_app_data",
    json!({
      "status": { "code": 5 },
      "config": st.config_data,
      "pending_config": st.config_data
    }),
  )?;
  emit_receive(app, "set_app_data", json!({ "status": { "code": 6 } }))?;
  emit_receive(app, "set_app_data", json!({ "status": { "code": 7 } }))?;
  let wallets = if let Some(dir) = crate::arqma_paths_config::wallet_files_dir(&st.config_data) {
    list_wallet_files(&dir).unwrap_or_else(|e| {
      eprintln!("[wallet_list_fs] {e}");
      json!({ "list": [], "directories": [] })
    })
  } else {
    json!({ "list": [], "directories": [] })
  };
  try_start_wallet_rpc(app, st, http).await;
  emit_receive(app, "wallet_list", wallets.clone())?;
  emit_receive(app, "set_app_data", json!({ "status": { "code": 0 } }))?;

  st.startup_seq_done = true;
  Ok(())
}

fn emit_show_notification (app: &AppHandle, kind: &str, message: &str) -> Result<(), String> {
  emit_receive(
    app,
    "show_notification",
    json!({ "type": kind, "message": message, "timeout": 3000 }),
  )
}

fn selected_node_string (config_data: &Value) -> String {
  let a = config_data
    .get("app")
    .and_then(|a| a.get("net_type"))
    .and_then(|n| n.as_str())
    .unwrap_or("mainnet");
  if let (Some(h), Some(p)) = (
    config_data
      .get("daemons")
      .and_then(|d| d.get(a))
      .and_then(|m| m.get("remote_host"))
      .and_then(|h| h.as_str()),
    config_data
      .get("daemons")
      .and_then(|d| d.get(a))
      .and_then(|m| m.get("remote_port"))
      .and_then(|p| p.as_u64()),
  ) {
    format!("{h}:{p}")
  } else {
    String::new()
  }
}

async fn apply_scan_and_remote (config_data: &mut Value, remotes: &Value) {
  let scan = config_data
    .get("app")
    .and_then(|a| a.get("scan"))
    .and_then(|s| s.as_bool())
    .unwrap_or(false);
  let is_local = config_data
    .get("daemons")
    .and_then(|d| d.get("mainnet"))
    .and_then(|m| m.get("type"))
    .and_then(|t| t.as_str())
    == Some("local");
  if is_local {
    return;
  }
  let list: Vec<(String, u16)> = remotes
    .as_array()
    .map(|a| {
      a.iter()
        .filter_map(|n| {
          let h = n.get("host")?.as_str()?.to_string();
          let p = n.get("port")?.as_u64()? as u16;
          Some((h, p))
        })
        .collect()
    })
    .unwrap_or_default();
  if let Some((h, p)) = pick_fastest_remote(&list, scan).await {
    if let Some(dm) = config_data
      .get_mut("daemons")
      .and_then(|d| d.get_mut("mainnet"))
    {
      if let Some(o) = dm.as_object_mut() {
        o.insert("remote_host".into(), json!(h));
        o.insert("remote_port".into(), json!(p));
      }
    }
  }
}
