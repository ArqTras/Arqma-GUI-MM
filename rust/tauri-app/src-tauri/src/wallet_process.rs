use crate::backend_state::WalletBackendState;
use crate::json_rpc_client::WalletRpcClient;
use crate::native_bin::find_resource_bin;
use rand::RngCore;
use serde_json::Value;
use std::process::{Command, Stdio};
use tauri::AppHandle;

/// Losowe `rpc-login` (160 B → 320 znaków hex) — poprawiony rozkład względem `Buffer.toString("hex")`.
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

/// Uruchomienie `arqma-wallet-rpc` (jeśli binarka istnieje) i utworzenie `WalletRpcClient` po odpowiedzi `get_languages`.
pub async fn try_start_wallet_rpc (
  app: &AppHandle,
  st: &mut WalletBackendState,
  http: &reqwest::Client,
) {
  if st.wallet_process.is_some() {
    return;
  }
  st.wallet = None;
  st.wallet_salt = String::new();
  let Some(exe) = find_resource_bin(app, "arqma-wallet-rpc.exe", "arqma-wallet-rpc") else {
    eprintln!("[wallet] brak pliku arqma-wallet-rpc w resource/bin (opcjonalny)");
    return;
  };
  let Some(daemon_addr) = wallet_daemon_addr(&st.config_data) else {
    eprintln!("[wallet] brak danych daemona w config");
    return;
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
      eprintln!("[wallet] brak katalogu portfela");
      return;
    }
  };
  if let Err(e) = std::fs::create_dir_all(&wdir) {
    eprintln!("[wallet] create_dir_all: {e}");
    return;
  }
  let log_level = st
    .config_data
    .get("wallet")
    .and_then(|w| w.get("log_level"))
    .and_then(|l| l.as_u64())
    .unwrap_or(1);
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
  let ch = match Command::new(&exe)
    .args(&args)
    .stdout(Stdio::null())
    .stderr(Stdio::null())
    .spawn()
  {
    Ok(c) => c,
    Err(e) => {
      eprintln!("[wallet] spawn: {e}");
      return;
    }
  };
  st.wallet_process = Some(ch);
  let client = WalletRpcClient::new(http, "127.0.0.1", rpc_port, user, pass);
  for _ in 0..60 {
    match client.call("get_languages", &Value::Null).await {
      Ok(r) if r.get("error").is_none() => {
        st.wallet = Some(client);
        eprintln!("[wallet] arqma-wallet-rpc: OK (get_languages)");
        return;
      }
      _ => {
        tokio::time::sleep(std::time::Duration::from_millis(200)).await;
      }
    }
  }
  eprintln!("[wallet] timeout — brak odpowiedzi get_languages (sprawdź katalog resource/bin i daemona)");
  st.wallet = None;
}
