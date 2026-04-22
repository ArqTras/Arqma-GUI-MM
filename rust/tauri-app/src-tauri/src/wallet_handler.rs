use crate::backend_state::WalletBackendState;
use crate::gateway_emit::emit_receive;
use crate::wallet_list_fs::list_wallet_files;
use reqwest::Client;
use serde_json::{json, Value};
use tauri::AppHandle;

/// When `arqma-wallet-rpc` is not running (missing bundled binary / no remote setup).
const ERR_NO_LOCAL_WALLET_RPC: &str =
  "No local arqma-wallet-rpc: add binaries under resource/bin or configure a remote node.";

/// Handles `module == "wallet"` — subset of `wallet-rpc.js::handle` (FS list, rest via JSON-RPC when a client exists).
pub async fn handle_wallet (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &Client,
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
      // Same as `hasPassword` in `wallet-rpc.js` (event: `set_has_password`, bool).
      if st.wallet_password_hash_hex.is_none() {
        emit_receive(app, "set_has_password", json!(false))?;
        return Ok(Value::Null);
      }
      let prompt = st
        .config_data
        .get("app")
        .and_then(|a| a.get("promptForPassword"))
        .and_then(|v| v.as_bool())
        == Some(true);
      if !prompt {
        emit_receive(app, "set_has_password", json!(true))?;
        return Ok(Value::Null);
      }
      if st.wallet_salt.is_empty() {
        emit_receive(app, "set_has_password", json!(false))?;
        return Ok(Value::Null);
      }
      let stored = st
        .wallet_password_hash_hex
        .as_deref()
        .unwrap_or("");
      let empty_h = match crate::wallet_password::pbkdf2_password_hex("", &st.wallet_salt) {
        Ok(s) => s,
        Err(_) => {
          emit_receive(app, "set_has_password", json!(false))?;
          return Ok(Value::Null);
        }
      };
      let same_as_empty = stored == empty_h.as_str();
      emit_receive(app, "set_has_password", json!(same_as_empty))?;
      return Ok(Value::Null);
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
    "get_coin_price" => {
      crate::wallet_relay_ops::get_coin_and_conversion(app, http).await;
    }
    "cancelTransaction" => {
      crate::wallet_relay_ops::cancel_transaction(st, p);
    }
    "unsubscribe_for_signature_data" => {
      emit_receive(app, "set_signature_data", json!([]))?;
    }
    "subscribe_for_signature_data" => {
      eprintln!("[wallet] subscribe_for_signature_data: no ZMQ (commented out in Node — no-op in Tauri)");
    }
    "remove_signature_data" => {
      eprintln!("[wallet] remove_signature_data: no ZMQ channel (same as Node — no-op in Tauri)");
    }
    "cancel_stake" => {}
    "relay_sweepAll" => {
      let w = st
        .wallet
        .as_ref()
        .map(|c| c.fork_for_heartbeat())
        .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
      crate::wallet_relay_ops::relay_sweep_all(app, st, &w, p).await;
    }
    "relay_transfer" => {
      let w = st
        .wallet
        .as_ref()
        .map(|c| c.fork_for_heartbeat())
        .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
      crate::wallet_relay_ops::relay_transfer(app, st, &w).await;
    }
    "relay_stake" => {
      let w = st
        .wallet
        .as_ref()
        .map(|c| c.fork_for_heartbeat())
        .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
      crate::wallet_relay_ops::relay_stake(app, st, &w, p).await;
    }
    "begin_Stake_Acquisition" => {
      crate::wallet_pools::start_stake_acquisition(app, st, http);
    }
    "end_Stake_Acquisition" => {
      crate::wallet_pools::end_stake_acquisition(st);
    }
    "unlock_stake" => {
      let w = st
        .wallet
        .as_ref()
        .map(|c| c.fork_for_heartbeat())
        .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
      unlock_stake(app, st, &w, p).await?;
    }
    "sweepAll" => {
      wallet_sweep_all(app, st, p).await?;
    }
    "validate_address" | "open_wallet" | "close_wallet" | "create_wallet" | "restore_wallet"
    | "restore_view_wallet" | "import_wallet" | "stake" | "register_service_node"
    | "transfer" | "add_address_book" | "delete_address_book" | "save_tx_notes"
    | "rescan_blockchain" | "rescan_spent" | "get_private_keys" | "export_key_images"
    | "import_key_images" | "change_wallet_password" | "delete_wallet" | "export_transactions" => {
      let (rpc, params) = map_wallet_rpc(method, p)?;
      let r = {
        let w = st
          .wallet
          .as_ref()
          .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
        // Like `wallet-rpc.js::saveWallet` before `close_wallet` — flush wallet state to disk (e.g. switch account).
        if method == "close_wallet" {
          match w.call("store", &json!({})).await {
            Ok(ref store_r) if store_r.get("error").is_some() => {
              eprintln!(
                "[wallet] store before close_wallet: {:?}",
                store_r.get("error")
              );
            }
            Err(e) => eprintln!("[wallet] store before close_wallet: {e}"),
            _ => {}
          }
        }
        w.call(&rpc, &params).await?
      };
      if r.get("error").is_some() {
        let err = r.get("error").cloned().unwrap_or(Value::Null);
        emit_receive(app, "set_wallet_error", json!({ "status": err.clone() }))?;
        let rpc_msg_capitalized = || {
          err
            .get("message")
            .and_then(|m| m.as_str())
            .map(|s| {
              let mut c = s.chars();
              match c.next() {
                None => s.to_string(),
                Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
              }
            })
            .unwrap_or_else(|| "Unknown error".to_string())
        };
        if method == "transfer" {
          let msg = rpc_msg_capitalized();
          emit_receive(
            app,
            "set_tx_status",
            json!({ "code": -200, "message": msg, "sending": false }),
          )?;
        }
        return Ok(Value::Null);
      }
      if method == "transfer" {
        crate::wallet_relay_ops::push_transfer_metadata(st, p, &r);
        if let Some(res) = r.get("result") {
          let fee_msg = res
            .get("fee_list")
            .and_then(|fl| fl.as_array())
            .and_then(|a| a.first())
            .and_then(|v| {
              v.as_u64()
                .or_else(|| v.as_i64().filter(|&i| i >= 0).map(|i| i as u64))
                .or_else(|| v.as_f64().map(|f| f as u64))
            })
            .map(|atoms| {
              let fee_ui = atoms as f64 / crate::wallet_relay_ops::COIN_UNITS;
              format!("Fee {fee_ui:.9}")
            })
            .unwrap_or_else(|| "Fee".to_string());
          emit_receive(
            app,
            "set_tx_status",
            json!({ "code": 200, "message": fee_msg, "sending": false }),
          )?;
        } else {
          emit_receive(
            app,
            "set_tx_status",
            json!({
              "code": -200,
              "message": "No result from transfer_split",
              "sending": false
            }),
          )?;
        }
      } else if method == "stake" {
        crate::wallet_relay_ops::push_stake_metadata(st, p, &r);
      } else if method == "change_wallet_password" {
        if !st.wallet_salt.is_empty() {
          if let Some(np) = p.get("new_password").and_then(|x| x.as_str()) {
            if let Ok(h) = crate::wallet_password::pbkdf2_password_hex(np, &st.wallet_salt) {
              st.wallet_password_hash_hex = Some(h);
            }
          }
        }
      }
      // Some actions expect extra gateway events from the backend.
      if method == "open_wallet" {
        let w = st
          .wallet
          .as_ref()
          .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
        if !st.wallet_salt.is_empty() {
          if let Some(pass) = p.get("password").and_then(|x| x.as_str()) {
            if let Ok(h) = crate::wallet_password::pbkdf2_password_hex(pass, &st.wallet_salt) {
              st.wallet_password_hash_hex = Some(h);
            }
          }
        }
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
        st.wh_display_name = name.to_string();
        st.wh_stored_height = 0;
        st.wh_stored_balance = 0;
        st.wh_stored_unlocked = 0;
        crate::wallet_heartbeat::start(app, st, is_local_net(st));
      } else if matches!(
        method,
        "create_wallet" | "restore_wallet" | "import_wallet" | "restore_view_wallet"
      ) {
        if !st.wallet_salt.is_empty() {
          if let Some(pass) = p.get("password").and_then(|x| x.as_str()) {
            if let Ok(h) = crate::wallet_password::pbkdf2_password_hex(pass, &st.wallet_salt) {
              st.wallet_password_hash_hex = Some(h);
            }
          }
        }
        let wname = p
          .get("name")
          .or_else(|| p.get("filename"))
          .and_then(|n| n.as_str())
          .unwrap_or("");
        st.wh_display_name = wname.to_string();
        st.wh_stored_height = 0;
        st.wh_stored_balance = 0;
        st.wh_stored_unlocked = 0;
        crate::wallet_heartbeat::start(app, st, is_local_net(st));
      } else if method == "close_wallet" {
        st.wallet_password_hash_hex = None;
        st.wh_display_name.clear();
        crate::wallet_heartbeat::stop(st);
      }
    }
    _ => {
      eprintln!("[wallet] unsupported method: {method}");
    }
  }
  Ok(Value::Null)
}

/// `wallet-rpc.js::sweepAll` — first `get_address`, then `sweep_all` with `address` (frontend only sends password / do_not_relay).
async fn wallet_sweep_all (
  app: &AppHandle,
  st: &mut WalletBackendState,
  p: &Value,
) -> Result<(), String> {
  let w = st
    .wallet
    .as_ref()
    .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
  let password = p.get("password").and_then(|x| x.as_str()).unwrap_or("");
  if !st.wallet_salt.is_empty() && !wallet_password_matches(st, password) {
    let origin = p.get("origin").cloned().unwrap_or(Value::Null);
    emit_receive(
      app,
      "set_tx_status",
      json!({
        "code": -100,
        "message": "Invalid password",
        "sending": false,
        "origin": origin
      }),
    )?;
    return Ok(());
  }
  let addr_r = w
    .call("get_address", &json!({ "account_index": 0 }))
    .await?;
  if addr_r.get("error").is_some() {
    let err = addr_r.get("error").cloned().unwrap_or(Value::Null);
    emit_receive(app, "set_wallet_error", json!({ "status": err.clone() }))?;
    let msg = err
      .get("message")
      .and_then(|m| m.as_str())
      .map(|s| {
        let mut c = s.chars();
        match c.next() {
          None => s.to_string(),
          Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
        }
      })
      .unwrap_or_else(|| "Unknown error".to_string());
    let origin = p.get("origin").cloned().unwrap_or(Value::Null);
    emit_receive(
      app,
      "set_tx_status",
      json!({
        "code": -100,
        "message": msg,
        "sending": false,
        "origin": origin
      }),
    )?;
    return Ok(());
  }
  let my_address = addr_r
    .get("result")
    .and_then(|r| r.get("address"))
    .and_then(|a| a.as_str())
    .ok_or_else(|| "get_address: missing result.address".to_string())?;
  let do_not = p
    .get("do_not_relay")
    .and_then(|v| v.as_bool())
    .unwrap_or(false);
  let params = json!({
    "address": my_address,
    "account_index": 0,
    "priority": 0,
    "ring_size": 16,
    "do_not_relay": do_not,
    "get_tx_metadata": true,
    "get_tx_hex": true
  });
  let r = w.call("sweep_all", &params).await?;
  if r.get("error").is_some() {
    let err = r.get("error").cloned().unwrap_or(Value::Null);
    emit_receive(app, "set_wallet_error", json!({ "status": err.clone() }))?;
    let msg = err
      .get("message")
      .and_then(|m| m.as_str())
      .map(|s| {
        let mut c = s.chars();
        match c.next() {
          None => s.to_string(),
          Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
        }
      })
      .unwrap_or_else(|| "Unknown error".to_string());
    let origin = p.get("origin").cloned().unwrap_or(Value::Null);
    emit_receive(
      app,
      "set_tx_status",
      json!({
        "code": -100,
        "message": msg,
        "sending": false,
        "origin": origin
      }),
    )?;
    return Ok(());
  }
  crate::wallet_relay_ops::push_sweep_metadata(st, p, &r);
  let origin = p.get("origin").cloned().unwrap_or(Value::Null);
  if let Some(res) = r.get("result") {
    let sum_fees = res
      .get("fee_list")
      .and_then(|fl| fl.as_array())
      .map(|arr| {
        arr
          .iter()
          .filter_map(|v| {
            v.as_u64()
              .or_else(|| v.as_i64().filter(|&i| i >= 0).map(|i| i as u64))
              .or_else(|| v.as_f64().map(|f| f as u64))
          })
          .sum::<u64>()
      })
      .unwrap_or(0);
    let fee_ui = sum_fees as f64 / crate::wallet_relay_ops::COIN_UNITS;
    let (code, message) = if do_not {
      (99i64, format!("{fee_ui:.9}"))
    } else {
      (100i64, "sweep_all_rpc_success_message".to_string())
    };
    emit_receive(
      app,
      "set_tx_status",
      json!({
        "code": code,
        "message": message,
        "sending": false,
        "origin": origin
      }),
    )?;
  } else {
    emit_receive(
      app,
      "set_tx_status",
      json!({
        "code": -100,
        "message": "No result from sweep_all",
        "sending": false,
        "origin": origin
      }),
    )?;
  }
  Ok(())
}

/// `wallet-rpc.js::unlockStake` — `can_request_stake_unlock` / `request_stake_unlock`.
async fn unlock_stake (
  app: &AppHandle,
  st: &WalletBackendState,
  w: &crate::json_rpc_client::WalletRpcClient,
  p: &Value,
) -> Result<(), String> {
  emit_receive(
    app,
    "set_snode_status_unlock",
    json!({ "code": 0, "message": "", "sending": false }),
  )?;
  let password = p.get("password").and_then(|x| x.as_str()).unwrap_or("");
  let service_node_key = p
    .get("service_node_key")
    .and_then(|x| x.as_str())
    .unwrap_or("");
  if service_node_key.is_empty() {
    return Ok(());
  }
  if !wallet_password_matches(st, password) {
    emit_receive(
      app,
      "set_snode_status_unlock",
      json!({ "code": -400, "message": "invalidPassword", "sending": false }),
    )?;
    return Ok(());
  }
  let confirmed = p
    .get("confirmed")
    .and_then(|c| c.as_bool())
    .unwrap_or(false);
  let params = json!({ "service_node_key": service_node_key });
  let r = if confirmed {
    w.call("request_stake_unlock", &params).await?
  } else {
    w.call("can_request_stake_unlock", &params).await?
  };
  if let Some(e) = r.get("error") {
    let msg = e
      .get("message")
      .and_then(|m| m.as_str())
      .unwrap_or("Unknown error");
    emit_receive(
      app,
      "set_snode_status_unlock",
      json!({ "code": -400, "message": msg, "sending": false }),
    )?;
    return Ok(());
  }
  if confirmed {
    if let Some(res) = r.get("result") {
      if res.is_object() {
        let msg = res
          .get("msg")
          .or_else(|| res.get("message"))
          .and_then(|m| m.as_str())
          .unwrap_or("");
        let code = if res.get("unlocked").and_then(|u| u.as_bool()) == Some(true) {
          400i64
        } else {
          -400
        };
        emit_receive(
          app,
          "set_snode_status_unlock",
          json!({ "code": code, "message": msg, "sending": false }),
        )?;
        return Ok(());
      }
    }
    emit_receive(
      app,
      "set_snode_status_unlock",
      json!({ "code": -400, "message": "Unknown error", "sending": false }),
    )?;
  } else {
    let (can, msg) = r
      .get("result")
      .map(|res| {
        let can = res
          .get("can_unlock")
          .and_then(|b| b.as_bool())
          .unwrap_or(false);
        let msg = res
          .get("msg")
          .or_else(|| res.get("message"))
          .and_then(|m| m.as_str())
          .unwrap_or("");
        (can, msg.to_string())
      })
      .unwrap_or((false, String::new()));
    let code = if can { 400i64 } else { -400 };
    emit_receive(
      app,
      "set_snode_status_unlock",
      json!({ "code": code, "message": msg, "sending": false }),
    )?;
  }
  Ok(())
}

fn wallet_password_matches (st: &WalletBackendState, password: &str) -> bool {
  if st.wallet_salt.is_empty() {
    return true;
  }
  let Some(want) = st.wallet_password_hash_hex.as_deref() else {
    return false;
  };
  let Ok(got) = crate::wallet_password::pbkdf2_password_hex(password, &st.wallet_salt) else {
    return false;
  };
  got == want
}

fn is_local_net (st: &WalletBackendState) -> bool {
  let net = st
    .config_data
    .get("app")
    .and_then(|a| a.get("net_type"))
    .and_then(|n| n.as_str())
    .unwrap_or("mainnet");
  st.config_data
    .get("daemons")
    .and_then(|d| d.get(net))
    .and_then(|x| x.get("type"))
    .and_then(|t| t.as_str())
    != Some("remote")
}

/// Map frontend method → JSON-RPC (method name, params).
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
    | "register_service_node" | "transfer" | "add_address_book" | "delete_address_book"
    | "save_tx_notes" | "get_private_keys" | "export_key_images" | "import_key_images"
    | "change_wallet_password" | "delete_wallet" | "export_transactions" => {
      Ok((wallet_rpc_method_name(method), p.clone()))
    }
    "rescan_blockchain" => Ok(v("rescan_blockchain", json!({}))),
    "rescan_spent" => Ok(v("rescan_spent", json!({}))),
    _ => Err(format!("unsupported wallet.method: {method}"))
  }
}

/// JSON-RPC `method` name (Monero/Arqma stack).
fn wallet_rpc_method_name (m: &str) -> String {
  match m {
    "sweepAll" => "sweep_all".to_string(),
    "transfer" => "transfer_split".to_string(),
    _ => m.to_string()
  }
}
