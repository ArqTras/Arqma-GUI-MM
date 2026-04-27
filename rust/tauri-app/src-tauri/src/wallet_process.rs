use crate::backend_state::WalletBackendState;
use serde_json::Value;
use std::path::PathBuf;
use crate::json_rpc_client::WalletRpcClient;
use std::sync::Arc;
use crate::native_bin::resolve_wallet_rpc_exe;
use crate::subprocess::new_child_command;
use rand::RngCore;
use std::process::Stdio;
use std::time::Duration;
use tauri::AppHandle;
use tokio::time::timeout;

/// Outcome of [`try_start_wallet_rpc`] (for UI / logs — optional subprocess is easy to mis-bundle).
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum WalletRpcStartResult {
  AlreadyRunning,
  Started,
  ExeNotFound,
  MissingDaemonInConfig,
  MissingWalletDir,
  WalletDirCreateFailed(String),
  SpawnFailed(String),
  /// Process spawned but HTTP JSON-RPC never answered (daemon down, wrong port, crash on start).
  RpcTimeout,
}

/// Same file as `arqma-wallet-rpc --log-file` in [`try_start_wallet_rpc`] (Electron also watches this stream via `stdout`).
pub fn arqma_wallet_rpc_log_path (config: &Value) -> Option<PathBuf> {
  let wdir = crate::arqma_paths_config::wallet_files_dir(&config)?;
  wdir
    .parent()
    .map(|p| p.join("logs").join("arqma-wallet-rpc.log"))
}

/// Random `rpc-login` (160 B → 320 hex chars) — distribution aligned to `Buffer.toString("hex")`.
fn generate_auth_triple () -> (String, String, String) {
  let mut b = [0u8; 64 + 64 + 32];
  rand::thread_rng().fill_bytes(&mut b);
  let s: String = b.iter().map(|x| format!("{x:02x}")).collect();
  (s[0..64].to_string(), s[64..128].to_string(), s[128..192].to_string())
}

fn wallet_daemon_addr (config: &Value) -> Option<String> {
  let a = config.get("app")?.get("net_type")?.as_str()?;
  let d = config.get("daemons")?.get(a)?;
  if d.get("type").and_then(|t| t.as_str()) == Some("remote") {
    let h = d.get("remote_host")?.as_str()?;
    let p = d.get("remote_port")?.as_u64()?;
    return Some(format!("{h}:{p}"));
  }
  let h = d.get("rpc_bind_ip")?.as_str()?;
  let p = d.get("rpc_bind_port")?.as_u64()?;
  Some(format!("{h}:{p}"))
}

/// Start `arqma-wallet-rpc` when the binary exists and create `WalletRpcClient` after `get_languages` succeeds.
pub async fn try_start_wallet_rpc (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &reqwest::Client,
) -> WalletRpcStartResult {
  if st.wallet_process.is_some() && st.wallet.is_some() {
    return WalletRpcStartResult::AlreadyRunning;
  }
  if st.wallet_process.is_some() && st.wallet.is_none() {
    if let Some(mut ch) = st.wallet_process.take() {
      let _ = ch.kill();
      let _ = ch.wait();
    }
  }
  st.wallet = None;
  st.wallet_salt = String::new();
  let Some(exe) = resolve_wallet_rpc_exe(app) else {
    eprintln!(
      "[wallet] arqma-wallet-rpc not found: set ARQMA_WALLET_RPC, ARQMA_BUILD_DIR, PATH, or place exe in src-tauri/bin before tauri build (see src-tauri/bin/README.txt)"
    );
    return WalletRpcStartResult::ExeNotFound;
  };
  let Some(daemon_addr) = wallet_daemon_addr(&st.config_data) else {
    eprintln!("[wallet] missing daemon data in config");
    return WalletRpcStartResult::MissingDaemonInConfig;
  };
  let (user, pass, salt) = generate_auth_triple();
  st.wallet_salt = salt;
  let net = st
    .config_data
    .get("app")
    .and_then(|a| a.get("net_type"))
    .and_then(|n| n.as_str())
    .unwrap_or("mainnet");
  let wdir = crate::arqma_paths_config::wallet_files_dir(&st.config_data);
  let wdir = match wdir {
    Some(p) => p,
    None => {
      eprintln!("[wallet] missing wallet directory");
      return WalletRpcStartResult::MissingWalletDir;
    }
  };
  if let Err(e) = std::fs::create_dir_all(&wdir) {
    eprintln!("[wallet] create_dir_all: {e}");
    return WalletRpcStartResult::WalletDirCreateFailed(e.to_string());
  }
  // Level 0 yields almost no wallet-rpc log lines — footer / `wallet_rpc_log_height` need
  // `Processed block` / sync lines (same as Electron defaulting wallet log to 1).
  let log_level = st
    .config_data
    .get("wallet")
    .and_then(|w| w.get("log_level"))
    .and_then(|l| l.as_u64())
    .unwrap_or(1)
    .max(1);
  let rpc_port = crate::arqma_paths_config::wallet_rpc_bind_port(&st.config_data);
  let log_dir = wdir.parent().map(|p| p.join("logs"));
  if let Some(ref ld) = log_dir {
    let _ = std::fs::create_dir_all(ld);
  }
  let log_file = log_dir
    .as_ref()
    .map(|d| d.join("arqma-wallet-rpc.log"))
    .and_then(|p| {
      let _ = std::fs::OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(&p);
      Some(p)
    });
  let mut args: Vec<String> = vec![
    "--rpc-login".into(),
    format!("{user}:{pass}"),
    "--rpc-bind-port".into(),
    rpc_port.to_string(),
    "--daemon-address".into(),
    daemon_addr,
    "--log-level".into(),
    log_level.to_string(),
    "--wallet-dir".into(),
    wdir.to_string_lossy().into(),
  ];
  if let Some(lf) = log_file {
    args.push("--log-file".into());
    args.push(lf.to_string_lossy().into());
  }
  match net {
    "testnet" => {
      args.push("--testnet".into());
    }
    "stagenet" => {
      args.push("--stagenet".into());
    }
    _ => {}
  }
  let ch = match new_child_command(&exe)
    .args(&args)
    .stdout(Stdio::null())
    .stderr(Stdio::null())
    .spawn()
  {
    Ok(c) => c,
    Err(e) => {
      eprintln!("[wallet] spawn: {e}");
      return WalletRpcStartResult::SpawnFailed(e.to_string());
    }
  };
  st.wallet_process = Some(ch);
  let client = WalletRpcClient::new(http, "127.0.0.1", rpc_port, user, pass);
  for _ in 0..60 {
    match client.call("get_languages", &Value::Null).await {
      Ok(r) if r.get("error").is_none() => {
        st.wallet = Some(Arc::new(client));
        eprintln!("[wallet] arqma-wallet-rpc: OK (get_languages)");
        return WalletRpcStartResult::Started;
      }
      _ => {
        tokio::time::sleep(std::time::Duration::from_millis(200)).await;
      }
    }
  }
  eprintln!("[wallet] timeout — no get_languages response (check arqma-wallet-rpc.log, daemon reachability, port)");
  if let Some(mut ch) = st.wallet_process.take() {
    let _ = ch.kill();
    let _ = ch.wait();
  }
  st.wallet = None;
  WalletRpcStartResult::RpcTimeout
}

/// If a wallet file is still open, flush and `close_wallet` (matches Electron `closeWallet` before `quit` /
/// `SIGKILL`); then `store` + `stop_wallet` to exit the daemon, wait for the child, `kill` on timeout.
pub async fn graceful_shutdown_wallet_rpc (st: &mut WalletBackendState) {
  if !st.wh_display_name.is_empty() {
    if let Some(w) = st.wallet_json_rpc() {
      match timeout(Duration::from_secs(30), w.call("store", &Value::Null)).await {
        Ok(Ok(r)) if r.get("error").is_some() => eprintln!("[wallet] pre-exit store: {:?}", r.get("error")),
        Ok(Err(e)) => eprintln!("[wallet] pre-exit store: {e}"),
        Ok(Ok(_)) => {}
        Err(_) => eprintln!("[wallet] pre-exit store: timed out, continuing to close_wallet"),
      }
      match timeout(Duration::from_secs(20), w.call("close_wallet", &Value::Null)).await {
        Ok(Ok(r)) if r.get("error").is_some() => eprintln!("[wallet] pre-exit close_wallet: {:?}", r.get("error")),
        Ok(Err(e)) => eprintln!("[wallet] pre-exit close_wallet: {e}"),
        Ok(Ok(_)) => {}
        Err(_) => eprintln!("[wallet] pre-exit close_wallet: timed out, continuing to stop"),
      }
    }
  }
  if let Some(w) = st.wallet_json_rpc() {
    // `store` can hang for a long time during blockchain scan; same for `stop_wallet` if RPC is busy.
    match timeout(Duration::from_secs(12), w.call("store", &Value::Null)).await {
      Ok(Ok(r)) if r.get("error").is_some() => eprintln!("[wallet] exit store: {:?}", r.get("error")),
      Ok(Err(e)) => eprintln!("[wallet] exit store: {e}"),
      Ok(Ok(_)) => {}
      Err(_) => eprintln!("[wallet] exit store: timed out, stopping anyway"),
    }
    match timeout(Duration::from_secs(8), w.call("stop_wallet", &Value::Null)).await {
      Ok(Ok(r)) if r.get("error").is_some() => eprintln!("[wallet] stop_wallet: {:?}", r.get("error")),
      Ok(Err(e)) => eprintln!("[wallet] stop_wallet: {e}"),
      Ok(Ok(_)) => {}
      Err(_) => eprintln!("[wallet] stop_wallet: timed out, will kill child"),
    }
  }
  st.wallet = None;
  let Some(mut ch) = st.wallet_process.take() else {
    st.wallet_salt.clear();
    return;
  };
  let deadline = std::time::Instant::now() + std::time::Duration::from_secs(6);
  loop {
    match ch.try_wait() {
      Ok(Some(_status)) => break,
      Ok(None) => {
        if std::time::Instant::now() >= deadline {
          eprintln!("[wallet] stop_wallet: child still running, sending kill");
          let _ = ch.kill();
          let _ = ch.wait();
          break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(120)).await;
      }
      Err(e) => {
        eprintln!("[wallet] try_wait: {e}, killing wallet-rpc child");
        let _ = ch.kill();
        let _ = ch.wait();
        break;
      }
    }
  }
  st.wallet_salt.clear();
}
