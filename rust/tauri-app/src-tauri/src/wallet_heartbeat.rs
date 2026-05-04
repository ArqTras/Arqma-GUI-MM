//! Wallet heartbeat pacing matches Electron **`wallet-rpc.js` → `startHeartbeat` / `heartbeatAction`**:
//! **5 s** between ticks on a **local** daemon, **60 s** when `daemons[net].type === "remote"`.
//! Each tick runs
//! `get_address` / `getheight` / `getbalance` like Electron; long `get_transfers` stays in a background task.
//! While catching up (wallet height behind daemon), `getheight` uses a **120 s** cap (Electron/Ryo-line
//! GUIs use ~5 s per call but run the three RPCs **in parallel**; here each call waits on
//! `wallet_rpc_lane`, so a single cap must cover queue + scan — see `gh_cap` below).
use crate::gateway_emit::emit_receive;
use crate::json_rpc_client::WalletRpcClient;
use crate::json_util::{json_rpc_no_error, value_as_u64, wallet_height_from_getheight};
use crate::sync_debug::is_sync_debug;
use crate::wallet_diag;
use crate::AppData;
use chrono::Utc;
use serde_json::{json, Value};
use tauri::AppHandle;
use tauri::Manager;
use std::time::{Duration, Instant};
use tokio::time::timeout;

/// Optional override for the **base** sleep between ticks (ms), replacing the Electron-style interval
/// (5 s local / 60 s remote). Set `ARQMA_WALLET_CATCHUP_POLL_MS` (e.g. `1000`) for local testing; pressure
/// backoff still applies on top when `wh_light_rpc_pressure > 0`.
fn catchup_poll_override_ms () -> Option<u64> {
  std::env::var("ARQMA_WALLET_CATCHUP_POLL_MS")
    .ok()
    .and_then(|s| s.trim().parse::<u64>().ok())
    .map(|ms| ms.clamp(1, 120_000))
}

fn periodic_store_secs () -> u64 {
  std::env::var("ARQMA_WALLET_PERIODIC_STORE_SECS")
    .ok()
    .and_then(|s| s.trim().parse::<u64>().ok())
    .map(|v| v.clamp(10, 3600))
    .unwrap_or(60)
}

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
  if let Some(h) = st.wh_periodic_store_task.take() {
    h.abort();
  }
  // Detach xfer `JoinHandle` without `abort()` — aggressive abort disrupted `arqma-wallet-rpc`
  // (HTTP session / worker) → `store` failed with reqwest 'error sending request' on close.
  let _ = st.wh_xfer_task.take();
  if let Some(h) = st.wallet_heartbeat.take() {
    h.abort();
  }
  if is_sync_debug() {
    eprintln!("[sync-debug][wallet-hb] stop heartbeat");
  }
  // Do not clear `wh_stored_*` here: `wallet_handler::close_wallet` calls `stop` *before*
  // `close_wallet_session_only` (store/close_wallet RPC). Zeroing would lose the last synced
  // height snapshot and skew backlog/telemetry (see debug `store_start` / close path).
  st.wh_heartbeat_ext_pending = false;
  st.wh_fetch_tx_pending = false;
  st.wh_catchup_last_heavy = None;
  st.wh_light_rpc_pressure = 0;
}

async fn run (app: &AppHandle, client: WalletRpcClient, is_local: bool) {
  // Mirrors `WalletRPC.startHeartbeat` in Electron `wallet-rpc.js`:
  // `this.local ? 5 * 1000 : 60 * 1000`.
  let electron_interval_ms = if is_local { 5000_u64 } else { 60_000_u64 };
  let mut cycle: u64 = 0;
  let mut last_periodic_store = Instant::now();
  while app.try_state::<AppData>().is_some() {
    cycle = cycle.wrapping_add(1);
    let t0 = Instant::now();
    if tick_once(app, &client).await {
      break;
    }
    maybe_schedule_periodic_store(app, &client, &mut last_periodic_store).await;
    let tick_ms = t0.elapsed().as_millis() as u64;
    let sleep_ms = {
      let Some(adata) = app.try_state::<AppData>() else {
        break;
      };
      let pressure = adata.backend.lock().await.wh_light_rpc_pressure;
      let base = catchup_poll_override_ms().unwrap_or(electron_interval_ms);
      if pressure == 0 {
        base
      } else {
        // Gentle exponential floor: failures → backoff up to ~12 s between ticks until recover.
        base
          .max(420u64.saturating_mul(1 + u64::from(pressure.min(28))))
          .min(12000)
      }
    };
    if is_sync_debug() {
      let Some(adata) = app.try_state::<AppData>() else {
        break;
      };
      let (wh, dh, pr) = {
        let b = adata.backend.lock().await;
        (b.wh_stored_height, b.daemon_last_height, b.wh_light_rpc_pressure)
      };
      eprintln!(
        "[sync-debug][wallet-hb] cycle={cycle} tick_ms={tick_ms} next_sleep_ms={sleep_ms} wh_stored={wh} daemon_last={dh} light_pressure={pr}"
      );
    }
    tokio::time::sleep(Duration::from_millis(sleep_ms)).await;
  }
}

async fn maybe_schedule_periodic_store (
  app: &AppHandle,
  c: &WalletRpcClient,
  last_periodic_store: &mut Instant,
) {
  let interval = Duration::from_secs(periodic_store_secs());
  if last_periodic_store.elapsed() < interval {
    return;
  }
  *last_periodic_store = Instant::now();
  let Some(adata) = app.try_state::<AppData>() else {
    return;
  };
  let (wallet_open, backlog) = {
    let b = adata.backend.lock().await;
    (
      !b.wh_display_name.is_empty(),
      b.daemon_last_height.saturating_sub(b.wh_stored_height),
    )
  };
  if !wallet_open {
    return;
  }
  let Ok(wallet_lane_hold) = adata.wallet_rpc_lane.clone().try_acquire_owned() else {
    return;
  };
  let c2 = c.split_session();
  let store_timeout_secs = if backlog > 5000 {
    120
  } else if backlog > 0 {
    45
  } else {
    15
  };
  let jh = tokio::spawn(async move {
    // Release lane before long `store` (same idea as background `get_transfers`): holding the permit
    // across the RPC blocked heartbeat `getheight` for up to `store_timeout_secs` → frozen sync % / UI.
    drop(wallet_lane_hold);
    match timeout(Duration::from_secs(store_timeout_secs), c2.call("store", &json!({}))).await {
      Ok(Ok(v)) if !json_rpc_no_error(&v) => {
        eprintln!("[wallet hb] periodic store rpc error: {:?}", v.get("error"));
      }
      Ok(Err(e)) => {
        eprintln!("[wallet hb] periodic store transport error: {e}");
      }
      Ok(Ok(_)) => {}
      Err(_) => {
        eprintln!(
          "[wallet hb] periodic store timeout after {}s (backlog={})",
          store_timeout_secs,
          backlog
        );
      }
    }
  });
  if let Some(adata2) = app.try_state::<AppData>() {
    let mut bk = adata2.backend.lock().await;
    if let Some(old) = bk.wh_periodic_store_task.replace(jh) {
      old.abort();
    }
  }
}

/// `true` means stop the loop.
async fn tick_once (app: &AppHandle, c: &WalletRpcClient) -> bool {
  let Some(adata) = app.try_state::<AppData>() else {
    return true;
  };
  let rpc_lane = adata.wallet_rpc_lane.clone();

  let (
    name,
    days_window,
    h0,
    b0,
    u0,
    ext_address_book,
    in_scan_rhythm,
    dh,
    backlog,
    force_fetch_tx,
  ) = {
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
    let in_scan_rhythm =
      dh == 0 || b.wh_stored_height < dh;
    let backlog = dh.saturating_sub(b.wh_stored_height);
    if !in_scan_rhythm {
      b.wh_catchup_last_heavy = None;
      b.wh_light_rpc_pressure = 0;
    }
    let force_fetch_tx = b.wh_fetch_tx_pending;
    (
      b.wh_display_name.clone(),
      d,
      b.wh_stored_height,
      b.wh_stored_balance,
      b.wh_stored_unlocked,
      b.wh_heartbeat_ext_pending,
      in_scan_rhythm,
      dh,
      backlog,
      force_fetch_tx,
    )
  };
  if is_sync_debug() {
    eprintln!(
      "[sync-debug][wallet-hb] tick wallet={} wh0={} daemon_last_h={} backlog={} scan_rhythm={} fetch_tx_pending={}",
      name,
      h0,
      dh,
      backlog,
      in_scan_rhythm,
      force_fetch_tx
    );
  }

  let p_addr = json!({ "account_index": 0 });
  let p_empty = json!({});
  let p_bal = json!({ "account_index": 0 });

  // Same order as Electron `heartbeatAction`: `getheight` first, then address + balance.
  // Electron `wallet-rpc.js`: each of the three uses `this.timeout` (5000 ms) but `Promise.allSettled`
  // runs them in parallel. Tauri holds `wallet_rpc_lane` per RPC, so after `open_wallet` / xfer the
  // process can be busy >15 s even when height matches daemon — avoid spurious timeouts (log noise,
  // `wh_light_rpc_pressure` backoff) by using 120 s in scan rhythm and a generous cap when "synced".
  let gh_cap = if in_scan_rhythm {
    Duration::from_secs(120)
  } else {
    Duration::from_secs(45)
  };
  let ab_cap = if in_scan_rhythm {
    Duration::from_secs(30)
  } else {
    Duration::from_secs(12)
  };

  let xfer_lane_heavy_bg = rpc_lane.clone();
  // Acquire **per RPC**, not one lumped hold: a long catch-up `getheight` (~120 s) must not prevent
  // `close_wallet` from taking the lone lane (`store`, `stop_wallet`).
  let _lane_gh = match rpc_lane.clone().acquire_owned().await {
    Ok(p) => p,
    Err(e) => {
      eprintln!("[wallet hb] tick: wallet_rpc_lane acquire(getheight): {}", e);
      return false;
    }
  };
  let gh = match timeout(gh_cap, c.call("getheight", &p_empty)).await {
    Ok(r) => r,
    Err(_) => {
      eprintln!("[wallet hb] getheight: timeout (wallet-rpc busy or scan backlog)");
      Err("timeout".to_string())
    }
  };
  drop(_lane_gh);

  let height_rpc_ok = matches!(&gh, Ok(v) if json_rpc_no_error(v));

  let ga = if height_rpc_ok {
    match rpc_lane.clone().acquire_owned().await {
      Ok(_lane_ga) => {
        let out = match timeout(ab_cap, c.call("get_address", &p_addr)).await {
          Ok(x) => x,
          Err(_) => Err("timeout".to_string()),
        };
        drop(_lane_ga);
        out
      }
      Err(e) => {
        eprintln!("[wallet hb] wallet_rpc_lane acquire(get_address): {}", e);
        Err("skipped".to_string())
      }
    }
  } else {
    Err("skipped".to_string())
  };

  let gb = match rpc_lane.clone().acquire_owned().await {
    Ok(_lane_gb) => {
      let out = match timeout(ab_cap, c.call("getbalance", &p_bal)).await {
        Ok(x) => x,
        Err(_) => Err("timeout".to_string()),
      };
      drop(_lane_gb);
      out
    }
    Err(e) => {
      eprintln!("[wallet hb] wallet_rpc_lane acquire(getbalance): {}", e);
      Err("skipped".to_string())
    }
  };

  // Oxen `heartbeatAction(true)`: if any of the three RPCs returns **-13** (“no wallet” / race while
  // another wallet syncs), close the session and notify — see `oxen-electron-gui-wallet` `wallet-rpc.js`.
  // `ext_address_book` is `wh_heartbeat_ext_pending` (first extended tick after `start`).
  if ext_address_book {
    let rpc_err_13 = |r: &Result<Value, String>| -> bool {
      matches!(
        r,
        Ok(v) if v.get("error").and_then(|e| e.get("code")).and_then(|c| c.as_i64()) == Some(-13)
      )
    };
    if rpc_err_13(&gh) || rpc_err_13(&ga) || rpc_err_13(&gb) {
      eprintln!(
        "[wallet hb] first extended tick: JSON-RPC code -13 (Oxen-style) — closing session and notifying UI"
      );
      if let Some(adata2) = app.try_state::<AppData>() {
        let mut b = adata2.backend.lock().await;
        stop(&mut b);
        crate::wallet_process::close_wallet_session_only(&mut b).await;
        b.wh_display_name.clear();
        b.wh_stored_height = 0;
        b.wh_stored_balance = 0;
        b.wh_stored_unlocked = 0;
      }
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
        "set_wallet_error",
        json!({
          "status": {
            "code": -1,
            "message": "Wallet session failed (-13)",
            "i18n": "notification.errors.failedWalletOpen"
          }
        }),
      );
      let _ = emit_receive(
        app,
        "reset_wallet_status",
        json!({
          "code": -1,
          "message": "Wallet session failed (-13)"
        }),
      );
      return true;
    }
  }

  {
    let mut b = adata.backend.lock().await;
    if matches!(gh.as_ref(), Ok(v) if json_rpc_no_error(v)) {
      b.wh_light_rpc_pressure = 0;
    } else {
      b.wh_light_rpc_pressure = b.wh_light_rpc_pressure.saturating_add(1).min(40);
    }
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
        // Emit balance fields whenever `getbalance` succeeds so the UI updates during scanning (Electron parity).
        info["balance"] = json!(bal);
        info["unlocked_balance"] = json!(unl);
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
  info["scan_poll_ts"] = json!(Utc::now().timestamp_millis());
  // Footer needs `height` every tick; `info` always contains it after the fallback above.
  let _ = emit_receive(app, "set_wallet_info", info.clone());
  let _ = emit_receive(
    app,
    "reset_wallet_status",
    json!({ "code": 0, "message": "OK" }),
  );

  // `wallet-rpc.js`: history lists refresh on **balance_change** until caught up; after sync every new
  // height also warrants a xfer pass. Opening a wallet keeps `force_fetch_tx` until the first xfer run.
  let xfer_trigger =
    force_fetch_tx || has_balance_change || (!in_scan_rhythm && new_h != h0);
  let heavy_height_changed = new_h != h0;
  let heavy_open_pending = force_fetch_tx;
  if xfer_trigger {
    if matches!(&gb, Ok(v) if json_rpc_no_error(v)) {
      let cur_h = new_h;
      // Run `get_transfers` (and the rest) on a second RPC session in the background. If it
      // stayed in this task, the heartbeat interval would not fire until the RPC finished, so
      // `getheight` would not refresh the footer (wallet sync % stuck for minutes).
      if let Ok(wallet_lane_hold) = xfer_lane_heavy_bg.clone().try_acquire_owned() {
            {
              let mut b = adata.backend.lock().await;
              b.wh_fetch_tx_pending = false;
            }
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
            let bal_ch = has_balance_change;
            let xfer_jh = tokio::spawn(async move {
              // **`try_acquire`** only gates *starting* xfer vs the main heartbeat tick (`getheight`/addr/balance).
              // **`get_transfers`** can run for minutes — **do not** hold `wallet_rpc_lane` across it or the footer
              // sync bar freezes (Electron used a concurrent queue here; heartbeat still polled height).
              drop(wallet_lane_hold);
              let txf_result =
                timeout(Duration::from_secs(300), c2.call("get_transfers", &p)).await;
              match txf_result {
                Err(_) => {
                  wallet_diag::log_always(
                    "get_transfers: timeout after 300s (heartbeat keeps updating footer)",
                  );
                }
                Ok(Err(e)) => {
                  wallet_diag::log_always(format!(
                    "get_transfers JSON-RPC transport: {e}"
                  ));
                }
                Ok(Ok(txf)) => {
                  if !json_rpc_no_error(&txf) {
                    wallet_diag::log_always(format!(
                      "get_transfers RPC error: {:?}",
                      txf.get("error")
                    ));
                  } else if let Some(r) = txf.get("result") {
                    let list = merge_transfers_list(r);
                    let n = list.len();
                    wallet_diag::log(format!(
                      "HEAVY get_transfers: {n} txs (height_changed={heavy_height_changed} balance_change={bal_ch} open_pending={heavy_open_pending})"
                    ));
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
        let mut bk = adata.backend.lock().await;
        if let Some(old) = bk.wh_xfer_task.replace(xfer_jh) {
          old.abort();
        }
      } else {
        wallet_diag::log_always(format!(
          "HEAVY get_transfers skipped: wallet_rpc_lane busy (height_changed={heavy_height_changed} balance_change={has_balance_change} open_pending={heavy_open_pending})"
        ));
        if is_sync_debug() {
          eprintln!(
            "[sync-debug][wallet-hb] get_transfers not started (wallet_rpc_lane busy)"
          );
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
