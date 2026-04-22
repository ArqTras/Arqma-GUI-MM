//! Tauri backend: routes `backend_send` (same idea as `foo:send` in Electron) plus preload-style commands.

mod json_util;
mod arqma_paths_config;
mod backend_state;
mod core_handler;
mod daemon_check;
mod daemon_handler;
mod daemon_process;
mod gateway_emit;
mod http_digest_arqma;
mod json_rpc_client;
mod remote_scan;
mod startup_run;
mod wallet_copy_old_gui;
mod wallet_handler;
mod wallet_list_fs;
mod wallet_password;
mod wallet_process;
mod native_bin;
mod subprocess;
mod daemon_heartbeat;
mod wallet_heartbeat;
mod wallet_relay_ops;
mod wallet_pools;

use backend_state::WalletBackendState;
use core_handler::handle_core;
use core_handler::IpcMessage;
use serde_json::Value;
use tokio::sync::Mutex;
use tauri::Emitter;
use tauri::RunEvent;
use tauri::Manager;

use arqma_wallet_core::merge_json as merge_json_value;

pub(crate) struct AppData {
  backend: Mutex<WalletBackendState>,
  http: reqwest::Client
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
  let mut b = state.backend.lock().await;
  let data = &message.data;

  match message.module.as_str() {
    "core" => {
      handle_core(&app, &mut b, &message.method, data, http).await?;
    }
    "daemon" => {
      crate::daemon_handler::handle_daemon(&app, &mut b, http, &message.method, data).await?;
    }
    "wallet" => {
      crate::wallet_handler::handle_wallet(&app, &mut b, http, &message.method, data).await?;
    }
    _ => {
      eprintln!("[backend_send] unknown module: {}", message.module);
    }
  }

  let _ = app.emit("backend-ping", "ok");
  Ok(Value::Null)
}

pub fn run () {
  tauri::Builder::default()
    .setup(|app| {
      if cfg!(debug_assertions) {
        eprintln!("[dev] arqma paths: {:?}", arqma_wallet_core::default_paths());
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
        http
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
            let mut b = st.backend.lock().await;
            b.shutdown_subprocesses();
          }
        });
      }
    });
}
