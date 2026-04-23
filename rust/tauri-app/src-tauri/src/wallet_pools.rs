//! `getPools` / `getPoolsData` — daemon `get_service_nodes` + wallet address (from `wallet-rpc.js`).
use crate::arqma_paths_config::daemon_rpc_host_port;
use crate::gateway_emit::emit_receive;
use crate::json_rpc_client::{WalletRpcClient, daemon_post};
use crate::wallet_relay_ops::COIN_UNITS;
use crate::AppData;
use reqwest::Client;
use serde_json::{json, Value};
use tauri::AppHandle;
use tauri::Manager;

const STAKING_SHARE: f64 = 18446744073709551612.0;

/// Like `Number.prototype.toLocaleString("en-US")` for ARQ amounts.
fn en_us_group_u64 (n: u64) -> String {
  if n == 0 {
    return "0".into();
  }
  let s = n.to_string();
  let mut acc = String::new();
  for (i, ch) in s.chars().rev().enumerate() {
    if i > 0 && i % 3 == 0 {
      acc.push(',');
    }
    acc.push(ch);
  }
  acc.chars().rev().collect()
}

/// Thousands separators and up to 9 fractional digits (trailing zeros trimmed) — like fractional `toLocaleString`.
fn en_us_format_amount (n: f64) -> String {
  if !n.is_finite() {
    return "0".into();
  }
  let sign = if n < 0.0 { "-" } else { "" };
  let n = n.abs();
  if n < 1e-12 {
    return format!("{sign}0");
  }
  let rounded = (n * 1_000_000_000.0).round() / 1_000_000_000.0;
  let s = format!("{:.9}", rounded);
  let s = s.trim_end_matches('0');
  let s = s.trim_end_matches('.');
  let parts: Vec<&str> = s.split('.').collect();
  let int_part: u64 = parts[0].parse().unwrap_or(0);
  let int_s = en_us_group_u64(int_part);
  if parts.len() < 2 || parts[1].is_empty() {
    return format!("{sign}{int_s}");
  }
  let dec = parts[1].trim_end_matches('0');
  if dec.is_empty() {
    format!("{sign}{int_s}")
  } else {
    format!("{sign}{int_s}.{dec}")
  }
}

/// Pool ownership percentage (like `toLocaleString` in `getPools`).
fn en_us_format_percent (n: f64) -> String {
  if !n.is_finite() || n == 0.0 {
    return String::new();
  }
  en_us_format_amount((n * 1e6).round() / 1e6)
}

fn unlock_time (requested: u64, height: u64) -> Value {
  if requested == 0 {
    return json!({ "amount": "", "i18n": "" });
  }
  let br = (requested as i64) - (height as i64);
  if br <= 0 {
    return json!({ "amount": "0", "i18n": "components.pool_list_tabular.days" });
  }
  if br < 720 {
    let h = (br as f64) / 30.0;
    return json!({ "amount": format!("{h:.1}"), "i18n": "components.pool_list_tabular.hours" });
  }
  let d = ((br as f64) / 720.0).ceil() as u64;
  json!({ "amount": d.to_string(), "i18n": "components.pool_list_tabular.days" })
}

fn operator_fee (portions: f64) -> Value {
  if portions == 0.0 {
    return json!(0);
  }
  if (portions - STAKING_SHARE).abs() < 1.0 {
    return json!("");
  }
  let x = (portions / STAKING_SHARE) * 100.0;
  if x >= 100.0 {
    return json!("");
  }
  json!(format!("{:.0} %", x))
}

/// `poolListHeightSorter` — descending by `registration_height` (`wallet-rpc.js`).
fn sort_operator_pools (pools: &mut [Value]) {
  fn reg_h (v: &Value) -> u64 {
    v
      .get("registration_height")
      .and_then(|h| h.as_u64().or(h.as_f64().map(|f| f as u64)))
      .unwrap_or(0)
  }
  pools.sort_by(|a, b| reg_h(b).cmp(&reg_h(a)));
}

/// `poolListContributorSorter` — `is_contributor` first, then descending `registration_height`.
fn sort_nonoperator_pools (pools: &mut [Value]) {
  use std::cmp::Ordering;
  fn reg_h (v: &Value) -> u64 {
    v
      .get("registration_height")
      .and_then(|h| h.as_u64().or(h.as_f64().map(|f| f as u64)))
      .unwrap_or(0)
  }
  fn is_contr (v: &Value) -> bool {
    v
      .get("is_contributor")
      .and_then(|b| b.as_bool())
      .unwrap_or(false)
  }
  pools.sort_by(|a, b| {
    let ac = is_contr(a);
    let bc = is_contr(b);
    if ac && !bc {
      return Ordering::Less;
    }
    if !ac && bc {
      return Ordering::Greater;
    }
    let ra = reg_h(a);
    let rb = reg_h(b);
    rb.cmp(&ra)
  });
}

pub async fn run_pool_tick (
  app: &AppHandle,
  http: &Client,
  w: &WalletRpcClient,
  config: &Value,
) {
  let Some((host, port)) = daemon_rpc_host_port(config) else {
    return;
  };
  let ginfo = match daemon_post(http, &host, port, "get_info", 0, &Value::Null).await {
    Ok(v) if v.get("error").is_none() => v,
    _ => return
  };
  let height = ginfo
    .pointer("/result/height")
    .and_then(|h| h.as_u64())
    .unwrap_or(0);
  let addr_r = w.call("get_address", &json!({ "account_index": 0 })).await;
  let my = match &addr_r {
    Ok(a) if a.get("error").is_none() => a
      .pointer("/result/address")
      .and_then(|a| a.as_str())
      .unwrap_or(""),
    _ => return
  }
  .to_string();
  let sn = match daemon_post(http, &host, port, "get_service_nodes", 0, &Value::Null).await {
    Ok(v) if v.get("error").is_none() => v,
    _ => return
  };
  let Some(states) = sn
    .pointer("/result/service_node_states")
    .and_then(|s| s.as_array())
  else {
    return;
  };
  let mut total_contributed_sum = 0.0f64;
  let mut active_count = 0u64;
  let mut staked_nodes_n = 0u64;
  let mut num_oper = 0u64;
  let mut total_staked_amt = 0.0f64;
  let mut op: Vec<Value> = Vec::new();
  let mut n_op: Vec<Value> = Vec::new();
  for pool in states {
    let total_c = pool
      .get("total_contributed")
      .and_then(|x| x.as_f64())
      .or_else(|| pool.get("total_contributed").and_then(|x| x.as_u64().map(|u| u as f64)))
      .unwrap_or(0.0);
    total_contributed_sum += total_c / COIN_UNITS;
    if pool.get("funded").and_then(|f| f.as_bool()) == Some(true) {
      active_count += 1;
    }
    let staked_s = en_us_format_amount(total_c / COIN_UNITS);
    let req = pool
      .get("staking_requirement")
      .and_then(|x| x.as_f64())
      .unwrap_or(0.0);
    let avail = en_us_format_amount(((req - total_c) / COIN_UNITS).max(0.0));
    let runl = pool
      .get("requested_unlock_height")
      .and_then(|x| x.as_u64())
      .unwrap_or(0);
    let lock = unlock_time(runl, height);
    let portions = pool
      .get("portions_for_operator")
      .and_then(|x| x.as_f64())
      .unwrap_or(0.0);
    let op_fee = operator_fee(portions);
    let op_addr = pool
      .get("operator_address")
      .and_then(|x| x.as_str())
      .unwrap_or("");
    let mut fpool = json!({
      "service_node_pubkey": pool.get("service_node_pubkey"),
      "operator_address": op_addr,
      "registration_height": pool.get("registration_height"),
      "funded": pool.get("funded"),
      "staked": staked_s,
      "equity": "",
      "lockup": lock,
      "available": avail,
      "operator_fee": op_fee,
      "is_contributor": false,
      "is_operator": false,
      "contributors": pool
        .get("contributors")
        .and_then(|c| c.as_array())
        .map(|a| a.len())
        .unwrap_or(0),
      "requested_unlock_height": pool.get("requested_unlock_height"),
      "last_reward_block_height": pool.get("last_reward_block_height"),
      "last_uptime_proof": pool.get("last_uptime_proof"),
      "staking_requirement": pool.get("staking_requirement"),
      "total_contributed": pool.get("total_contributed")
    });
    if op_addr != my {
      if let Some(cont) = pool.get("contributors").and_then(|c| c.as_array()) {
        if cont.iter().any(|k| {
          k.get("address")
            .and_then(|a| a.as_str())
            .map(|a| a == my)
            .unwrap_or(false)
        }) {
          let amount: f64 = cont
            .iter()
            .filter_map(|c| {
              if c
                .get("address")
                .and_then(|a| a.as_str())
                .map(|a| a == my)
                .unwrap_or(false)
              {
                c.get("amount").and_then(|a| a.as_f64().or(a.as_u64().map(|u| u as f64)))
              } else {
                None
              }
            })
            .sum();
          let eq = if total_c > 0.0 { (amount / total_c) * 100.0 } else { 0.0 };
          if let Some(obj) = fpool.as_object_mut() {
            obj.insert("equity".into(), json!(en_us_format_percent(eq)));
            obj.insert("is_contributor".into(), json!(true));
            obj.insert("is_operator".into(), json!(false));
          }
          n_op.push(fpool);
          staked_nodes_n += 1;
        } else {
          n_op.push(fpool);
        }
      } else {
        n_op.push(fpool);
      }
    } else {
      let amount: f64 = pool
        .get("contributors")
        .and_then(|c| c.as_array())
        .map(|a| {
          a
            .iter()
            .filter(|c| {
              c
                .get("address")
                .and_then(|x| x.as_str())
                .map(|a| a == my.as_str())
                .unwrap_or(false)
            })
            .filter_map(|c| c.get("amount").and_then(|m| m.as_f64().or(m.as_u64().map(|u| u as f64))))
            .sum()
        })
        .unwrap_or(0.0);
      if let Some(obj) = fpool.as_object_mut() {
        let eq = if total_c > 0.0 { (amount / total_c) * 100.0 } else { 0.0 };
        obj.insert("equity".into(), json!(en_us_format_percent(eq)));
        obj.insert("is_contributor".into(), json!(false));
        obj.insert("is_operator".into(), json!(true));
      }
      op.push(fpool);
      num_oper += 1;
      total_staked_amt += amount / COIN_UNITS;
      staked_nodes_n += 1;
    }
  }
  sort_operator_pools(&mut op);
  sort_nonoperator_pools(&mut n_op);
  let pools = json!({
    "operator_pools": op,
    "nonoperator_pools": n_op,
    "staker": { "stake": {
      "burnt_xeq": 0,
      "total_staked": total_staked_amt,
      "staked_nodes": staked_nodes_n,
      "num_operating": num_oper,
      "total_contributed": total_contributed_sum,
      "active_pool_count": active_count
    }}
  });
  let _ = emit_receive(app, "set_pools_data", pools);
}

pub fn start_stake_acquisition (
  app: &AppHandle,
  st: &mut crate::backend_state::WalletBackendState,
  http: &Client,
) {
  if st.wallet.is_none() {
    return;
  }
  if let Some(h) = st.stake_acquisition_task.take() {
    h.abort();
  }
  let app = app.clone();
  let c = http.clone();
  st.stake_acquisition_task = Some(tokio::spawn(async move {
    use tokio::time::{interval, MissedTickBehavior};
    let mut intv = interval(std::time::Duration::from_secs(5));
    intv.set_missed_tick_behavior(MissedTickBehavior::Skip);
    while app.try_state::<AppData>().is_some() {
      intv.tick().await;
      let Some(adata) = app.try_state::<AppData>() else {
        break;
      };
      let (cfg, fork) = {
        let b = adata.backend.lock().await;
        if b.wallet.is_none() {
          return;
        }
        (b.config_data.clone(), b.wallet.as_ref().unwrap().fork_for_heartbeat())
      };
      run_pool_tick(&app, &c, &fork, &cfg).await;
    }
  }));
}

pub fn end_stake_acquisition (st: &mut crate::backend_state::WalletBackendState) {
  if let Some(h) = st.stake_acquisition_task.take() {
    h.abort();
  }
}
