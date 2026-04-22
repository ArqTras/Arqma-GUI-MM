//! Start lokalnego `arqmad` albo weryfikacja zdalnego RPC (odpowiednik `Daemon.start` w `backend.js`).

use crate::arqma_paths_config::daemon_rpc_host_port;
use crate::backend_state::WalletBackendState;
use crate::json_rpc_client::daemon_post;
use crate::native_bin::find_resource_bin;
use arqma_wallet_core::write_config_file;
use reqwest::Client;
use serde_json::{json, Value};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use tauri::AppHandle;

/// `Daemon.start` — `remote`: pierwsze `get_info`, lokal: spawn `arqmad` i `get_info`.
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
    .ok_or("daemons: brak wpisu")?;
  let typ = d.get("type").and_then(|t| t.as_str()).unwrap_or("local");
  if typ == "remote" {
    let Some((h, p)) = daemon_rpc_host_port(&st.config_data) else {
      return Err("Zdalny daemon: brak host/port w konfiguracji".to_string());
    };
    let r = daemon_post(http, &h, p, "get_info", 0, &Value::Null).await?;
    if r.get("error").is_some() {
      return Err("Remote daemon can not be reached".to_string());
    }
    return Ok(());
  }
  let Some(exe) = find_resource_bin(app, "arqmad.exe", "arqmad") else {
    eprintln!("[daemon] brak arqmad w resource/bin (wymagany do trybu lokalnego)");
    return Err("Błąd: brak binarki arqmad (tryb lokalny)".to_string());
  };
  let data_dir = st
    .config_data
    .get("app")
    .and_then(|a| a.get("data_dir"))
    .and_then(|p| p.as_str())
    .ok_or("app.data_dir: brak")?
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
  let ch = Command::new(&exe)
    .args(&args)
    .stdout(Stdio::null())
    .stderr(Stdio::null())
    .spawn()
    .map_err(|e| e.to_string())?;
  st.daemon_process = Some(ch);
  let Some((h, port)) = daemon_rpc_host_port(&st.config_data) else {
    return Err("Po starcie: brak host/port do poll get_info".to_string());
  };
  for _ in 0..150 {
    let r = daemon_post(http, &h, port, "get_info", 0, &Value::Null).await;
    match r {
      Ok(v) if v.get("error").is_none() => {
        eprintln!("[daemon] arqmad: get_info OK");
        return Ok(());
      }
      _ => {
        if let Some(dproc) = st.daemon_process.as_mut() {
          match dproc.try_wait() {
            Ok(Some(status)) if !status.success() => {
              st.daemon_process = None;
              return Err("Proces arqmad zakończył się przed get_info (sprawdź logi)".to_string());
            }
            _ => {}
          }
        }
        tokio::time::sleep(std::time::Duration::from_millis(200)).await;
      }
    }
  }
  eprintln!("[daemon] timeout get_info (sprawdź porty i firewall)");
  Err("Timeout: lokalny arqmad nie odpowiada (get_info)".to_string())
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

/// Gdy w `startup` wykryto `arqmad --version` = brak, przełącz bieżącą sieć na `type: remote` (jak w `backend.js`).
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
    eprintln!("[daemon] set remote: zapis config: {e}");
  }
}
