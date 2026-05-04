use crate::backend_state::WalletBackendState;
use crate::gateway_emit::emit_receive;
use crate::json_rpc_client::WalletRpcClient;
use std::sync::Arc;
use crate::native_bin::{bundled_exe_candidates, resolve_wallet_rpc_exe};
use crate::subprocess::new_child_command;
use rand::RngCore;
use serde_json::Value;
use serde_json::json;
use std::io::{BufRead, BufReader};
use std::process::{Child, Stdio};
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

#[cfg(unix)]
fn shutdown_term_wait_secs () -> u64 {
  std::env::var("ARQMA_WALLET_SHUTDOWN_TERM_WAIT_SECS")
    .ok()
    .and_then(|s| s.trim().parse::<u64>().ok())
    .map(|v| v.clamp(1, 5))
    .unwrap_or(1)
}

#[cfg(windows)]
fn shutdown_term_wait_secs () -> u64 {
  std::env::var("ARQMA_WALLET_SHUTDOWN_TERM_WAIT_SECS")
    .ok()
    .and_then(|s| s.trim().parse::<u64>().ok())
    .map(|v| v.clamp(1, 5))
    .unwrap_or(2)
}

#[cfg(unix)]
fn send_sigterm(child: &Child) {
  let pid = child.id().to_string();
  let _ = std::process::Command::new("kill")
    .args(["-15", pid.as_str()])
    .status();
}

#[cfg(windows)]
fn send_windows_soft_stop(child: &Child) {
  let pid = child.id().to_string();
  // On Windows `arqma-wallet-rpc` often ignores soft terminate; force tree kill for immediate close UX.
  let _ = std::process::Command::new("taskkill")
    .args(["/PID", pid.as_str(), "/T", "/F"])
    .status();
}

#[cfg(windows)]
pub fn force_kill_wallet_rpc_process_tree () {
  let _ = std::process::Command::new("taskkill")
    .args(["/IM", "arqma-wallet-rpc.exe", "/T", "/F"])
    .status();
}

#[cfg(not(windows))]
pub fn force_kill_wallet_rpc_process_tree () {}

/// Reqwest timeout for local `arqma-wallet-rpc` (`store` during scan can exceed generic HTTP client 120s).
pub(crate) fn wallet_rpc_http_timeout_secs () -> u64 {
  std::env::var("ARQMA_WALLET_RPC_HTTP_TIMEOUT_SECS")
    .ok()
    .and_then(|s| s.trim().parse::<u64>().ok())
    .map(|v| v.clamp(120, 3600))
    .unwrap_or(600)
}

/// Electron `wallet-rpc.js::storeFlushTimeoutMs` — used for explicit **`save_wallet`** (`store` only).
pub fn save_wallet_flush_timeout_ms () -> u64 {
  std::env::var("ARQMA_WALLET_STORE_FLUSH_TIMEOUT_MS")
    .ok()
    .and_then(|s| s.trim().parse::<u64>().ok())
    .map(|v| v.clamp(5_000, 3_600_000))
    .unwrap_or(180_000)
}

/// First `store` wait on wallet **switch** close.
///
/// **Default (unset):** full [`wallet_rpc_http_timeout_secs`] so `store` can finish while scanning —
/// otherwise progress is often **not** written before kill (see `ARQMA_WALLET_SWITCH_STORE_MAX_SECS`).
///
/// **`ARQMA_WALLET_SWITCH_STORE_MAX_SECS`:** cap in seconds (`1..=full`). Lower = faster UI, higher
/// risk of **no flush** if wallet-rpc is busy → reopen at old height. **`0`** = same as unset (full).
fn switch_close_first_store_secs (full: u64, _scan_backlog: u64) -> u64 {
  match std::env::var("ARQMA_WALLET_SWITCH_STORE_MAX_SECS") {
    Ok(s) if s.trim().is_empty() || s.trim() == "0" => full,
    Ok(s) => s
      .trim()
      .parse::<u64>()
      .ok()
      .map(|v| v.clamp(1, full))
      .unwrap_or(full),
    Err(_) => full,
  }
}

/// Hard cap on the first **`store`** wait inside [`close_wallet_session_only`].
///
/// [`switch_close_first_store_secs`] can be hundreds of seconds; until it returns we still have a live
/// `arqma-wallet-rpc` child (scan + `Wallet:` logs). **`0`** = no cap (legacy behaviour).
fn wallet_exit_store_cap_secs () -> Option<u64> {
  match std::env::var("ARQMA_WALLET_EXIT_STORE_CAP_SECS") {
    Ok(s) if s.trim() == "0" => None,
    Ok(s) => s
      .trim()
      .parse::<u64>()
      .ok()
      .map(|v| v.clamp(3, 900)),
    Err(_) => Some(35),
  }
}

/// Hard cap on JSON-RPC **`close_wallet`** wait before [`force_shutdown_wallet_rpc`]. **`0`** = use
/// branch-derived timeout only.
fn wallet_exit_close_cap_secs () -> Option<u64> {
  match std::env::var("ARQMA_WALLET_EXIT_CLOSE_CAP_SECS") {
    Ok(s) if s.trim() == "0" => None,
    Ok(s) => s
      .trim()
      .parse::<u64>()
      .ok()
      .map(|v| v.clamp(2, 600)),
    Err(_) => Some(20),
  }
}

fn build_wallet_rpc_reqwest_client () -> Result<reqwest::Client, String> {
  let secs = wallet_rpc_http_timeout_secs();
  reqwest::Client::builder()
    .timeout(std::time::Duration::from_secs(secs))
    .build()
    .map_err(|e| e.to_string())
}

async fn terminate_then_kill (ch: &mut Child, context: &str) {
  #[cfg(unix)]
  {
    eprintln!("[wallet] {context}: sending SIGTERM before force kill");
    send_sigterm(ch);
    let term_deadline =
      std::time::Instant::now() + std::time::Duration::from_secs(shutdown_term_wait_secs());
    loop {
      match ch.try_wait() {
        Ok(Some(_)) => return,
        Ok(None) => {
          if std::time::Instant::now() >= term_deadline {
            break;
          }
          tokio::time::sleep(std::time::Duration::from_millis(120)).await;
        }
        Err(_) => break,
      }
    }
  }
  eprintln!("[wallet] {context}: force kill fallback");
  let _ = ch.kill();
  let _ = ch.wait();
}

/// Random `rpc-login` (160 B → 320 hex chars) — distribution aligned with `Buffer.toString("hex")`.
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

fn parse_scan_height_line (line: &str) -> Option<u64> {
  // Electron `wallet-rpc.js` `height_regexes`: same line shapes on stdout.
  let t = line.trim();
  if let Some(rest) = t.strip_prefix("Skipped block by height:") {
    let digits: String = rest.trim().chars().take_while(|c| c.is_ascii_digit()).collect();
    return digits.parse().ok();
  }
  // - "Processed block: <...>, height <n>"
  // - "Skipped block by timestamp, height: <n>"
  // - "Blockchain sync progress: <...>, height <n>"
  let idx = if let Some(i) = line.rfind("height ") {
    i + "height ".len()
  } else if let Some(i) = line.rfind("height: ") {
    i + "height: ".len()
  } else {
    return None;
  };
  let tail = &line[idx..];
  let digits: String = tail
    .chars()
    .take_while(|c| c.is_ascii_digit())
    .collect();
  if digits.is_empty() {
    return None;
  }
  digits.parse::<u64>().ok()
}

fn wallet_rpc_stdio_log_to_terminal () -> bool {
  match std::env::var("ARQMA_WALLET_RPC_STDIO_LOG") {
    Ok(s) if s.trim() == "0" => false,
    _ => true,
  }
}

/// Electron `wallet-rpc.js`: `process.stdout.write(\`Wallet: ${data}\`)` for **all** wallet-rpc stdio chunks.
/// We mirror that on the Rust process stderr so `tauri dev` shows sync / "Received money" like Quasar Electron.
/// Set `ARQMA_WALLET_RPC_STDIO_LOG=0` to silence (height parsing + UI emits still run).
///
/// Scan height lines can appear on **stdout or stderr**; we parse both streams like stdout in Node.
fn spawn_wallet_scan_log_reader<R: std::io::Read + Send + 'static> (reader: R, app: AppHandle) {
  let log_stdio = wallet_rpc_stdio_log_to_terminal();
  std::thread::spawn(move || {
    let mut last_emit = std::time::Instant::now()
      .checked_sub(std::time::Duration::from_secs(2))
      .unwrap_or_else(std::time::Instant::now);
    let mut last_height: u64 = 0;
    let rd = BufReader::new(reader);
    for line in rd.lines().map_while(Result::ok) {
      if log_stdio && !line.trim().is_empty() {
        eprintln!("Wallet: {line}");
      }
      let Some(h) = parse_scan_height_line(&line) else {
        continue;
      };
      if h == 0 {
        continue;
      }
      let now = std::time::Instant::now();
      let should_emit = h > last_height
        || now.duration_since(last_emit) >= std::time::Duration::from_millis(900);
      if !should_emit {
        continue;
      }
      last_height = last_height.max(h);
      last_emit = now;
      let ts = chrono::Utc::now().timestamp_millis();
      let h = last_height;
      let app_mt = app.clone();
      let app_emit = app.clone();
      // `emit` touches WebKit on macOS — must not run from the stdio reader std::thread.
      let _ = app_mt.run_on_main_thread(move || {
        let _ = emit_receive(
          &app_emit,
          "set_wallet_info",
          json!({
            "height": h,
            "scan_poll_ts": ts
          }),
        );
      });
    }
  });
}

fn spawn_wallet_scan_stdio_bridges (child: &mut Child, app: &AppHandle) {
  let app_h = app.clone();
  if let Some(stdout) = child.stdout.take() {
    spawn_wallet_scan_log_reader(stdout, app_h.clone());
  }
  if let Some(stderr) = child.stderr.take() {
    spawn_wallet_scan_log_reader(stderr, app_h);
  }
}

/// Start `arqma-wallet-rpc` when the binary exists and create `WalletRpcClient` after `get_languages` succeeds.
///
/// Callers should hold [`crate::AppData::wallet_rpc_lane`] (or exclusively own the Wallet RPC endpoint) while
/// this runs — same lane as heartbeat / `backend_send(wallet)` — so `get_languages` does not race other JSON-RPC.
pub async fn try_start_wallet_rpc (
  app: &AppHandle,
  st: &mut WalletBackendState,
  _http: &reqwest::Client,
) -> WalletRpcStartResult {
  crate::agent_debug::log(
    "H3",
    "wallet_process.rs:try_start_wallet_rpc:entry",
    "try_start_wallet_rpc entry",
    json!({
      "wallet_process_exists": st.wallet_process.is_some(),
      "wallet_client_exists": st.wallet.is_some()
    }),
  );
  if st.wallet_process.is_some() && st.wallet.is_some() {
    crate::agent_debug::log(
      "H3",
      "wallet_process.rs:try_start_wallet_rpc:already_running",
      "wallet rpc already running",
      json!({}),
    );
    return WalletRpcStartResult::AlreadyRunning;
  }
  if st.wallet_process.is_some() && st.wallet.is_none() {
    if let Some(mut ch) = st.wallet_process.take() {
      terminate_then_kill(&mut ch, "restart stale wallet-rpc child").await;
    }
  }
  st.wallet = None;
  st.wallet_salt = String::new();
  let Some(exe) = resolve_wallet_rpc_exe(app) else {
    let cand: Vec<String> = bundled_exe_candidates(app, "arqma-wallet-rpc.exe", "arqma-wallet-rpc")
      .into_iter()
      .take(20)
      .map(|p| p.display().to_string())
      .collect();
    eprintln!(
      "[wallet] arqma-wallet-rpc not found: set ARQMA_WALLET_RPC, ARQMA_BUILD_DIR, PATH, or place exe in src-tauri/bin before tauri build (see src-tauri/bin/README.txt)"
    );
    eprintln!("[wallet] tried (first): {}", cand.join(" | "));
    crate::agent_debug::log(
      "H3",
      "wallet_process.rs:try_start_wallet_rpc:exe_missing",
      "wallet rpc executable not found",
      json!({
        "candidates": cand,
        "cwd": std::env::current_dir().ok().map(|p| p.display().to_string())
      }),
    );
    return WalletRpcStartResult::ExeNotFound;
  };
  eprintln!(
    "[wallet] using arqma-wallet-rpc: {}",
    exe.display()
  );
  crate::agent_debug::log(
    "H3",
    "wallet_process.rs:try_start_wallet_rpc:exe_resolved",
    "wallet rpc exe path",
    json!({ "exe": exe.display().to_string() }),
  );
  let Some(daemon_addr_raw) = wallet_daemon_addr(&st.config_data) else {
    eprintln!("[wallet] missing daemon data in config");
    crate::agent_debug::log(
      "H3",
      "wallet_process.rs:try_start_wallet_rpc:daemon_cfg_missing",
      "daemon config missing for wallet rpc",
      json!({}),
    );
    return WalletRpcStartResult::MissingDaemonInConfig;
  };
  let daemon_addr = daemon_addr_raw.trim().to_string();
  if daemon_addr.is_empty() {
    eprintln!("[wallet] daemon-address resolved empty; refusing to start wallet-rpc");
    return WalletRpcStartResult::MissingDaemonInConfig;
  }
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
  // Electron `wallet-rpc.js`: `Math.max(1, Number(log_level !== undefined ? log_level : 1) || 1)`.
  // Level **0** suppresses blockchain sync lines (“Processed block…”, “Skipped block…”) on stdout/stderr;
  // **1** matches Electron default and feeds the scan-progress bridge → `set_wallet_info` / footer.
  let log_level_raw = st
    .config_data
    .get("wallet")
    .and_then(|w| w.get("log_level"));
  let log_level = log_level_raw
    .and_then(|l| {
      l.as_u64()
        .or_else(|| l.as_i64().map(|i| i.clamp(0, 4) as u64))
    })
    .unwrap_or(1)
    .max(1)
    .min(4);
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
    daemon_addr.clone(),
    "--log-level".into(),
    log_level.to_string(),
    "--wallet-dir".into(),
    wdir.to_string_lossy().into(),
  ];
  eprintln!(
    "[wallet] starting wallet-rpc --daemon-address={daemon_addr} --rpc-bind-port={rpc_port} --log-level={log_level}"
  );
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
    .stdout(Stdio::piped())
    .stderr(Stdio::piped())
    .spawn()
  {
    Ok(c) => c,
    Err(e) => {
      eprintln!("[wallet] spawn: {e}");
      return WalletRpcStartResult::SpawnFailed(e.to_string());
    }
  };
  let mut ch = ch;
  spawn_wallet_scan_stdio_bridges(&mut ch, app);
  st.wallet_process = Some(ch);
  crate::agent_debug::log(
    "H3",
    "wallet_process.rs:try_start_wallet_rpc:spawned",
    "wallet rpc process spawned",
    json!({
      "exe": exe.display().to_string(),
      "daemon_addr": daemon_addr,
      "rpc_port": rpc_port
    }),
  );
  let rpc_http = match build_wallet_rpc_reqwest_client() {
    Ok(c) => c,
    Err(e) => {
      eprintln!("[wallet] wallet rpc http client build failed: {e}");
      crate::agent_debug::log(
        "H6",
        "wallet_process.rs:try_start_wallet_rpc:http_client_err",
        "wallet rpc reqwest build failed",
        json!({ "error": e }),
      );
      if let Some(mut ch) = st.wallet_process.take() {
        terminate_then_kill(&mut ch, "wallet rpc http client build failed").await;
      }
      return WalletRpcStartResult::SpawnFailed(e);
    }
  };
  crate::agent_debug::log(
    "H6",
    "wallet_process.rs:try_start_wallet_rpc:http_client",
    "wallet rpc dedicated reqwest client",
    json!({ "timeout_secs": wallet_rpc_http_timeout_secs() }),
  );
  let client = WalletRpcClient::new(&rpc_http, "127.0.0.1", rpc_port, user, pass);
  for _ in 0..60 {
    match client.call("get_languages", &Value::Null).await {
      Ok(r) if r.get("error").is_none() => {
        st.wallet = Some(Arc::new(client));
        crate::agent_debug::log(
          "H3",
          "wallet_process.rs:try_start_wallet_rpc:ready",
          "wallet rpc responded to get_languages",
          json!({}),
        );
        eprintln!("[wallet] arqma-wallet-rpc: OK (get_languages)");
        return WalletRpcStartResult::Started;
      }
      _ => {
        tokio::time::sleep(std::time::Duration::from_millis(200)).await;
      }
    }
  }
  eprintln!(
    "[wallet] timeout — no get_languages response (exe={}; check arqma-wallet-rpc.log, daemon reachability, port)",
    exe.display()
  );
  crate::agent_debug::log(
    "H3",
    "wallet_process.rs:try_start_wallet_rpc:timeout",
    "wallet rpc timeout waiting for get_languages",
    json!({ "exe": exe.display().to_string() }),
  );
  if let Some(mut ch) = st.wallet_process.take() {
    terminate_then_kill(&mut ch, "wallet-rpc startup timeout cleanup").await;
  }
  st.wallet = None;
  WalletRpcStartResult::RpcTimeout
}

/// Flush wallet, ask `arqma-wallet-rpc` to exit (`stop_wallet` — same as Monero docs), wait for the child;
/// falls back to `kill` if the process does not exit in time. Avoids orphaned RPC after app/wallet close.
///
/// Expects no concurrent access to the wallet JSON-RPC HTTP session: e.g. callers pass
/// [`tokio::sync::OwnedSemaphorePermit`] from [`crate::AppData::wallet_rpc_lane`] into
/// [`WalletBackendState::shutdown_subprocesses_async`], or invoke after heartbeats/Xfer are stopped.
pub async fn graceful_shutdown_wallet_rpc (st: &mut WalletBackendState) {
  crate::agent_debug::log(
    "H1",
    "wallet_process.rs:graceful_shutdown_wallet_rpc:entry",
    "graceful shutdown entry",
    json!({
      "wallet_client_exists": st.wallet.is_some(),
      "wallet_process_exists": st.wallet_process.is_some()
    }),
  );
  st.close_store_timed_out = false;
  if let Some(w) = st.wallet.as_ref().map(|c| c.fork_for_heartbeat()) {
    let store_t = wallet_rpc_http_timeout_secs();
    let t0 = std::time::Instant::now();
    match timeout(std::time::Duration::from_secs(store_t), w.call("store", &Value::Null)).await {
      Ok(Ok(r)) if r.get("error").is_some() => {
        crate::agent_debug::log(
          "H1",
          "wallet_process.rs:graceful_shutdown_wallet_rpc:store_rpc_error",
          "graceful store rpc error",
          json!({
            "elapsed_ms": t0.elapsed().as_millis(),
            "error": r.get("error").cloned().unwrap_or(Value::Null)
          }),
        );
        eprintln!("[wallet] quick store: {:?}", r.get("error"))
      }
      Ok(Err(e)) => {
        crate::agent_debug::log(
          "H1",
          "wallet_process.rs:graceful_shutdown_wallet_rpc:store_transport",
          "graceful store transport error",
          json!({
            "elapsed_ms": t0.elapsed().as_millis(),
            "error": e.to_string()
          }),
        );
        eprintln!("[wallet] quick store transport: {e}")
      }
      Ok(Ok(_)) => {
        crate::agent_debug::log(
          "H1",
          "wallet_process.rs:graceful_shutdown_wallet_rpc:store_ok",
          "graceful store ok",
          json!({ "elapsed_ms": t0.elapsed().as_millis() }),
        );
        eprintln!("[wallet] quick store: ok")
      }
      Err(_) => {
        crate::agent_debug::log(
          "H1",
          "wallet_process.rs:graceful_shutdown_wallet_rpc:store_timeout",
          "graceful store timeout",
          json!({ "elapsed_ms": t0.elapsed().as_millis(), "store_timeout_secs": store_t }),
        );
        eprintln!("[wallet] quick store: timeout after {store_t}s")
      }
    }
    let stop_t = wallet_rpc_http_timeout_secs();
    let t1 = std::time::Instant::now();
    match timeout(std::time::Duration::from_secs(stop_t), w.call("stop_wallet", &Value::Null)).await {
      Ok(Ok(r)) if r.get("error").is_some() => {
        crate::agent_debug::log(
          "H1",
          "wallet_process.rs:graceful_shutdown_wallet_rpc:stop_rpc_error",
          "graceful stop_wallet rpc error",
          json!({
            "elapsed_ms": t1.elapsed().as_millis(),
            "error": r.get("error").cloned().unwrap_or(Value::Null)
          }),
        );
        eprintln!("[wallet] quick stop_wallet: {:?}", r.get("error"))
      }
      Ok(Err(e)) => {
        crate::agent_debug::log(
          "H1",
          "wallet_process.rs:graceful_shutdown_wallet_rpc:stop_transport",
          "graceful stop_wallet transport error",
          json!({
            "elapsed_ms": t1.elapsed().as_millis(),
            "error": e.to_string()
          }),
        );
        eprintln!("[wallet] quick stop_wallet transport: {e}")
      }
      Ok(Ok(_)) => {
        crate::agent_debug::log(
          "H1",
          "wallet_process.rs:graceful_shutdown_wallet_rpc:stop_ok",
          "graceful stop_wallet ok",
          json!({ "elapsed_ms": t1.elapsed().as_millis() }),
        );
        eprintln!("[wallet] quick stop_wallet: ok")
      }
      Err(_) => {
        crate::agent_debug::log(
          "H1",
          "wallet_process.rs:graceful_shutdown_wallet_rpc:stop_timeout",
          "graceful stop_wallet timeout",
          json!({ "elapsed_ms": t1.elapsed().as_millis(), "stop_timeout_secs": stop_t }),
        );
        eprintln!("[wallet] quick stop_wallet: timeout after {stop_t}s")
      }
    }
  }
  st.wallet = None;
  let Some(mut ch) = st.wallet_process.take() else {
    crate::agent_debug::log(
      "H1",
      "wallet_process.rs:graceful_shutdown_wallet_rpc:no_child",
      "no wallet child process to stop",
      json!({}),
    );
    st.wallet_salt.clear();
    return;
  };
  #[cfg(unix)]
  {
    eprintln!("[wallet] immediate close: sending SIGTERM (15) to wallet-rpc child");
    send_sigterm(&ch);
  }
  #[cfg(windows)]
  {
    eprintln!("[wallet] immediate close: sending Windows force stop (/F) to wallet-rpc child");
    send_windows_soft_stop(&ch);
  }
  let deadline = std::time::Instant::now() + std::time::Duration::from_secs(shutdown_term_wait_secs());
  loop {
    match ch.try_wait() {
      Ok(Some(status)) => {
        crate::agent_debug::log(
          "H1",
          "wallet_process.rs:graceful_shutdown_wallet_rpc:exited",
          "wallet child exited",
          json!({ "status": status.code() }),
        );
        break;
      }
      Ok(None) => {
        if std::time::Instant::now() >= deadline {
          eprintln!("[wallet] close_wallet: child still running after soft stop timeout, forcing kill");
          terminate_then_kill(&mut ch, "close_wallet soft-stop timeout").await;
          break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(120)).await;
      }
      Err(e) => {
        eprintln!("[wallet] try_wait: {e}, terminating wallet-rpc child");
        terminate_then_kill(&mut ch, "close_wallet try_wait error").await;
        break;
      }
    }
  }
  st.wallet_salt.clear();
}

/// Persist + `close_wallet` JSON-RPC, then stop the child **only if** the session did not close cleanly.
///
/// Matches **Oxen** `oxen-electron-gui-wallet` / **Arqma Electron** `wallet-rpc.js::closeWallet`: after a
/// successful `close_wallet` the `wallet-rpc` process stays up for the next `open_wallet` on the same
/// HTTP endpoint. If `close_wallet` fails or there was no RPC client, [`force_shutdown_wallet_rpc`]
/// tears down the child. Set `ARQMA_WALLET_FORCE_KILL_AFTER_CLOSE=1` to always kill after `store`/`close_wallet`
/// (previous Tauri behaviour when you need to silence background scan logs).
pub async fn close_wallet_session_only (st: &mut WalletBackendState) {
  st.close_store_timed_out = false;
  let mut close_ok = false;
  let exit_store_cap = wallet_exit_store_cap_secs();
  let exit_close_cap = wallet_exit_close_cap_secs();
  if let Some(w) = st.wallet.as_ref().map(|c| c.fork_for_heartbeat()) {
    let scan_backlog = st.daemon_last_height.saturating_sub(st.wh_stored_height);
    let store_t = wallet_rpc_http_timeout_secs();
    let mut store_deadline = switch_close_first_store_secs(store_t, scan_backlog);
    if let Some(cap) = exit_store_cap {
      store_deadline = store_deadline.min(cap).max(1);
    }
    // Short first `store` → skip long retry + cap `close_wallet` RPC (see below).
    let fast_switch = store_deadline < store_t && store_deadline <= 20;
    // #region agent log
    crate::agent_debug::log(
      "H1",
      "wallet_process.rs:close_wallet_session_only:store_start",
      "close wallet store start",
      json!({
        "scan_backlog": scan_backlog,
        "store_timeout_secs": store_t,
        "store_deadline_secs_first": store_deadline,
        "fast_switch": fast_switch,
        "http_timeout_config_secs": wallet_rpc_http_timeout_secs(),
        "daemon_last_height": st.daemon_last_height,
        "wallet_height": st.wh_stored_height
      }),
    );
    // #endregion
    if exit_store_cap.is_some() {
      eprintln!(
        "[wallet] session close: first `store` RPC timeout ≤{store_deadline}s (exit cap; ARQMA_WALLET_EXIT_STORE_CAP_SECS=0 for no cap)"
      );
    }
    if fast_switch {
      eprintln!(
        "[wallet] close: fast switch (`ARQMA_WALLET_SWITCH_STORE_MAX_SECS`): first `store` ≤{store_deadline}s, no long store retry, short `close_wallet` RPC — \
scan may not persist if wallet-rpc is busy. Unset that env for default full save wait ({store_t}s)."
      );
    } else if scan_backlog > 5_000 {
      eprintln!(
        "[wallet] close: large backlog ({scan_backlog}); first `store` may take up to {store_deadline}s."
      );
    }
    let t_store = std::time::Instant::now();
    let mut store_ok = false;
    match timeout(
      std::time::Duration::from_secs(store_deadline),
      w.call("store", &Value::Null),
    )
    .await
    {
      Ok(Ok(r)) if r.get("error").is_some() => {
        // #region agent log
        crate::agent_debug::log(
          "H2",
          "wallet_process.rs:close_wallet_session_only:store_rpc_error",
          "close wallet store rpc error",
          json!({
            "elapsed_ms": t_store.elapsed().as_millis(),
            "error": r.get("error").cloned().unwrap_or(Value::Null)
          }),
        );
        // #endregion
        eprintln!(
          "[wallet] switch close store: rpc error after {}ms: {:?}",
          t_store.elapsed().as_millis(),
          r.get("error")
        )
      }
      Ok(Err(e)) => {
        // #region agent log
        crate::agent_debug::log(
          "H2",
          "wallet_process.rs:close_wallet_session_only:store_transport_error",
          "close wallet store transport error",
          json!({
            "elapsed_ms": t_store.elapsed().as_millis(),
            "error": e.to_string(),
            "wallet_process_exists": st.wallet_process.is_some()
          }),
        );
        // #endregion
        eprintln!(
          "[wallet] switch close store transport after {}ms: {e}",
          t_store.elapsed().as_millis()
        )
      }
      Ok(Ok(r)) => {
        // #region agent log
        crate::agent_debug::log(
          "H2",
          "wallet_process.rs:close_wallet_session_only:store_ok",
          "close wallet store ok",
          json!({
            "elapsed_ms": t_store.elapsed().as_millis(),
            "result": r.get("result").cloned().unwrap_or(Value::Null)
          }),
        );
        // #endregion
        eprintln!(
          "[wallet] switch close store: ok after {}ms result={}",
          t_store.elapsed().as_millis(),
          r.get("result").cloned().unwrap_or(Value::Null)
        );
        store_ok = true;
      }
      Err(_) => {
        st.close_store_timed_out = true;
        // #region agent log
        crate::agent_debug::log(
          "H2",
          "wallet_process.rs:close_wallet_session_only:store_timeout",
          "close wallet store timeout",
          json!({
            "elapsed_ms": t_store.elapsed().as_millis(),
            "store_deadline_secs_first": store_deadline,
            "store_timeout_secs_http_max": store_t,
            "scan_backlog": scan_backlog
          }),
        );
        // #endregion
        eprintln!(
          "[wallet] switch close store: timeout after {store_deadline}s (scan_backlog={scan_backlog}, http_max={store_t}s)"
        )
      }
    }
    if !store_ok && !fast_switch && exit_store_cap.is_none() {
      // One immediate retry helps when wallet-rpc is between heavy refresh chunks.
      let retry_t = std::cmp::max(60_u64, store_t / 5).min(store_t);
      let t_retry = std::time::Instant::now();
      match timeout(std::time::Duration::from_secs(retry_t), w.call("store", &Value::Null)).await {
        Ok(Ok(r)) if r.get("error").is_some() => eprintln!(
          "[wallet] switch close store retry: rpc error after {}ms: {:?}",
          t_retry.elapsed().as_millis(),
          r.get("error")
        ),
        Ok(Err(e)) => eprintln!(
          "[wallet] switch close store retry transport after {}ms: {e}",
          t_retry.elapsed().as_millis()
        ),
        Ok(Ok(r)) => {
          eprintln!(
            "[wallet] switch close store retry: ok after {}ms result={}",
            t_retry.elapsed().as_millis(),
            r.get("result").cloned().unwrap_or(Value::Null)
          );
          st.close_store_timed_out = false;
        }
        Err(_) => eprintln!("[wallet] switch close store retry: timeout after {retry_t}s"),
      }
    } else if !store_ok && fast_switch {
      eprintln!("[wallet] switch close: skipping store retry (fast switch)");
    }
    let mut close_t = if fast_switch {
      wallet_rpc_http_timeout_secs().min(12)
    } else {
      wallet_rpc_http_timeout_secs()
    };
    if let Some(cap) = exit_close_cap {
      close_t = close_t.min(cap).max(2);
    }
    let t_close = std::time::Instant::now();
    match timeout(std::time::Duration::from_secs(close_t), w.call("close_wallet", &Value::Null)).await {
      Ok(Ok(r)) if r.get("error").is_some() => {
        // #region agent log
        crate::agent_debug::log(
          "H3",
          "wallet_process.rs:close_wallet_session_only:close_rpc_error",
          "close_wallet rpc error",
          json!({
            "elapsed_ms": t_close.elapsed().as_millis(),
            "error": r.get("error").cloned().unwrap_or(Value::Null)
          }),
        );
        // #endregion
        eprintln!(
          "[wallet] switch close close_wallet: rpc error after {}ms: {:?}",
          t_close.elapsed().as_millis(),
          r.get("error")
        )
      }
      Ok(Err(e)) => {
        // #region agent log
        crate::agent_debug::log(
          "H3",
          "wallet_process.rs:close_wallet_session_only:close_transport_error",
          "close_wallet transport error",
          json!({
            "elapsed_ms": t_close.elapsed().as_millis(),
            "error": e.to_string(),
            "wallet_process_exists": st.wallet_process.is_some()
          }),
        );
        // #endregion
        eprintln!(
          "[wallet] switch close close_wallet transport after {}ms: {e}",
          t_close.elapsed().as_millis()
        )
      }
      Ok(Ok(_)) => {
        // #region agent log
        crate::agent_debug::log(
          "H3",
          "wallet_process.rs:close_wallet_session_only:close_ok",
          "close_wallet rpc ok",
          json!({ "elapsed_ms": t_close.elapsed().as_millis() }),
        );
        // #endregion
        eprintln!(
          "[wallet] switch close close_wallet: ok after {}ms",
          t_close.elapsed().as_millis()
        );
        close_ok = true;
      }
      Err(_) => eprintln!("[wallet] switch close close_wallet: timeout after {close_t}s"),
    }
  } else {
    eprintln!("[wallet] switch close: missing wallet rpc client — stopping subprocess if still running");
  }
  let force_kill_after_close = std::env::var("ARQMA_WALLET_FORCE_KILL_AFTER_CLOSE")
    .ok()
    .map(|s| {
      let t = s.trim();
      t == "1" || t.eq_ignore_ascii_case("true") || t.eq_ignore_ascii_case("yes")
    })
    .unwrap_or(false);
  // #region agent log
  crate::agent_debug::log(
    "H3",
    "wallet_process.rs:close_wallet_session_only:subprocess_policy",
    "wallet-rpc subprocess after session close",
    json!({
      "close_store_timed_out": st.close_store_timed_out,
      "close_wallet_rpc_ok": close_ok,
      "wallet_process_exists": st.wallet_process.is_some(),
      "force_kill_after_close": force_kill_after_close
    }),
  );
  // #endregion
  if force_kill_after_close || !close_ok {
    eprintln!(
      "[wallet] session close: stopping arqma-wallet-rpc subprocess (close_wallet_ok={close_ok}, force_kill_after_close={force_kill_after_close})"
    );
    force_shutdown_wallet_rpc(st).await;
  } else {
    eprintln!(
      "[wallet] session close: `close_wallet` ok — leaving arqma-wallet-rpc running (Oxen / Electron parity). Set ARQMA_WALLET_FORCE_KILL_AFTER_CLOSE=1 to always terminate."
    );
  }
}

/// Fallback path when lane/RPC is wedged: drop RPC client and hard-stop wallet-rpc child.
pub async fn force_shutdown_wallet_rpc (st: &mut WalletBackendState) {
  st.wallet = None;
  let Some(mut ch) = st.wallet_process.take() else {
    st.wallet_salt.clear();
    return;
  };
  #[cfg(unix)]
  {
    eprintln!("[wallet] force fallback: sending SIGTERM (15) to wallet-rpc child");
    send_sigterm(&ch);
  }
  #[cfg(windows)]
  {
    eprintln!("[wallet] force fallback: sending Windows force stop (/F) to wallet-rpc child");
    send_windows_soft_stop(&ch);
  }
  let _ = tokio::time::timeout(
    std::time::Duration::from_secs(shutdown_term_wait_secs()),
    async {
      loop {
        match ch.try_wait() {
          Ok(Some(_)) => break,
          Ok(None) => tokio::time::sleep(std::time::Duration::from_millis(120)).await,
          Err(_) => break,
        }
      }
    },
  )
  .await;
  let _ = ch.kill();
  let _ = ch.wait();
  st.wallet_salt.clear();
}
