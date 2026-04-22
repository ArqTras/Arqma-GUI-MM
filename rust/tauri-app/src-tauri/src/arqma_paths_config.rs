use serde_json::Value;
use std::path::PathBuf;

/// Adres publicznego (lub lokalnego) daemona z `config_data.daemons[net]`.
pub fn daemon_rpc_host_port (config: &Value) -> Option<(String, u16)> {
  let a = config
    .get("app")?
    .get("net_type")?
    .as_str()?;
  let d = config
    .get("daemons")?
    .get(a)?
    .as_object()?;
  let typ = d.get("type")?.as_str()?;
  if typ == "remote" {
    let h = d.get("remote_host")?.as_str()?.to_string();
    let p = d.get("remote_port")?.as_u64()? as u16;
    return Some((h, p));
  }
  let h = d.get("rpc_bind_ip")?.as_str()?.to_string();
  let p = d.get("rpc_bind_port")?.as_u64()? as u16;
  Some((h, p))
}

/// Katalog plików portfela — jak `WalletRPC.wallet_dir` (mainnet: `.../wallets`).
pub fn wallet_files_dir (config: &Value) -> Option<PathBuf> {
  let wdata = config
    .get("app")?
    .get("wallet_data_dir")?
    .as_str()?;
  let net = config
    .get("app")?
    .get("net_type")?
    .as_str()?;
  let sub = match net {
    "stagenet" => PathBuf::from(wdata).join("stagenet").join("wallets"),
    "testnet" => PathBuf::from(wdata).join("testnet").join("wallets"),
    _ => PathBuf::from(wdata).join("wallets")
  };
  Some(sub)
}

/// Port lokalnego `arqma-wallet-rpc` w konfiguracji.
pub fn wallet_rpc_bind_port (config: &Value) -> u16 {
  config
    .get("wallet")
    .and_then(|w| w.get("rpc_bind_port"))
    .and_then(|p| p.as_u64())
    .unwrap_or(9999) as u16
}

/// Adres `arqmad` w trybie lokalnym (dla wersji z linii komend) — tylko `check_version`.
#[allow(dead_code)]
pub fn local_daemon_addr (config: &Value) -> Option<(String, u16)> {
  let a = config
    .get("app")?
    .get("net_type")?
    .as_str()?;
  let d = config
    .get("daemons")?
    .get(a)?
    .as_object()?;
  let h = d.get("rpc_bind_ip")?.as_str()?.to_string();
  let p = d.get("rpc_bind_port")?.as_u64()? as u16;
  Some((h, p))
}
