//! `get_info` / `get_connections` / `get_bans` loop like `Daemon.heartbeat` in Electron.
use crate::arqma_paths_config::daemon_rpc_host_port;
use crate::backend_state::WalletBackendState;
use crate::daemon_process::restart_local_daemon_if_exited;
use crate::gateway_emit::BackendReceiveSink;
use crate::json_rpc_client::daemon_post;
use crate::json_util::{json_rpc_no_error, value_as_u64};
use crate::sync_debug::is_sync_debug;
use crate::AppData;
use reqwest::Client;
use serde_json::{json, Value};
use tauri::AppHandle;
use tauri::Manager;
use tokio::time::{interval, MissedTickBehavior};

fn app_testnet(cfg: &serde_json::Value) -> bool {
    cfg.get("app")
        .and_then(|a| a.get("testnet"))
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
}

/// Start background loop after successful `ensure_daemon_for_startup` (5s local / 30s remote; slow path every 60s, local only).
pub fn start(app: &AppHandle, st: &mut WalletBackendState, is_local: bool, http: &Client) {
    if let Some(h) = st.daemon_heartbeat.take() {
        h.abort();
    }
    st.daemon_last_height = 0;
    let app = app.clone();
    let c = http.clone();
    let fast_secs = if is_local { 5u64 } else { 30 };
    st.daemon_heartbeat = Some(tokio::spawn(async move {
        run_heartbeat_loop(&app, &c, is_local, fast_secs).await
    }));
}

async fn run_heartbeat_loop(app: &AppHandle, http: &Client, is_local: bool, fast_secs: u64) {
    let mut int_fast = interval(std::time::Duration::from_secs(fast_secs));
    int_fast.set_missed_tick_behavior(MissedTickBehavior::Skip);
    let mut int_slow = interval(std::time::Duration::from_secs(60));
    int_slow.set_missed_tick_behavior(MissedTickBehavior::Skip);
    if is_local {
        loop {
            if app.try_state::<AppData>().is_none() {
                break;
            }
            tokio::select! {
              _ = int_fast.tick() => {
                tick_fast(&app, http).await;
              }
              _ = int_slow.tick() => {
                tick_slow(&app, http).await;
              }
            }
        }
    } else {
        loop {
            if app.try_state::<AppData>().is_none() {
                break;
            }
            int_fast.tick().await;
            tick_fast(&app, http).await;
        }
    }
}

async fn tick_fast(app: &AppHandle, http: &Client) {
    let Some(adata) = app.try_state::<AppData>() else {
        return;
    };
    let (host, port) = {
        let b = adata.backend.lock().await;
        let Some(p) = daemon_rpc_host_port(&b.config_data) else {
            return;
        };
        p
    };
    let r = match daemon_post(http, &host, port, "get_info", 0, &Value::Null).await {
        Ok(v) => v,
        Err(e) => {
            if is_sync_debug() {
                eprintln!(
          "[sync-debug][daemon-hb] get_info HTTP/RPC transport failed host={host} port={port}: {e}"
        );
            }
            // Local daemon can die after startup; attempt self-heal restart in background heartbeat.
            if let Some(adata) = app.try_state::<AppData>() {
                let mut b = adata.backend.lock().await;
                if let Err(re) = restart_local_daemon_if_exited(app, &mut b, http).await {
                    eprintln!("[daemon-hb] local daemon auto-restart failed: {re}");
                }
            }
            return;
        }
    };
    if !json_rpc_no_error(&r) {
        eprintln!(
            "[daemon-hb] get_info JSON-RPC error: {}",
            r.get("error").unwrap_or(&Value::Null)
        );
        return;
    }
    let Some(h) = r.pointer("/result/height").and_then(value_as_u64) else {
        if is_sync_debug() {
            eprintln!("[sync-debug][daemon-hb] get_info: missing /result/height");
        }
        return;
    };
    let mut result = r.get("result").cloned().unwrap_or(Value::Null);
    let pool_enabled = {
        let b = adata.backend.lock().await;
        b.config_data
            .get("pool")
            .and_then(|p| p.get("server"))
            .and_then(|s| s.get("enabled"))
            .and_then(|e| e.as_bool())
            .unwrap_or(false)
    };
    let is_ready_daemon = result
        .get("is_ready")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    // Many `arqmad` builds never flip RPC `is_ready` to true; keep the raw flag for diagnostics / UI.
    if let Some(o) = result.as_object_mut() {
        o.insert("is_ready_daemon_rpc".to_string(), json!(is_ready_daemon));
    }
    let target_h = result
        .get("target_height")
        .and_then(value_as_u64)
        .unwrap_or(h);
    let h_wo = result
        .get("height_without_bootstrap")
        .and_then(value_as_u64)
        .unwrap_or(h);
    // Same "daemon caught up" notion as `footer.vue` (local): compare `height_without_bootstrap`
    // to `max(height, target_height)`. Relying on `is_ready` alone can show the solo-pool
    // "not fully synced" banner while the footer already shows 100% (e.g. during wallet scan).
    let footer_target = h.max(target_h);
    let daemon_chain_caught_up = h_wo >= footer_target;
    // Some `arqmad` builds report `is_ready: false` even when `height_without_bootstrap` meets the tip
    // (pool / quorum edge cases). Do not strand wallet sync on that flag — expose a UI-friendly truth.
    let is_ready_for_ui = daemon_chain_caught_up || is_ready_daemon;
    if let Some(o) = result.as_object_mut() {
        o.insert("is_ready".to_string(), json!(is_ready_for_ui));
    }
    let daemon_available = h > 0;
    let synced = (h >= target_h.saturating_sub(1) && is_ready_for_ui) || daemon_available;
    let difficulty = result.get("difficulty").and_then(value_as_u64).unwrap_or(0);
    let target = result.get("target").and_then(value_as_u64).unwrap_or(120);
    let network_hashrate = if target == 0 { 0 } else { difficulty / target };
    let pool_status = if !pool_enabled {
        0
    } else if synced {
        2
    } else {
        1
    };
    {
        let mut b = adata.backend.lock().await;
        // Same tip as the footer: use network head `max(height, target_height)` so wallet catch-up
        // backlog and LIGHT/HEAVY heartbeat still match a syncing daemon (height < target_height).
        b.daemon_last_height = footer_target;
    }
    if is_sync_debug() {
        eprintln!(
      "[sync-debug][daemon-hb] get_info ok height={} h_wo={} target_h={} tip={} is_ready_daemon(rpc)={} is_ready(UI)={} chain_tip_aligned={} pool_enabled={}",
      h,
      h_wo,
      target_h,
      footer_target,
      is_ready_daemon,
      is_ready_for_ui,
      daemon_chain_caught_up,
      pool_enabled
    );
    }
    // Emit on every successful poll so `target_height`, `height_without_bootstrap`, `is_ready`
    // stay fresh (wallet footer / sync logic); not only when `height` increases.
    let _ = BackendReceiveSink::emit_receive(app, "set_daemon_data", json!({ "info": result }));
    if pool_enabled {
        // Solo `solo_pool` task owns `status`, `workers`, `activeWorkers` and hashrate stats.
        // Only push daemon-sourced network fields to avoid clobbering merged `stats` (incl. activeWorkers -> 0).
        let _ = BackendReceiveSink::emit_receive(
            app,
            "set_pool_data",
            json!({
              "desynced": !daemon_chain_caught_up,
              "stats": {
                "networkHashrate": network_hashrate,
                "diff": difficulty,
                "height": h
              }
            }),
        );
    } else {
        let _ = BackendReceiveSink::emit_receive(
            app,
            "set_pool_data",
            json!({
              "status": pool_status,
              "desynced": false,
              "system_clock_error": false,
              "stats": {
                "networkHashrate": network_hashrate,
                "diff": difficulty,
                "height": h,
                "activeWorkers": 0
              }
            }),
        );
    }
}

async fn tick_slow(app: &AppHandle, http: &Client) {
    let Some(adata) = app.try_state::<AppData>() else {
        return;
    };
    let (host, port, testnet, pool_enabled) = {
        let b = adata.backend.lock().await;
        let Some(p) = daemon_rpc_host_port(&b.config_data) else {
            return;
        };
        let pool_on = b
            .config_data
            .get("pool")
            .and_then(|p| p.get("server"))
            .and_then(|s| s.get("enabled"))
            .and_then(|e| e.as_bool())
            .unwrap_or(false);
        (p.0, p.1, app_testnet(&b.config_data), pool_on)
    };
    if pool_enabled {
        if let Some(sce) = explorer_clock_skew(http, testnet).await {
            let _ = BackendReceiveSink::emit_receive(
                app,
                "set_pool_data",
                json!({ "system_clock_error": sce }),
            );
        }
    }
    let c1 = daemon_post(http, &host, port, "get_connections", 0, &Value::Null).await;
    let c2 = daemon_post(http, &host, port, "get_bans", 0, &Value::Null).await;
    let c3 = daemon_post(http, &host, port, "get_txpool_backlog", 0, &Value::Null).await;
    let mut out = json!({});
    {
        let o = out.as_object_mut().unwrap();
        if let Ok(ref v) = c1 {
            if json_rpc_no_error(v) {
                if let Some(con) = v.pointer("/result/connections") {
                    o.insert("connections".into(), con.clone());
                }
            }
        }
        if let Ok(ref v) = c2 {
            if json_rpc_no_error(v) {
                if let Some(b) = v.pointer("/result/bans") {
                    o.insert("bans".into(), b.clone());
                }
            }
        }
        if let Ok(ref v) = c3 {
            if json_rpc_no_error(v) {
                if let Some(b) = v.pointer("/result/backlog") {
                    o.insert("tx_pool_backlog".into(), b.clone());
                }
            }
        }
    }
    if out.as_object().map(|m| m.is_empty()).unwrap_or(true) {
        return;
    }
    let _ = BackendReceiveSink::emit_receive(app, "set_daemon_data", out);
}

/// Same idea as `Pool.watchdog` in arqma-electron-wallet `pool.js`: compare local clock to explorer.
async fn explorer_clock_skew(http: &Client, testnet: bool) -> Option<bool> {
    let url = if testnet {
        "https://stageblocks.arqma.com/api/networkinfo"
    } else {
        "https://explorer.arqma.com/api/networkinfo"
    };
    let r = http
        .get(url)
        .timeout(std::time::Duration::from_secs(12))
        .send()
        .await
        .ok()?;
    let v: Value = r.json().await.ok()?;
    let server_time = v.pointer("/data/server_time")?.as_u64()?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()?
        .as_secs();
    let allowed: u64 = 15 * 60;
    Some((now as i64 - server_time as i64).unsigned_abs() > allowed)
}
