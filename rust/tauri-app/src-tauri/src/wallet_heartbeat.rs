//! `getheight` / `getbalance` / `get_transfers` loop like `WalletRPC.heartbeatAction` in Electron.
//! Initial `get_transfers` is also forced once when `wh_pending_initial_transfers` is set (open /
//! new wallet), matching Electron’s first heartbeat where `wallet_state.balance` is still `null`.
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

/// `wallet-rpc.js` `this.timeout` (ms) — `heartbeatAction` uses it for `get_address` / `getheight` /
/// `getbalance`.
const WALLET_HEARTBEAT_RPC_TIMEOUT: Duration = Duration::from_secs(5);
/// `sendRPC` with `timeout === 0` uses **30000** ms (`timeoutMs` in `wallet-rpc.js`).
const WALLET_RPC_UNTYPED_TIMEOUT: Duration = Duration::from_secs(30);
/// `this.twoMinuteTimeout` for long calls such as `rescan_blockchain`.
const WALLET_RPC_TWO_MIN_TIMEOUT: Duration = Duration::from_secs(120);
/// While the wallet is catching up, `getheight` may block for a long time (same worker as scan);
/// a short timeout would drop every response and the footer % would look frozen for the whole rescan.
const WALLET_LIGHT_GETHEIGHT_TIMEOUT: Duration = Duration::from_secs(120);
/// After catch-up, `getheight` is usually fast; allow more than heartbeat 5s when `wallet-rpc` is still busy.
const WALLET_HEAVY_GETHEIGHT_TIMEOUT: Duration = Duration::from_secs(30);

async fn rpc_timeout (
  limit: Duration,
  fut: impl std::future::Future<Output = Result<Value, String>>,
) -> Result<Value, String> {
  match timeout(limit, fut).await {
    Ok(Ok(v)) => Ok(v),
    Ok(Err(e)) => Err(e),
    Err(_) => Err("timeout".to_string()),
  }
}

/// While the wallet height is behind the daemon tip, the main digest loop is **light** (`getheight`
/// only, fast sleeps) so the footer keeps moving. Balance / `get_transfers` follow Electron’s
/// cadence on a **second** digest session (`maybe_spawn_scan_rhythm_balance_probe`).

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
  if let Some(h) = st.wallet_log_height.take() {
    h.abort();
  }
  if is_sync_debug() {
    eprintln!("[sync-debug][wallet-hb] stop heartbeat");
  }
  st.wh_stored_height = 0;
  st.wh_stored_balance = 0;
  st.wh_stored_unlocked = 0;
  st.wh_pending_initial_transfers = false;
  st.wh_heartbeat_ext_pending = false;
  st.wh_catchup_last_heavy = None;
  st.wh_getheight_error_streak = 0;
  st.wh_last_scan_balance_probe = None;
  st.wh_last_catchup_store_at = None;
  st.wh_height_at_last_store = 0;
  st.wh_did_sync_store = false;
}

async fn run (app: &AppHandle, client: WalletRpcClient, is_local: bool) {
  // Poll faster while the wallet is still far from the last known chain height (`daemon_last_height`)
  // so the footer "blocks scanned" / % update visibly during long rescans. When caught up, back off
  // to 1s (local) — same as Electron `setInterval` for local. For **remote** daemon, Electron uses
  // `60 * 1000` ms between `heartbeatAction`; match that here when not in catch-up (light `getheight`
  // rhythm still uses short sleeps so remote rescans are not stuck for a minute between height ticks).
  let mut cycle: u64 = 0;
  while app.try_state::<AppData>().is_some() {
    cycle = cycle.wrapping_add(1);
    let t0 = Instant::now();
    if tick_once(app, &client, is_local).await {
      break;
    }
    let tick_ms = t0.elapsed().as_millis() as u64;
    let sleep_ms = {
      let Some(adata) = app.try_state::<AppData>() else {
        break;
      };
      let b = adata.backend.lock().await;
      let wh = b.wh_stored_height;
      let dh = b.daemon_last_height;
      let in_catchup_rhythm = wh > 0 && dh > 0 && wh + 1 < dh;
      if in_catchup_rhythm {
        // Larger backlog -> poll `getheight` more often so the footer does not look “stuck” while wallet-rpc is in a long scan.
        let backlog = dh.saturating_sub(wh);
        if backlog > 500_000 {
          250u64
        } else if backlog > 100_000 {
          350u64
        } else {
          500u64
        }
      } else if is_local {
        1_000u64
      } else {
        60_000u64
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

fn scan_balance_probe_interval (is_local: bool) -> Duration {
  if is_local {
    WALLET_HEARTBEAT_RPC_TIMEOUT
  } else {
    Duration::from_secs(60)
  }
}

/// Like Electron `heartbeatAction` while scanning: periodic `getbalance`, then when transfers are
/// needed (`balance` change or `wh_pending_initial_transfers`) **`get_address` and `get_transfers`
/// in parallel** (cf. `Promise.allSettled`), then address list / optional address book on the address
/// session — main digest loop keeps `getheight` only.
async fn maybe_spawn_scan_rhythm_balance_probe (
  app: &AppHandle,
  main_client: &WalletRpcClient,
  is_local: bool,
  wallet_name: &str,
  days_window: u64,
  ext_address_book: bool,
) {
  let interval = scan_balance_probe_interval(is_local);
  let Some(adata) = app.try_state::<AppData>() else {
    return;
  };
  // `arqma-wallet-rpc` typically serves JSON-RPC from one worker: parallel `getbalance` /
  // `get_transfers` on split digest sessions can queue ahead of `getheight` and freeze the footer
  // for thousands of blocks (CLI shows tip while GUI height stalls).
  {
    let b = adata.backend.lock().await;
    if b.wh_display_name != wallet_name {
      return;
    }
    let backlog = b.daemon_last_height.saturating_sub(b.wh_stored_height);
    if backlog > 0 {
      return;
    }
  }
  let should = {
    let b = adata.backend.lock().await;
    if b.wh_display_name != wallet_name {
      return;
    }
    match b.wh_last_scan_balance_probe {
      None => true,
      Some(t) => t.elapsed() >= interval,
    }
  };
  if !should {
    return;
  }
  let sem = {
    let b = adata.backend.lock().await;
    b.wh_transfers_sem.clone()
  };
  let Ok(permit) = sem.try_acquire_owned() else {
    return;
  };
  {
    let Some(adata) = app.try_state::<AppData>() else {
      return;
    };
    let mut b = adata.backend.lock().await;
    if b.wh_display_name != wallet_name {
      return;
    }
    b.wh_last_scan_balance_probe = Some(Instant::now());
  }
  let wallet_name = wallet_name.to_string();
  let app2 = app.clone();
  let c_bal = main_client.split_session();
  let c_addr = main_client.split_session();
  let c_tx = main_client.split_session();
  tokio::spawn(async move {
    let _p = permit;
    let p_bal = json!({ "account_index": 0 });
    let gb = rpc_timeout(WALLET_HEARTBEAT_RPC_TIMEOUT, c_bal.call("getbalance", &p_bal)).await;
    if gb.is_err() {
      return;
    }
    let gb_ok = match &gb {
      Ok(v) if json_rpc_no_error(v) => v.clone(),
      _ => return,
    };
    let Some(r) = gb_ok.get("result") else {
      return;
    };
    let Some(bal) = r.get("balance").and_then(value_as_u64) else {
      return;
    };
    let unl = r
      .get("unlocked_balance")
      .or_else(|| r.get("unlocked"))
      .and_then(value_as_u64)
      .unwrap_or(bal);
    let (stored_h, balance_change, need_transfers) = {
      let Some(adata) = app2.try_state::<AppData>() else {
        return;
      };
      let mut b = adata.backend.lock().await;
      if b.wh_display_name != wallet_name {
        return;
      }
      let ch = b.wh_stored_balance != bal || b.wh_stored_unlocked != unl;
      let pend = b.wh_pending_initial_transfers;
      // Catch-up skipped sidecar entirely (`backlog > 0`); here `backlog == 0` at probe scheduling time.
      let need = ch || pend;
      if ch {
        b.wh_stored_balance = bal;
        b.wh_stored_unlocked = unl;
      }
      (b.wh_stored_height, ch, need)
    };
    if balance_change {
      let _ = emit_receive(
        &app2,
        "set_wallet_info",
        json!({
          "name": wallet_name,
          "balance": bal,
          "unlocked_balance": unl,
          "height": stored_h
        }),
      );
      let _ = emit_receive(
        &app2,
        "reset_wallet_status",
        json!({ "code": 0, "message": "OK" }),
      );
    }
    if !need_transfers {
      return;
    }
    let min_height = stored_h.saturating_sub(days_window);
    let p_addr = json!({ "account_index": 0 });
    let p_tx = json!({
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
        "[sync-debug][wallet-hb] scan-rhythm sidecar join get_address+get_transfers min_h={min_height} h={stored_h}"
      );
    }
    let (ga, txf) = tokio::join!(
      rpc_timeout(WALLET_HEARTBEAT_RPC_TIMEOUT, c_addr.call("get_address", &p_addr)),
      rpc_timeout(WALLET_RPC_UNTYPED_TIMEOUT, c_tx.call("get_transfers", &p_tx))
    );
    if let Ok(ref ga_v) = ga {
      if json_rpc_no_error(ga_v) && json_rpc_no_error(&gb_ok) {
        if let Some(built) = build_address_list_object(ga_v, &gb_ok) {
          if let Some(final_al) = top_up_unused_subaddresses(&c_addr, built).await {
            let _ = emit_receive(&app2, "set_wallet_address_list", final_al);
          }
        }
      }
    }
    if ext_address_book {
      if let Ok(bk) = fetch_address_book_map(&c_addr).await {
        let _ = emit_receive(&app2, "set_wallet_address_book", bk);
      }
      if let Some(adata) = app2.try_state::<AppData>() {
        let mut b = adata.backend.lock().await;
        if b.wh_display_name == wallet_name {
          b.wh_heartbeat_ext_pending = false;
        }
      }
    }
    if let Ok(ref txv) = txf {
      if json_rpc_no_error(txv) {
        if let Some(res) = txv.get("result") {
          let list = merge_transfers_list(res);
          let _ = emit_receive(
            &app2,
            "set_wallet_transactions",
            json!({ "tx_list": list }),
          );
          if let Some(adata) = app2.try_state::<AppData>() {
            let mut b = adata.backend.lock().await;
            if b.wh_display_name == wallet_name {
              b.wh_pending_initial_transfers = false;
            }
          }
        }
      }
    }
  });
}

/// `true` means stop the loop.
async fn tick_once (app: &AppHandle, c: &WalletRpcClient, is_local: bool) -> bool {
  let Some(adata) = app.try_state::<AppData>() else {
    return true;
  };
  let (
    name,
    days_window,
    h0,
    b0,
    u0,
    ext_address_book,
    in_scan_rhythm,
    do_heavy,
    dh,
    backlog,
    pending_initial_transfers,
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
    let backlog = dh.saturating_sub(b.wh_stored_height);
    let in_scan_rhythm =
      b.wh_stored_height > 0 && dh > 0 && backlog > 0;
    if !in_scan_rhythm {
      b.wh_catchup_last_heavy = None;
    }
    // Heavy path only after catch-up; during catch-up balance/transfers use the sidecar session.
    let do_heavy = !in_scan_rhythm;
    let pending_initial_transfers = b.wh_pending_initial_transfers;
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
      backlog,
      pending_initial_transfers,
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

  // While `wh < daemon_tip`: only `getheight` on this digest session; balance/transfers use a
  // forked client on the Electron heartbeat cadence (see `maybe_spawn_scan_rhythm_balance_probe`).
  if in_scan_rhythm {
    // Do **not** use the 5s heartbeat timeout here: during chain scan `getheight` routinely exceeds it,
    // which would yield only timeouts and a stuck footer until the scan finished.
    let gh = rpc_timeout(WALLET_LIGHT_GETHEIGHT_TIMEOUT, c.call("getheight", &p_empty)).await;
    if gh.is_err() {
      eprintln!("[wallet hb] getheight (light): timeout");
    }
    let rpc_err = matches!(&gh, Ok(v) if !json_rpc_no_error(v));
    let rpc_ok = matches!(&gh, Ok(v) if json_rpc_no_error(v));
    let should_auto_hard = if let Some(adata) = app.try_state::<AppData>() {
      let mut b = adata.backend.lock().await;
      if rpc_ok {
        b.wh_getheight_error_streak = 0;
        false
      } else if rpc_err {
        b.wh_getheight_error_streak = b.wh_getheight_error_streak.saturating_add(1);
        let cool = b
          .wh_last_automatic_hard_rescan
          .map(|t| t.elapsed().as_secs() >= 600)
          .unwrap_or(true);
        b.wh_getheight_error_streak >= 3 && cool
      } else {
        false
      }
    } else {
      false
    };
    if should_auto_hard {
      eprintln!(
        "[wallet hb] getheight: repeated JSON-RPC error while scanning — calling rescan_blockchain {{ hard: true }}"
      );
      let res = timeout(WALLET_RPC_TWO_MIN_TIMEOUT, c.call("rescan_blockchain", &json!({ "hard": true }))).await;
      if let Some(adata) = app.try_state::<AppData>() {
        let mut b = adata.backend.lock().await;
        b.wh_last_automatic_hard_rescan = Some(Instant::now());
        b.wh_getheight_error_streak = 0;
      }
      match res {
        Ok(Ok(v)) if v.get("error").is_some() => eprintln!("[wallet hb] auto rescan hard: {:?}", v.get("error")),
        Ok(Err(e)) => eprintln!("[wallet hb] auto rescan hard: {e}"),
        Err(_) => eprintln!("[wallet hb] auto rescan hard: RPC timed out (120s)"),
        _ => eprintln!("[wallet hb] auto rescan hard: accepted"),
      }
    }
    let mut info = json!({ "name": &name });
    let mut new_h = h0;
    if let Ok(ref v) = gh {
      if json_rpc_no_error(v) {
        if let Some(h) = wallet_height_from_getheight(v) {
          // Do not move the footer backwards on a flaky / interleaved RPC read while scanning.
          new_h = h.max(h0);
          info["height"] = json!(new_h);
        }
      }
    }
    if info.get("height").is_none() {
      info["height"] = json!(new_h);
    }
    let now_ms = std::time::SystemTime::now()
      .duration_since(std::time::UNIX_EPOCH)
      .map(|d| d.as_millis() as u64)
      .unwrap_or(0);
    info["scan_poll_ts"] = json!(now_ms);
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
    let gh_ok_height = matches!(
      &gh,
      Ok(v) if json_rpc_no_error(v) && wallet_height_from_getheight(v).is_some()
    );
    if gh_ok_height {
      let backlog_rem = dh.saturating_sub(new_h);
      const STORE_MIN_INTERVAL: Duration = Duration::from_secs(90);
      const STORE_BLOCK_STRIDE: u64 = 2000;
      let mut do_store = false;
      if let Some(adata_s) = app.try_state::<AppData>() {
        let mut b = adata_s.backend.lock().await;
        if b.wh_display_name == name {
          let at_tip = dh > 0 && new_h >= dh.saturating_sub(1);
          if at_tip && !b.wh_did_sync_store {
            b.wh_did_sync_store = true;
            do_store = true;
          } else if backlog_rem > 0 && !b.wh_did_sync_store {
            let time_ok = b
              .wh_last_catchup_store_at
              .map(|t| t.elapsed() >= STORE_MIN_INTERVAL)
              .unwrap_or(false);
            let stride_ok =
              new_h.saturating_sub(b.wh_height_at_last_store) >= STORE_BLOCK_STRIDE;
            if time_ok || stride_ok {
              do_store = true;
            }
          }
          if do_store {
            b.wh_last_catchup_store_at = Some(Instant::now());
            b.wh_height_at_last_store = new_h;
          }
        }
      }
      if do_store {
        // Same digest session as `getheight` — a parallel `store` on `split_session` can still
        // queue behind other work and starve height polls on single-worker wallet-rpc.
        let _ = rpc_timeout(Duration::from_secs(180), c.call("store", &json!({}))).await;
        if is_sync_debug() {
          eprintln!("[sync-debug][wallet-hb] catch-up store (sequential) done");
        }
      }
    }
    if is_sync_debug() {
      eprintln!(
        "[sync-debug][wallet-hb] LIGHT path done new_h={} prev_h0={} emitted_height={}",
        new_h, h0, emitted_height
      );
    }
    maybe_spawn_scan_rhythm_balance_probe(
      app,
      c,
      is_local,
      name.as_str(),
      days_window,
      ext_address_book,
    )
    .await;
    return false;
  }
  // Keep calls sequential (digest `nc` on one TCP session) — do **not** use `join!` here
  // (intermittent 401s were seen on parallel calls).
  // If wallet-rpc is busy scanning, a call can block indefinitely and freeze the whole heartbeat;
  // cap each RPC so the next tick (and `getheight` progress) can run.
  // Run `getheight` first: if it fails, skip the other calls this tick (avoids three timeouts in
  // a row when the endpoint is saturated — faster recovery on the next interval).
  let gh = rpc_timeout(WALLET_HEAVY_GETHEIGHT_TIMEOUT, c.call("getheight", &p_empty)).await;
  if gh.is_err() {
    eprintln!("[wallet hb] getheight: timeout (wallet-rpc may be busy scanning)");
  }
  let height_rpc_ok = matches!(&gh, Ok(v) if json_rpc_no_error(v));
  let ga = if height_rpc_ok {
    rpc_timeout(WALLET_HEARTBEAT_RPC_TIMEOUT, c.call("get_address", &p_addr)).await
  } else {
    Err("skipped".to_string())
  };
  let gb = if height_rpc_ok {
    rpc_timeout(WALLET_HEARTBEAT_RPC_TIMEOUT, c.call("getbalance", &p_bal)).await
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
        new_h = h.max(h0);
        info["height"] = json!(new_h);
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
  // Wallet already at tip (no LIGHT catch-up ticks) — still persist once like CLI `store`.
  if height_rpc_ok && new_h >= dh.saturating_sub(1) && dh > 0 {
    let mut do_tip_store = false;
    if let Some(adata2) = app.try_state::<AppData>() {
      let mut b2 = adata2.backend.lock().await;
      if b2.wh_display_name == name && !b2.wh_did_sync_store {
        b2.wh_did_sync_store = true;
        do_tip_store = true;
        b2.wh_last_catchup_store_at = Some(Instant::now());
        b2.wh_height_at_last_store = new_h;
      }
    }
    if do_tip_store {
      let _ = rpc_timeout(Duration::from_secs(180), c.call("store", &json!({}))).await;
    }
  }
  // Footer needs `height` every tick; `info` always contains it after the fallback above.
  let _ = emit_receive(app, "set_wallet_info", info.clone());
  let _ = emit_receive(
    app,
    "reset_wallet_status",
    json!({ "code": 0, "message": "OK" }),
  );

  let fetch_transfers = has_balance_change || pending_initial_transfers;
  if fetch_transfers {
    if let (Ok(ghv), Ok(gbv)) = (&gh, &gb) {
      if json_rpc_no_error(ghv) && json_rpc_no_error(gbv) {
        if let Some(cur_h) = wallet_height_from_getheight(ghv) {
          // Background work on forked digest sessions so the main heartbeat keeps ticking. When the
          // extended address book is due, `get_transfers` and `get_address_book` run in parallel
          // (cf. Electron `Promise.allSettled`); address list still uses `get_address`/`getbalance`
          // from this tick (`opt_ga` / `opt_gb`).
          let sem = {
            let b = adata.backend.lock().await;
            b.wh_transfers_sem.clone()
          };
          if let Ok(permit) = sem.try_acquire_owned() {
            if let Some(adata2) = app.try_state::<AppData>() {
              let mut b2 = adata2.backend.lock().await;
              b2.wh_pending_initial_transfers = false;
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
                "[sync-debug][wallet-hb] spawn bg cur_h={cur_h} min_height={min_height} ext_book={ext_address_book}"
              );
            }
            let app2 = app.clone();
            let c_tx = c.split_session();
            let c_book = c.split_session();
            let extb = ext_address_book;
            let opt_ga = if let Ok(v) = &ga { Some(v.clone()) } else { None };
            let opt_gb = if let Ok(v) = &gb { Some(v.clone()) } else { None };
            tokio::spawn(async move {
              let _p = permit;
              let (txf, bk_opt): (_, Option<Result<Value, String>>) = if extb {
                let (t, b) = tokio::join!(
                  rpc_timeout(WALLET_RPC_UNTYPED_TIMEOUT, c_tx.call("get_transfers", &p)),
                  rpc_timeout(WALLET_RPC_UNTYPED_TIMEOUT, fetch_address_book_map(&c_book))
                );
                (t, Some(b))
              } else {
                (
                  rpc_timeout(WALLET_RPC_UNTYPED_TIMEOUT, c_tx.call("get_transfers", &p)).await,
                  None,
                )
              };
              if let Ok(ref txv) = txf {
                if json_rpc_no_error(txv) {
                  if let Some(r) = txv.get("result") {
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
                    if let Some(final_al) = top_up_unused_subaddresses(&c_tx, built).await {
                      let _ = emit_receive(&app2, "set_wallet_address_list", final_al);
                    }
                  }
                }
              }
              if extb {
                if let Some(Ok(ref bk)) = bk_opt {
                  let _ = emit_receive(&app2, "set_wallet_address_book", bk.clone());
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
