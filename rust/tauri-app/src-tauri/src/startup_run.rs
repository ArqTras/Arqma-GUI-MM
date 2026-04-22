use crate::backend_state::WalletBackendState;
use crate::daemon_check::{check_daemon_reachable, RemoteNodeIssue};
use crate::daemon_handler::arqmad_version_probe_str;
use crate::daemon_process::{ensure_daemon_for_startup, set_current_net_to_remote};
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

/// Sekwencja startu (`Backend.startup` w Node): config, węzeł, `daemon_heartbeat`, opcjonalnie `arqma-wallet-rpc`, lista portfeli.
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

  let net = st
    .config_data
    .get("app")
    .and_then(|a| a.get("net_type"))
    .and_then(|n| n.as_str())
    .unwrap_or("mainnet")
    .to_string();
  let daemon_typ = st
    .config_data
    .get("daemons")
    .and_then(|d| d.get(&net))
    .and_then(|x| x.get("type"))
    .and_then(|t| t.as_str())
    .unwrap_or("remote")
    .to_string();

  emit_receive(app, "set_app_data", json!({ "status": { "code": 3 } }))?;

  match check_daemon_reachable(http, &st.config_data).await {
    Ok(()) => {}
    Err(RemoteNodeIssue::NetMismatch) => {
      emit_show_notification(
        app,
        "negative",
        "Error: Remote node is using a different nettype",
      )?;
      emit_receive(app, "set_app_data", json!({ "status": { "code": -1 } }))?;
      st.startup_seq_done = true;
      return Ok(());
    }
    Err(RemoteNodeIssue::Inaccessible) => {
      if daemon_typ == "local_remote" {
        if let Some(dm) = st.config_data.get_mut("daemons").and_then(|d| d.get_mut(&net)) {
          if let Some(o) = dm.as_object_mut() {
            o.insert("type".into(), json!("local"));
          }
        }
        write_config_file(&st.paths, &st.config_data).map_err(|e| e.to_string())?;
        emit_receive(
          app,
          "show_notification",
          json!({
            "type": "warning",
            "textColor": "black",
            "message": "Warning: Could not access remote node, switching to local only",
            "timeout": 3000
          }),
        )?;
        emit_receive(
          app,
          "set_app_data",
          json!({ "config": st.config_data, "pending_config": st.config_data }),
        )?;
      } else {
        emit_show_notification(
          app,
          "negative",
          "Error: Could not access remote node, please try another remote node",
        )?;
        emit_receive(app, "set_app_data", json!({ "status": { "code": -1 } }))?;
        st.startup_seq_done = true;
        return Ok(());
      }
    }
  }

  let ver = arqmad_version_probe_str(app);
  if ver != "unknown" {
    emit_receive(
      app,
      "set_app_data",
      json!({ "status": { "code": 4, "message": ver } }),
    )?;
  } else {
    set_current_net_to_remote(st);
    emit_receive(
      app,
      "set_app_data",
      json!({
        "status": { "code": 5 },
        "config": st.config_data,
        "pending_config": st.config_data
      }),
    )?;
  }

  if let Err(e) = ensure_daemon_for_startup(app, st, http).await {
    eprintln!("[startup] daemon: {e}");
    let is_remote = st
      .config_data
      .get("daemons")
      .and_then(|d| d.get(&net))
      .and_then(|x| x.get("type"))
      .and_then(|t| t.as_str())
      == Some("remote");
    let msg = if is_remote {
      "Remote daemon can not be reached"
    } else {
      "Local daemon internal error"
    };
    emit_show_notification(app, "negative", msg)?;
    emit_receive(app, "set_app_data", json!({ "status": { "code": -1 } }))?;
    st.startup_seq_done = true;
    return Ok(());
  }

  let is_local = daemon_typ != "remote";
  crate::daemon_heartbeat::start(app, st, is_local, http);

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
