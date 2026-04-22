use arqma_wallet_core::ArqmaPaths;
use crate::json_rpc_client::WalletRpcClient;
use serde::Serialize;
use serde_json::Value;
use tokio::task::JoinHandle;

/// Metadata pending `relay_tx` (like `tx_metadata_list` in `wallet-rpc.js`).
#[derive(Debug, Clone, Serialize)]
pub struct WalletTxMetadata {
  pub tx_metadata: String,
  #[serde(skip_serializing_if = "Option::is_none")]
  pub tx_hash: Option<String>,
  /// `sweepAll` | `transfer_split` | `stake`
  pub kind: String,
  #[serde(default, skip_serializing_if = "String::is_empty")]
  pub note: String,
  #[serde(skip_serializing_if = "Option::is_none")]
  pub amount: Option<u64>,
  #[serde(skip_serializing_if = "Option::is_none")]
  pub service_node_key: Option<String>
}

/// Backend state matching `this.config_data` / `this.remotes` in Node `Backend`.
pub struct WalletBackendState {
  pub paths: ArqmaPaths,
  pub config_data: Value,
  pub defaults: Value,
  pub remotes: Value,
  pub ethereum: Value,
  pub startup_seq_done: bool,
  /// PBKDF2 salt (hex) for password checks — like `this.auth[2]` in `wallet-rpc.js`.
  pub wallet_salt: String,
  /// Password hash (128 hex chars), like `this.wallet_state.password_hash` in Node.
  pub wallet_password_hash_hex: Option<String>,
  pub wallet: Option<WalletRpcClient>,
  pub wallet_process: Option<std::process::Child>,
  /// Local `arqmad` child process (none when `type: remote`).
  pub daemon_process: Option<std::process::Child>,
  /// `get_info` heartbeat loop (cancelled on shutdown / exit).
  pub daemon_heartbeat: Option<JoinHandle<()>>,
  /// Last block height sent to UI from daemon heartbeat (avoid spamming).
  pub daemon_last_height: u64,
  /// Like `WalletRPC.heartbeat` — `getheight` + balance in background (forked RPC client).
  pub wallet_heartbeat: Option<JoinHandle<()>>,
  /// Open wallet display name (filename) for `set_wallet_info` / heartbeat.
  pub wh_display_name: String,
  pub wh_stored_height: u64,
  pub wh_stored_balance: u64,
  pub wh_stored_unlocked: u64,
  /// First extended tick (like `extended` in `heartbeatAction`, e.g. `get_address_book`).
  pub wh_heartbeat_ext_pending: bool,
  /// Pending `relay_tx` payloads (sweep / transfer / stake).
  pub tx_metadata_list: Vec<WalletTxMetadata>,
  /// `getPoolsData` loop after height changes (like `begin_Stake_Acquisition`).
  pub stake_acquisition_task: Option<JoinHandle<()>>,
  pub next_rpc_id: u64
}

impl Default for WalletBackendState {
  fn default () -> Self {
    let paths = arqma_wallet_core::default_paths();
    let defaults = arqma_wallet_core::build_defaults(&paths);
    let config_data = arqma_wallet_core::build_initial_config_data(&paths);
    let remotes = serde_json::json!([]);
    let ethereum = arqma_wallet_core::default_ethereum();
    Self {
      paths,
      config_data,
      defaults,
      remotes,
      ethereum,
      startup_seq_done: false,
      wallet_salt: String::new(),
      wallet_password_hash_hex: None,
      wallet: None,
      wallet_process: None,
      daemon_process: None,
      daemon_heartbeat: None,
      daemon_last_height: 0,
      wallet_heartbeat: None,
      wh_display_name: String::new(),
      wh_stored_height: 0,
      wh_stored_balance: 0,
      wh_stored_unlocked: 0,
      wh_heartbeat_ext_pending: false,
      tx_metadata_list: Vec::new(),
      stake_acquisition_task: None,
      next_rpc_id: 0
    }
  }
}

impl WalletBackendState {
  /// Stop heartbeats, exit `arqma-wallet-rpc` via RPC (`stop_wallet`), stop local daemon child, clear wallet UI state.
  pub async fn shutdown_subprocesses_async (&mut self) {
    if let Some(h) = self.daemon_heartbeat.take() {
      h.abort();
    }
    if let Some(h) = self.stake_acquisition_task.take() {
      h.abort();
    }
    if let Some(h) = self.wallet_heartbeat.take() {
      h.abort();
    }
    crate::wallet_process::graceful_shutdown_wallet_rpc(self).await;
    if let Some(mut ch) = self.daemon_process.take() {
      let _ = ch.kill();
      let _ = ch.wait();
    }
    self.wallet_password_hash_hex = None;
    self.wh_display_name.clear();
    self.wh_stored_height = 0;
    self.wh_stored_balance = 0;
    self.wh_stored_unlocked = 0;
    self.wh_heartbeat_ext_pending = false;
    self.tx_metadata_list.clear();
  }
}
