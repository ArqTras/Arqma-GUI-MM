use crate::backend_state::WalletBackendState;
use crate::gateway_emit::emit_receive;
use crate::sync_debug::is_sync_debug;
use crate::wallet_list_fs::list_wallet_files;
use reqwest::Client;
use chrono::{DateTime, Utc};
use serde_json::{json, Value};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::Duration;
use tauri::AppHandle;
use tokio::time::MissedTickBehavior;

/// When `arqma-wallet-rpc` is not running (no env/PATH/bundle binary / no remote setup).
const ERR_NO_LOCAL_WALLET_RPC: &str =
  "No local arqma-wallet-rpc: set ARQMA_WALLET_RPC or ARQMA_BUILD_DIR (upstream build/release), PATH, resource/bin, or configure a remote node.";

fn open_rpc_timeout_secs () -> u64 {
  std::env::var("ARQMA_WALLET_OPEN_RPC_TIMEOUT_SECS")
    .ok()
    .and_then(|s| s.trim().parse::<u64>().ok())
    .map(|v| v.clamp(5, 300))
    .unwrap_or(90)
}

/// Parallel `getheight` / `getbalance` right after UI unblocks — must stay short so we do not hold
/// `backend` mutex while wallet-rpc is scan-busy (otherwise heartbeat cannot tick).
fn open_wallet_snapshot_rpc_secs () -> u64 {
  std::env::var("ARQMA_WALLET_OPEN_SNAPSHOT_RPC_SECS")
    .ok()
    .and_then(|s| s.trim().parse::<u64>().ok())
    .map(|v| v.clamp(5, 120))
    .unwrap_or(25)
}

fn wallet_file_probe(st: &WalletBackendState) -> Value {
  let name = st.wh_display_name.clone();
  let Some(dir) = crate::arqma_paths_config::wallet_files_dir(&st.config_data) else {
    return json!({ "wallet_name": name, "path": "", "exists": false, "reason": "wallet_dir_missing" });
  };
  if name.is_empty() {
    return json!({ "wallet_name": name, "path": "", "exists": false, "reason": "wallet_name_empty" });
  }
  let path = dir.join(&name);
  match std::fs::metadata(&path) {
    Ok(md) => {
      let modified_ms = md
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
      json!({
        "wallet_name": name,
        "path": path.to_string_lossy(),
        "exists": true,
        "readonly": md.permissions().readonly(),
        "len": md.len(),
        "modified_ms": modified_ms
      })
    }
    Err(e) => json!({
      "wallet_name": name,
      "path": path.to_string_lossy(),
      "exists": false,
      "meta_error": e.to_string()
    }),
  }
}

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
      // Primary path: `backend_send` runs this **without** `backend` mutex (several HTTP calls).
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
    "add_address_book" => {
      wallet_add_address_book(app, st, http, p).await?;
    }
    "delete_address_book" => {
      wallet_delete_address_book(app, st, http, p).await?;
    }
    "restore_wallet" => {
      wallet_restore_wallet(app, st, http, p).await?;
    }
    "restore_view_wallet" => {
      wallet_restore_view_wallet(app, st, http, p).await?;
    }
    "import_wallet" => {
      wallet_import_wallet(app, st, http, p).await?;
    }
    "stake" => {
      wallet_stake(app, st, http, p).await?;
    }
    "register_service_node" => {
      wallet_register_service_node(app, st, http, p).await?;
    }
    "save_tx_notes" => {
      wallet_save_tx_notes(app, st, http, p).await?;
    }
    "get_private_keys" => {
      wallet_get_private_keys(app, st, http, p).await?;
    }
    "export_key_images" => {
      wallet_export_key_images(app, st, http, p).await?;
    }
    "import_key_images" => {
      wallet_import_key_images(app, st, http, p).await?;
    }
    "change_wallet_password" => {
      wallet_change_wallet_password(app, st, http, p).await?;
    }
    "delete_wallet" => {
      wallet_delete_wallet(app, st, http, p).await?;
    }
    "export_transactions" => {
      wallet_export_transactions(app, st, http, p).await?;
    }
    "validate_address" | "open_wallet" | "close_wallet" | "create_wallet"
    | "save_wallet"
    | "transfer"
    | "rescan_blockchain" | "rescan_spent" => {
      if method == "open_wallet" || method == "close_wallet" {
        crate::agent_debug::log(
          "H5",
          "wallet_handler.rs:handle_wallet:pre_try_start",
          "wallet method before try_start_wallet_rpc",
          json!({
            "method": method,
            "wallet_name": p.get("name").or_else(|| p.get("filename")).and_then(|v| v.as_str()).unwrap_or(""),
            "has_wallet_client": st.wallet.is_some(),
            "has_wallet_process": st.wallet_process.is_some()
          }),
        );
      }
      // After a clean `close_wallet` the wallet-rpc child may stay running (Oxen / Electron); `try_start`
      // returns `AlreadyRunning` when process + client exist. Unclean close still kills the child.
      let start_res = crate::wallet_process::try_start_wallet_rpc(app, st, http).await;
      if method == "open_wallet" || method == "close_wallet" {
        crate::agent_debug::log(
          "H3",
          "wallet_handler.rs:handle_wallet:post_try_start",
          "wallet method after try_start_wallet_rpc",
          json!({ "method": method, "start_result": format!("{start_res:?}") }),
        );
      }
      // Stop heartbeat before holding `wallet` RPC ref — avoids borrow conflict & frees RPC during `store`.
      if method == "close_wallet" {
        crate::wallet_heartbeat::stop(st);
        // Background xfer holds `wallet_rpc_lane`; `backend_send("wallet")` acquires it before this body — waits until xfer completes.
      }
      // `try_start_wallet_rpc` clears the client on reconnect failure; still allow leaving the wallet UI.
      if method == "close_wallet" && st.wallet.is_none() {
        crate::wallet_diag::log_always(
          "close_wallet: no wallet RPC client (session already down or RPC never started) — clearing state",
        );
        st.wallet_password_hash_hex = None;
        st.wh_display_name.clear();
        crate::agent_debug::log(
          "H1",
          "wallet_handler.rs:handle_wallet:close_wallet_no_client",
          "close_wallet idempotent (no RPC)",
          json!({}),
        );
        let _ = emit_receive(
          app,
          "set_wallet_info",
          json!({
            "name": "",
            "height": 0,
            "balance": 0,
            "unlocked_balance": 0,
            "scan_poll_ts": Utc::now().timestamp_millis()
          }),
        );
        // So the next `open_wallet` can transition 1 → 0 (wallet-select `statusWatcher` ignores duplicate 0).
        let _ = emit_receive(
          app,
          "reset_wallet_status",
          json!({ "code": 1, "message": null }),
        );
        return Ok(Value::Null);
      }
      let (rpc, params) = map_wallet_rpc(method, p)?;
      if method == "create_wallet" {
        // Electron `createWallet`: clear error state before `create_wallet` RPC.
        emit_receive(app, "reset_wallet_error", json!({}))?;
      }
      let r = {
        let w = st
          .wallet
          .as_ref()
          .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
        // Immediate close mode: do not block UI on `store`/`close_wallet` RPC when wallet-rpc is scan-busy.
        if method == "close_wallet" {
          crate::agent_debug::log(
            "H6",
            "wallet_handler.rs:handle_wallet:close_immediate_skip_store_rpc",
            "immediate close: skipping blocking store/close_wallet RPC",
            wallet_file_probe(st),
          );
        }
        if method == "close_wallet" {
          Value::Null
        } else {
          if method == "open_wallet" {
            let open_timeout = open_rpc_timeout_secs();
            match tokio::time::timeout(Duration::from_secs(open_timeout), w.call(&rpc, &params)).await {
              Ok(Ok(v)) => v,
              Ok(Err(e)) => {
                let _ = emit_receive(
                  app,
                  "reset_wallet_status",
                  json!({
                    "code": -1,
                    "message": format!("open_wallet: {e}")
                  }),
                );
                return Err(format!("open_wallet RPC failed: {e}"));
              }
              Err(_) => {
                let _ = emit_receive(
                  app,
                  "reset_wallet_status",
                  json!({
                    "code": -1,
                    "message": format!("open_wallet: timeout after {open_timeout}s")
                  }),
                );
                return Err(format!("open_wallet RPC timed out after {open_timeout}s"));
              }
            }
          } else if method == "save_wallet" {
            // Electron `saveWallet()` → `sendRPC("store", {}, storeFlushTimeoutMs)`.
            let flush_ms = crate::wallet_process::save_wallet_flush_timeout_ms();
            match tokio::time::timeout(Duration::from_millis(flush_ms), w.call(&rpc, &params)).await {
              Ok(Ok(v)) => v,
              Ok(Err(e)) => return Err(format!("save_wallet: store RPC failed: {e}")),
              Err(_) => {
                return Err(format!(
                  "save_wallet: store timed out after {flush_ms}ms (Electron storeFlushTimeoutMs; override ARQMA_WALLET_STORE_FLUSH_TIMEOUT_MS)"
                ));
              }
            }
          } else if method == "validate_address" {
            // Electron `validateAddress`: transport failure → `set_valid_address` invalid (not `set_wallet_error`).
            match w.call(&rpc, &params).await {
              Ok(v) => v,
              Err(_) => {
                let addr = p.get("address").and_then(|a| a.as_str()).unwrap_or("");
                emit_receive(app, "set_valid_address", json!({ "address": addr, "valid": false }))?;
                return Ok(Value::Null);
              }
            }
          } else {
            w.call(&rpc, &params).await?
          }
        }
      };
      if method == "validate_address" && r.get("error").is_some() {
        let addr = p.get("address").and_then(|a| a.as_str()).unwrap_or("");
        emit_receive(app, "set_valid_address", json!({ "address": addr, "valid": false }))?;
        return Ok(Value::Null);
      }
      if method != "close_wallet" && r.get("error").is_some() {
        if method == "open_wallet" || method == "close_wallet" {
          crate::agent_debug::log(
            "H5",
            "wallet_handler.rs:handle_wallet:rpc_error",
            "wallet rpc returned error for open/close",
            json!({ "method": method, "error": r.get("error").cloned().unwrap_or(Value::Null) }),
          );
        }
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
        let rpc_msg = rpc_msg_capitalized();
        if method == "open_wallet" {
          let _ = emit_receive(
            app,
            "reset_wallet_status",
            json!({ "code": -1, "message": rpc_msg.clone() }),
          );
        }
        if method == "transfer" {
          let msg = rpc_msg.clone();
          emit_receive(
            app,
            "set_tx_status",
            json!({ "code": -200, "message": msg, "sending": false }),
          )?;
        }
        return Ok(Value::Null);
      }
      if method == "validate_address" {
        emit_validate_address_from_rpc_result(app, st, p, &r)?;
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
          if p
            .get("address_book")
            .and_then(|ab| ab.get("save"))
            .and_then(|v| v.as_bool())
            == Some(true)
          {
            if let Some(addr) = p.get("address").and_then(|a| a.as_str()) {
              if !addr.is_empty() {
                let ab = p.get("address_book").cloned().unwrap_or_else(|| json!({}));
                let add_p = json!({
                  "address": addr,
                  "payment_id": p.get("payment_id").and_then(|x| x.as_str()).unwrap_or(""),
                  "name": ab.get("name").and_then(|x| x.as_str()).unwrap_or(""),
                  "description": ab.get("description").and_then(|x| x.as_str()).unwrap_or(""),
                  "starred": false,
                  "index": false
                });
                if let Err(e) = wallet_add_address_book(app, st, http, &add_p).await {
                  eprintln!("[wallet] transfer save address_book: {e}");
                }
              }
            }
          }
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
      }
      // Some actions expect extra gateway events from the backend.
      if method == "open_wallet" {
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

        // Let the UI leave `$q.loading` **before** `getheight` / `getbalance`: those RPCs can queue behind a
        // long-running scan and would otherwise block this handler for minutes (heartbeat also contends on
        // `backend`, so the footer stayed at 0 % with a frozen spinner on reopen).
        st.wh_display_name = name.to_string();
        st.wh_stored_height = 0;
        st.wh_stored_balance = 0;
        st.wh_stored_unlocked = 0;
        st.wh_catchup_last_heavy = None;
        st.wh_fetch_tx_pending = true;

        emit_receive(
          app,
          "set_wallet_info",
          json!({
            "name": name,
            "height": 0,
            "balance": 0,
            "unlocked_balance": 0,
            "scan_poll_ts": Utc::now().timestamp_millis()
          }),
        )?;
        emit_receive(
          app,
          "reset_wallet_status",
          json!({ "code": 0, "message": "OK" }),
        )?;
        crate::wallet_heartbeat::start(app, st, is_local_net(st));

        let w = st
          .wallet
          .as_ref()
          .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
        let snap_t = open_wallet_snapshot_rpc_secs();
        let p_empty = json!({});
        let p_bal = json!({ "account_index": 0 });
        let (gh_r, gb_r) = tokio::join!(
          tokio::time::timeout(Duration::from_secs(snap_t), w.call("getheight", &p_empty)),
          tokio::time::timeout(Duration::from_secs(snap_t), w.call("getbalance", &p_bal)),
        );

        let opened_height: u64 = match &gh_r {
          Ok(Ok(h)) => crate::json_util::wallet_height_from_getheight(h).unwrap_or(0),
          Err(_) => {
            eprintln!(
              "[wallet] open_wallet: getheight snapshot timed out after {snap_t}s (heartbeat will refresh)"
            );
            0
          }
          Ok(Err(_)) => 0,
        };
        let mut bal = 0u64;
        let mut unl = 0u64;
        if let Ok(Ok(ref v)) = gb_r {
          if crate::json_util::json_rpc_no_error(v) {
            bal = v
              .pointer("/result/balance")
              .and_then(crate::json_util::value_as_u64)
              .unwrap_or(0);
            unl = v
              .pointer("/result/unlocked_balance")
              .or_else(|| v.pointer("/result/unlocked"))
              .and_then(crate::json_util::value_as_u64)
              .unwrap_or(0);
          }
        }
        st.wh_stored_height = opened_height;
        st.wh_stored_balance = bal;
        st.wh_stored_unlocked = unl;
        emit_receive(
          app,
          "set_wallet_info",
          json!({
            "name": name,
            "height": opened_height,
            "balance": bal,
            "unlocked_balance": unl,
            "scan_poll_ts": Utc::now().timestamp_millis()
          }),
        )?;

        emit_receive(
          app,
          "set_wallet_transactions",
          json!({ "tx_list": [] }),
        )?;

        // Electron: missing `{name}.address.txt` → `get_address`, write file, `listWallets`.
        if let Some(wdir) = crate::arqma_paths_config::wallet_files_dir(&st.config_data) {
          let addr_path = wdir.join(format!("{name}.address.txt"));
          if !addr_path.exists() {
            let p_addr = json!({ "account_index": 0 });
            match tokio::time::timeout(Duration::from_secs(30), w.call("get_address", &p_addr)).await {
              Ok(Ok(a)) if crate::json_util::json_rpc_no_error(&a) => {
                if let Some(addr) = a.pointer("/result/address").and_then(|x| x.as_str()) {
                  let _ = std::fs::write(&addr_path, addr);
                  let _ = emit_wallet_list(app, st).await;
                }
              }
              _ => {}
            }
          }
        }

        // Electron: `query_key` spend_key — all `0` ⇒ view-only wallet.
        let p_sp = json!({ "key_type": "spend_key" });
        match tokio::time::timeout(Duration::from_secs(25), w.call("query_key", &p_sp)).await {
          Ok(Ok(q)) if crate::json_util::json_rpc_no_error(&q) => {
            if let Some(key) = q.pointer("/result/key").and_then(|x| x.as_str()) {
              if key.chars().all(|c| c == '0') {
                let _ = emit_receive(app, "set_wallet_info", json!({ "view_only": true }));
              }
            }
          }
          _ => {}
        }

        if is_sync_debug() {
          eprintln!(
            "[sync-debug][wallet] open_wallet file={name} is_local_net={}",
            is_local_net(st)
          );
        }
        crate::wallet_diag::log_always(format!(
          "open_wallet: {name} height={opened_height} (xfer after sync catch-up)"
        ));
        crate::agent_debug::log(
          "H2",
          "wallet_handler.rs:handle_wallet:open_wallet_started_hb",
          "open_wallet completed and heartbeat started",
          json!({ "name": name, "opened_height": opened_height }),
        );
      } else if method == "create_wallet" {
        refresh_wallet_password_hash_from_params(st, p);
        let wname = p
          .get("name")
          .or_else(|| p.get("filename"))
          .and_then(|n| n.as_str())
          .unwrap_or("");
        st.wh_display_name = wname.to_string();
        if let Some(w) = st.wallet.as_ref() {
          let wf = w.fork_for_heartbeat();
          let _ = finalize_new_wallet_like_electron(app, st, &wf, wname).await;
        }
      } else if method == "close_wallet" {
        crate::wallet_diag::log_always(
          "close_wallet: stopping heartbeat and clearing active wallet state"
        );
        st.wallet_password_hash_hex = None;
        // `store` / `close_wallet` RPC via [`close_wallet_session_only`]; subprocess is stopped only if
        // close fails (Oxen / Arqma Electron parity), unless `ARQMA_WALLET_FORCE_KILL_AFTER_CLOSE=1`.
        crate::wallet_process::close_wallet_session_only(st).await;
        st.wh_display_name.clear();
        st.wh_stored_height = 0;
        st.wh_stored_balance = 0;
        st.wh_stored_unlocked = 0;
        let _ = emit_receive(
          app,
          "set_wallet_info",
          json!({
            "name": "",
            "height": 0,
            "balance": 0,
            "unlocked_balance": 0,
            "scan_poll_ts": Utc::now().timestamp_millis()
          }),
        );
        let _ = emit_receive(
          app,
          "reset_wallet_status",
          json!({ "code": 1, "message": null }),
        );
        crate::agent_debug::log(
          "H1",
          "wallet_handler.rs:handle_wallet:close_wallet_done",
          "close_wallet branch finished",
          json!({
            "wallet_name_after_clear": st.wh_display_name,
            "wallet_client_after_clear": st.wallet.is_some(),
            "wallet_process_after_clear": st.wallet_process.is_some()
          }),
        );
      }
    }
    _ => {
      eprintln!("[wallet] unsupported method: {method}");
    }
  }
  Ok(Value::Null)
}

/// Row index for `delete_address_book` / replace-before-add (`false` / missing = none).
fn address_book_row_index (p: &Value) -> Option<u64> {
  match p.get("index") {
    None => None,
    Some(v) if v.is_null() => None,
    Some(v) if v.is_boolean() => None,
    Some(v) => v
      .as_u64()
      .or_else(|| v.as_i64().filter(|&i| i >= 0).map(|i| i as u64)),
  }
}

/// Same as `wallet-rpc.js::addAddressBook` RPC params (`description` = `starred::name::notes` with `::`).
fn map_add_address_book_rpc_params (p: &Value) -> Result<Value, String> {
  let address = p
    .get("address")
    .and_then(|a| a.as_str())
    .ok_or_else(|| "add_address_book: address".to_string())?
    .to_string();
  let name = p
    .get("name")
    .and_then(|n| n.as_str())
    .unwrap_or("")
    .to_string();
  let description = p
    .get("description")
    .and_then(|d| d.as_str())
    .unwrap_or("")
    .to_string();
  let starred = p.get("starred").and_then(|s| s.as_bool()).unwrap_or(false);
  let mut parts: Vec<String> = Vec::new();
  if starred {
    parts.push("starred".into());
  }
  parts.push(name);
  parts.push(description);
  let desc = parts.join("::");
  let mut out = serde_json::Map::new();
  out.insert("address".into(), json!(address));
  out.insert("description".into(), json!(desc));
  if let Some(pid) = p.get("payment_id").and_then(|x| x.as_str()) {
    if !pid.is_empty() {
      out.insert("payment_id".into(), json!(pid));
    }
  }
  Ok(Value::Object(out))
}

/// `wallet-rpc.js::addAddressBook` — optional delete-by-index, `add_address_book`, `store`, refresh UI list.
async fn wallet_add_address_book (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &Client,
  p: &Value,
) -> Result<(), String> {
  let _ = crate::wallet_process::try_start_wallet_rpc(app, st, http).await;
  let w = st
    .wallet
    .as_ref()
    .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
  let display_addr = p
    .get("address")
    .and_then(|a| a.as_str())
    .unwrap_or("")
    .to_string();
  if let Some(idx) = address_book_row_index(p) {
    let dr = w.call("delete_address_book", &json!({ "index": idx })).await?;
    if dr.get("error").is_some() {
      eprintln!(
        "[wallet] add_address_book: delete before replace: {:?}",
        dr.get("error")
      );
    }
  }
  let params = map_add_address_book_rpc_params(p)?;
  let r = w.call("add_address_book", &params).await?;
  if r.get("error").is_some() {
    let err = r.get("error").cloned().unwrap_or(Value::Null);
    emit_receive(app, "set_wallet_error", json!({ "status": err }))?;
    emit_receive(
      app,
      "show_notification",
      json!({
        "type": "negative",
        "message": "Wallet RPC Error, Address Rejected",
        "timeout": 3000
      }),
    )?;
    return Ok(());
  }
  let _ = w.call("store", &json!({})).await;
  let bk = crate::wallet_heartbeat::fetch_address_book_map(w).await?;
  emit_receive(app, "set_wallet_address_book", bk)?;
  emit_receive(
    app,
    "show_notification",
    json!({
      "type": "positive",
      "message": format!("Address Book updated with {display_addr}"),
      "timeout": 3000
    }),
  )?;
  Ok(())
}

/// `wallet-rpc.js::deleteAddressBook` — `delete_address_book`, `store`, refresh UI list.
async fn wallet_delete_address_book (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &Client,
  p: &Value,
) -> Result<(), String> {
  let Some(idx) = address_book_row_index(p) else {
    return Ok(());
  };
  let _ = crate::wallet_process::try_start_wallet_rpc(app, st, http).await;
  let w = st
    .wallet
    .as_ref()
    .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
  let r = w
    .call("delete_address_book", &json!({ "index": idx }))
    .await?;
  if r.get("error").is_some() {
    let err = r.get("error").cloned().unwrap_or(Value::Null);
    emit_receive(app, "set_wallet_error", json!({ "status": err }))?;
    return Ok(());
  }
  let _ = w.call("store", &json!({})).await;
  let bk = crate::wallet_heartbeat::fetch_address_book_map(w).await?;
  emit_receive(app, "set_wallet_address_book", bk)?;
  Ok(())
}

fn normalize_restore_seed (seed: &str) -> String {
  seed.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn wallet_filename_from_params (p: &Value) -> Option<&str> {
  p
    .get("name")
    .or_else(|| p.get("filename"))
    .and_then(|n| n.as_str())
    .filter(|s| !s.is_empty())
}

fn prompt_password_enabled (st: &WalletBackendState) -> bool {
  st
    .config_data
    .get("app")
    .and_then(|a| a.get("promptForPassword"))
    .and_then(|v| v.as_bool())
    == Some(true)
}

/// `promptForPasswordCheck` + `isValidPasswordHash` when `app.promptForPassword` is true.
fn wallet_password_ok_for_tx (st: &WalletBackendState, password: &str) -> bool {
  if !prompt_password_enabled(st) {
    return true;
  }
  wallet_password_matches(st, password)
}

fn refresh_wallet_password_hash_from_password (st: &mut WalletBackendState, password: &str) {
  if st.wallet_salt.is_empty() {
    return;
  }
  if let Ok(h) = crate::wallet_password::pbkdf2_password_hex(password, &st.wallet_salt) {
    st.wallet_password_hash_hex = Some(h);
  }
}

fn refresh_wallet_password_hash_from_params (st: &mut WalletBackendState, p: &Value) {
  if let Some(pw) = p.get("password").and_then(|x| x.as_str()) {
    refresh_wallet_password_hash_from_password(st, pw);
  }
}

fn trim_wallet_import_path (path_str: &str) -> String {
  let t = path_str.trim();
  if t.ends_with(".keys") {
    t[..t.len() - ".keys".len()].to_string()
  } else if t.ends_with(".address.txt") {
    t[..t.len() - ".address.txt".len()].to_string()
  } else {
    t.to_string()
  }
}

fn rpc_error_message_capitalized (err: &Value) -> String {
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
}

async fn emit_wallet_list (app: &AppHandle, st: &WalletBackendState) -> Result<(), String> {
  if let Some(dir) = crate::arqma_paths_config::wallet_files_dir(&st.config_data) {
    let w = list_wallet_files(&dir)?;
    emit_receive(app, "wallet_list", w)?;
  }
  Ok(())
}

/// `wallet-rpc.js::finalizeNewWallet` — `store`, `.address.txt`, `wallet_list`, `set_wallet_info`, `set_wallet_secret` (mnemonic), heartbeat.
async fn finalize_new_wallet_like_electron (
  app: &AppHandle,
  st: &mut WalletBackendState,
  w: &crate::json_rpc_client::WalletRpcClient,
  filename: &str,
) -> Result<(), String> {
  let p_addr = json!({ "account_index": 0 });
  let p_empty = json!({});
  let p_bal = json!({ "account_index": 0 });
  let p_mn = json!({ "key_type": "mnemonic" });
  let p_sp = json!({ "key_type": "spend_key" });
  let (ga, gh, gb, qm, qs) = tokio::join!(
    w.call("get_address", &p_addr),
    w.call("getheight", &p_empty),
    w.call("getbalance", &p_bal),
    w.call("query_key", &p_mn),
    w.call("query_key", &p_sp),
  );
  let mut info = json!({
    "name": filename,
    "address": "",
    "balance": 0,
    "unlocked_balance": 0,
    "height": 0,
    "view_only": false
  });
  if let Ok(ref a) = ga {
    if crate::json_util::json_rpc_no_error(a) {
      if let Some(addr) = a.pointer("/result/address").and_then(|x| x.as_str()) {
        info["address"] = json!(addr);
      }
    }
  }
  if let Ok(ref h) = gh {
    if crate::json_util::json_rpc_no_error(h) {
      if let Some(height) = crate::json_util::wallet_height_from_getheight(h) {
        info["height"] = json!(height);
      }
    }
  }
  if let Ok(ref b) = gb {
    if crate::json_util::json_rpc_no_error(b) {
      if let Some(r) = b.get("result") {
        if let Some(bal) = r.get("balance").and_then(|v| crate::json_util::value_as_u64(v)) {
          info["balance"] = json!(bal);
        }
        if let Some(ub) = r
          .get("unlocked_balance")
          .and_then(|v| crate::json_util::value_as_u64(v))
        {
          info["unlocked_balance"] = json!(ub);
        }
      }
    }
  }
  if let Ok(ref m) = qm {
    if crate::json_util::json_rpc_no_error(m) {
      if let Some(key) = m.pointer("/result/key").and_then(|x| x.as_str()) {
        emit_receive(
          app,
          "set_wallet_secret",
          json!({ "mnemonic": key, "spend_key": "", "view_key": "" }),
        )?;
      }
    }
  }
  if let Ok(ref s) = qs {
    if crate::json_util::json_rpc_no_error(s) {
      if let Some(key) = s.pointer("/result/key").and_then(|x| x.as_str()) {
        if key.chars().all(|c| c == '0') {
          info["view_only"] = json!(true);
        }
      }
    }
  }
  let _ = w.call("store", &json!({})).await;
  if let Some(wdir) = crate::arqma_paths_config::wallet_files_dir(&st.config_data) {
    let addr_path = wdir.join(format!("{filename}.address.txt"));
    if !addr_path.exists() {
      if let Some(addr) = info.get("address").and_then(|x| x.as_str()) {
        let _ = std::fs::write(&addr_path, addr);
      }
    }
    emit_wallet_list(app, st).await?;
  }
  emit_receive(app, "set_wallet_info", info.clone())?;
  st.wh_stored_height = info
    .get("height")
    .and_then(crate::json_util::value_as_u64)
    .unwrap_or(0);
  st.wh_stored_balance = info
    .get("balance")
    .and_then(crate::json_util::value_as_u64)
    .unwrap_or(0);
  st.wh_stored_unlocked = info
    .get("unlocked_balance")
    .and_then(crate::json_util::value_as_u64)
    .unwrap_or(0);
  st.wh_catchup_last_heavy = None;
  crate::wallet_heartbeat::start(app, st, is_local_net(st));
  Ok(())
}

async fn wallet_restore_wallet (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &Client,
  p: &Value,
) -> Result<(), String> {
  let _ = crate::wallet_process::try_start_wallet_rpc(app, st, http).await;
  emit_receive(app, "reset_wallet_error", json!({}))?;
  let rh = match crate::wallet_rpc_electron::resolve_restore_refresh_height(st, http, p).await {
    Ok(h) => h,
    Err(e) => {
      emit_receive(
        app,
        "set_wallet_error",
        json!({ "status": { "code": -1, "message": e } }),
      )?;
      return Ok(());
    }
  };
  let mut p2 = p.clone();
  if let Some(seed) = p.get("seed").and_then(|s| s.as_str()) {
    if let Some(o) = p2.as_object_mut() {
      o.insert("seed".into(), json!(normalize_restore_seed(seed)));
    }
  }
  let params = crate::wallet_rpc_electron::map_restore_deterministic_wallet(&p2, rh)?;
  let r = {
    let w = st
      .wallet
      .as_ref()
      .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
    w.call("restore_deterministic_wallet", &params).await?
  };
  if r.get("error").is_some() {
    let err = r.get("error").cloned().unwrap_or(Value::Null);
    emit_receive(app, "set_wallet_error", json!({ "status": err }))?;
    return Ok(());
  }
  refresh_wallet_password_hash_from_params(st, p);
  let filename = wallet_filename_from_params(p).unwrap_or("");
  st.wh_display_name = filename.to_string();
  let wf = st
    .wallet
    .as_ref()
    .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?
    .fork_for_heartbeat();
  finalize_new_wallet_like_electron(app, st, &wf, filename).await?;
  Ok(())
}

async fn wallet_restore_view_wallet (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &Client,
  p: &Value,
) -> Result<(), String> {
  let _ = crate::wallet_process::try_start_wallet_rpc(app, st, http).await;
  emit_receive(app, "reset_wallet_error", json!({}))?;
  let mut refresh_h = match crate::wallet_rpc_electron::resolve_restore_refresh_height(st, http, p).await {
    Ok(h) => h,
    Err(e) => {
      emit_receive(
        app,
        "set_wallet_error",
        json!({ "status": { "code": -1, "message": e } }),
      )?;
      return Ok(());
    }
  };
  if p
    .get("refresh_type")
    .and_then(|t| t.as_str())
    .unwrap_or("height")
    == "height"
  {
    let raw = p.get("refresh_start_height");
    let is_int = raw
      .and_then(|v| {
        v.as_u64()
          .map(|_| true)
          .or_else(|| v.as_i64().map(|_| true))
      })
      .unwrap_or(false);
    if !is_int {
      refresh_h = 0;
    }
  }
  let params = crate::wallet_rpc_electron::map_generate_from_keys(p, refresh_h)?;
  let r = {
    let w = st
      .wallet
      .as_ref()
      .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
    w.call("generate_from_keys", &params).await?
  };
  if r.get("error").is_some() {
    let err = r.get("error").cloned().unwrap_or(Value::Null);
    emit_receive(app, "set_wallet_error", json!({ "status": err }))?;
    return Ok(());
  }
  refresh_wallet_password_hash_from_params(st, p);
  let filename = wallet_filename_from_params(p).unwrap_or("");
  st.wh_display_name = filename.to_string();
  let wf = st
    .wallet
    .as_ref()
    .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?
    .fork_for_heartbeat();
  finalize_new_wallet_like_electron(app, st, &wf, filename).await?;
  Ok(())
}

async fn wallet_import_wallet (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &Client,
  p: &Value,
) -> Result<(), String> {
  let _ = crate::wallet_process::try_start_wallet_rpc(app, st, http).await;
  emit_receive(app, "reset_wallet_error", json!({}))?;
  let filename = wallet_filename_from_params(p).ok_or_else(|| "import_wallet: name".to_string())?;
  let import_path_raw = p
    .get("path")
    .and_then(|x| x.as_str())
    .ok_or_else(|| "import_wallet: path".to_string())?;
  let import_base = trim_wallet_import_path(import_path_raw);
  let import_src = PathBuf::from(&import_base);
  if !import_src.exists() {
    emit_receive(
      app,
      "set_wallet_error",
      json!({ "status": { "code": -1, "message": "Invalid wallet path" } }),
    )?;
    return Ok(());
  }
  let Some(wdir) = crate::arqma_paths_config::wallet_files_dir(&st.config_data) else {
    return Ok(());
  };
  let destination = wdir.join(filename);
  if destination.exists() || wdir.join(format!("{filename}.keys")).exists() {
    emit_receive(
      app,
      "set_wallet_error",
      json!({ "status": { "code": -1, "message": "Wallet with name already exists" } }),
    )?;
    return Ok(());
  }
  let keys_src = PathBuf::from(format!("{import_base}.keys"));
  let dest_keys = wdir.join(format!("{filename}.keys"));
  if let Err(e) = std::fs::copy(&import_src, &destination) {
    eprintln!("[wallet] import copy: {e}");
    emit_receive(
      app,
      "set_wallet_error",
      json!({ "status": { "code": -1, "message": "Failed to copy wallet" } }),
    )?;
    return Ok(());
  }
  if keys_src.exists() {
    if let Err(e) = std::fs::copy(&keys_src, &dest_keys) {
      eprintln!("[wallet] import copy keys: {e}");
      let _ = std::fs::remove_file(&destination);
      emit_receive(
        app,
        "set_wallet_error",
        json!({ "status": { "code": -1, "message": "Failed to copy wallet" } }),
      )?;
      return Ok(());
    }
  }
  let password = p
    .get("password")
    .and_then(|x| x.as_str())
    .ok_or_else(|| "import_wallet: password".to_string())?;
  let open_r = {
    let w = st
      .wallet
      .as_ref()
      .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
    w
      .call(
        "open_wallet",
        &json!({ "filename": filename.to_string(), "password": password }),
      )
      .await?
  };
  if open_r.get("error").is_some() {
    let _ = std::fs::remove_file(&destination);
    let _ = std::fs::remove_file(&dest_keys);
    emit_receive(
      app,
      "set_wallet_error",
      json!({ "status": open_r.get("error").cloned().unwrap_or(Value::Null) }),
    )?;
    return Ok(());
  }
  refresh_wallet_password_hash_from_params(st, p);
  st.wh_display_name = filename.to_string();
  let wf = st
    .wallet
    .as_ref()
    .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?
    .fork_for_heartbeat();
  finalize_new_wallet_like_electron(app, st, &wf, filename).await?;
  Ok(())
}

async fn wallet_stake (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &Client,
  p: &Value,
) -> Result<(), String> {
  let origin = p.get("origin").cloned().unwrap_or(Value::Null);
  let reply_note = |msg: &str| {
    emit_receive(
      app,
      "show_notification",
      json!({
        "type": "negative",
        "message": msg,
        "timeout": 3000,
        "origin": origin.clone()
      }),
    )
  };
  let password = p.get("password").and_then(|x| x.as_str()).unwrap_or("");
  if !wallet_password_ok_for_tx(st, password) {
    reply_note("Password Error")?;
    return Ok(());
  }
  let _ = crate::wallet_process::try_start_wallet_rpc(app, st, http).await;
  let w = st
    .wallet
    .as_ref()
    .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
  let params = crate::wallet_rpc_electron::map_stake_rpc(p)?;
  let r = w.call("stake", &params).await?;
  if r.get("error").is_some() {
    let msg = r
      .get("error")
      .map(|e| rpc_error_message_capitalized(e))
      .unwrap_or_else(|| "Unknown error".to_string());
    emit_receive(
      app,
      "set_tx_status",
      json!({ "code": -300, "message": msg, "sending": false }),
    )?;
    return Ok(());
  }
  if r.get("result").is_some() {
    let fee_msg = r
      .get("result")
      .and_then(|res| res.get("fee"))
      .and_then(crate::json_util::value_as_u64)
      .map(|atoms| {
        let fee_ui = atoms as f64 / crate::wallet_relay_ops::COIN_UNITS;
        format!("Fee {fee_ui:.9}")
      })
      .unwrap_or_else(|| "Fee".to_string());
    emit_receive(
      app,
      "set_tx_status",
      json!({
        "code": 300,
        "message": fee_msg,
        "sending": false
      }),
    )?;
    crate::wallet_relay_ops::push_stake_metadata(st, p, &r);
  }
  Ok(())
}

async fn wallet_register_service_node (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &Client,
  p: &Value,
) -> Result<(), String> {
  let password = p.get("password").and_then(|x| x.as_str()).unwrap_or("");
  if !wallet_password_ok_for_tx(st, password) {
    emit_receive(
      app,
      "set_snode_status",
      json!({ "registration": { "code": -1, "sending": false } }),
    )?;
    return Ok(());
  }
  let _ = crate::wallet_process::try_start_wallet_rpc(app, st, http).await;
  let w = st
    .wallet
    .as_ref()
    .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
  let params = crate::wallet_rpc_electron::map_register_service_node(p)?;
  let r = w.call("register_service_node", &params).await?;
  if r.get("error").is_some() {
    let msg = r
      .get("error")
      .map(|e| rpc_error_message_capitalized(e))
      .unwrap_or_else(|| "Unknown error".to_string());
    emit_receive(
      app,
      "set_snode_status",
      json!({ "registration": { "code": -1, "message": msg, "sending": false } }),
    )?;
    return Ok(());
  }
  emit_receive(
    app,
    "set_snode_status",
    json!({ "registration": { "code": 0, "sending": false } }),
  )?;
  Ok(())
}

async fn wallet_save_tx_notes (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &Client,
  p: &Value,
) -> Result<(), String> {
  let _ = crate::wallet_process::try_start_wallet_rpc(app, st, http).await;
  let w = st
    .wallet
    .as_ref()
    .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
  let params = crate::wallet_rpc_electron::map_set_tx_notes(p)?;
  let _ = w.call("set_tx_notes", &params).await;
  let txid = p.get("txid").and_then(|t| t.as_str()).unwrap_or("");
  if txid.is_empty() {
    return Ok(());
  }
  let tr = w
    .call("get_transfer_by_txid", &json!({ "txid": txid }))
    .await?;
  if let Some(xfer) = tr.pointer("/result/transfer") {
    emit_receive(app, "set_wallet_transaction", xfer.clone())?;
  }
  Ok(())
}

async fn wallet_get_private_keys (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &Client,
  p: &Value,
) -> Result<(), String> {
  let _ = crate::wallet_process::try_start_wallet_rpc(app, st, http).await;
  let mut secret = json!({ "mnemonic": "", "spend_key": "", "view_key": "" });
  let password = p.get("password").and_then(|x| x.as_str()).unwrap_or("");
  if !wallet_password_ok_for_tx(st, password) {
    emit_receive(
      app,
      "set_wallet_secret",
      json!({ "mnemonic": "Invalid password", "spend_key": -1, "view_key": -1 }),
    )?;
    return Ok(());
  }
  let w = st
    .wallet
    .as_ref()
    .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
  let pk_m = json!({ "key_type": "mnemonic" });
  let pk_s = json!({ "key_type": "spend_key" });
  let pk_v = json!({ "key_type": "view_key" });
  let (m, s, v) = tokio::join!(
    w.call("query_key", &pk_m),
    w.call("query_key", &pk_s),
    w.call("query_key", &pk_v),
  );
  for (res, key_field) in [(m, "mnemonic"), (s, "spend_key"), (v, "view_key")] {
    if let Ok(ref ok) = res {
      if ok.get("error").is_none() {
        if let Some(k) = ok.pointer("/result/key") {
          if let Some(o) = secret.as_object_mut() {
            o.insert(key_field.into(), k.clone());
          }
        }
      }
    }
  }
  emit_receive(app, "set_wallet_secret", secret)?;
  Ok(())
}

fn wallet_data_dir_path (st: &WalletBackendState) -> Option<PathBuf> {
  st
    .config_data
    .get("app")
    .and_then(|a| a.get("wallet_data_dir"))
    .and_then(|d| d.as_str())
    .map(PathBuf::from)
}

async fn wallet_export_key_images (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &Client,
  p: &Value,
) -> Result<(), String> {
  let _ = crate::wallet_process::try_start_wallet_rpc(app, st, http).await;
  let password = p.get("password").and_then(|x| x.as_str()).unwrap_or("");
  if !wallet_password_ok_for_tx(st, password) {
    emit_receive(
      app,
      "show_notification",
      json!({ "type": "negative", "message": "Invalid password", "timeout": 3000 }),
    )?;
    return Ok(());
  }
  let w = st
    .wallet
    .as_ref()
    .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
  let name = st.wh_display_name.as_str();
  let out_path = if let Some(dir) = p.get("path").and_then(|x| x.as_str()) {
    PathBuf::from(dir).join("key_image_export")
  } else {
    wallet_data_dir_path(st)
      .unwrap_or_default()
      .join("images")
      .join(name)
      .join("key_image_export")
  };
  let images_dir = wallet_data_dir_path(st)
    .unwrap_or_default()
    .join("images")
    .join(name);
  let _ = std::fs::create_dir_all(&images_dir);
  let params = crate::wallet_rpc_electron::map_export_key_images(p)?;
  let data = w.call("export_key_images", &params).await?;
  if data.get("error").is_some() || data.get("result").is_none() {
    emit_receive(
      app,
      "show_notification",
      json!({ "type": "negative", "message": "Error exporting key images", "timeout": 3000 }),
    )?;
    return Ok(());
  }
  if let Some(ski) = data.pointer("/result/signed_key_images") {
    let body = serde_json::to_string(ski).unwrap_or_else(|_| "{}".into());
    if let Err(e) = std::fs::write(&out_path, body) {
      eprintln!("[wallet] export key images write: {e}");
      emit_receive(
        app,
        "show_notification",
        json!({ "type": "negative", "message": "Error exporting key images", "timeout": 3000 }),
      )?;
      return Ok(());
    }
    emit_receive(
      app,
      "show_notification",
      json!({
        "message": format!("Key images exported to {}", out_path.display()),
        "timeout": 3000
      }),
    )?;
  } else {
    emit_receive(
      app,
      "show_notification",
      json!({
        "type": "warning",
        "textColor": "black",
        "message": "No key images found to export",
        "timeout": 3000
      }),
    )?;
  }
  Ok(())
}

async fn wallet_import_key_images (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &Client,
  p: &Value,
) -> Result<(), String> {
  let _ = crate::wallet_process::try_start_wallet_rpc(app, st, http).await;
  let password = p.get("password").and_then(|x| x.as_str()).unwrap_or("");
  if !wallet_password_ok_for_tx(st, password) {
    emit_receive(
      app,
      "show_notification",
      json!({ "type": "negative", "message": "Invalid password", "timeout": 3000 }),
    )?;
    return Ok(());
  }
  let w = st
    .wallet
    .as_ref()
    .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
  let name = st.wh_display_name.as_str();
  let file_path = if let Some(dir) = p.get("path").and_then(|x| x.as_str()) {
    PathBuf::from(dir).join("key_image_export")
  } else {
    wallet_data_dir_path(st)
      .unwrap_or_default()
      .join("images")
      .join(name)
      .join("key_image_export")
  };
  let text = match std::fs::read_to_string(&file_path) {
    Ok(t) => t,
    Err(_) => {
      emit_receive(
        app,
        "show_notification",
        json!({ "type": "negative", "message": "Error parsing key images as JSON", "timeout": 3000 }),
      )?;
      return Ok(());
    }
  };
  let signed: Value = match serde_json::from_str(&text) {
    Ok(v) => v,
    Err(_) => {
      emit_receive(
        app,
        "show_notification",
        json!({ "type": "negative", "message": "Error parsing key images as JSON", "timeout": 3000 }),
      )?;
      return Ok(());
    }
  };
  let data = w
    .call("import_key_images", &json!({ "signed_key_images": signed }))
    .await?;
  if data.get("error").is_some() || data.get("result").is_none() {
    emit_receive(
      app,
      "show_notification",
      json!({
        "type": "negative",
        "message": "Error importing key images. change to local daemon",
        "timeout": 3000
      }),
    )?;
    return Ok(());
  }
  emit_receive(
    app,
    "show_notification",
    json!({ "message": "Key images imported", "timeout": 3000 }),
  )?;
  Ok(())
}

async fn wallet_change_wallet_password (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &Client,
  p: &Value,
) -> Result<(), String> {
  let old_password = p.get("old_password").and_then(|x| x.as_str()).unwrap_or("");
  if !wallet_password_ok_for_tx(st, old_password) {
    emit_receive(
      app,
      "show_notification",
      json!({ "type": "negative", "message": "Invalid old password", "timeout": 3000 }),
    )?;
    return Ok(());
  }
  let _ = crate::wallet_process::try_start_wallet_rpc(app, st, http).await;
  let w = st
    .wallet
    .as_ref()
    .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
  let params = crate::wallet_rpc_electron::map_change_wallet_password(p)?;
  let data = w.call("change_wallet_password", &params).await?;
  if data.get("error").is_some() || data.get("result").is_none() {
    emit_receive(
      app,
      "show_notification",
      json!({ "type": "negative", "message": "Error changing password", "timeout": 3000 }),
    )?;
    return Ok(());
  }
  if let Some(np) = p.get("new_password").and_then(|x| x.as_str()) {
    refresh_wallet_password_hash_from_password(st, np);
  }
  emit_receive(
    app,
    "show_notification",
    json!({ "message": "Password updated", "timeout": 3000 }),
  )?;
  Ok(())
}

async fn wallet_delete_wallet (
  app: &AppHandle,
  st: &mut WalletBackendState,
  _http: &Client,
  p: &Value,
) -> Result<(), String> {
  let password = p.get("password").and_then(|x| x.as_str()).unwrap_or("");
  if !wallet_password_ok_for_tx(st, password) {
    emit_receive(
      app,
      "show_notification",
      json!({ "type": "negative", "message": "Invalid password", "timeout": 3000 }),
    )?;
    return Ok(());
  }
  let wallet_name = st.wh_display_name.clone();
  if wallet_name.is_empty() {
    return Ok(());
  }
  emit_receive(
    app,
    "show_loading",
    json!({ "message": "Deleting wallet" }),
  )?;
  if let Some(ref w) = st.wallet {
    let _ = w.call("store", &json!({})).await;
    let _ = w.call("close_wallet", &json!({})).await;
  }
  st.wallet_password_hash_hex = None;
  st.wh_display_name.clear();
  crate::wallet_heartbeat::stop(st);
  crate::wallet_process::graceful_shutdown_wallet_rpc(st).await;
  if let Some(wdir) = crate::arqma_paths_config::wallet_files_dir(&st.config_data) {
    let base = wdir.join(&wallet_name);
    let _ = std::fs::remove_file(&base);
    let _ = std::fs::remove_file(base.with_extension("keys"));
    let _ = std::fs::remove_file(wdir.join(format!("{wallet_name}.address.txt")));
  }
  emit_wallet_list(app, st).await?;
  emit_receive(app, "hide_loading", json!({}))?;
  emit_receive(app, "return_to_wallet_select", json!({}))?;
  Ok(())
}

/// Same `payment_id` rules as `wallet-rpc.js::getTransactions` before CSV export.
fn normalize_payment_id_for_export (pid: &str) -> String {
  let t = pid.trim();
  if t.chars().all(|c| c == '0' || c.is_whitespace()) {
    return String::new();
  }
  if t.len() >= 16 {
    let tail = &t[16..];
    if tail.chars().all(|c| c == '0' || c.is_whitespace()) {
      return t.chars().take(16).collect();
    }
  }
  t.to_string()
}

async fn wallet_export_transactions (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &Client,
  p: &Value,
) -> Result<(), String> {
  let mut reply = json!({
    "code": -99,
    "message": "backend.transaction_export_failed",
    "origin": "wallet_settings"
  });
  let password = p.get("password").and_then(|x| x.as_str()).unwrap_or("");
  if !wallet_password_ok_for_tx(st, password) {
    reply["message"] = json!("backend.Invalid_password");
    emit_receive(app, "set_tx_status", reply)?;
    return Ok(());
  }
  let _ = crate::wallet_process::try_start_wallet_rpc(app, st, http).await;
  let w = st
    .wallet
    .as_ref()
    .ok_or_else(|| ERR_NO_LOCAL_WALLET_RPC.to_string())?;
  let min_height = 0u64;
  let gt_params = json!({
    "in": true,
    "out": true,
    "pending": true,
    "failed": true,
    "pool": false,
    "filter_by_height": true,
    "min_height": min_height
  });
  let gt = w.call("get_transfers", &gt_params).await?;
  let mut list = if let Some(r) = gt.get("result") {
    crate::wallet_heartbeat::merge_transfers_list(r)
  } else {
    Vec::new()
  };
  for tx in &mut list {
    if let Some(o) = tx.as_object_mut() {
      if let Some(s) = o.get("payment_id").and_then(|v| v.as_str()) {
        let np = normalize_payment_id_for_export(s);
        o.insert("payment_id".into(), json!(np));
      }
    }
  }
  let export_dir = p
    .get("path")
    .and_then(|x| x.as_str())
    .ok_or_else(|| "export_transactions: path".to_string())?;
  let csv_path = Path::new(export_dir).join("transactions.csv");
  let file = std::fs::File::create(&csv_path).map_err(|e| e.to_string())?;
  let mut bw = std::io::BufWriter::new(file);
  for (index, mut transaction) in list.iter().cloned().enumerate() {
    if let Some(o) = transaction.as_object_mut() {
      o.remove("subaddr_index");
      o.remove("subaddr_indices");
      o.remove("suggested_confirmations_threshold");
    }
    if index == 0 {
      if let Some(o) = transaction.as_object() {
        let mut headers: Vec<String> = o.keys().cloned().collect();
        headers.insert(3, "destinations".into());
        writeln!(bw, "{}", headers.join("|")).map_err(|e| e.to_string())?;
      }
    } else {
      if let Some(o) = transaction.as_object_mut() {
        if let Some(am) = o.get("amount") {
          if let Some(a) = crate::json_util::value_as_u64(am) {
            o.insert(
              "amount".into(),
              json!(a as f64 / crate::wallet_relay_ops::COIN_UNITS),
            );
          }
        }
        if let Some(dest) = o.get("destinations").and_then(|d| d.as_array()) {
          if !dest.is_empty() {
            o.insert("destinations".into(), json!(serde_json::to_string(dest).unwrap_or_default()));
          }
        }
        if let Some(fee_v) = o.get("fee").and_then(crate::json_util::value_as_u64) {
          if fee_v > 0 {
            o.insert(
              "fee".into(),
              json!(fee_v as f64 / crate::wallet_relay_ops::COIN_UNITS),
            );
          }
        }
        if let Some(ts) = o.get("timestamp").and_then(|t| t.as_u64()) {
          let dt = DateTime::<Utc>::from_timestamp(ts as i64, 0)
            .map(|d| d.format("%m/%d/%y %I:%M:%S %p").to_string())
            .unwrap_or_default()
            .replace(',', "");
          o.insert("timestamp".into(), json!(dt));
        }
      }
      let vals: Vec<String> = if let Some(o) = transaction.as_object() {
        o.values()
          .map(|v| match v {
            Value::String(s) => s.clone(),
            Value::Number(n) => n.to_string(),
            Value::Bool(b) => b.to_string(),
            Value::Null => String::new(),
            _ => v.to_string(),
          })
          .collect()
      } else {
        vec![]
      };
      let mut foo = vals;
      if foo.len() == 13 {
        foo.insert(3, "[]".into());
      }
      writeln!(bw, "{}", foo.join("|")).map_err(|e| e.to_string())?;
    }
  }
  reply["code"] = json!(100);
  reply["message"] = json!("backend.transaction_export_complete");
  emit_receive(app, "set_tx_status", reply)?;
  Ok(())
}

/// Count spendable incoming transfers (`incoming_transfers`); fallback to sum of `num_unspent_outputs` from `getbalance`.
async fn count_spendable_outputs_for_sweep (w: &crate::json_rpc_client::WalletRpcClient) -> u64 {
  let inc = w
    .call(
      "incoming_transfers",
      &json!({ "transfer_type": "available", "account_index": 0 }),
    )
    .await
    .unwrap_or(Value::Null);
  if inc.get("error").is_none() {
    if let Some(arr) = inc.pointer("/result/transfers").and_then(|x| x.as_array()) {
      return arr.len() as u64;
    }
  }
  let gb = w
    .call("getbalance", &json!({ "account_index": 0 }))
    .await
    .unwrap_or(Value::Null);
  gb.pointer("/result/per_subaddress")
    .and_then(|x| x.as_array())
    .map(|rows| {
      rows
        .iter()
        .filter_map(|row| row.get("num_unspent_outputs").and_then(|v| v.as_u64()))
        .sum()
    })
    .unwrap_or(0)
}

/// `wallet-rpc.js::sweepAll` — `get_address` then `sweep_all` with the same fields as Node (`address`, `account_index`,
/// `priority`, `ring_size`, `do_not_relay`, `get_tx_metadata`, `get_tx_hex`). UI sends `do_not_relay: true` then `relay_sweepAll`.
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
  let origin = p.get("origin").cloned().unwrap_or(Value::Null);
  let output_count = count_spendable_outputs_for_sweep(w).await;
  let _ = emit_receive(
    app,
    "sweep_all_progress",
    json!({
      "origin": origin.clone(),
      "stage": "outputs_counted",
      "total": output_count
    }),
  );
  let _ = emit_receive(
    app,
    "sweep_all_progress",
    json!({
      "origin": origin.clone(),
      "stage": "building_tx",
      "total": output_count,
      "wait_round": 0u32
    }),
  );
  let params = json!({
    "address": my_address,
    "account_index": 0,
    "priority": 0,
    "ring_size": 16,
    "do_not_relay": do_not,
    "get_tx_metadata": true,
    "get_tx_hex": true
  });
  let r = {
    let sweep = w.call("sweep_all", &params);
    let mut sweep = Box::pin(sweep);
    let mut interval = tokio::time::interval(Duration::from_secs(3));
    interval.set_missed_tick_behavior(MissedTickBehavior::Skip);
    interval.tick().await;
    let mut wait_round: u32 = 0;
    loop {
      tokio::select! {
        biased;
        res = &mut sweep => {
          break res;
        }
        _ = interval.tick() => {
          wait_round = wait_round.saturating_add(1);
          let _ = emit_receive(
            app,
            "sweep_all_progress",
            json!({
              "origin": origin.clone(),
              "stage": "building_tx",
              "total": output_count,
              "wait_round": wait_round
            }),
          );
        }
      }
    }
  };
  let r = r?;
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
    let _ = emit_receive(app, "sweep_all_progress", Value::Null);
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
  let _ = emit_receive(app, "sweep_all_progress", Value::Null);
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

/// Electron `wallet-rpc.js::validateAddress` → `set_valid_address` (incl. `net_type` vs result `nettype`).
fn emit_validate_address_from_rpc_result (
  app: &AppHandle,
  st: &WalletBackendState,
  p: &Value,
  r: &Value,
) -> Result<(), String> {
  let address = p.get("address").and_then(|a| a.as_str()).unwrap_or("");
  let Some(res) = r.get("result") else {
    emit_receive(app, "set_valid_address", json!({ "address": address, "valid": false }))?;
    return Ok(());
  };
  let valid = res.get("valid").and_then(|v| v.as_bool()).unwrap_or(false);
  let nettype = res
    .get("nettype")
    .and_then(|v| v.as_str())
    .or_else(|| res.get("net_type").and_then(|v| v.as_str()))
    .unwrap_or("");
  let app_net = st
    .config_data
    .get("app")
    .and_then(|a| a.get("net_type"))
    .and_then(|n| n.as_str())
    .unwrap_or("mainnet");
  let net_matches = app_net == nettype;
  let is_valid = valid && net_matches;
  emit_receive(
    app,
    "set_valid_address",
    json!({
      "address": address,
      "valid": is_valid,
      "nettype": nettype
    }),
  )?;
  Ok(())
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

/// UI `amount` (number / string) → `f64`.
fn json_amount_as_f64 (v: &Value) -> Option<f64> {
  v.as_f64()
    .or_else(|| v.as_u64().map(|u| u as f64))
    .or_else(|| v.as_i64().map(|i| i as f64))
    .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
}

/// Same shape as `wallet-rpc.js::transfer` → `transfer_split` (destinations in atomic units).
fn map_transfer_split_params (p: &Value) -> Result<Value, String> {
  let amount_ui = p
    .get("amount")
    .and_then(json_amount_as_f64)
    .ok_or_else(|| "transfer: amount".to_string())?;
  let address = p
    .get("address")
    .and_then(|a| a.as_str())
    .ok_or_else(|| "transfer: address".to_string())?
    .to_string();
  let amount_fixed: f64 = format!("{:.9}", amount_ui)
    .parse()
    .map_err(|_| "transfer: amount parse".to_string())?;
  let atoms = (amount_fixed * crate::wallet_relay_ops::COIN_UNITS).round() as u64;
  let priority = p
    .get("priority")
    .and_then(|v| v.as_u64())
    .or_else(|| p.get("priority").and_then(|v| v.as_i64()).map(|i| i.max(0) as u64))
    .unwrap_or(0);
  Ok(json!({
    "destinations": [{ "amount": atoms, "address": address }],
    "priority": priority,
    "ring_size": 16,
    "do_not_relay": true,
    "get_tx_metadata": true
  }))
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
    "save_wallet" => Ok(v("store", Value::Null)),
    "create_wallet" => {
      let name = p.get("name").and_then(|x| x.as_str()).ok_or("name")?.to_string();
      let password = p.get("password").and_then(|x| x.as_str()).ok_or("password")?.to_string();
      let language = p.get("language").and_then(|x| x.as_str()).unwrap_or("English");
      Ok(v(
        "create_wallet",
        json!({ "filename": name, "password": password, "language": language }),
      ))
    }
    "transfer" => Ok(("transfer_split".to_string(), map_transfer_split_params(p)?)),
    "rescan_blockchain" => Ok(v("rescan_blockchain", json!({}))),
    "rescan_spent" => Ok(v("rescan_spent", json!({}))),
    _ => Err(format!("unsupported wallet.method: {method}")),
  }
}
