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

/// Handles `module == "core"` in `Backend.handle` (IPC like Node: init, config, URL, SVG/PNG export, explorer).
pub async fn handle_core (
  app: &AppHandle,
  st: &mut WalletBackendState,
  method: &str,
  data: &Value,
  http: &Client,
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
      write_config_file(&st.paths, &st.config_data).map_err(|e| e.to_string())?;
      st.shutdown_subprocesses();
      st.startup_seq_done = false;
      run_core_startup(app, st, http).await?;
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
