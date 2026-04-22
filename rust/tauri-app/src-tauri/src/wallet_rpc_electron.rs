//! RPC params and helpers aligned with `src-electron/main-process/modules/wallet-rpc.js` + `daemon.js::timestampToHeight`.

use crate::arqma_paths_config::daemon_rpc_host_port;
use crate::backend_state::WalletBackendState;
use crate::json_rpc_client::daemon_post;
use chrono::{NaiveDate, TimeZone, Utc};
use reqwest::Client;
use serde_json::{json, Value};

fn next_daemon_id (st: &mut WalletBackendState) -> u64 {
  let n = st.next_rpc_id;
  st.next_rpc_id = st.next_rpc_id.saturating_add(1);
  n
}

fn json_block_height (bh: &Value) -> Result<u64, String> {
  bh.get("height")
    .and_then(|v| v.as_u64())
    .or_else(|| {
      bh.get("height")
        .and_then(|v| v.as_i64())
        .filter(|&i| i >= 0)
        .map(|i| i as u64)
    })
    .ok_or_else(|| "block_header: height".to_string())
}

fn json_block_timestamp (bh: &Value) -> Result<i64, String> {
  bh.get("timestamp")
    .and_then(|v| v.as_i64())
    .or_else(|| {
      bh.get("timestamp")
        .and_then(|v| v.as_u64())
        .map(|u| u as i64)
    })
    .ok_or_else(|| "block_header: timestamp".to_string())
}

/// Same refinement loop as `daemon.js::timestampToHeight`.
pub async fn timestamp_to_height (
  st: &mut WalletBackendState,
  http: &Client,
  mut timestamp: i64,
) -> Result<u64, String> {
  let (host, port) = daemon_rpc_host_port(&st.config_data)
    .ok_or_else(|| "timestamp_to_height: daemon host/port missing".to_string())?;
  if timestamp > 999999999999 {
    timestamp /= 1000;
  }
  let mut pivot_h: i64 = 137_500;
  let mut pivot_ts: i64 = 1_528_073_506;
  for _ in 0..12 {
    let diff = (timestamp - pivot_ts) / 240;
    let estimated_height = (pivot_h + diff).max(0) as u64;
    let id = next_daemon_id(st);
    let r = daemon_post(
      http,
      &host,
      port,
      "get_block_header_by_height",
      id,
      &json!({ "height": estimated_height }),
    )
    .await?;
    if r.get("error").is_some() {
      let code = r.pointer("/error/code").and_then(|c| c.as_i64());
      if code == Some(-2) {
        let id2 = next_daemon_id(st);
        let last =
          daemon_post(http, &host, port, "get_last_block_header", id2, &Value::Null).await?;
        if last.get("error").is_some() || last.pointer("/result/block_header").is_none() {
          return Err("timestamp_to_height: get_last_block_header failed".into());
        }
        let bh = last.pointer("/result/block_header").unwrap();
        let new_h = json_block_height(bh)?;
        let new_ts = json_block_timestamp(bh)?;
        if (timestamp - new_ts).abs() < 3600 {
          return Ok(new_h);
        }
        pivot_h = new_h as i64;
        pivot_ts = new_ts;
        continue;
      }
      return Err(
        r.pointer("/error/message")
          .and_then(|m| m.as_str())
          .unwrap_or("daemon RPC error")
          .to_string(),
      );
    }
    let bh = r
      .pointer("/result/block_header")
      .or_else(|| r.get("result"))
      .ok_or_else(|| "timestamp_to_height: missing block_header".to_string())?;
    let new_h = json_block_height(bh)?;
    let new_ts = json_block_timestamp(bh)?;
    if (timestamp - new_ts).abs() < 3600 {
      return Ok(new_h);
    }
    pivot_h = new_h as i64;
    pivot_ts = new_ts;
  }
  Ok(pivot_h.max(0) as u64)
}

pub async fn resolve_restore_refresh_height (
  st: &mut WalletBackendState,
  http: &Client,
  p: &Value,
) -> Result<u64, String> {
  let rt = p.get("refresh_type").and_then(|t| t.as_str()).unwrap_or("height");
  if rt != "date" {
    return p
      .get("refresh_start_height")
      .and_then(|v| v.as_u64())
      .or_else(|| {
        p.get("refresh_start_height")
          .and_then(|v| v.as_i64())
          .filter(|&i| i >= 0)
          .map(|i| i as u64)
      })
      .ok_or_else(|| "restore: refresh_start_height".to_string());
  }
  let date_str = p
    .get("refresh_start_date")
    .and_then(|d| d.as_str())
    .ok_or_else(|| "restore: refresh_start_date".to_string())?;
  let nd = NaiveDate::parse_from_str(date_str, "%Y/%m/%d")
    .map_err(|_| format!("restore: invalid date '{date_str}'"))?;
  let naive = nd
    .and_hms_opt(0, 0, 0)
    .ok_or_else(|| "restore: date".to_string())?;
  let ts = Utc.from_utc_datetime(&naive).timestamp();
  timestamp_to_height(st, http, ts).await
}

pub fn map_restore_deterministic_wallet (p: &Value, restore_height: u64) -> Result<Value, String> {
  let filename = p
    .get("name")
    .or_else(|| p.get("filename"))
    .and_then(|n| n.as_str())
    .ok_or_else(|| "restore_wallet: name".to_string())?
    .to_string();
  let password = p
    .get("password")
    .and_then(|x| x.as_str())
    .ok_or_else(|| "restore_wallet: password".to_string())?
    .to_string();
  let seed = p
    .get("seed")
    .and_then(|s| s.as_str())
    .ok_or_else(|| "restore_wallet: seed".to_string())?
    .trim()
    .to_string();
  Ok(json!({
    "filename": filename,
    "password": password,
    "seed": seed,
    "restore_height": restore_height
  }))
}

pub fn map_generate_from_keys (p: &Value, refresh_start_height: u64) -> Result<Value, String> {
  let filename = p
    .get("name")
    .or_else(|| p.get("filename"))
    .and_then(|n| n.as_str())
    .ok_or_else(|| "restore_view_wallet: name".to_string())?
    .to_string();
  let password = p
    .get("password")
    .and_then(|x| x.as_str())
    .ok_or_else(|| "restore_view_wallet: password".to_string())?
    .to_string();
  let address = p
    .get("address")
    .and_then(|a| a.as_str())
    .ok_or_else(|| "restore_view_wallet: address".to_string())?
    .to_string();
  let viewkey = p
    .get("viewkey")
    .and_then(|k| k.as_str())
    .ok_or_else(|| "restore_view_wallet: viewkey".to_string())?
    .to_string();
  Ok(json!({
    "filename": filename,
    "password": password,
    "address": address,
    "viewkey": viewkey,
    "refresh_start_height": refresh_start_height
  }))
}

pub fn map_stake_rpc (p: &Value) -> Result<Value, String> {
  let amount_ui = p
    .get("amount")
    .and_then(|a| {
      a.as_f64()
        .or_else(|| a.as_u64().map(|u| u as f64))
        .or_else(|| a.as_i64().map(|i| i as f64))
        .or_else(|| a.as_str().and_then(|s| s.parse().ok()))
    })
    .ok_or_else(|| "stake: amount".to_string())?;
  let amount_fixed: f64 = format!("{:.9}", amount_ui)
    .parse()
    .map_err(|_| "stake: amount parse".to_string())?;
  let atoms = (amount_fixed * crate::wallet_relay_ops::COIN_UNITS).round() as u64;
  let service_node_key = p
    .get("key")
    .or_else(|| p.get("service_node_key"))
    .and_then(|k| k.as_str())
    .ok_or_else(|| "stake: key".to_string())?
    .to_string();
  let destination = p
    .get("destination")
    .and_then(|d| d.as_str())
    .ok_or_else(|| "stake: destination".to_string())?
    .to_string();
  Ok(json!({
    "amount": atoms,
    "destination": destination,
    "service_node_key": service_node_key,
    "do_not_relay": true,
    "get_tx_metadata": true
  }))
}

pub fn map_register_service_node (p: &Value) -> Result<Value, String> {
  let s = p
    .get("string")
    .or_else(|| p.get("register_service_node_str"))
    .and_then(|x| x.as_str())
    .ok_or_else(|| "register_service_node: string".to_string())?
    .to_string();
  Ok(json!({ "register_service_node_str": s }))
}

pub fn map_set_tx_notes (p: &Value) -> Result<Value, String> {
  let txid = p
    .get("txid")
    .and_then(|t| t.as_str())
    .ok_or_else(|| "save_tx_notes: txid".to_string())?
    .to_string();
  let note = p.get("note").and_then(|n| n.as_str()).unwrap_or("").to_string();
  Ok(json!({
    "txids": [txid],
    "notes": [note]
  }))
}

pub fn map_change_wallet_password (p: &Value) -> Result<Value, String> {
  let old_password = p
    .get("old_password")
    .and_then(|x| x.as_str())
    .ok_or_else(|| "change_wallet_password: old_password".to_string())?
    .to_string();
  let new_password = p
    .get("new_password")
    .and_then(|x| x.as_str())
    .ok_or_else(|| "change_wallet_password: new_password".to_string())?
    .to_string();
  Ok(json!({ "old_password": old_password, "new_password": new_password }))
}

pub fn map_export_key_images (p: &Value) -> Result<Value, String> {
  let all = p.get("all").and_then(|v| v.as_bool()).unwrap_or(false);
  Ok(json!({ "all": all }))
}
