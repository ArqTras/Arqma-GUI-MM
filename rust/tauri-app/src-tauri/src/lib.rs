//! Tauri backend: routes `backend_send` (same idea as `foo:send` in Electron) plus preload-style commands.

mod agent_debug;
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
mod solo_pool_sink;
mod solo_pool;

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use backend_state::WalletBackendState;
use core_handler::handle_core;
use core_handler::IpcMessage;
use serde_json::{json, Value};
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
  pub(crate) wallet_rpc_lane: Arc<Semaphore>,
  /// Ensures [`wallet_exit_shutdown_handle`] runs at most once (`confirm_close` then [`RunEvent::Exit`], or vice versa).
  pub(crate) wallet_exit_shutdown_done: Arc<AtomicBool>,
  /// Serializes `backend_send` for `module == "wallet"` (except `get_coin_price`) — matches Electron `PQueue({ concurrency: 1 })`
  /// so `open_wallet` cannot run while `close_wallet` still holds `wallet_closing` / long `store`.
  pub(crate) wallet_ipc_serial: std::sync::Arc<tokio::sync::Mutex<()>>,
}

/// Flush/stop wallet-rpc and local daemon before the process exits.
async fn wallet_exit_shutdown_handle (st: &AppData) {
  if st
    .wallet_exit_shutdown_done
    .swap(true, Ordering::SeqCst)
  {
    // #region agent log
    crate::agent_debug::log(
      "F",
      "lib.rs:wallet_exit_shutdown_handle",
      "skip duplicate wallet exit shutdown",
      json!({}),
    );
    // #endregion
    return;
  }
  // #region agent log
  crate::agent_debug::log(
    "A",
    "lib.rs:wallet_exit_shutdown_handle",
    "wallet exit shutdown starting",
    json!({}),
  );
  // #endregion
  let http = st.http.clone();
  {
    let mut b = st.backend.lock().await;
    if let Some(h) = b.wh_xfer_task.take() {
      h.abort();
    }
    if let Some(h) = b.wallet_heartbeat.take() {
      h.abort();
    }
  }
  // #region agent log
  crate::agent_debug::log(
    "E",
    "lib.rs:wallet_exit_shutdown_handle",
    "wallet xfer/heartbeat tasks aborted, before 120ms sleep",
    json!({}),
  );
  // #endregion
  tokio::time::sleep(std::time::Duration::from_millis(120)).await;
  let lane = match st.wallet_rpc_lane.clone().acquire_owned().await {
    Ok(p) => p,
    Err(e) => {
      eprintln!("[exit] wallet_rpc_lane acquire: {e}");
      // #region agent log
      crate::agent_debug::log(
        "B",
        "lib.rs:wallet_exit_shutdown_handle",
        "wallet_rpc_lane acquire_owned failed",
        json!({ "error": e.to_string() }),
      );
      // #endregion
      return;
    }
  };
  // #region agent log
  crate::agent_debug::log(
    "B",
    "lib.rs:wallet_exit_shutdown_handle",
    "wallet_rpc_lane acquired",
    json!({}),
  );
  // #endregion
  let mut b = st.backend.lock().await;
  let had_wallet_client = b.wallet.is_some();
  // #region agent log
  crate::agent_debug::log(
    "C",
    "lib.rs:wallet_exit_shutdown_handle",
    "before shutdown_subprocesses_async",
    json!({ "had_wallet_client": had_wallet_client }),
  );
  // #endregion
  b.shutdown_subprocesses_async(&http, Some(lane)).await;
  // #region agent log
  crate::agent_debug::log(
    "C",
    "lib.rs:wallet_exit_shutdown_handle",
    "after shutdown_subprocesses_async",
    json!({ "had_wallet_client": had_wallet_client }),
  );
  // #endregion
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
async fn confirm_close (
  app: tauri::AppHandle,
  state: tauri::State<'_, AppData>,
  _restart: bool,
) -> Result<(), String> {
  // Run before `app.exit`: on failure `exit` may call `process::exit` and skip [`RunEvent::Exit`].
  wallet_exit_shutdown_handle(&state).await;
  app.exit(0);
  Ok(())
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
      if message.method == "get_coin_price" {
        // Never hold `backend` across these HTTP calls: default reqwest timeout × several URLs
        // can block for many minutes and wedges `close_wallet`, heartbeat, and pool ticks on `backend.lock()`.
        const PRICE_AGGREGATE_SECS: u64 = 22;
        if tokio::time::timeout(
          Duration::from_secs(PRICE_AGGREGATE_SECS),
          crate::wallet_relay_ops::get_coin_and_conversion(&app, http),
        )
        .await
        .is_err()
        {
          eprintln!(
            "[wallet] get_coin_price: exceeded {PRICE_AGGREGATE_SECS}s aggregate HTTP — emitting zeros"
          );
          let _ = crate::gateway_emit::BackendReceiveSink::emit_receive(&app, "set_coin_price", json!(0.0));
          let _ = crate::gateway_emit::BackendReceiveSink::emit_receive(
            &app,
            "set_conversion_data",
            json!({ "sats": 0.0_f64, "currentPrice": 0.0_f64 }),
          );
        }
      } else {
        let _wallet_ipc_serial = state.wallet_ipc_serial.lock().await;
      // xfer drops `wallet_rpc_lane` before long `get_transfers`, but abrupt `abort()` can strand server-side
      // work and leave `store` blocked until daemon drains — await JoinHandle (internal xfer cap ~300s).
      if message.method == "close_wallet" {
        let close_gate_start = std::time::Instant::now();
        let t_backend_wait = std::time::Instant::now();
        // #region agent log
        crate::agent_debug::log(
          "H15",
          "lib.rs:backend_send:close_wallet_before_backend_lock",
          "close_wallet about to await backend mutex",
          json!({}),
        );
        // #endregion
        {
          let mut b = state.backend.lock().await;
          // #region agent log
          crate::agent_debug::log(
            "H16",
            "lib.rs:backend_send:close_wallet_backend_locked",
            "close_wallet acquired backend mutex",
            json!({ "backend_wait_ms": t_backend_wait.elapsed().as_millis() }),
          );
          // #endregion
          if let Some(mut h) = b.wh_xfer_task.take() {
            // Background `get_transfers` can run ~300s; waiting the full join made **close_wallet** feel
            // stuck for minutes. Default **5s** grace then `abort()` so `store`/`close_wallet` can proceed
            // (set `ARQMA_WALLET_CLOSE_XFER_WAIT_SECS` higher if you prefer to wait for xfer to finish).
            let xfer_cap_secs = std::env::var("ARQMA_WALLET_CLOSE_XFER_WAIT_SECS")
              .ok()
              .and_then(|s| s.trim().parse::<u64>().ok())
              .map(|v| v.clamp(5, 600))
              .unwrap_or(5);
            let t_xfer = std::time::Instant::now();
            let xfer_outcome = tokio::time::timeout(
              Duration::from_secs(xfer_cap_secs),
              &mut h,
            )
            .await;
            let timed_out = xfer_outcome.is_err();
            if timed_out {
              h.abort();
              let _ = h.await;
            }
            // #region agent log
            {
              let (outcome, err_s) = match &xfer_outcome {
                Ok(Ok(())) => ("ok".to_string(), String::new()),
                Ok(Err(e)) => ("panic".to_string(), e.to_string()),
                Err(_) => ("timeout_aborted".to_string(), String::new()),
              };
              crate::agent_debug::log(
                "H13",
                "lib.rs:backend_send:close_wallet_xfer_join",
                "close_wallet xfer join result",
                json!({
                  "xfer_wait_ms": t_xfer.elapsed().as_millis(),
                  "xfer_cap_secs": xfer_cap_secs,
                  "xfer_outcome": outcome,
                  "join_err": err_s,
                }),
              );
            }
            // #endregion
            if timed_out {
              eprintln!(
                "[wallet] close_wallet: xfer wait {xfer_cap_secs}s — aborted background get_transfers (export ARQMA_WALLET_CLOSE_XFER_WAIT_SECS to wait longer)"
              );
            }
          }
          // Periodic `store` spawn holds `wallet_rpc_lane` for up to 120s; aborting the main heartbeat
          // task does not cancel that spawn — `close_wallet` would block on lane acquire and `open_wallet`
          // would spin on `wallet_closing` (user sees endless loader after switch).
          if let Some(h) = b.wh_periodic_store_task.take() {
            h.abort();
            // #region agent log
            crate::agent_debug::log(
              "H17",
              "lib.rs:backend_send:close_wallet_abort_periodic_store",
              "close_wallet aborted wh_periodic_store_task to release wallet_rpc_lane",
              json!({}),
            );
            // #endregion
          }
          // `begin_Stake_Acquisition` → `run_pool_tick` holds `wallet_rpc_lane` for the whole tick; it can
          // wake during the 120 ms gap before `close_wallet` acquires the lane and wedge the close/open chain.
          let had_stake = b.stake_acquisition_task.is_some();
          crate::wallet_pools::end_stake_acquisition(&mut b);
          if had_stake {
            // #region agent log
            crate::agent_debug::log(
              "H18",
              "lib.rs:backend_send:close_wallet_abort_stake_acquisition",
              "close_wallet aborted stake_acquisition_task (pool tick held lane)",
              json!({}),
            );
            // #endregion
          }
          if let Some(h) = b.wallet_heartbeat.take() {
            h.abort();
            let _ = tokio::time::timeout(Duration::from_secs(2), h).await;
          }
        }
        tokio::time::sleep(Duration::from_millis(120)).await;
        // Set `wallet_closing` **after** xfer join + heartbeat abort — otherwise `open_wallet` spins for
        // the whole `ARQMA_WALLET_CLOSE_XFER_WAIT_SECS` window while no lane work is happening yet.
        state.wallet_closing.store(true, Ordering::SeqCst);
        // #region agent log
        crate::agent_debug::log(
          "H14",
          "lib.rs:backend_send:wallet_ipc_close_enter",
          "close_wallet: wallet_closing set after prep (before lane)",
          json!({ "prep_elapsed_ms": close_gate_start.elapsed().as_millis() }),
        );
        crate::agent_debug::log(
          "H4",
          "lib.rs:backend_send:close_wallet_pre_lane",
          "close_wallet reached lane acquire",
          json!({ "prep_elapsed_ms": close_gate_start.elapsed().as_millis() }),
        );
        // #endregion
      }
      let _wallet_lane = if message.method == "close_wallet" {
        let lane_wait_start = std::time::Instant::now();
        let lane_deadline_secs = crate::wallet_process::wallet_rpc_http_timeout_secs()
          .saturating_add(120)
          .max(180);
        let permit = match tokio::time::timeout(
          Duration::from_secs(lane_deadline_secs),
          state.wallet_rpc_lane.clone().acquire_owned(),
        )
        .await
        {
          Ok(Ok(p)) => p,
          Ok(Err(e)) => return Err(format!("wallet_rpc_lane: {}", e)),
          Err(_) => {
            eprintln!(
              "[wallet] close_wallet: wallet_rpc_lane acquire timed out after {lane_deadline_secs}s — forcing wallet-rpc shutdown"
            );
            {
              let mut b = state.backend.lock().await;
              crate::wallet_process::force_shutdown_wallet_rpc(&mut b).await;
            }
            state.wallet_closing.store(false, Ordering::SeqCst);
            return Err(format!(
              "close_wallet: wallet_rpc_lane acquire timed out after {lane_deadline_secs}s",
            ));
          }
        };
        // #region agent log
        crate::agent_debug::log(
          "H4",
          "lib.rs:backend_send:close_wallet_lane_acquired",
          "close_wallet acquired wallet_rpc_lane",
          json!({ "lane_wait_ms": lane_wait_start.elapsed().as_millis() }),
        );
        // #endregion
        Some(permit)
      } else if message.method == "open_wallet" {
        // **Do not** hold `wallet_rpc_lane` across `handle_wallet(open_wallet)`.
        // `open_wallet` ends by spawning the wallet heartbeat; `tick_once` immediately
        // `acquire_owned`s the same semaphore (capacity 1). The IPC handler still holds
        // this permit until after `wallet_res?` → deadlock: no sync, frozen UI / menu.
        // Other wallet IPC is serialized by `backend` mutex; heartbeat is not running yet
        // during `try_start_wallet_rpc` + `open_wallet` RPC.
        None
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
            // Native wallet2 backend mode: do not try to restart wallet-rpc subprocess.
            eprintln!("[wallet] open_wallet failed/timed out (wallet2 backend): skipping wallet-rpc restart fallback");
            Err(e)
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
        if window.label() == MAIN_WINDOW_LABEL && window.hide().is_ok() {
          api.prevent_close();
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
        wallet_rpc_lane: Arc::new(Semaphore::new(1)),
        wallet_exit_shutdown_done: Arc::new(AtomicBool::new(false)),
        wallet_ipc_serial: std::sync::Arc::new(tokio::sync::Mutex::new(())),
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
      match event {
        RunEvent::ExitRequested { code, .. } => {
          // #region agent log
          crate::agent_debug::log(
            "F",
            "lib.rs:RunEvent::ExitRequested",
            "exit requested (observe vs Exit for ordering)",
            json!({ "code": code }),
          );
          // #endregion
        }
        RunEvent::Exit => {
          tauri::async_runtime::block_on(async {
            // #region agent log
            crate::agent_debug::log(
              "A",
              "lib.rs:RunEvent::Exit",
              "exit handler entered",
              json!({}),
            );
            // #endregion
            if let Some(st) = app.try_state::<AppData>() {
              wallet_exit_shutdown_handle(&st).await;
            } else {
              // #region agent log
              crate::agent_debug::log(
                "A",
                "lib.rs:RunEvent::Exit",
                "try_state AppData missing — shutdown skipped",
                json!({}),
              );
              // #endregion
            }
          });
        }
        _ => {}
      }
    });
}

/// Config base directory for [`run_flutter_solo_pool_async`]: first non-empty CLI arg, else `ARQMA_CONFIG_DIR`, else OS default (`arqma_wallet_core::default_paths`).
pub fn resolve_paths_for_flutter_solo_pool_sidecar () -> arqma_wallet_core::ArqmaPaths {
  let mut paths = arqma_wallet_core::default_paths();
  if let Some(a) = std::env::args().nth(1) {
    let t = a.trim();
    if !t.is_empty() {
      paths.config_dir = t.to_string();
      return paths;
    }
  }
  if let Ok(d) = std::env::var("ARQMA_CONFIG_DIR") {
    let t = d.trim();
    if !t.is_empty() {
      paths.config_dir = t.to_string();
    }
  }
  paths
}

/// Standalone process: load `gui/config.json`, run Stratum solo pool, emit gateway-shaped JSON lines on stdout until Ctrl+C.
pub async fn run_flutter_solo_pool_async () -> Result<(), String> {
  use arqma_wallet_core::load_config_snapshot;
  let paths = resolve_paths_for_flutter_solo_pool_sidecar();
  let snap = load_config_snapshot(&paths).map_err(|e| e.to_string())?;
  let mut st = WalletBackendState::default();
  st.paths = paths;
  st.defaults = snap.defaults.clone();
  st.config_data = snap.config_data.clone();
  st.remotes = snap.remotes.clone();
  st.ethereum = snap.ethereum.clone();
  if let Some(pool) = st.config_data.get_mut("pool") {
    solo_pool::strip_legacy_uniform_pool_option(pool);
  }
  let bind_ip = st
    .config_data
    .get("pool")
    .and_then(|p| p.get("server"))
    .and_then(|s| s.get("bindIP"))
    .and_then(|v| v.as_str())
    .unwrap_or("");
  if bind_ip.is_empty() || bind_ip == "0.0.0.0" || bind_ip == "127.0.0.1" {
    st.config_data = merge_json_value(
      &st.config_data,
      &json!({ "pool": { "server": { "bindIP": solo_pool::preferred_bind_ip() } } }),
    );
  }
  st.config_data = merge_json_value(
    &st.config_data,
    &json!({ "wallet": { "rpc_bind_port": 19999_u64 } }),
  );
  solo_pool::stop(&mut st);
  solo_pool::start(solo_pool_sink::JsonlStdoutSoloPoolSink, &mut st);
  if st.solo_pool_task.is_none() {
    return Ok(());
  }
  tokio::signal::ctrl_c().await.map_err(|e| e.to_string())?;
  solo_pool::stop(&mut st);
  Ok(())
}
