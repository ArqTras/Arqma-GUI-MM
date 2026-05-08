use arqma_wallet_core::ArqmaPaths;
use crate::json_rpc_client::WalletRpcClient;
use serde::Serialize;
use serde_json::Value;
use std::sync::Arc;
use std::time::Instant;
use tokio::sync::oneshot;
use tokio::sync::OwnedSemaphorePermit;
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
  /// Shared handle to the HTTP digest JSON-RPC client (implements [`arqma_wallet_rpc::WalletJsonRpc`]).
  pub wallet: Option<Arc<WalletRpcClient>>,
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
  /// After `open_wallet`, force next heartbeat xfer when `new_h == h0` would otherwise skip `get_transfers`.
  pub wh_fetch_tx_pending: bool,
  /// Background `get_transfers` + address list (spawned from heartbeat) — detach on `stop` so shutdown
  /// does not abort mid-RPC; `wallet_rpc_lane` still serializes concurrent use of `arqma-wallet-rpc`.
  pub wh_xfer_task: Option<JoinHandle<()>>,
  /// Background periodic `store` (see `maybe_schedule_periodic_store`) — holds `wallet_rpc_lane` for
  /// the whole RPC; must be aborted before `close_wallet` acquires the lane or IPC can wedge.
  pub wh_periodic_store_task: Option<JoinHandle<()>>,
  /// During long rescans, throttle heavy RPC (balance, transfers) to avoid slowing the node-side
  /// block scan; set when a **heavy** heartbeat just ran (see `wallet_heartbeat` catch-up mode).
  pub wh_catchup_last_heavy: Option<Instant>,
  /// Consecutive LIGHT `getheight` failures (transport/timeouts/rpc.error). Increases sleep in
  /// `wallet_heartbeat::run` so we do not DDoS `arqma-wallet-rpc` when it cannot accept TCP fast enough.
  pub wh_light_rpc_pressure: u32,
  /// `close_wallet` path timed out on explicit `store`; graceful shutdown can skip duplicate `store`.
  pub close_store_timed_out: bool,
  /// Pending `relay_tx` payloads (sweep / transfer / stake).
  pub tx_metadata_list: Vec<WalletTxMetadata>,
  /// `getPoolsData` loop after height changes (like `begin_Stake_Acquisition`).
  pub stake_acquisition_task: Option<JoinHandle<()>>,
  /// Lightweight Solo Pool TCP server runtime.
  pub solo_pool_task: Option<JoinHandle<()>>,
  pub solo_pool_shutdown: Option<oneshot::Sender<()>>,
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
      wh_fetch_tx_pending: false,
      wh_xfer_task: None,
      wh_periodic_store_task: None,
      wh_catchup_last_heavy: None,
      wh_light_rpc_pressure: 0,
      close_store_timed_out: false,
      tx_metadata_list: Vec::new(),
      stake_acquisition_task: None,
      solo_pool_task: None,
      solo_pool_shutdown: None,
      next_rpc_id: 0
    }
  }
}

impl WalletBackendState {
  /// Stop heartbeats, exit `arqma-wallet-rpc` via RPC (`store` / `stop_wallet`), then local `arqmad` via
  /// `stop_daemon` RPC (fallback `stop`)
  /// and child wait/kill, clear wallet UI state.
  ///
  /// When shutting down wallet RPC, pass [`OwnedSemaphorePermit`] from [`crate::AppData::wallet_rpc_lane`]
  /// (see app `Exit` handler) so `store` / `stop_wallet` do not race heartbeat or background xfer.
  /// `save_config_init` passes [`Some`] (see `backend_send` lane-before-mutex for that method).
  /// Less critical paths may use `None` if concurrent wallet RPC is ruled out.
  pub async fn shutdown_subprocesses_async (
    &mut self,
    http: &reqwest::Client,
    rpc_lane_hold: Option<OwnedSemaphorePermit>,
  ) {
    // Hold optional `wallet_rpc_lane` permit until RPC shutdown + daemon stop complete.
    let _rpc_lane_scope = rpc_lane_hold;

    if let Some(h) = self.daemon_heartbeat.take() {
      h.abort();
    }
    if let Some(h) = self.stake_acquisition_task.take() {
      h.abort();
    }
    if let Some(tx) = self.solo_pool_shutdown.take() {
      let _ = tx.send(());
    }
    if let Some(h) = self.solo_pool_task.take() {
      h.abort();
    }
    if let Some(h) = self.wh_xfer_task.take() {
      h.abort();
    }
    if let Some(h) = self.wallet_heartbeat.take() {
      h.abort();
    }
    crate::wallet_process::graceful_shutdown_wallet_rpc(self).await;
    crate::daemon_process::shutdown_local_daemon_child(self, http).await;
    self.wallet_password_hash_hex = None;
    self.wh_display_name.clear();
    self.wh_stored_height = 0;
    self.wh_stored_balance = 0;
    self.wh_stored_unlocked = 0;
    self.wh_heartbeat_ext_pending = false;
    self.wh_fetch_tx_pending = false;
    self.wh_catchup_last_heavy = None;
    self.wh_light_rpc_pressure = 0;
    self.close_store_timed_out = false;
    self.tx_metadata_list.clear();
  }
}
