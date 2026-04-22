use crate::backend_state::WalletBackendState;
use crate::gateway_emit::emit_receive;
use crate::wallet_list_fs::list_wallet_files;
use serde_json::{json, Value};
use tauri::AppHandle;

/// Obsługa `module == "wallet"` — podzbiór `wallet-rpc.js::handle` (lista z FS, reszta przez JSON-RPC, jeśli jest klient).
pub async fn handle_wallet (
  app: &AppHandle,
  st: &mut WalletBackendState,
  method: &str,
  data: &Value,
) -> Result<Value, String> {
  let p = data;
  match method {
    "list_wallets" => {
      if let Some(dir) = crate::arqma_paths_config::wallet_files_dir(&st.config_data) {
        let w = list_wallet_files(&dir)?;
        emit_receive(app, "wallet_list", w)?;
      } else {
        emit_receive(
          app,
          "wallet_list",
          json!({ "list": [], "directories": [] }),
        )?;
      }
    }
    "has_password" => {
      // W Electron `hasPassword` sprawdza lokalne pliki — uproszczenie: false.
      let _ = p;
      emit_receive(app, "set_password_status", json!({ "has": false }))?;
    }
    "copy_old_gui_wallets" => {
      emit_receive(
        app,
        "set_old_gui_import_status",
        json!({ "code": 1, "failed_wallets": [] }),
      )?;
      let list = p
        .get("wallets")
        .and_then(|x| x.as_array())
        .map(|a| a.as_slice())
        .unwrap_or(&[]);
      let failed = crate::wallet_copy_old_gui::run_copy_old_gui_wallets(&st.config_data, list)?;
      emit_receive(
        app,
        "set_old_gui_import_status",
        json!({ "code": 0, "failed_wallets": failed }),
      )?;
      if let Some(dir) = crate::arqma_paths_config::wallet_files_dir(&st.config_data) {
        let w = list_wallet_files(&dir)?;
        emit_receive(app, "wallet_list", w)?;
      }
    }
    "validate_address" | "open_wallet" | "close_wallet" | "create_wallet" | "restore_wallet"
    | "restore_view_wallet" | "import_wallet" | "stake" | "relay_stake" | "relay_sweepAll"
    | "sweepAll" | "cancelTransaction" | "register_service_node" | "transfer" | "relay_transfer"
    | "add_address_book" | "delete_address_book" | "save_tx_notes" | "rescan_blockchain"
    | "rescan_spent" | "get_private_keys" | "export_key_images" | "import_key_images"
    | "change_wallet_password" | "delete_wallet" | "export_transactions" | "get_coin_price"
    | "begin_Stake_Acquisition" | "end_Stake_Acquisition" | "unsubscribe_for_signature_data"
    | "remove_signature_data" => {
      let w = st
        .wallet
        .as_ref()
        .ok_or_else(|| "Brak lokalnego arqma-wallet-rpc (dodaj bin do resource/bin albo skonfiguruj węzeł).".to_string())?;
      let (rpc, params) = map_wallet_rpc(method, p)?;
      let r = w.call(&rpc, &params).await?;
      if r.get("error").is_some() {
        emit_receive(
          app,
          "set_wallet_error",
          json!({ "status": r.get("error").cloned().unwrap_or(Value::Null) }),
        )?;
        return Ok(Value::Null);
      }
      // Dla kilku akcji front oczekuje dodatkowych zdarzeń — na razie tylko sukces RPC.
      if method == "open_wallet" {
        let name = p
          .get("name")
          .or_else(|| p.get("filename"))
          .and_then(|n| n.as_str())
          .unwrap_or("");
        emit_receive(app, "reset_wallet_error", json!({}))?;
        emit_receive(
          app,
          "reset_wallet_status",
          json!({ "code": 0, "message": "OK" }),
        )?;
        if let Ok(h) = w.call("getheight", &json!({})).await {
          if let Some(height) = h
            .get("result")
            .and_then(|x| x.get("height"))
            .or_else(|| h.pointer("/result/height"))
          {
            emit_receive(
              app,
              "set_wallet_info",
              json!({ "name": name, "height": height }),
            )?;
          }
        }
      }
    }
    _ => {
      eprintln!("[wallet] nieobsługiwane: {method}");
    }
  }
  Ok(Value::Null)
}

/// Mapa front → JSON-RPC (nazwa metody, parametry).
fn map_wallet_rpc (method: &str, p: &Value) -> Result<(String, Value), String> {
  let v = |s: &str, x: Value| (s.to_string(), x);
  match method {
    "validate_address" => Ok(v("validate_address", json!({ "address": p.get("address") }))),
    "open_wallet" => {
      let filename = p
        .get("name")
        .or_else(|| p.get("filename"))
        .and_then(|a| a.as_str())
        .ok_or("open_wallet: name")?
        .to_string();
      let password = p
        .get("password")
        .and_then(|x| x.as_str())
        .ok_or("open_wallet: password")?
        .to_string();
      Ok(v(
        "open_wallet",
        json!({ "filename": filename, "password": password }),
      ))
    }
    "close_wallet" => Ok(v("close_wallet", json!({}))),
    "create_wallet" => {
      let name = p.get("name").and_then(|x| x.as_str()).ok_or("name")?.to_string();
      let password = p.get("password").and_then(|x| x.as_str()).ok_or("password")?.to_string();
      let language = p.get("language").and_then(|x| x.as_str()).unwrap_or("English");
      Ok(v(
        "create_wallet",
        json!({ "filename": name, "password": password, "language": language }),
      ))
    }
    "restore_wallet" | "restore_view_wallet" | "import_wallet" | "stake" | "relay_stake"
    | "sweepAll" | "register_service_node" | "transfer" | "add_address_book" | "delete_address_book"
    | "save_tx_notes" | "get_private_keys" | "export_key_images" | "import_key_images"
    | "change_wallet_password" | "delete_wallet" | "export_transactions" => {
      Ok((wallet_rpc_method_name(method), p.clone()))
    }
    "rescan_blockchain" => Ok(v("rescan_blockchain", json!({}))),
    "rescan_spent" => Ok(v("rescan_spent", json!({}))),
    "relay_sweepAll" | "cancelTransaction" | "relay_transfer" | "get_coin_price"
    | "begin_Stake_Acquisition" | "end_Stake_Acquisition" | "unsubscribe_for_signature_data"
    | "remove_signature_data" => Err(format!("{method}: wymaga pełnej logiki (jeszcze nie)")),
    _ => Err(format!("niewspierany wallet.method: {method}"))
  }
}

/// Nazwa `method` w JSON-RPC (Monero/Arqma).
fn wallet_rpc_method_name (m: &str) -> String {
  match m {
    "sweepAll" => "sweep_all".to_string(),
    _ => m.to_string()
  }
}
