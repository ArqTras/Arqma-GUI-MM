use arqma_wallet_core::ArqmaPaths;
use crate::json_rpc_client::WalletRpcClient;
use serde_json::Value;

/// Stan odpowiadający `this.config_data` / `this.remotes` w `Backend` (Node).
pub struct WalletBackendState {
  pub paths: ArqmaPaths,
  pub config_data: Value,
  pub defaults: Value,
  pub remotes: Value,
  pub ethereum: Value,
  pub startup_seq_done: bool,
  /// Sól PBKDF2 (hex) do porównań haseł — jak `this.auth[2]` w `wallet-rpc.js`.
  pub wallet_salt: String,
  pub wallet: Option<WalletRpcClient>,
  pub wallet_process: Option<std::process::Child>,
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
      wallet: None,
      wallet_process: None,
      next_rpc_id: 0
    }
  }
}
