//! Tauri backend: routes `backend_send` (same idea as `foo:send` in Electron) plus preload-style commands.

mod json_util;
mod arqma_paths_config;
mod backend_state;
mod core_handler;
mod daemon_check;
mod daemon_handler;
mod daemon_process;
mod gateway_emit;
mod json_rpc_client;
mod remote_scan;
mod startup_run;
mod wallet_copy_old_gui;
mod wallet_handler;
mod wallet_rpc_electron;
mod wallet_list_fs;
mod wallet_password;
mod wallet_process;
mod native_bin;
mod subprocess;
mod daemon_heartbeat;
mod sync_debug;
mod wallet_diag;
mod wallet_heartbeat;
mod wallet_relay_ops;
mod wallet_pools;
mod solo_pool;

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use backend_state::WalletBackendState;
use core_handler::handle_core;
use core_handler::IpcMessage;
use serde_json::Value;
use tokio::sync::Mutex;
use tokio::sync::Semaphore;
use tauri::Emitter;
use tauri::Manager;
use tauri::RunEvent;
use tauri::WindowEvent;
use tauri::image::Image;
use tauri::menu::{Menu, MenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};

use arqma_wallet_core::merge_json as merge_json_value;

pub(crate) struct AppData {
  backend: Mutex<WalletBackendState>,
  http: reqwest::Client,
  /// `open_wallet` must not block on [`Self::backend`] while `close_wallet` awaits long `store`/RPC.
  pub(crate) wallet_closing: Arc<AtomicBool>,
  /// Serializes logical JSON-RPC usage against local `arqma-wallet-rpc` (parity with Electron wallet command queue).
  /// Acquire **before** the backend mutex for `wallet`/`save_config_init`/exit paths (see heartbeat, `backend_send`).
  pub(crate) wallet_rpc_lane: Arc<Semaphore>
}

#[tauri::command]
fn app_log_error (module: String, method: String, message: String) {
  eprintln!("[error] {module}::{method} {message}")
}

#[tauri::command]
fn app_log_info (module: String, method: String, message: String) {
  eprintln!("[info]  {module}::{method} {message}")
}

#[tauri::command]
fn app_is_dev () -> bool {
  cfg!(debug_assertions)
}

#[tauri::command]
fn app_version_str (app: tauri::AppHandle) -> String {
  app.package_info().version.to_string()
}

#[tauri::command]
fn util_join_path (data_dir: String, subdirectory: String, file_name: String) -> String {
  use std::path::PathBuf;
  PathBuf::from(data_dir)
    .join(subdirectory)
    .join(file_name)
    .to_string_lossy()
    .to_string()
}

#[tauri::command]
fn fs_read_json_remotes (data_dir: String, subdirectory: String, file_name: String) -> Result<Value, String> {
  use std::fs;
  use std::path::PathBuf;
  let p = PathBuf::from(&data_dir).join(&subdirectory).join(&file_name);
  let s = fs::read_to_string(&p).map_err(|e| e.to_string())?;
  serde_json::from_str(&s).map_err(|e| e.to_string())
}

#[tauri::command]
fn util_no_mutate (v1: Value, v2: Value) -> Value {
  merge_json_value(&v1, &v2)
}

#[tauri::command]
fn clip_write_text (text: String) -> Result<(), String> {
  arboard::Clipboard::new()
    .map_err(|e| e.to_string())?
    .set_text(text)
    .map_err(|e| e.to_string())
}

#[tauri::command]
fn clip_write_image (_v1: String) {}

#[tauri::command]
fn image_from_data_url (data: String) -> String {
  data
}

#[tauri::command]
fn app_save_log_level (app: tauri::AppHandle, value: String) -> Result<(), String> {
  use std::fs;
  use std::io::Read;
  use std::io::Write;
  let dir = if cfg!(debug_assertions) {
    app.path().resource_dir().map_err(|e| e.to_string())?
  } else {
    app
      .path()
      .app_data_dir()
      .map_err(|e| e.to_string())?
  };
  if let Err(e) = fs::create_dir_all(&dir) {
    eprintln!("[config] app_save_log_level mkdir: {e}");
  }
  let p = dir.join(".env");
  let mut s = String::new();
  if p.exists() {
    let _ = fs::File::open(&p)
      .and_then(|mut f| f.read_to_string(&mut s));
  }
  let mut lines: Vec<String> = if s.is_empty() {
    vec![format!("LOG_LEVEL={value}")]
  } else {
    s.lines().map(String::from).collect()
  };
  if lines.is_empty() || lines[0].is_empty() {
    lines[0] = format!("LOG_LEVEL={value}");
  } else {
    let mut found = false;
    for line in &mut lines {
      if line.starts_with("LOG_LEVEL") {
        *line = format!("LOG_LEVEL={value}");
        found = true;
        break;
      }
    }
    if !found {
      lines.insert(0, format!("LOG_LEVEL={value}"));
    }
  }
  let mut f = fs::File::create(&p).map_err(|e| e.to_string())?;
  f.write_all(lines.join("\n").as_bytes()).map_err(|e| e.to_string())?;
  Ok(())
}

#[tauri::command]
fn daemon_version_probe (app: tauri::AppHandle) -> String {
  crate::daemon_handler::arqmad_version_probe_str(&app)
}

#[tauri::command]
fn confirm_close (app: tauri::AppHandle, _restart: bool) {
  app.exit(0);
}

#[tauri::command]
fn dialog_open_dir (default_path: String) -> Option<String> {
  let mut b = rfd::FileDialog::new();
  if !default_path.is_empty() {
    b = b.set_directory(default_path);
  }
  b.pick_folder()
    .map(|p| p.to_string_lossy().to_string())
}

#[tauri::command]
async fn backend_send (app: tauri::AppHandle, state: tauri::State<'_, AppData>, message: IpcMessage) -> Result<Value, String> {
  eprintln!("[backend_send] {}::{}", message.module, message.method);

  let http = &state.http;
  let data = &message.data;

  match message.module.as_str() {
    "core" => {
      let rpc_lane_shutdown = if message.method == "save_config_init" {
        Some(
          state
            .wallet_rpc_lane
            .clone()
            .acquire_owned()
            .await
            .map_err(|e| format!("wallet_rpc_lane: {}", e))?,
        )
      } else {
        None
      };
      let mut b = state.backend.lock().await;
      handle_core(
        &app,
        &mut b,
        &message.method,
        data,
        http,
        rpc_lane_shutdown,
      )
      .await?;
    }
    "daemon" => {
      let mut b = state.backend.lock().await;
      crate::daemon_handler::handle_daemon(&app, &mut b, http, &message.method, data).await?;
    }
    "wallet" => {
      if message.method == "open_wallet" {
        // Must cover worst-case `close_wallet` RPC (`store` can run as long as wallet-rpc HTTP timeout).
        let wait_cap =
          crate::wallet_process::wallet_rpc_http_timeout_secs().saturating_add(60);
        let deadline = std::time::Instant::now() + Duration::from_secs(wait_cap.max(30));
        let wait_start = std::time::Instant::now();
        let mut wait_loops: u32 = 0;
        loop {
          let closing = state.wallet_closing.load(Ordering::SeqCst);
          if !closing {
            break;
          }
          wait_loops = wait_loops.saturating_add(1);
          if wait_loops == 1 || wait_loops % 32 == 0 {
            eprintln!(
              "[wallet] open_wallet: waiting for in-flight close (wallet_closing), elapsed={}ms — close may be saving (store); large backlog can take many minutes",
              wait_start.elapsed().as_millis()
            );
          }
          if std::time::Instant::now() >= deadline {
            // #region agent log
            let payload = serde_json::json!({
              "sessionId": "dc1ad5",
              "runId": "pre-fix",
              "hypothesisId": "H5",
              "location": "lib.rs:backend_send:open_wallet_wait_timeout",
              "message": "open_wallet wait for close timed out",
              "data": {
                "wait_ms": wait_start.elapsed().as_millis(),
                "wait_loops": wait_loops
              },
              "timestamp": chrono::Utc::now().timestamp_millis()
            });
            if let Ok(mut f) = std::fs::OpenOptions::new()
              .create(true)
              .append(true)
              .open("C:\\GitHub\\NOWE\\GUI-Rust\\debug-dc1ad5.log")
            {
              use std::io::Write;
              let _ = writeln!(f, "{}", payload);
              let _ = f.flush();
            }
            // #endregion
            return Err("wallet is closing, try again in a moment".to_string());
          }
          tokio::time::sleep(Duration::from_millis(160)).await;
        }
        // #region agent log
        let payload = serde_json::json!({
          "sessionId": "dc1ad5",
          "runId": "pre-fix",
          "hypothesisId": "H5",
          "location": "lib.rs:backend_send:open_wallet_wait_done",
          "message": "open_wallet wait for close finished",
          "data": {
            "wait_ms": wait_start.elapsed().as_millis(),
            "wait_loops": wait_loops
          },
          "timestamp": chrono::Utc::now().timestamp_millis()
        });
        if let Ok(mut f) = std::fs::OpenOptions::new()
          .create(true)
          .append(true)
          .open("C:\\GitHub\\NOWE\\GUI-Rust\\debug-dc1ad5.log")
        {
          use std::io::Write;
          let _ = writeln!(f, "{}", payload);
          let _ = f.flush();
        }
        // #endregion
      }
      // xfer drops `wallet_rpc_lane` before long `get_transfers`, but abrupt `abort()` can strand server-side
      // work and leave `store` blocked until daemon drains — await JoinHandle (internal xfer cap ~300s).
      if message.method == "close_wallet" {
        // Block new `open_wallet` before any `await` — previously H14 logged here without setting
        // `wallet_closing`, so `open_wallet` could take `wallet_rpc_lane` + `backend` and wedge `close_wallet`
        // on `backend.lock()` with no NDJSON until the stall clears (matches gap after H14 in logs).
        state.wallet_closing.store(true, Ordering::SeqCst);
        // #region agent log
        {
          let payload = serde_json::json!({
            "sessionId": "dc1ad5",
            "runId": "pre-fix",
            "hypothesisId": "H14",
            "location": "lib.rs:backend_send:wallet_ipc_close_enter",
            "message": "close_wallet: wallet_closing gate set (before backend lock)",
            "data": {},
            "timestamp": chrono::Utc::now().timestamp_millis()
          });
          if let Ok(mut f) = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open("C:\\GitHub\\NOWE\\GUI-Rust\\debug-dc1ad5.log")
          {
            use std::io::Write;
            let _ = writeln!(f, "{}", payload);
            let _ = f.flush();
          }
        }
        // #endregion
        let close_gate_start = std::time::Instant::now();
        let t_backend_wait = std::time::Instant::now();
        // #region agent log
        {
          let payload = serde_json::json!({
            "sessionId": "dc1ad5",
            "runId": "pre-fix",
            "hypothesisId": "H15",
            "location": "lib.rs:backend_send:close_wallet_before_backend_lock",
            "message": "close_wallet about to await backend mutex",
            "data": {},
            "timestamp": chrono::Utc::now().timestamp_millis()
          });
          if let Ok(mut f) = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open("C:\\GitHub\\NOWE\\GUI-Rust\\debug-dc1ad5.log")
          {
            use std::io::Write;
            let _ = writeln!(f, "{}", payload);
            let _ = f.flush();
          }
        }
        // #endregion
        {
          let mut b = state.backend.lock().await;
          // #region agent log
          {
            let payload = serde_json::json!({
              "sessionId": "dc1ad5",
              "runId": "pre-fix",
              "hypothesisId": "H16",
              "location": "lib.rs:backend_send:close_wallet_backend_locked",
              "message": "close_wallet acquired backend mutex",
              "data": { "backend_wait_ms": t_backend_wait.elapsed().as_millis() },
              "timestamp": chrono::Utc::now().timestamp_millis()
            });
            if let Ok(mut f) = std::fs::OpenOptions::new()
              .create(true)
              .append(true)
              .open("C:\\GitHub\\NOWE\\GUI-Rust\\debug-dc1ad5.log")
            {
              use std::io::Write;
              let _ = writeln!(f, "{}", payload);
              let _ = f.flush();
            }
          }
          // #endregion
          if let Some(h) = b.wh_xfer_task.take() {
            let xfer_cap_secs = std::env::var("ARQMA_WALLET_CLOSE_XFER_WAIT_SECS")
              .ok()
              .and_then(|s| s.trim().parse::<u64>().ok())
              .map(|v| v.clamp(120, 900))
              .unwrap_or(360);
            let t_xfer = std::time::Instant::now();
            let xfer_wait = tokio::time::timeout(Duration::from_secs(xfer_cap_secs), h).await;
            // #region agent log
            {
              let (outcome, err_s) = match &xfer_wait {
                Ok(join_r) => match join_r {
                  Ok(_) => ("ok".to_string(), String::new()),
                  Err(e) => ("panic".to_string(), e.to_string()),
                },
                Err(_) => ("timeout".to_string(), String::new()),
              };
              let payload = serde_json::json!({
                "sessionId": "dc1ad5",
                "runId": "pre-fix",
                "hypothesisId": "H13",
                "location": "lib.rs:backend_send:close_wallet_xfer_join",
                "message": "close_wallet xfer join result",
                "data": {
                  "xfer_wait_ms": t_xfer.elapsed().as_millis(),
                  "xfer_cap_secs": xfer_cap_secs,
                  "xfer_outcome": outcome,
                  "join_err": err_s,
                },
                "timestamp": chrono::Utc::now().timestamp_millis()
              });
              if let Ok(mut f) = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open("C:\\GitHub\\NOWE\\GUI-Rust\\debug-dc1ad5.log")
              {
                use std::io::Write;
                let _ = writeln!(f, "{}", payload);
                let _ = f.flush();
              }
            }
            // #endregion
            if xfer_wait.is_err() {
              eprintln!(
                "[wallet] close_wallet: xfer exceeded {xfer_cap_secs}s — continuing (store may be delayed)"
              );
            }
          }
          // Periodic `store` spawn holds `wallet_rpc_lane` for up to 120s; aborting the main heartbeat
          // task does not cancel that spawn — `close_wallet` would block on lane acquire and `open_wallet`
          // would spin on `wallet_closing` (user sees endless loader after switch).
          if let Some(h) = b.wh_periodic_store_task.take() {
            h.abort();
            // #region agent log
            {
              let payload = serde_json::json!({
                "sessionId": "dc1ad5",
                "runId": "pre-fix",
                "hypothesisId": "H17",
                "location": "lib.rs:backend_send:close_wallet_abort_periodic_store",
                "message": "close_wallet aborted wh_periodic_store_task to release wallet_rpc_lane",
                "data": {},
                "timestamp": chrono::Utc::now().timestamp_millis()
              });
              if let Ok(mut f) = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open("C:\\GitHub\\NOWE\\GUI-Rust\\debug-dc1ad5.log")
              {
                use std::io::Write;
                let _ = writeln!(f, "{}", payload);
                let _ = f.flush();
              }
            }
            // #endregion
          }
          // `begin_Stake_Acquisition` → `run_pool_tick` holds `wallet_rpc_lane` for the whole tick; it can
          // wake during the 120 ms gap before `close_wallet` acquires the lane and wedge the close/open chain.
          let had_stake = b.stake_acquisition_task.is_some();
          crate::wallet_pools::end_stake_acquisition(&mut b);
          if had_stake {
            // #region agent log
            {
              let payload = serde_json::json!({
                "sessionId": "dc1ad5",
                "runId": "pre-fix",
                "hypothesisId": "H18",
                "location": "lib.rs:backend_send:close_wallet_abort_stake_acquisition",
                "message": "close_wallet aborted stake_acquisition_task (pool tick held lane)",
                "data": {},
                "timestamp": chrono::Utc::now().timestamp_millis()
              });
              if let Ok(mut f) = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open("C:\\GitHub\\NOWE\\GUI-Rust\\debug-dc1ad5.log")
              {
                use std::io::Write;
                let _ = writeln!(f, "{}", payload);
                let _ = f.flush();
              }
            }
            // #endregion
          }
          if let Some(h) = b.wallet_heartbeat.take() {
            h.abort();
            let _ = tokio::time::timeout(Duration::from_secs(2), h).await;
          }
        }
        tokio::time::sleep(Duration::from_millis(120)).await;
        // #region agent log
        let payload = serde_json::json!({
          "sessionId": "dc1ad5",
          "runId": "pre-fix",
          "hypothesisId": "H4",
          "location": "lib.rs:backend_send:close_wallet_pre_lane",
          "message": "close_wallet reached lane acquire",
          "data": { "prep_elapsed_ms": close_gate_start.elapsed().as_millis() },
          "timestamp": chrono::Utc::now().timestamp_millis()
        });
        if let Ok(mut f) = std::fs::OpenOptions::new()
          .create(true)
          .append(true)
          .open("C:\\GitHub\\NOWE\\GUI-Rust\\debug-dc1ad5.log")
        {
          use std::io::Write;
          let _ = writeln!(f, "{}", payload);
          let _ = f.flush();
        }
        // #endregion
      }
      let _wallet_lane = if message.method == "get_coin_price" {
        None
      } else if message.method == "close_wallet" {
        let lane_wait_start = std::time::Instant::now();
        Some(
          state
            .wallet_rpc_lane
            .clone()
            .acquire_owned()
            .await
            .map_err(|e| format!("wallet_rpc_lane: {}", e))
            .map(|permit| {
              // #region agent log
              let payload = serde_json::json!({
                "sessionId": "dc1ad5",
                "runId": "pre-fix",
                "hypothesisId": "H4",
                "location": "lib.rs:backend_send:close_wallet_lane_acquired",
                "message": "close_wallet acquired wallet_rpc_lane",
                "data": { "lane_wait_ms": lane_wait_start.elapsed().as_millis() },
                "timestamp": chrono::Utc::now().timestamp_millis()
              });
              if let Ok(mut f) = std::fs::OpenOptions::new()
                .create(true)
                .append(true)
                .open("C:\\GitHub\\NOWE\\GUI-Rust\\debug-dc1ad5.log")
              {
                use std::io::Write;
                let _ = writeln!(f, "{}", payload);
                let _ = f.flush();
              }
              // #endregion
              permit
            })?,
        )
      } else if message.method == "open_wallet" {
        // Align with `close_wallet` holding the lane for `store` (HTTP timeout can be ~600s).
        let open_lane_secs = crate::wallet_process::wallet_rpc_http_timeout_secs()
          .saturating_add(60)
          .clamp(30, 900);
        match tokio::time::timeout(
          Duration::from_secs(open_lane_secs),
          state.wallet_rpc_lane.clone().acquire_owned(),
        )
        .await
        {
          Ok(Ok(permit)) => Some(permit),
          Ok(Err(e)) => return Err(format!("wallet_rpc_lane: {}", e)),
          Err(_) => {
            return Err(format!(
              "open_wallet: wallet_rpc_lane acquire timeout after {open_lane_secs}s (another call may be saving the wallet)"
            ));
          }
        }
      } else {
        Some(
          state
            .wallet_rpc_lane
            .clone()
            .acquire_owned()
            .await
            .map_err(|e| format!("wallet_rpc_lane: {}", e))?,
        )
      };
      let wallet_res = {
        let mut b = state.backend.lock().await;
        crate::wallet_handler::handle_wallet(&app, &mut b, http, &message.method, data).await
      };
      let wallet_res = if message.method == "open_wallet" {
        match wallet_res {
          Ok(v) => Ok(v),
          Err(e) if e.contains("open_wallet RPC timed out") || e.contains("open_wallet RPC failed") => {
            eprintln!("[wallet] open_wallet failed/timed out, restarting wallet-rpc and retrying once");
            crate::wallet_process::force_kill_wallet_rpc_process_tree();
            {
              let mut b = state.backend.lock().await;
              b.wallet = None;
              b.wallet_process = None;
              b.wallet_salt.clear();
            }
            tokio::time::sleep(Duration::from_millis(260)).await;
            let mut b = state.backend.lock().await;
            crate::wallet_handler::handle_wallet(&app, &mut b, http, &message.method, data).await
          }
          Err(e) => Err(e),
        }
      } else {
        wallet_res
      };
      if message.method == "close_wallet" {
        state.wallet_closing.store(false, Ordering::SeqCst);
      }
      wallet_res?;
    }
    _ => {
      eprintln!("[backend_send] unknown module: {}", message.module);
    }
  }

  let _ = app.emit("backend-ping", "ok");
  Ok(Value::Null)
}

const MAIN_WINDOW_LABEL: &str = "main";
const TRAY_OPEN_ID: &str = "tray_open";

/// tray.png next to tauri `Cargo.toml` (Vite public asset).
const TRAY_ICON_PNG: &[u8] =
  include_bytes!(concat!(env!("CARGO_MANIFEST_DIR"), "/../public/tray.png"));

fn show_main_window (app: &tauri::AppHandle) {
  if let Some(w) = app.get_webview_window(MAIN_WINDOW_LABEL) {
    let _ = w.unminimize();
    let _ = w.show();
    let _ = w.set_focus();
  }
}

fn try_create_tray (app: &tauri::App) -> tauri::Result<()> {
  let icon = Image::from_bytes(TRAY_ICON_PNG)?;
  let h_tray = app.handle().clone();
  let menu = Menu::new(app)?;
  let open = MenuItem::with_id(
    app,
    TRAY_OPEN_ID,
    "Open",
    true,
    None::<&str>,
  )?;
  menu.append(&open)?;
  let _ = TrayIconBuilder::new()
    .menu(&menu)
    .icon(icon)
    .tooltip("Arqma-Wallet")
    .show_menu_on_left_click(false)
    .on_menu_event(move |app, e| {
      if e.id() == TRAY_OPEN_ID {
        show_main_window(app);
      }
    })
    .on_tray_icon_event(move |_, e| {
      match e {
        TrayIconEvent::Click {
          button: MouseButton::Left,
          button_state: MouseButtonState::Up,
          ..
        } => {
          show_main_window(&h_tray);
        }
        TrayIconEvent::DoubleClick {
          button: MouseButton::Left,
          ..
        } => {
          show_main_window(&h_tray);
        }
        _ => {}
      }
    })
    .build(app)?;
  Ok(())
}

pub fn run () {
  tauri::Builder::default()
    .on_window_event(|window, event| {
      if let WindowEvent::CloseRequested { api, .. } = event {
        if window.label() == MAIN_WINDOW_LABEL {
          if window.hide().is_ok() {
            api.prevent_close();
          }
        }
      }
    })
    .setup(|app| {
      if sync_debug::is_sync_debug() {
        eprintln!(
          "[sync-debug] ARQMA_SYNC_DEBUG is set — verbose wallet/daemon sync logs on stderr (unset or 0 to silence)"
        );
      }
      if cfg!(debug_assertions) {
        eprintln!("[dev] arqma paths: {:?}", arqma_wallet_core::default_paths());
      }
      if let Err(e) = try_create_tray(app) {
        eprintln!("[tray] could not create system tray: {e}");
      }
      let h = app.handle().clone();
      tauri::async_runtime::spawn(async move {
        tokio::time::sleep(std::time::Duration::from_millis(300)).await;
        let _ = h.emit(
          "backend-receive",
          serde_json::json!({ "event": "initialize" }),
        );
      });
      Ok(())
    })
    .manage({
      let http = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(120))
        .build()
        .expect("reqwest::Client");
      AppData {
        backend: Mutex::new(WalletBackendState::default()),
        http,
        wallet_closing: Arc::new(AtomicBool::new(false)),
        wallet_rpc_lane: Arc::new(Semaphore::new(1))
      }
    })
    .invoke_handler(tauri::generate_handler![
      app_log_error,
      app_log_info,
      app_is_dev,
      app_version_str,
      util_join_path,
      fs_read_json_remotes,
      util_no_mutate,
      clip_write_text,
      clip_write_image,
      image_from_data_url,
      app_save_log_level,
      daemon_version_probe,
      confirm_close,
      dialog_open_dir,
      backend_send
    ])
    .build(tauri::generate_context!())
    .expect("Tauri Builder error")
    .run(|app, event| {
      if let RunEvent::Exit = event {
        tauri::async_runtime::block_on(async {
          if let Some(st) = app.try_state::<AppData>() {
            let http = st.http.clone();
            // Abort tasks that hold `wallet_rpc_lane` first; otherwise Exit would await `acquire_owned`
            // indefinitely while heartbeat/xfer still hold the single permit (`store` could never run).
            {
              let mut b = st.backend.lock().await;
              if let Some(h) = b.wh_xfer_task.take() {
                h.abort();
              }
              if let Some(h) = b.wallet_heartbeat.take() {
                h.abort();
              }
            }
            tokio::time::sleep(std::time::Duration::from_millis(120)).await;
            let lane = match st.wallet_rpc_lane.clone().acquire_owned().await {
              Ok(p) => p,
              Err(e) => {
                eprintln!("[exit] wallet_rpc_lane acquire: {e}");
                return;
              }
            };
            let mut b = st.backend.lock().await;
            b.shutdown_subprocesses_async(&http, Some(lane)).await;
          }
        });
      }
    });
}
