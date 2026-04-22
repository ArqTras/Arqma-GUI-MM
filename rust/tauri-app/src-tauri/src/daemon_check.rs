//! Odpowiednik `Daemon.checkRemote` — `get_info` po HTTP (tryb zdalny / `local_remote`).
use crate::arqma_paths_config::daemon_rpc_host_port;
use crate::json_rpc_client::daemon_post;
use reqwest::Client;
use serde_json::Value;

/// Rozłączenie: przy `Inaccessible` backend może przełączyć `local_remote` → `local`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RemoteNodeIssue {
  Inaccessible,
  NetMismatch
}

/// Dla `type: local` zwraca Ok (Node nie weryfikuje RPC przed spawem).
/// Dla `remote` / `local_remote` — musi odpowiedzieć `get_info` i zgodna sieć.
pub async fn check_daemon_reachable (http: &Client, config: &Value) -> Result<(), RemoteNodeIssue> {
  let net = config
    .get("app")
    .and_then(|a| a.get("net_type"))
    .and_then(|n| n.as_str())
    .unwrap_or("mainnet");
  let d = config
    .get("daemons")
    .and_then(|d| d.get(net))
    .and_then(|x| x.as_object())
    .ok_or(RemoteNodeIssue::Inaccessible)?;
  let typ = d.get("type").and_then(|t| t.as_str()).unwrap_or("remote");
  if typ == "local" {
    return Ok(());
  }
  let Some((h, p)) = daemon_rpc_host_port(config) else {
    return Err(RemoteNodeIssue::Inaccessible);
  };
  let r = match daemon_post(http, &h, p, "get_info", 0, &Value::Null).await {
    Ok(v) => v,
    Err(_) => return Err(RemoteNodeIssue::Inaccessible)
  };
  if r.get("error").is_some() {
    return Err(RemoteNodeIssue::Inaccessible);
  }
  let res_net = r
    .pointer("/result/nettype")
    .or_else(|| r.pointer("/result/result/nettype"))
    .and_then(|v| v.as_str())
    .map(|s| s.to_lowercase());
  if let Some(nt) = res_net {
    let want = match net {
      "stagenet" => "stage",
      "testnet" => "test",
      _ => "main"
    };
    if !nt.contains(want) {
      return Err(RemoteNodeIssue::NetMismatch);
    }
  }
  Ok(())
}
