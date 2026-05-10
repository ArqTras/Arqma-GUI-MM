//! Start local `arqmad` or verify remote RPC (same role as `Daemon.start` in `backend.js`).

use crate::arqma_paths_config::daemon_rpc_host_port;
use crate::backend_state::WalletBackendState;
use crate::json_rpc_client::daemon_post;
use crate::json_util::json_rpc_no_error;
use crate::native_bin::resolve_arqmad_exe;
use arqma_wallet_core::write_config_file;
use reqwest::Client;
use serde_json::{json, Value};
use crate::subprocess::new_child_command;
use std::path::PathBuf;
use std::process::Stdio;
use tauri::AppHandle;

#[cfg(unix)]
fn send_daemon_sigterm(pid: u32) {
  let pid_s = pid.to_string();
  let _ = std::process::Command::new("kill")
    .args(["-15", pid_s.as_str()])
    .status();
}

#[cfg(windows)]
fn send_daemon_soft_stop(pid: u32) {
  let pid_s = pid.to_string();
  let _ = std::process::Command::new("taskkill")
    .args(["/PID", pid_s.as_str(), "/T"])
    .status();
}

#[cfg(windows)]
fn send_daemon_force_stop(pid: u32) {
  let pid_s = pid.to_string();
  let _ = std::process::Command::new("taskkill")
    .args(["/PID", pid_s.as_str(), "/T", "/F"])
    .status();
}

/// `Daemon.start` — `remote`: first `get_info`; local: spawn `arqmad` then `get_info`.
pub async fn ensure_daemon_for_startup (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &Client,
) -> Result<(), String> {
  if st.daemon_process.is_some() {
    return Ok(());
  }
  let net = st
    .config_data
    .get("app")
    .and_then(|a| a.get("net_type"))
    .and_then(|n| n.as_str())
    .unwrap_or("mainnet");
  let d = st
    .config_data
    .get("daemons")
    .and_then(|x| x.get(net))
    .and_then(|v| v.as_object())
    .ok_or("daemons: missing entry")?;
  let typ = d.get("type").and_then(|t| t.as_str()).unwrap_or("local");
  if typ == "remote" {
    let Some((h, p)) = daemon_rpc_host_port(&st.config_data) else {
      return Err("Remote daemon: missing host/port in configuration".to_string());
    };
    let r = daemon_post(http, &h, p, "get_info", 0, &Value::Null).await?;
    if r.get("error").is_some() {
      return Err("Remote daemon can not be reached".to_string());
    }
    return Ok(());
  }
  let Some(exe) = resolve_arqmad_exe(app) else {
    eprintln!(
      "[daemon] arqmad not found (local mode): set ARQMA_DAEMON, ARQMA_BUILD_DIR, PATH, or resource/bin"
    );
    return Err(
      "Error: arqmad binary missing (local mode). Set ARQMA_DAEMON or ARQMA_BUILD_DIR, or add Arqma build/bin to PATH."
        .to_string(),
    );
  };
  let data_dir = st
    .config_data
    .get("app")
    .and_then(|a| a.get("data_dir"))
    .and_then(|p| p.as_str())
    .ok_or("app.data_dir: missing")?
    .to_string();
  let main_data = PathBuf::from(&data_dir);
  let net_dir: PathBuf = match net {
    "stagenet" => main_data.join("stagenet"),
    "testnet" => main_data.join("testnet"),
    _ => main_data.clone()
  };
  let _ = std::fs::create_dir_all(net_dir.join("logs"));
  let log_file = net_dir.join("logs").join("daemon.log");
  let p2p_ip = d
    .get("p2p_bind_ip")
    .and_then(|v| v.as_str())
    .unwrap_or("0.0.0.0");
  let p2p_p = d
    .get("p2p_bind_port")
    .and_then(port_u64)
    .unwrap_or(19_993);
  let rpc_ip = d
    .get("rpc_bind_ip")
    .and_then(|v| v.as_str())
    .unwrap_or("127.0.0.1");
  let rpc_p = d
    .get("rpc_bind_port")
    .and_then(port_u64)
    .unwrap_or(19_994);
  let out_p = d
    .get("out_peers")
    .and_then(num_str)
    .unwrap_or("-1".into());
  let in_p = d
    .get("in_peers")
    .and_then(num_str)
    .unwrap_or("-1".into());
  let lim_up = d
    .get("limit_rate_up")
    .and_then(num_str)
    .unwrap_or("-1".into());
  let lim_down = d
    .get("limit_rate_down")
    .and_then(num_str)
    .unwrap_or("-1".into());
  let log_lv = d
    .get("log_level")
    .and_then(|v| v.as_u64().or_else(|| v.as_i64().map(|i| i as u64)))
    .unwrap_or(0);
  let mut args: Vec<String> = vec![
    "--data-dir".into(),
    data_dir,
    "--p2p-bind-ip".into(),
    p2p_ip.into(),
    "--p2p-bind-port".into(),
    p2p_p.to_string(),
    "--rpc-bind-ip".into(),
    rpc_ip.into(),
    "--rpc-bind-port".into(),
    rpc_p.to_string(),
    "--out-peers".into(),
    out_p,
    "--in-peers".into(),
    in_p,
    "--limit-rate-up".into(),
    lim_up,
    "--limit-rate-down".into(),
    lim_down,
    "--log-level".into(),
    log_lv.to_string(),
  ];
  if net == "testnet" {
    args.push("--testnet".into());
  } else if net == "stagenet" {
    args.push("--stagenet".into());
  }
  args.push("--log-file".into());
  args.push(log_file.to_string_lossy().into());
  if rpc_ip != "127.0.0.1" {
    args.push("--confirm-external-bind".into());
  }
  if typ == "local_remote" && net == "mainnet" {
    if let (Some(rh), Some(rp)) = (
      d.get("remote_host").and_then(|h| h.as_str()),
      d.get("remote_port").and_then(|p| p.as_u64()),
    ) {
      args.push("--bootstrap-daemon-address".into());
      args.push(format!("{rh}:{rp}"));
    }
  }
  eprintln!("[daemon] start arqmad: {:?}", args);
  let ch = new_child_command(&exe)
    .args(&args)
    // Keep stdin open; otherwise `arqmad` can receive EOF immediately in GUI runs and exit.
    .stdin(Stdio::piped())
    .stdout(Stdio::null())
    .stderr(Stdio::null())
    .spawn()
    .map_err(|e| e.to_string())?;
  st.daemon_process = Some(ch);
  let Some((h, port)) = daemon_rpc_host_port(&st.config_data) else {
    return Err("After start: missing host/port for get_info polling".to_string());
  };
  // ~120s wall time at 200ms sleep between attempts (Flutter `spawnLocalArqmadAndWait` uses the same idea).
  for _ in 0..600 {
    let r = daemon_post(http, &h, port, "get_info", 0, &Value::Null).await;
    match r {
      Ok(v) if crate::json_util::json_rpc_no_error(&v) => {
        eprintln!("[daemon] arqmad: get_info OK");
        return Ok(());
      }
      _ => {
        if let Some(dproc) = st.daemon_process.as_mut() {
          match dproc.try_wait() {
            Ok(Some(status)) if !status.success() => {
              st.daemon_process = None;
              return Err("arqmad process exited before get_info (check logs)".to_string());
            }
            _ => {}
          }
        }
        tokio::time::sleep(std::time::Duration::from_millis(200)).await;
      }
    }
  }
  eprintln!(
    "[daemon] get_info timeout at http://{h}:{port}/json_rpc (check ports, firewall, rpc_bind vs config)"
  );
  Err(format!(
    "Timeout: local arqmad did not respond (get_info at {h}:{port})"
  ))
}

/// `stop_daemon` JSON-RPC (Monero/Arqma `COMMAND_RPC_STOP_DAEMON`), then wait for the child.
/// Fallback to legacy **`stop`** only if daemon returns `-32601` (method missing on old builds).
/// `kill` if the child does not exit in time — same spirit as Electron `SIGTERM` on the process.
/// Call after [`crate::wallet_process::graceful_shutdown_wallet_rpc`] so wallet disconnects first.
pub async fn shutdown_local_daemon_child (st: &mut WalletBackendState, http: &Client) {
  if st.daemon_process.is_none() {
    return;
  }
  if let Some((h, p)) = daemon_rpc_host_port(&st.config_data) {
    for method in ["stop_daemon", "stop"] {
      let id = st.next_rpc_id;
      st.next_rpc_id = st.next_rpc_id.saturating_add(1);
      match daemon_post(http, &h, p, method, id, &Value::Null).await {
        Ok(v) if json_rpc_no_error(&v) => {
          eprintln!("[daemon] `{method}` RPC ok");
          break;
        }
        Ok(v) => {
          let code = v.pointer("/error/code").and_then(|c| c.as_i64());
          if method == "stop_daemon" && code == Some(-32601) {
            continue;
          }
          eprintln!("[daemon] `{method}` RPC error: {v}");
          break;
        }
        Err(e) => {
          eprintln!("[daemon] `{method}` transport: {e}");
          if method == "stop_daemon" {
            continue;
          }
          break;
        }
      }
    }
  }
  let Some(mut ch) = st.daemon_process.take() else {
    return;
  };
  let pid = ch.id();
  #[cfg(unix)]
  {
    eprintln!("[daemon] graceful stop: sending SIGTERM (15) to arqmad");
    send_daemon_sigterm(pid);
  }
  #[cfg(windows)]
  {
    eprintln!("[daemon] graceful stop: sending Windows soft stop to arqmad");
    send_daemon_soft_stop(pid);
  }
  let deadline = std::time::Instant::now() + std::time::Duration::from_secs(4);
  loop {
    match ch.try_wait() {
      Ok(Some(_)) => {
        eprintln!("[daemon] arqmad process exited");
        return;
      }
      Ok(None) => {
        if std::time::Instant::now() >= deadline {
          eprintln!("[daemon] arqmad still running after graceful stop, forcing kill");
          #[cfg(windows)]
          {
            send_daemon_force_stop(pid);
          }
          let _ = ch.kill();
          let _ = ch.wait();
          return;
        }
        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
      }
      Err(e) => {
        eprintln!("[daemon] try_wait: {e}, killing arqmad");
        let _ = ch.kill();
        let _ = ch.wait();
        return;
      }
    }
  }
}

/// Heartbeat safety net: if local daemon process has exited, start it again.
/// Returns `Ok(true)` when restart was attempted and completed.
pub async fn restart_local_daemon_if_exited (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &Client,
) -> Result<bool, String> {
  let net = st
    .config_data
    .get("app")
    .and_then(|a| a.get("net_type"))
    .and_then(|n| n.as_str())
    .unwrap_or("mainnet");
  let typ = st
    .config_data
    .get("daemons")
    .and_then(|d| d.get(net))
    .and_then(|x| x.get("type"))
    .and_then(|t| t.as_str())
    .unwrap_or("local");
  if typ == "remote" {
    return Ok(false);
  }
  let exited = match st.daemon_process.as_mut() {
    Some(ch) => match ch.try_wait() {
      Ok(Some(status)) => {
        eprintln!("[daemon] process exited during heartbeat: {status}");
        true
      }
      Ok(None) => false,
      Err(e) => {
        eprintln!("[daemon] process state check failed during heartbeat: {e}");
        true
      }
    },
    None => true,
  };
  if !exited {
    return Ok(false);
  }
  st.daemon_process = None;
  ensure_daemon_for_startup(app, st, http).await?;
  eprintln!("[daemon] local daemon auto-restarted");
  Ok(true)
}

fn num_str (v: &Value) -> Option<String> {
  if let Some(n) = v.as_i64() {
    return Some(n.to_string());
  }
  if let Some(n) = v.as_f64() {
    return Some(n.to_string());
  }
  v.as_u64().map(|n| n.to_string())
}

fn port_u64 (v: &Value) -> Option<u64> {
  v.as_u64()
    .or_else(|| v.as_i64().filter(|&i| i >= 0).map(|i| i as u64))
}

/// When `startup` finds no `arqmad --version`, switch current net entry to `type: remote` (as in `backend.js`).
pub fn set_current_net_to_remote (st: &mut WalletBackendState) {
  let net = st
    .config_data
    .get("app")
    .and_then(|a| a.get("net_type"))
    .and_then(|n| n.as_str())
    .unwrap_or("mainnet")
    .to_string();
  if let Some(dm) = st
    .config_data
    .get_mut("daemons")
    .and_then(|d| d.get_mut(&net))
  {
    if let Some(o) = dm.as_object_mut() {
      o.insert("type".into(), json!("remote"));
    }
  }
  if let Err(e) = write_config_file(&st.paths, &st.config_data) {
    eprintln!("[daemon] set remote: failed to write config: {e}");
  }
}
