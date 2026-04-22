//! `get_info` / `get_connections` / `get_bans` loop like `Daemon.heartbeat` in Electron.
use crate::arqma_paths_config::daemon_rpc_host_port;
use crate::backend_state::WalletBackendState;
use crate::gateway_emit::emit_receive;
use crate::json_rpc_client::daemon_post;
use crate::json_util::value_as_u64;
use crate::AppData;
use reqwest::Client;
use serde_json::{json, Value};
use tauri::AppHandle;
use tauri::Manager;
use tokio::time::{interval, MissedTickBehavior};

/// Start background loop after successful `ensure_daemon_for_startup` (5s local / 60s remote; slow path every 60s, local only).
pub fn start (app: &AppHandle, st: &mut WalletBackendState, is_local: bool, http: &Client) {
  if let Some(h) = st.daemon_heartbeat.take() {
    h.abort();
  }
  st.daemon_last_height = 0;
  let app = app.clone();
  let c = http.clone();
  let fast_secs = if is_local { 5u64 } else { 60 };
  st.daemon_heartbeat = Some(tokio::spawn(async move {
    run_heartbeat_loop(&app, &c, is_local, fast_secs).await
  }));
}

async fn run_heartbeat_loop (app: &AppHandle, http: &Client, is_local: bool, fast_secs: u64) {
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

async fn tick_fast (app: &AppHandle, http: &Client) {
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
    Err(_) => return
  };
  if r.get("error").is_some() {
    return;
  }
  let Some(h) = r.pointer("/result/height").and_then(value_as_u64) else {
    return;
  };
  let result = r.get("result").cloned().unwrap_or(Value::Null);
  {
    let mut b = adata.backend.lock().await;
    b.daemon_last_height = h;
  }
  // Emit on every successful poll so `target_height`, `height_without_bootstrap`, `is_ready`
  // stay fresh (wallet footer / sync logic); not only when `height` increases.
  let _ = emit_receive(
    app,
    "set_daemon_data",
    json!({ "info": result }),
  );
}

async fn tick_slow (app: &AppHandle, http: &Client) {
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
  let c1 = daemon_post(http, &host, port, "get_connections", 0, &Value::Null).await;
  let c2 = daemon_post(http, &host, port, "get_bans", 0, &Value::Null).await;
  let c3 = daemon_post(http, &host, port, "get_txpool_backlog", 0, &Value::Null).await;
  let mut out = json!({});
  {
    let o = out.as_object_mut().unwrap();
    if let Ok(ref v) = c1 {
      if v.get("error").is_none() {
        if let Some(con) = v.pointer("/result/connections") {
          o.insert("connections".into(), con.clone());
        }
      }
    }
    if let Ok(ref v) = c2 {
      if v.get("error").is_none() {
        if let Some(b) = v.pointer("/result/bans") {
          o.insert("bans".into(), b.clone());
        }
      }
    }
    if let Ok(ref v) = c3 {
      if v.get("error").is_none() {
        if let Some(b) = v.pointer("/result/backlog") {
          o.insert("tx_pool_backlog".into(), b.clone());
        }
      }
    }
  }
  if out.as_object().map(|m| m.is_empty()).unwrap_or(true) {
    return;
  }
  let _ = emit_receive(app, "set_daemon_data", out);
}
