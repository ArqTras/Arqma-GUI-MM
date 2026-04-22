use serde_json::Value;
use std::path::PathBuf;

/// Public (or local) daemon RPC endpoint from `config_data.daemons[net]`.
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

/// `wallets` directory for the given network (like `this.dirs[type]/wallets` in `wallet-rpc.js`).
pub fn wallet_files_dir_for_net (config: &Value, net: &str) -> Option<PathBuf> {
  let wdata = config
    .get("app")?
    .get("wallet_data_dir")?
    .as_str()?;
  let sub = match net {
    "stagenet" => PathBuf::from(wdata).join("stagenet").join("wallets"),
    "testnet" => PathBuf::from(wdata).join("testnet").join("wallets"),
    _ => PathBuf::from(wdata).join("wallets")
  };
  Some(sub)
}

/// Wallet files directory — like `WalletRPC.wallet_dir` (from `app.net_type`).
pub fn wallet_files_dir (config: &Value) -> Option<PathBuf> {
  let net = config
    .get("app")?
    .get("net_type")?
    .as_str()?;
  wallet_files_dir_for_net(config, net)
}

/// Local `arqma-wallet-rpc` bind port from configuration.
pub fn wallet_rpc_bind_port (config: &Value) -> u16 {
  config
    .get("wallet")
    .and_then(|w| w.get("rpc_bind_port"))
    .and_then(|p| p.as_u64())
    .unwrap_or(9999) as u16
}

/// `arqmad` address in local mode (CLI version) — only for `check_version`.
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
