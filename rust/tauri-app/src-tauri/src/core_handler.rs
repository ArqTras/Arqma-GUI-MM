use crate::backend_state::WalletBackendState;
use crate::gateway_emit::emit_receive;
use crate::startup_run::run_core_startup;
use arqma_wallet_core::validate::validate_config_against_defaults;
use arqma_wallet_core::{default_paths, merge_json, remotes_path, write_config_file};
use base64::Engine;
use reqwest::Client;
use serde::Deserialize;
use serde_json::{json, Value};
use std::fs;
use std::path::Path;
use tauri::AppHandle;
use tokio::sync::OwnedSemaphorePermit;

/// Handles `module == "core"` in `Backend.handle` (IPC like Node: init, config, URL, SVG/PNG export, explorer).
///
/// For `save_config_init`, `backend_send` acquires [`crate::AppData::wallet_rpc_lane`] first and passes
/// [`Some`] as `_rpc_lane_shutdown` so [`WalletBackendState::shutdown_subprocesses_async`] can call `store`/`stop_wallet` exclusively.
pub async fn handle_core (
  app: &AppHandle,
  st: &mut WalletBackendState,
  method: &str,
  data: &Value,
  http: &Client,
  // When Some (save_config_init from backend_send): exclusive wallet RPC lane during subprocess shutdown.
  _rpc_lane_shutdown: Option<OwnedSemaphorePermit>,
) -> Result<Value, String> {
  let params = data;
  match method {
    "init" => {
      if st.startup_seq_done {
        return Ok(Value::Null);
      }
      run_core_startup(app, st, http).await?;
    }
    "set_daysOfTransactions" => {
      let n = params.get("daysOfTransactions").cloned().unwrap_or(json!(1));
      st.config_data = merge_json(
        &st.config_data,
        &json!({ "app": { "daysOfTransactions": n } }),
      );
    }
    "set_inactivityTimeout" => {
      let n = params.get("inactivityTimeout").cloned().unwrap_or(json!(5));
      st.config_data = merge_json(
        &st.config_data,
        &json!({ "app": { "inactivityTimeout": n } }),
      );
    }
    "change_remotes" => {
      st.remotes = params.clone();
      let rpath = remotes_path(Path::new(&st.paths.config_dir));
      fs::write(
        &rpath,
        serde_json::to_string_pretty(params).map_err(|e| e.to_string())?,
      )
      .map_err(|e| e.to_string())?;
      emit_receive(
        app,
        "set_app_data",
        json!({ "remotes": st.remotes }),
      )?;
    }
    "change_ethereum" => {
      let e = st
        .config_data
        .get("ethereum")
        .cloned()
        .unwrap_or_else(|| json!({}));
      let merged = merge_json(&e, params);
      st.config_data = merge_json(
        &st.config_data,
        &json!({ "ethereum": merged }),
      );
      st.ethereum = st
        .config_data
        .get("ethereum")
        .cloned()
        .unwrap_or_else(|| json!({}));
      emit_receive(app, "set_ethereum_data", st.ethereum.clone())?;
    }
    "change_scan" => {
      st.config_data = merge_json(
        &st.config_data,
        &json!({ "app": { "scan": params } }),
      );
      emit_receive(app, "set_app_data", json!({ "scan": params }))?;
    }
    "quick_save_config" => {
      st.config_data = merge_json(
        &st.config_data,
        &json!({
          "ethereum": merge_json(
            st.config_data.get("ethereum").unwrap_or(&json!({})),
            params,
          )
        }),
      );
      st.ethereum = st
        .config_data
        .get("ethereum")
        .cloned()
        .unwrap();
      write_config_file(&st.paths, &st.config_data).map_err(|e| e.to_string())?;
      emit_receive(
        app,
        "set_app_data",
        json!({ "config": params, "pending_config": params }),
      )?;
    }
    "save_config" => {
      maybe_push_mainnet_remote_to_disk(st, params)?;
      let old = st.config_data.clone();
      st.config_data = merge_json(&st.config_data, params);
      st.ethereum = st
        .config_data
        .get("ethereum")
        .cloned()
        .unwrap_or_else(|| json!({}));
      st.config_data = validate_config_against_defaults(&st.config_data, &st.defaults);
      let config_changed = serde_json::to_string(&old)
        .ok()
        .as_ref()
        .zip(serde_json::to_string(&st.config_data).ok().as_ref())
        .map(|(a, b)| a != b)
        .unwrap_or(true);
      write_config_file(&st.paths, &st.config_data).map_err(|e| e.to_string())?;
      emit_receive(
        app,
        "set_app_data",
        json!({
          "config": st.config_data,
          "pending_config": st.config_data
        }),
      )?;
      if config_changed {
        emit_receive(app, "settings_changed_reboot", json!({}))?;
      }
    }
    "save_config_init" => {
      maybe_push_mainnet_remote_to_disk(st, params)?;
      st.config_data = merge_json(&st.config_data, params);
      st.ethereum = st
        .config_data
        .get("ethereum")
        .cloned()
        .unwrap_or_else(|| json!({}));
      st.config_data = validate_config_against_defaults(&st.config_data, &st.defaults);
      if let Some(pool) = st.config_data.get_mut("pool") {
        crate::solo_pool::strip_legacy_uniform_pool_option(pool);
      }
      write_config_file(&st.paths, &st.config_data).map_err(|e| e.to_string())?;
      st.shutdown_subprocesses_async(http, _rpc_lane_shutdown).await;
      st.startup_seq_done = false;
      run_core_startup(app, st, http).await?;
    }
    "save_pool_config" => {
      let net = st
        .config_data
        .get("app")
        .and_then(|a| a.get("net_type"))
        .and_then(|n| n.as_str())
        .unwrap_or("mainnet");
      let daemon_type = st
        .config_data
        .get("daemons")
        .and_then(|d| d.get(net))
        .and_then(|n| n.get("type"))
        .and_then(|t| t.as_str())
        .unwrap_or("remote")
        .to_string();
      let old_enabled = st
        .config_data
        .get("pool")
        .and_then(|p| p.get("server"))
        .and_then(|s| s.get("enabled"))
        .and_then(|e| e.as_bool())
        .unwrap_or(false);
      let merged_pool = merge_json(
        st.config_data.get("pool").unwrap_or(&json!({})),
        params,
      );
      let normalized_bind_ip = merged_pool
        .get("server")
        .and_then(|s| s.get("bindIP"))
        .and_then(|v| v.as_str())
        .unwrap_or("");
      let merged_pool = if normalized_bind_ip.is_empty() || normalized_bind_ip == "0.0.0.0" || normalized_bind_ip == "127.0.0.1" {
        merge_json(
          &merged_pool,
          &json!({ "server": { "bindIP": crate::solo_pool::preferred_bind_ip() } }),
        )
      } else {
        merged_pool
      };
      let mut merged_pool = normalize_pool_var_diff(merged_pool);
      crate::solo_pool::strip_legacy_uniform_pool_option(&mut merged_pool);
      st.config_data = merge_json(&st.config_data, &json!({ "pool": merged_pool }));
      if daemon_type == "remote" {
        st.config_data = merge_json(
          &st.config_data,
          &json!({ "pool": { "server": { "enabled": false } } }),
        );
        emit_receive(
          app,
          "show_notification",
          json!({
            "type": "warning",
            "message": "Solo pool requires local daemon mode",
            "timeout": 3500
          }),
        )?;
      }
      st.config_data = validate_config_against_defaults(&st.config_data, &st.defaults);
      write_config_file(&st.paths, &st.config_data).map_err(|e| e.to_string())?;
      emit_receive(
        app,
        "set_app_data",
        json!({
          "config": st.config_data
        }),
      )?;
      let enabled = st
        .config_data
        .get("pool")
        .and_then(|p| p.get("server"))
        .and_then(|s| s.get("enabled"))
        .and_then(|e| e.as_bool())
        .unwrap_or(false);
      let status = if !enabled {
        0
      } else if old_enabled {
        2
      } else {
        1
      };
      if enabled {
        crate::solo_pool::start(app, st);
      } else {
        crate::solo_pool::stop(st);
      }
      emit_receive(
        app,
        "set_pool_data",
        json!({
          "status": status
        }),
      )?;
    }
    "open_url" => {
      let u = params
        .get("url")
        .and_then(|x| x.as_str())
        .ok_or_else(|| "open_url: missing url".to_string())?;
      open::that(u).map_err(|e| e.to_string())?;
    }
    "open_explorer" => {
      if params.get("type").and_then(|t| t.as_str()) == Some("swap_tx_id") {
        let ex = params
          .get("explorer")
          .and_then(|e| e.as_str())
          .unwrap_or("");
        let id = params.get("id").and_then(|i| i.as_str()).unwrap_or("");
        let url = format!("{ex}{id}");
        open::that(&url).map_err(|e| e.to_string())?;
        return Ok(Value::Null);
      }
      let end = match params.get("type").and_then(|t| t.as_str()) {
        Some("tx") => "tx",
        Some("service_node") => "service_node",
        _ => return Ok(Value::Null),
      };
      let id = params
        .get("id")
        .and_then(|i| i.as_str())
        .ok_or_else(|| "open_explorer: missing id".to_string())?;
      let url = format!("https://explorer.arqma.com/{end}/{id}");
      open::that(&url).map_err(|e| e.to_string())?;
    }
    "save_svg" => {
      let title = format!(
        "Zapisz {}",
        params
          .get("type")
          .and_then(|t| t.as_str())
          .unwrap_or("plik")
      );
      let home = default_paths();
      let svg = params
        .get("svg")
        .and_then(|s| s.as_str())
        .ok_or_else(|| "save_svg: missing svg".to_string())?
        .to_string();
      let path = rfd::FileDialog::new()
        .set_title(&title)
        .add_filter("SVG", &["svg"])
        .set_file_name("arqma-qr.svg")
        .set_directory(&home.wallet_dir)
        .save_file();
      if let Some(p) = path {
        fs::write(&p, &svg).map_err(|e| e.to_string())?;
        let msg = format!(
          "{} zapisano do {}",
          params
            .get("type")
            .and_then(|t| t.as_str())
            .unwrap_or("Plik"),
          p.display()
        );
        emit_receive(
          app,
          "show_notification",
          json!({ "type": "positive", "message": msg, "timeout": 3000 }),
        )?;
      }
    }
    "save_png" => {
      let title = format!(
        "Zapisz {}",
        params
          .get("type")
          .and_then(|t| t.as_str())
          .unwrap_or("Identicon")
      );
      let img = params
        .get("img")
        .and_then(|i| i.as_str())
        .ok_or_else(|| "save_png: missing img".to_string())?;
      let b64 = img
        .strip_prefix("data:image/png;base64,")
        .or_else(|| img.strip_prefix("data:image/png;base64;"))
        .unwrap_or(img);
      let bytes = base64::engine::general_purpose::STANDARD
        .decode(b64.trim())
        .map_err(|e| format!("save_png: base64: {e}"))?;
      let home = default_paths();
      let path = rfd::FileDialog::new()
        .set_title(&title)
        .add_filter("PNG", &["png"])
        .set_file_name("arqma-identicon.png")
        .set_directory(&home.wallet_dir)
        .save_file();
      if let Some(p) = path {
        fs::write(&p, &bytes).map_err(|e| e.to_string())?;
        let msg = format!(
          "{} zapisano do {}",
          params
            .get("type")
            .and_then(|t| t.as_str())
            .unwrap_or("Plik"),
          p.display()
        );
        emit_receive(
          app,
          "show_notification",
          json!({ "type": "positive", "message": msg, "timeout": 3000 }),
        )?;
      }
    }
    _ => {
      eprintln!("[core] unsupported method: {method}");
    }
  }
  Ok(Value::Null)
}

fn empty_data () -> Value {
  json!({})
}

fn normalize_pool_var_diff (pool: Value) -> Value {
  let vd = pool
    .get("varDiff")
    .cloned()
    .unwrap_or_else(|| json!({}));
  let start = vd
    .get("startDiff")
    .and_then(|v| v.as_u64())
    .unwrap_or(150_000)
    .clamp(1000, 100_000_000);
  let mut min_d = vd
    .get("minDiff")
    .and_then(|v| v.as_u64())
    .unwrap_or(150_000)
    .clamp(1, 100_000_000);
  let mut max_d = vd
    .get("maxDiff")
    .and_then(|v| v.as_u64())
    .unwrap_or(10_000_000)
    .clamp(1, 100_000_000);
  if min_d > max_d {
    std::mem::swap(&mut min_d, &mut max_d);
  }
  let start = start.clamp(min_d, max_d);
  let target = vd.get("targetTime").and_then(|v| v.as_u64()).unwrap_or(20).clamp(5, 600);
  let retarget = vd.get("retargetTime").and_then(|v| v.as_u64()).unwrap_or(30).clamp(1, 3600);
  let variance = vd.get("variancePercent").and_then(|v| v.as_u64()).unwrap_or(25).clamp(1, 95);
  let jump = vd.get("maxJump").and_then(|v| v.as_u64()).unwrap_or(200).clamp(1, 10_000);
  merge_json(
    &pool,
    &json!({
      "varDiff": {
        "enabled": true,
        "startDiff": start,
        "minDiff": min_d,
        "maxDiff": max_d,
        "targetTime": target,
        "retargetTime": retarget,
        "variancePercent": variance,
        "maxJump": jump
      }
    }),
  )
}

/// New remote `mainnet` node → append to `remotes.json` (as in `backend.js` on `save_config`).
fn maybe_push_mainnet_remote_to_disk (
  st: &mut WalletBackendState,
  params: &Value,
) -> Result<(), String> {
  let Some(host) = params
    .get("daemons")
    .and_then(|d| d.get("mainnet"))
    .and_then(|m| m.get("remote_host"))
    .and_then(|h| h.as_str())
  else {
    return Ok(());
  };
  let port = params
    .get("daemons")
    .and_then(|d| d.get("mainnet"))
    .and_then(|m| m.get("remote_port"))
    .and_then(|p| p.as_u64())
    .unwrap_or(19_994);
  let arr = st
    .remotes
    .as_array_mut()
    .ok_or_else(|| "remotes: oczekiwano tablicy".to_string())?;
  let exists = arr.iter().any(|n| {
    n.get("host").and_then(|h| h.as_str()) == Some(host)
      && n.get("port").and_then(|p| p.as_u64()) == Some(port)
  });
  if exists {
    return Ok(());
  }
  arr.push(json!({ "host": host, "port": port }));
  let rpath = remotes_path(Path::new(&st.paths.config_dir));
  fs::write(
    &rpath,
    serde_json::to_string_pretty(&st.remotes).map_err(|e| e.to_string())?,
  )
  .map_err(|e| e.to_string())?;
  Ok(())
}

/// Payload for `invoke("backend_send", { message: ... })` from the frontend.
#[derive(Deserialize)]
pub struct IpcMessage {
  pub module: String,
  pub method: String,
  #[serde(default = "empty_data")]
  pub data: Value,
}
