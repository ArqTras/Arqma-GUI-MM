//! `getheight` / `getbalance` / `get_transfers` loop like `WalletRPC.heartbeatAction` in Electron.
use crate::gateway_emit::emit_receive;
use crate::json_rpc_client::WalletRpcClient;
use crate::json_util::{json_rpc_no_error, value_as_u64, wallet_height_from_getheight};
use crate::sync_debug::is_sync_debug;
use crate::AppData;
use serde_json::{json, Value};
use tauri::AppHandle;
use tauri::Manager;
use std::time::{Duration, Instant};
use tokio::time::timeout;

/// While the wallet height is behind the daemon tip, use **only** `getheight` (light heartbeat).
/// Periodic `get_address` / `getbalance` / `get_transfers` contended with `wallet-rpc`’s own block
/// scan and kept `getheight` from advancing — footer % looked frozen near 100% for hundreds of blocks.

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
  st.wh_heartbeat_ext_pending = true;
  if is_sync_debug() {
    eprintln!(
      "[sync-debug][wallet-hb] start heartbeat is_local={is_local} wallet={}",
      st.wh_display_name
    );
  }
  st.wallet_heartbeat = Some(tokio::spawn(async move { run(&app, c, is_local).await }));
}

pub fn stop (st: &mut crate::backend_state::WalletBackendState) {
  if let Some(h) = st.wallet_heartbeat.take() {
    h.abort();
  }
  if is_sync_debug() {
    eprintln!("[sync-debug][wallet-hb] stop heartbeat");
  }
  st.wh_stored_height = 0;
  st.wh_stored_balance = 0;
  st.wh_stored_unlocked = 0;
  st.wh_heartbeat_ext_pending = false;
  st.wh_catchup_last_heavy = None;
}

async fn run (app: &AppHandle, client: WalletRpcClient, is_local: bool) {
  // Poll faster while the wallet is still far from the last known chain height (`daemon_last_height`)
  // so the footer "blocks scanned" / % update visibly during long rescans. When caught up, back off
  // to 1s (local) / 2s (remote daemon) to reduce wallet-rpc load.
  let mut cycle: u64 = 0;
  while app.try_state::<AppData>().is_some() {
    cycle = cycle.wrapping_add(1);
    let t0 = Instant::now();
    if tick_once(app, &client).await {
      break;
    }
    let tick_ms = t0.elapsed().as_millis() as u64;
    let sleep_ms = {
      let Some(adata) = app.try_state::<AppData>() else {
        break;
      };
      let b = adata.backend.lock().await;
      let base = if is_local { 1_000u64 } else { 2_000u64 };
      let wh = b.wh_stored_height;
      let dh = b.daemon_last_height;
      if wh > 0 && dh > 0 && wh + 1 < dh {
        // Larger backlog -> poll `getheight` more often so the footer does not look “stuck” while wallet-rpc is in a long scan.
        let backlog = dh.saturating_sub(wh);
        if backlog > 500_000 {
          250u64
        } else if backlog > 100_000 {
          350u64
        } else {
          500u64
        }
      } else {
        base
      }
    };
    if is_sync_debug() {
      let Some(adata) = app.try_state::<AppData>() else {
        break;
      };
      let (wh, dh) = {
        let b = adata.backend.lock().await;
        (b.wh_stored_height, b.daemon_last_height)
      };
      eprintln!(
        "[sync-debug][wallet-hb] cycle={cycle} tick_ms={tick_ms} next_sleep_ms={sleep_ms} wh_stored={wh} daemon_last={dh}"
      );
    }
    tokio::time::sleep(Duration::from_millis(sleep_ms)).await;
  }
}

/// `true` means stop the loop.
async fn tick_once (app: &AppHandle, c: &WalletRpcClient) -> bool {
  let Some(adata) = app.try_state::<AppData>() else {
    return true;
  };
  let (name, days_window, h0, b0, u0, ext_address_book, in_scan_rhythm, do_heavy, dh, backlog) = {
    let mut b = adata.backend.lock().await;
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
    let dh = b.daemon_last_height;
    let backlog = dh.saturating_sub(b.wh_stored_height);
    let in_scan_rhythm =
      b.wh_stored_height > 0 && dh > 0 && backlog > 0;
    if !in_scan_rhythm {
      b.wh_catchup_last_heavy = None;
    }
    // Never interleave balance/address/transfers RPCs while catching up — same process as Electron
    // “light” polling, but we previously ran HEAVY every 20s here which starved scan progress.
    let do_heavy = !in_scan_rhythm;
    (
      b.wh_display_name.clone(),
      d,
      b.wh_stored_height,
      b.wh_stored_balance,
      b.wh_stored_unlocked,
      b.wh_heartbeat_ext_pending,
      in_scan_rhythm,
      do_heavy,
      dh,
      backlog
    )
  };
  if is_sync_debug() {
    eprintln!(
      "[sync-debug][wallet-hb] tick wallet={} wh0={} daemon_last_h={} backlog={} scan_rhythm={} heavy={}",
      name, h0, dh, backlog, in_scan_rhythm, do_heavy
    );
  }

  let p_addr = json!({ "account_index": 0 });
  let p_empty = json!({});
  let p_bal = json!({ "account_index": 0 });

  // While `wh < daemon_tip`: only `getheight` — no balance/address/transfers on this RPC session.
  if in_scan_rhythm {
    // During heavy scan wallet-rpc often **blocks** `getheight` for many seconds; too short
    // a timeout yields a false “frozen” height in the footer (UI keeps seeing the same value).
    let gh = match timeout(Duration::from_secs(20), c.call("getheight", &p_empty)).await {
      Ok(r) => r,
      Err(_) => {
        eprintln!("[wallet hb] getheight (light): timeout");
        Err("timeout".to_string())
      }
    };
    let mut info = json!({ "name": &name });
    let mut new_h = h0;
    if let Ok(ref v) = gh {
      if json_rpc_no_error(v) {
        if let Some(h) = wallet_height_from_getheight(v) {
          new_h = h;
          info["height"] = json!(h);
        }
      }
    }
    if info.get("height").is_none() {
      info["height"] = json!(new_h);
    }
    {
      let mut b = adata.backend.lock().await;
      b.wh_stored_height = new_h;
    }
    let emitted_height = !info.get("height").is_none();
    if emitted_height {
      let _ = emit_receive(app, "set_wallet_info", info);
      let _ = emit_receive(
        app,
        "reset_wallet_status",
        json!({ "code": 0, "message": "OK" }),
      );
    }
    if is_sync_debug() {
      eprintln!(
        "[sync-debug][wallet-hb] LIGHT path done new_h={} prev_h0={} emitted_height={}",
        new_h, h0, emitted_height
      );
    }
    return false;
  }
  // Keep calls sequential (digest `nc` on one TCP session) — do **not** use `join!` here
  // (intermittent 401s were seen on parallel calls).
  // If wallet-rpc is busy scanning, a call can block indefinitely and freeze the whole heartbeat;
  // cap each RPC so the next tick (and `getheight` progress) can run.
  // Run `getheight` first: if it fails, skip the other calls this tick (avoids three timeouts in
  // a row when the endpoint is saturated — faster recovery on the next interval).
  let gh = match timeout(Duration::from_secs(15), c.call("getheight", &p_empty)).await {
    Ok(r) => r,
    Err(_) => {
      eprintln!("[wallet hb] getheight: timeout (wallet-rpc may be busy scanning)");
      Err("timeout".to_string())
    }
  };
  let height_rpc_ok = matches!(&gh, Ok(v) if json_rpc_no_error(v));
  let ga = if height_rpc_ok {
    match timeout(Duration::from_secs(6), c.call("get_address", &p_addr)).await {
      Ok(r) => r,
      Err(_) => Err("timeout".to_string()),
    }
  } else {
    Err("skipped".to_string())
  };
  let gb = if height_rpc_ok {
    match timeout(Duration::from_secs(6), c.call("getbalance", &p_bal)).await {
      Ok(r) => r,
      Err(_) => Err("timeout".to_string()),
    }
  } else {
    Err("skipped".to_string())
  };

  if is_sync_debug() {
    match &gh {
      Ok(v) if !json_rpc_no_error(v) => {
        eprintln!(
          "[sync-debug][wallet-hb] HEAVY getheight rpc error: {}",
          v.get("error").unwrap_or(&Value::Null)
        );
      }
      Ok(v) => {
        if let Some(h) = wallet_height_from_getheight(v) {
          eprintln!(
            "[sync-debug][wallet-hb] HEAVY getheight ok height={} (tick h0={})",
            h, h0
          );
        } else {
          eprintln!(
            "[sync-debug][wallet-hb] HEAVY getheight ok but missing result.height: {}",
            v.to_string().chars().take(400).collect::<String>()
          );
        }
      }
      Err(e) => eprintln!("[sync-debug][wallet-hb] HEAVY getheight err={e}"),
    }
    match &ga {
      Ok(v) if !json_rpc_no_error(v) => {
        eprintln!(
          "[sync-debug][wallet-hb] get_address error: {}",
          v.get("error").unwrap_or(&Value::Null)
        );
      }
      Err(e) if e.as_str() != "skipped" => {
        eprintln!("[sync-debug][wallet-hb] get_address err={e}");
      }
      _ => {}
    }
    match &gb {
      Ok(v) if !json_rpc_no_error(v) => {
        eprintln!(
          "[sync-debug][wallet-hb] getbalance error: {}",
          v.get("error").unwrap_or(&Value::Null)
        );
      }
      Err(e) if e.as_str() != "skipped" => {
        eprintln!("[sync-debug][wallet-hb] getbalance err={e}");
      }
      _ => {}
    }
  }

  let mut info = json!({ "name": &name });
  let mut new_h = h0;
  let mut new_b = b0;
  let mut new_u = u0;

  if let Ok(ref v) = gh {
    if json_rpc_no_error(v) {
      if let Some(h) = wallet_height_from_getheight(v) {
        new_h = h;
        info["height"] = json!(h);
      }
    }
  }
  // If `getheight` timed out or errored, keep last known height in the payload so the footer does
  // not look "stuck" with no number until the next successful RPC.
  if info.get("height").is_none() {
    info["height"] = json!(new_h);
  }
  if let Ok(ref v) = ga {
    if json_rpc_no_error(v) {
      if let Some(a) = v.pointer("/result/address") {
        info["address"] = a.clone();
      }
    }
  }
  let mut has_balance_change = false;
  if let Ok(ref v) = gb {
    if json_rpc_no_error(v) {
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

  // Commit height + emit **before** `get_transfers` / address-book work. That slow path can take
  // minutes on large windows; if we only updated after it, the footer "wallet sync" % would freeze
  // even though `wallet-rpc` `getheight` had already advanced.
  {
    let mut b = adata.backend.lock().await;
    b.wh_stored_height = new_h;
    b.wh_stored_balance = new_b;
    b.wh_stored_unlocked = new_u;
  }
  // Footer needs `height` every tick; `info` always contains it after the fallback above.
  let _ = emit_receive(app, "set_wallet_info", info.clone());
  let _ = emit_receive(
    app,
    "reset_wallet_status",
    json!({ "code": 0, "message": "OK" }),
  );

  if has_balance_change {
    if let (Ok(ghv), Ok(gbv)) = (&gh, &gb) {
      if json_rpc_no_error(ghv) && json_rpc_no_error(gbv) {
        if let Some(cur_h) = wallet_height_from_getheight(ghv) {
          // Run `get_transfers` (and the rest) on a second RPC session in the background. If it
          // stayed in this task, the heartbeat interval would not fire until the RPC finished, so
          // `getheight` would not refresh the footer (wallet sync % stuck for minutes).
          let sem = {
            let b = adata.backend.lock().await;
            b.wh_transfers_sem.clone()
          };
          if let Ok(permit) = sem.try_acquire_owned() {
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
            if is_sync_debug() {
              eprintln!(
                "[sync-debug][wallet-hb] spawn get_transfers bg cur_h={cur_h} min_height={min_height}"
              );
            }
            let app2 = app.clone();
            let c2 = c.split_session();
            let extb = ext_address_book;
            let opt_ga = if let Ok(v) = &ga { Some(v.clone()) } else { None };
            let opt_gb = if let Ok(v) = &gb { Some(v.clone()) } else { None };
            tokio::spawn(async move {
              let _p = permit;
              if let Ok(txf) = c2.call("get_transfers", &p).await {
                if txf.get("error").is_none() {
                  if let Some(r) = txf.get("result") {
                    let list = merge_transfers_list(r);
                    let _ = emit_receive(
                      &app2,
                      "set_wallet_transactions",
                      json!({ "tx_list": list }),
                    );
                  }
                }
              }
              if let (Some(ga_ok), Some(gb_ok)) = (opt_ga, opt_gb) {
                if json_rpc_no_error(&ga_ok) && json_rpc_no_error(&gb_ok) {
                  if let Some(built) = build_address_list_object(&ga_ok, &gb_ok) {
                    if let Some(final_al) = top_up_unused_subaddresses(&c2, built).await {
                      let _ = emit_receive(&app2, "set_wallet_address_list", final_al);
                    }
                  }
                }
              }
              if extb {
                if let Ok(bk) = fetch_address_book_map(&c2).await {
                  let _ = emit_receive(&app2, "set_wallet_address_book", bk);
                }
                if let Some(adata) = app2.try_state::<AppData>() {
                  let mut b = adata.backend.lock().await;
                  b.wh_heartbeat_ext_pending = false;
                }
              }
            });
          } else if is_sync_debug() {
            eprintln!(
              "[sync-debug][wallet-hb] get_transfers not started (transfers semaphore busy)"
            );
          }
        }
      }
    }
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
    if !json_rpc_no_error(&r) {
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
  if !json_rpc_no_error(&r) {
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
