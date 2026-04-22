//! `getheight` / `getbalance` / `get_transfers` loop like `WalletRPC.heartbeatAction` in Electron.
use crate::json_rpc_client::WalletRpcClient;
use crate::gateway_emit::emit_receive;
use crate::json_util::value_as_u64;
use crate::AppData;
use serde_json::{json, Value};
use tauri::AppHandle;
use tauri::Manager;
use tokio::time::{interval, MissedTickBehavior};

pub fn start (app: &AppHandle, st: &mut crate::backend_state::WalletBackendState, is_local: bool) {
  if st.wh_display_name.is_empty() {
    return;
  }
  if st.wallet.is_none() {
    return;
  }
  if let Some(h) = st.wallet_heartbeat.take() {
    h.abort();
  }
  let w = st.wallet.as_ref().expect("checked");
  let c = w.fork_for_heartbeat();
  let app = app.clone();
  let period = if is_local { 5u64 } else { 60u64 };
  st.wh_heartbeat_ext_pending = true;
  st.wallet_heartbeat = Some(tokio::spawn(async move { run(&app, c, period).await }));
}

pub fn stop (st: &mut crate::backend_state::WalletBackendState) {
  if let Some(h) = st.wallet_heartbeat.take() {
    h.abort();
  }
  st.wh_stored_height = 0;
  st.wh_stored_balance = 0;
  st.wh_stored_unlocked = 0;
  st.wh_heartbeat_ext_pending = false;
}

async fn run (app: &AppHandle, client: WalletRpcClient, period_secs: u64) {
  let mut intv = interval(std::time::Duration::from_secs(period_secs));
  intv.set_missed_tick_behavior(MissedTickBehavior::Skip);
  while app.try_state::<AppData>().is_some() {
    intv.tick().await;
    if tick_once(&app, &client).await {
      break;
    }
  }
}

/// `true` means stop the loop.
async fn tick_once (app: &AppHandle, c: &WalletRpcClient) -> bool {
  let Some(adata) = app.try_state::<AppData>() else {
    return true;
  };
  let (name, days_window, h0, b0, u0, ext_address_book) = {
    let b = adata.backend.lock().await;
    if b.wh_display_name.is_empty() {
      return true;
    }
    let d = b
      .config_data
      .get("app")
      .and_then(|a| a.get("daysOfTransactions"))
      .and_then(|d| d.as_u64())
      .unwrap_or(1)
      * 720;
    (
      b.wh_display_name.clone(),
      d,
      b.wh_stored_height,
      b.wh_stored_balance,
      b.wh_stored_unlocked,
      b.wh_heartbeat_ext_pending
    )
  };

  let p_addr = json!({ "account_index": 0 });
  let p_empty = json!({});
  let p_bal = json!({ "account_index": 0 });
  let (ga, gh, gb) = tokio::join!(
    c.call("get_address", &p_addr),
    c.call("getheight", &p_empty),
    c.call("getbalance", &p_bal),
  );

  let mut info = json!({ "name": &name });
  let mut new_h = h0;
  let mut new_b = b0;
  let mut new_u = u0;

  if let Ok(ref v) = gh {
    if v.get("error").is_none() {
      if let Some(h) = v.pointer("/result/height").and_then(value_as_u64) {
        new_h = h;
        info["height"] = json!(h);
      }
    }
  }
  if let Ok(ref v) = ga {
    if v.get("error").is_none() {
      if let Some(a) = v.pointer("/result/address") {
        info["address"] = a.clone();
      }
    }
  }
  let mut has_balance_change = false;
  if let Ok(ref v) = gb {
    if v.get("error").is_none() {
      if let (Some(bal), Some(unl)) = (
        v.pointer("/result/balance").and_then(value_as_u64),
        v.pointer("/result/unlocked_balance")
          .or_else(|| v.pointer("/result/unlocked"))
          .and_then(value_as_u64),
      ) {
        has_balance_change = !(b0 == bal && u0 == unl);
        new_b = bal;
        new_u = unl;
        if has_balance_change {
          info["balance"] = json!(bal);
          info["unlocked_balance"] = json!(unl);
        }
      }
    }
  }

  if has_balance_change {
    if let (Ok(ghv), Ok(gbv)) = (&gh, &gb) {
      if ghv.get("error").is_none() && gbv.get("error").is_none() {
        if let Some(cur_h) = ghv.pointer("/result/height").and_then(value_as_u64) {
          let min_height = cur_h.saturating_sub(days_window);
          let p = json!({
            "in": true,
            "out": true,
            "pending": true,
            "failed": true,
            "pool": false,
            "filter_by_height": true,
            "min_height": min_height
          });
          if let Ok(txf) = c.call("get_transfers", &p).await {
            if txf.get("error").is_none() {
              if let Some(r) = txf.get("result") {
                let list = merge_transfers_list(r);
                let _ = emit_receive(
                  app,
                  "set_wallet_transactions",
                  json!({ "tx_list": list }),
                );
              }
            }
          }
          if let (Ok(ref ga_ok), Ok(ref gb_ok)) = (&ga, &gb) {
            if ga_ok.get("error").is_none() && gb_ok.get("error").is_none() {
              if let Some(built) = build_address_list_object(ga_ok, gb_ok) {
                if let Some(final_al) = top_up_unused_subaddresses(c, built).await {
                  let _ = emit_receive(app, "set_wallet_address_list", final_al);
                }
              }
            }
          }
          if ext_address_book {
            if let Ok(bk) = fetch_address_book_map(c).await {
              let _ = emit_receive(app, "set_wallet_address_book", bk);
            }
            let mut b = adata.backend.lock().await;
            b.wh_heartbeat_ext_pending = false;
          }
        }
      }
    }
  }

  {
    let mut b = adata.backend.lock().await;
    b.wh_stored_height = new_h;
    b.wh_stored_balance = new_b;
    b.wh_stored_unlocked = new_u;
  }

  if !info.get("height").is_none() || has_balance_change {
    let _ = emit_receive(app, "set_wallet_info", info);
    let _ = emit_receive(
      app,
      "reset_wallet_status",
      json!({ "code": 0, "message": "OK" }),
    );
  }
  false
}

pub fn merge_transfers_list (result: &Value) -> Vec<Value> {
  let mut out: Vec<Value> = Vec::new();
  for k in [
    "in", "out", "pending", "failed", "pool", "miner", "snode", "gov", "stake"
  ] {
    if let Some(arr) = result.get(k).and_then(|v| v.as_array()) {
      for x in arr {
        out.push(x.clone());
      }
    }
  }
  out.sort_by(|a, b| {
    let ta = a.get("timestamp").and_then(|t| t.as_u64());
    let tb = b.get("timestamp").and_then(|t| t.as_u64());
    match (ta, tb) {
      (Some(x), Some(y)) => y.cmp(&x),
      (None, Some(_)) => std::cmp::Ordering::Less,
      (Some(_), None) => std::cmp::Ordering::Greater,
      (None, None) => std::cmp::Ordering::Equal
    }
  });
  for x in &mut out {
    if let Some(s) = x.get("payment_id").and_then(|p| p.as_str()) {
      if s.chars().all(|c| c == '0' || c == ' ') {
        if let Some(o) = x.as_object_mut() {
          o.insert("payment_id".into(), json!(""));
        }
      }
    }
  }
  out
}

/// `get_address` + `getbalance` → `{ primary, used, unused }` (like `getAddressList` in Node, without `create_address`).
fn build_address_list_object (ga: &Value, gb: &Value) -> Option<Value> {
  let res_a = ga.get("result")?;
  let res_b = gb.get("result")?;
  let mut rows: Vec<Value> = if let Some(a) = res_a.get("addresses").and_then(|x| x.as_array()) {
    a.iter().cloned().collect()
  } else {
    let addr = res_a.get("address").and_then(|s| s.as_str())?;
    vec![json!({ "address": addr, "address_index": 0, "used": true })]
  };
  for a in &mut rows {
    if let Some(m) = a.as_object_mut() {
      m.insert("balance".into(), json!(null));
      m.insert("unlocked_balance".into(), json!(null));
      m.insert("num_unspent_outputs".into(), json!(null));
    }
  }
  if let Some(parr) = res_b.get("per_subaddress").and_then(|p| p.as_array()) {
  for a in &mut rows {
    let idx = index_u64(a.get("address_index"));
    let Some(need) = idx else { continue };
    for ps in parr {
        if index_u64(ps.get("address_index")) == Some(need) {
          if let Some(m) = a.as_object_mut() {
            m.insert("balance".into(), ps.get("balance").cloned().unwrap_or(json!(null)));
            m.insert(
              "unlocked_balance".into(),
              ps
                .get("unlocked_balance")
                .cloned()
                .or_else(|| ps.get("unlocked").cloned())
                .unwrap_or(json!(null)),
            );
            m.insert(
              "num_unspent_outputs".into(),
              ps
                .get("num_unspent_outputs")
                .cloned()
                .unwrap_or(json!(null)),
            );
          }
          break;
        }
      }
    }
  }
  let mut primary: Vec<Value> = Vec::new();
  let mut used_l: Vec<Value> = Vec::new();
  let mut unused: Vec<Value> = Vec::new();
  for a in rows {
    let idx = index_u64(a.get("address_index"));
    let is_used = a.get("used").and_then(|u| u.as_bool());
    if idx == Some(0) {
      primary.push(a);
    } else if is_used == Some(true) {
      used_l.push(a);
    } else {
      unused.push(a);
    }
  }
  if unused.len() > 10 {
    unused.truncate(10);
  }
  Some(json!({ "primary": primary, "used": used_l, "unused": unused }))
}

fn index_u64 (v: Option<&Value>) -> Option<u64> {
  let v = v?;
  v.as_u64()
    .or_else(|| v.as_i64().map(|i| i as u64))
    .or_else(|| v.as_f64().map(|f| f as u64))
}

/// Pad unused subaddresses up to 10 (as in `wallet-rpc.js`).
async fn top_up_unused_subaddresses (
  c: &WalletRpcClient,
  al: Value,
) -> Option<Value> {
  const LIMIT: usize = 10;
  let primary_arr = al.get("primary")?.as_array()?;
  let p0a = primary_arr
    .get(0)?
    .get("address")
    .and_then(|a| a.as_str())?;
  let primary = primary_arr.clone();
  let used: Vec<Value> = al.get("used")?.as_array()?.clone();
  let mut unused: Vec<Value> = al.get("unused")?.as_array()?.clone();
  if unused.len() > LIMIT {
    unused.truncate(LIMIT);
  }
  if p0a.starts_with("RYoK") || p0a.starts_with("RYoH") {
    return Some(json!({ "primary": primary, "used": used, "unused": unused }));
  }
  while unused.len() < LIMIT {
    let r = c.call("create_address", &json!({ "account_index": 0 })).await.ok()?;
    if r.get("error").is_some() {
      break;
    }
    match r.get("result") {
      Some(x) if !x.is_null() => {
        unused.push(x.clone());
      }
      _ => break
    }
  }
  Some(json!({ "primary": primary, "used": used, "unused": unused }))
}

/// Build payload for `set_wallet_address_book` (`address_book` + `address_book_starred`).
pub async fn fetch_address_book_map (c: &WalletRpcClient) -> Result<Value, String> {
  let r = c.call("get_address_book", &json!({})).await?;
  if r.get("error").is_some() {
    return Ok(json!({ "address_book": [], "address_book_starred": [] }));
  }
  let Some(entries) = r.pointer("/result/entries").and_then(|e| e.as_array()) else {
    return Ok(json!({ "address_book": [], "address_book_starred": [] }));
  };
  let mut book: Vec<Value> = Vec::new();
  let mut starred: Vec<Value> = Vec::new();
  for e in entries {
    let mut e = e.clone();
    if let Some(fulld) = e.get("description").and_then(|d| d.as_str()).map(str::to_string) {
      let p: Vec<&str> = fulld.split("::").collect();
      if p.len() == 3 {
        if let Some(o) = e.as_object_mut() {
          o.insert("starred".into(), json!(p[0] == "starred"));
          o.insert("name".into(), json!(p[1]));
          o.insert("description".into(), json!(p[2]));
        }
      } else if p.len() == 2 {
        if let Some(o) = e.as_object_mut() {
          o.insert("starred".into(), json!(false));
          o.insert("name".into(), json!(p[0]));
          o.insert("description".into(), json!(p[1]));
        }
      } else if let Some(o) = e.as_object_mut() {
        o.insert("starred".into(), json!(false));
        o.insert("name".into(), json!(&fulld));
        o.insert("description".into(), json!(""));
      }
    } else if let Some(o) = e.as_object_mut() {
      o.insert("starred".into(), json!(false));
      o.insert("name".into(), json!(""));
      o.insert("description".into(), json!(""));
    }
    if let Some(pid) = e
      .get("payment_id")
      .and_then(|p| p.as_str())
      .map(str::to_string)
    {
      if let Some(m) = e.as_object_mut() {
        if pid.chars().all(|c| c == '0' || c == ' ') {
          m.insert("payment_id".into(), json!(""));
        } else if pid.len() > 16 && pid[16..].chars().all(|c| c == '0' || c == ' ') {
          m.insert("payment_id".into(), json!(&pid[..16]));
        }
      }
    }
    let is_star = e
      .get("starred")
      .and_then(|s| s.as_bool())
      .unwrap_or(false);
    if is_star {
      starred.push(e);
    } else {
      book.push(e);
    }
  }
  Ok(json!({ "address_book": book, "address_book_starred": starred }))
}
