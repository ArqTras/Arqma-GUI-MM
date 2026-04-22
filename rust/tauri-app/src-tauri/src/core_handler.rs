use crate::backend_state::WalletBackendState;
use crate::gateway_emit::emit_receive;
use crate::startup_run::run_core_startup;
use reqwest::Client;
use arqma_wallet_core::{default_paths, merge_json, remotes_path, write_config_file};
use serde::Deserialize;
use serde_json::{json, Value};
use std::fs;
use std::path::Path;
use tauri::AppHandle;

/// Obsługa `module == "core"` w `Backend.handle` (uproszczona; dalej: pełne `save_config` jak w Node).
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
    "save_config" | "save_config_init" => {
      st.config_data = merge_json(&st.config_data, params);
      st.ethereum = st
        .config_data
        .get("ethereum")
        .cloned()
        .unwrap_or_else(|| json!({}));
      write_config_file(&st.paths, &st.config_data).map_err(|e| e.to_string())?;
      emit_receive(
        app,
        "set_app_data",
        json!({
          "config": st.config_data,
          "pending_config": st.config_data
        }),
      )?;
    }
    "open_url" => {
      let u = params
        .get("url")
        .and_then(|x| x.as_str())
        .ok_or_else(|| "open_url: brak url".to_string())?;
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
        .ok_or_else(|| "open_explorer: brak id".to_string())?;
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
        .ok_or_else(|| "save_svg: brak svg".to_string())?
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
    _ => {}
  }
  Ok(Value::Null)
}

fn empty_data () -> Value {
  json!({})
}

/// Argument `invoke("backend_send", { message: ... })` z frontu.
#[derive(Deserialize)]
pub struct IpcMessage {
  pub module: String,
  pub method: String,
  #[serde(default = "empty_data")]
  pub data: Value,
}
