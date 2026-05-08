use async_trait::async_trait;
use serde_json::{json, Value};
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use arqma_wallet2_api::{NetworkKind, Wallet2OpenConfig, Wallet2Session};

use crate::error::WalletRpcError;
use crate::traits::WalletJsonRpc;

#[derive(Clone, Debug)]
pub struct Wallet2ApiConfig {
  pub wallet_dir: String,
  pub daemon_address: String,
  pub network: NetworkKind,
}

impl Wallet2ApiConfig {
  pub fn mainnet (wallet_dir: impl Into<String>, daemon_address: impl Into<String>) -> Self {
    Self {
      wallet_dir: wallet_dir.into(),
      daemon_address: daemon_address.into(),
      network: NetworkKind::Mainnet,
    }
  }
}

/// Minimal JSON-RPC compatibility adapter over native `wallet2_api` session.
///
/// Current scope intentionally covers the methods used by close/open/heartbeat:
/// - `getheight`
/// - `getbalance`
/// - `store`
/// - `close_wallet`
///
/// Other methods return transport error until fully mapped.
#[derive(Clone)]
pub struct Wallet2ApiClient {
  cfg: Arc<Wallet2ApiConfig>,
  inner: Arc<Mutex<Option<Wallet2Session>>>,
}

impl Wallet2ApiClient {
  pub fn new (cfg: Wallet2ApiConfig) -> Self {
    Self {
      cfg: Arc::new(cfg),
      inner: Arc::new(Mutex::new(None)),
    }
  }

  pub fn fork_for_heartbeat (&self) -> Self {
    self.clone()
  }

  pub fn split_session (&self) -> Self {
    self.clone()
  }

  pub async fn call_json (&self, method: &str, _params: &Value) -> Result<Value, WalletRpcError> {
    let mut g = self
      .inner
      .lock()
      .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
    match method {
      "open_wallet" => {
        let filename = _params
          .get("filename")
          .or_else(|| _params.get("name"))
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 open_wallet: missing filename".to_string()))?;
        let password = _params
          .get("password")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 open_wallet: missing password".to_string()))?;
        let path = resolve_wallet_path(&self.cfg.wallet_dir, filename);
        let session = Wallet2Session::open(&Wallet2OpenConfig {
          wallet_path: path,
          password: password.to_string(),
          daemon_address: self.cfg.daemon_address.clone(),
          network: self.cfg.network.clone(),
        })
        .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        *g = Some(session);
        Ok(json!({ "result": {} }))
      }
      "create_wallet" => {
        let filename = _params
          .get("filename")
          .or_else(|| _params.get("name"))
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 create_wallet: missing filename".to_string()))?;
        let password = _params
          .get("password")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 create_wallet: missing password".to_string()))?;
        let language = _params
          .get("language")
          .and_then(|v| v.as_str())
          .unwrap_or("English");
        let path = resolve_wallet_path(&self.cfg.wallet_dir, filename);
        let mut session = match g.take() {
          Some(s) => s,
          None => Wallet2Session::open(&Wallet2OpenConfig {
            wallet_path: path.clone(),
            password: password.to_string(),
            daemon_address: self.cfg.daemon_address.clone(),
            network: self.cfg.network.clone(),
          })
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?,
        };
        session
          .create_wallet(
            &path,
            password,
            language,
            &self.cfg.network,
            &self.cfg.daemon_address,
          )
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        *g = Some(session);
        Ok(json!({ "result": {} }))
      }
      "restore_deterministic_wallet" => {
        let filename = _params
          .get("filename")
          .or_else(|| _params.get("name"))
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 restore_deterministic_wallet: missing filename".to_string()))?;
        let password = _params
          .get("password")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 restore_deterministic_wallet: missing password".to_string()))?;
        let seed = _params
          .get("seed")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 restore_deterministic_wallet: missing seed".to_string()))?;
        let restore_height = _params
          .get("restore_height")
          .and_then(|v| v.as_u64())
          .unwrap_or(0);
        let path = resolve_wallet_path(&self.cfg.wallet_dir, filename);
        let mut session = match g.take() {
          Some(s) => s,
          None => Wallet2Session::open(&Wallet2OpenConfig {
            wallet_path: path.clone(),
            password: password.to_string(),
            daemon_address: self.cfg.daemon_address.clone(),
            network: self.cfg.network.clone(),
          })
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?,
        };
        session
          .restore_deterministic_wallet(
            &path,
            password,
            seed,
            restore_height,
            &self.cfg.network,
            &self.cfg.daemon_address,
          )
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        *g = Some(session);
        Ok(json!({ "result": {} }))
      }
      "generate_from_keys" => {
        let filename = _params
          .get("filename")
          .or_else(|| _params.get("name"))
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 generate_from_keys: missing filename".to_string()))?;
        let password = _params
          .get("password")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 generate_from_keys: missing password".to_string()))?;
        let address = _params
          .get("address")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 generate_from_keys: missing address".to_string()))?;
        let view_key = _params
          .get("viewkey")
          .or_else(|| _params.get("view_key"))
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 generate_from_keys: missing viewkey".to_string()))?;
        let spend_key = _params
          .get("spendkey")
          .or_else(|| _params.get("spend_key"))
          .and_then(|v| v.as_str())
          .unwrap_or("");
        let restore_height = _params
          .get("restore_height")
          .or_else(|| _params.get("refresh_start_height"))
          .and_then(|v| v.as_u64())
          .unwrap_or(0);
        let language = _params
          .get("language")
          .and_then(|v| v.as_str())
          .unwrap_or("English");
        let path = resolve_wallet_path(&self.cfg.wallet_dir, filename);
        let mut session = match g.take() {
          Some(s) => s,
          None => Wallet2Session::open(&Wallet2OpenConfig {
            wallet_path: path.clone(),
            password: password.to_string(),
            daemon_address: self.cfg.daemon_address.clone(),
            network: self.cfg.network.clone(),
          })
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?,
        };
        session
          .generate_from_keys(
            &path,
            password,
            language,
            restore_height,
            address,
            view_key,
            spend_key,
            &self.cfg.network,
            &self.cfg.daemon_address,
          )
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        *g = Some(session);
        Ok(json!({ "result": {} }))
      }
      "getheight" => {
        let s = g
          .as_ref()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let h = s
          .height()
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        Ok(json!({ "result": { "height": h } }))
      }
      "get_address" => {
        let s = g
          .as_ref()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let addr = s
          .address()
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        Ok(json!({ "result": { "address": addr } }))
      }
      "getbalance" => {
        let s = g
          .as_ref()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let b = s
          .balance()
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        Ok(json!({ "result": { "balance": b.balance, "unlocked_balance": b.unlocked_balance } }))
      }
      "query_key" => {
        let key_type = _params
          .get("key_type")
          .and_then(|v| v.as_str())
          .unwrap_or("");
        let s = g
          .as_ref()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let key = match key_type {
          "mnemonic" => s.seed(),
          "spend_key" => s.secret_spend_key(),
          "view_key" => s.secret_view_key(),
          other => {
            return Ok(json!({
              "error": {
                "code": -32001,
                "message": format!("wallet2 backend: query_key `{other}` not implemented")
              }
            }));
          }
        }
        .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        Ok(json!({ "result": { "key": key } }))
      }
      "get_address_book" => {
        let s = g
          .as_ref()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let raw = s
          .get_address_book_json()
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        let parsed = serde_json::from_str::<Value>(&raw)
          .unwrap_or_else(|_| json!({ "entries": [] }));
        Ok(json!({ "result": parsed }))
      }
      "add_address_book" => {
        let address = _params
          .get("address")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 add_address_book: missing address".to_string()))?;
        let payment_id = _params
          .get("payment_id")
          .and_then(|v| v.as_str())
          .unwrap_or("");
        let description = _params
          .get("description")
          .and_then(|v| v.as_str())
          .unwrap_or("");
        let s = g
          .as_mut()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let ok = s
          .add_address_book(address, payment_id, description)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        if ok {
          Ok(json!({ "result": {} }))
        } else {
          Ok(unsupported(method))
        }
      }
      "delete_address_book" => {
        let idx = _params
          .get("index")
          .and_then(|v| v.as_u64())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 delete_address_book: missing index".to_string()))?;
        let s = g
          .as_mut()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let ok = s
          .delete_address_book(idx)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        if ok {
          Ok(json!({ "result": {} }))
        } else {
          Ok(unsupported(method))
        }
      }
      "set_tx_notes" => {
        let txid = _params
          .get("txids")
          .and_then(|v| v.as_array())
          .and_then(|a| a.first())
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 set_tx_notes: missing txid".to_string()))?;
        let note = _params
          .get("notes")
          .and_then(|v| v.as_array())
          .and_then(|a| a.first())
          .and_then(|v| v.as_str())
          .unwrap_or("");
        let s = g
          .as_mut()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let ok = s
          .set_tx_note(txid, note)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        if ok {
          Ok(json!({ "result": {} }))
        } else {
          Ok(unsupported(method))
        }
      }
      "get_transfer_by_txid" => {
        let txid = _params
          .get("txid")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 get_transfer_by_txid: missing txid".to_string()))?;
        let s = g
          .as_ref()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let raw = s
          .get_transfer_by_txid_json(txid)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        let transfer = serde_json::from_str::<Value>(&raw).unwrap_or_else(|_| json!({}));
        Ok(json!({ "result": { "transfer": transfer } }))
      }
      "change_wallet_password" => {
        let new_password = _params
          .get("new_password")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 change_wallet_password: missing new_password".to_string()))?;
        let s = g
          .as_mut()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let ok = s
          .set_password(new_password)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        if ok {
          Ok(json!({ "result": {} }))
        } else {
          Ok(unsupported(method))
        }
      }
      "export_key_images" => {
        let filename = _params
          .get("filename")
          .and_then(|v| v.as_str())
          .unwrap_or("key_image_export");
        let s = g
          .as_ref()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let ok = s
          .export_key_images(filename)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        if ok {
          Ok(json!({ "result": { "signed_key_images": [] } }))
        } else {
          Ok(unsupported(method))
        }
      }
      "import_key_images" => {
        let signed = _params
          .get("signed_key_images")
          .ok_or_else(|| WalletRpcError::Transport("wallet2 import_key_images: missing signed_key_images".to_string()))?;
        let s = g
          .as_ref()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let now = SystemTime::now()
          .duration_since(UNIX_EPOCH)
          .map(|d| d.as_millis())
          .unwrap_or(0);
        let tmp_file = std::env::temp_dir().join(format!("arqma-wallet2-keyimages-{now}.json"));
        let body = serde_json::to_string(signed)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        fs::write(&tmp_file, body).map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        let import_res = s
          .import_key_images(&tmp_file.to_string_lossy())
          .map_err(|e| WalletRpcError::Transport(e.to_string()));
        let _ = fs::remove_file(&tmp_file);
        let ok = import_res?;
        if ok {
          Ok(json!({ "result": {} }))
        } else {
          Ok(unsupported(method))
        }
      }
      "rescan_blockchain" => {
        let s = g
          .as_mut()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let ok = s
          .rescan_blockchain()
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        if ok {
          Ok(json!({ "result": {} }))
        } else {
          Ok(unsupported(method))
        }
      }
      "rescan_spent" => {
        let s = g
          .as_mut()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let ok = s
          .rescan_spent()
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        if ok {
          Ok(json!({ "result": {} }))
        } else {
          Ok(unsupported(method))
        }
      }
      "stake" => {
        let service_node_key = _params
          .get("service_node_key")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 stake: missing service_node_key".to_string()))?;
        let amount_atoms = _params
          .get("amount")
          .and_then(|v| v.as_u64().or_else(|| v.as_i64().filter(|i| *i >= 0).map(|i| i as u64)))
          .ok_or_else(|| WalletRpcError::Transport("wallet2 stake: missing amount".to_string()))?;
        let s = g
          .as_mut()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let raw = s
          .stake_prepare_json(service_node_key, &amount_atoms.to_string())
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        let parsed = serde_json::from_str::<Value>(&raw)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        Ok(json!({ "result": parsed }))
      }
      "sweep_all" => {
        let address = _params
          .get("address")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 sweep_all: missing address".to_string()))?;
        let do_not_relay = _params
          .get("do_not_relay")
          .and_then(|v| v.as_bool())
          .unwrap_or(false);
        let s = g
          .as_mut()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let raw = s
          .sweep_all_prepare_json(address, do_not_relay)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        let parsed = serde_json::from_str::<Value>(&raw)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        Ok(json!({ "result": parsed }))
      }
      "relay_tx" => {
        let hex = _params
          .get("hex")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 relay_tx: missing hex".to_string()))?;
        let s = g
          .as_mut()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let raw = s
          .relay_tx_json(hex)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        let parsed = serde_json::from_str::<Value>(&raw)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        Ok(json!({ "result": parsed }))
      }
      "can_request_stake_unlock" => {
        let service_node_key = _params
          .get("service_node_key")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 can_request_stake_unlock: missing service_node_key".to_string()))?;
        let s = g
          .as_mut()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let raw = s
          .can_request_stake_unlock_json(service_node_key)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        let parsed = serde_json::from_str::<Value>(&raw)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        Ok(json!({ "result": parsed }))
      }
      "request_stake_unlock" => {
        let service_node_key = _params
          .get("service_node_key")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 request_stake_unlock: missing service_node_key".to_string()))?;
        let s = g
          .as_mut()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let raw = s
          .request_stake_unlock_json(service_node_key)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        let parsed = serde_json::from_str::<Value>(&raw)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        Ok(json!({ "result": parsed }))
      }
      "get_accounts" => {
        let account_tag = _params
          .get("tag")
          .or_else(|| _params.get("account_tag"))
          .and_then(|v| v.as_u64())
          .unwrap_or(0) as u32;
        let s = g
          .as_ref()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let raw = s
          .get_accounts_json(account_tag)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        let parsed = serde_json::from_str::<Value>(&raw)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        Ok(json!({ "result": parsed }))
      }
      "create_address" => {
        let account_index = _params
          .get("account_index")
          .and_then(|v| v.as_u64())
          .unwrap_or(0) as u32;
        let label = _params
          .get("label")
          .and_then(|v| v.as_str())
          .unwrap_or("");
        let s = g
          .as_mut()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let raw = s
          .create_address_json(account_index, label)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        let parsed = serde_json::from_str::<Value>(&raw)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        Ok(json!({ "result": parsed }))
      }
      "validate_address" => {
        let address = _params
          .get("address")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 validate_address: missing address".to_string()))?;
        let any_net_type = _params
          .get("any_net_type")
          .and_then(|v| v.as_bool())
          .unwrap_or(false);
        let allow_openalias = _params
          .get("allow_openalias")
          .and_then(|v| v.as_bool())
          .unwrap_or(false);
        let s = g
          .as_ref()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let raw = s
          .validate_address_json(address, any_net_type, allow_openalias)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        let parsed = serde_json::from_str::<Value>(&raw)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        Ok(json!({ "result": parsed }))
      }
      "register_service_node" => {
        let register_service_node_str = _params
          .get("register_service_node_str")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 register_service_node: missing register_service_node_str".to_string()))?;
        let s = g
          .as_mut()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let _ = s
          .register_service_node_json(register_service_node_str)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        Ok(json!({ "result": {} }))
      }
      "transfer_split" => {
        let dst = _params
          .get("destinations")
          .and_then(|v| v.as_array())
          .and_then(|a| a.first())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 transfer_split: missing destinations".to_string()))?;
        let address = dst
          .get("address")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 transfer_split: missing destination.address".to_string()))?;
        let amount = dst
          .get("amount")
          .and_then(|v| v.as_u64().or_else(|| v.as_i64().filter(|i| *i >= 0).map(|i| i as u64)))
          .ok_or_else(|| WalletRpcError::Transport("wallet2 transfer_split: missing destination.amount".to_string()))?;
        let priority = _params
          .get("priority")
          .and_then(|v| v.as_u64().or_else(|| v.as_i64().filter(|i| *i >= 0).map(|i| i as u64)))
          .unwrap_or(0) as u32;
        let do_not_relay = _params
          .get("do_not_relay")
          .and_then(|v| v.as_bool())
          .unwrap_or(false);
        let s = g
          .as_mut()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let raw = s
          .transfer_split_prepare_json(address, amount, priority, do_not_relay)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        let parsed = serde_json::from_str::<Value>(&raw)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        Ok(json!({ "result": parsed }))
      }
      "transfer" => {
        // Compatibility alias: UI and legacy code paths may still call `transfer`.
        let dst = _params
          .get("destinations")
          .and_then(|v| v.as_array())
          .and_then(|a| a.first())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 transfer: missing destinations".to_string()))?;
        let address = dst
          .get("address")
          .and_then(|v| v.as_str())
          .ok_or_else(|| WalletRpcError::Transport("wallet2 transfer: missing destination.address".to_string()))?;
        let amount = dst
          .get("amount")
          .and_then(|v| v.as_u64().or_else(|| v.as_i64().filter(|i| *i >= 0).map(|i| i as u64)))
          .ok_or_else(|| WalletRpcError::Transport("wallet2 transfer: missing destination.amount".to_string()))?;
        let priority = _params
          .get("priority")
          .and_then(|v| v.as_u64().or_else(|| v.as_i64().filter(|i| *i >= 0).map(|i| i as u64)))
          .unwrap_or(0) as u32;
        let do_not_relay = _params
          .get("do_not_relay")
          .and_then(|v| v.as_bool())
          .unwrap_or(false);
        let s = g
          .as_mut()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let raw = s
          .transfer_split_prepare_json(address, amount, priority, do_not_relay)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        let parsed = serde_json::from_str::<Value>(&raw)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        Ok(json!({ "result": parsed }))
      }
      "get_transfers" => {
        let in_flag = _params.get("in").and_then(|v| v.as_bool()).unwrap_or(false);
        let out_flag = _params.get("out").and_then(|v| v.as_bool()).unwrap_or(false);
        let pending_flag = _params.get("pending").and_then(|v| v.as_bool()).unwrap_or(false);
        let failed_flag = _params.get("failed").and_then(|v| v.as_bool()).unwrap_or(false);
        let pool_flag = _params.get("pool").and_then(|v| v.as_bool()).unwrap_or(false);
        let min_height = _params.get("min_height").and_then(|v| v.as_u64()).unwrap_or(0);
        let max_height = _params.get("max_height").and_then(|v| v.as_u64()).unwrap_or(u64::MAX);
        let s = g
          .as_ref()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        let raw = s
          .get_transfers_json(
            in_flag,
            out_flag,
            pending_flag,
            failed_flag,
            pool_flag,
            min_height,
            max_height,
          )
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        let parsed = serde_json::from_str::<Value>(&raw)
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        Ok(json!({ "result": parsed }))
      }
      "get_languages" => Ok(json!({ "result": { "languages": ["English"] } })),
      "store" => {
        let s = g
          .as_mut()
          .ok_or_else(|| WalletRpcError::Transport("wallet2: no wallet session".to_string()))?;
        s.store()
          .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        Ok(json!({ "result": {} }))
      }
      "close_wallet" | "stop_wallet" => {
        if let Some(s) = g.as_mut() {
          s.close()
            .map_err(|e| WalletRpcError::Transport(e.to_string()))?;
        }
        *g = None;
        Ok(json!({ "result": {} }))
      }
      _ => Ok(unsupported(method)),
    }
  }
}

fn resolve_wallet_path (wallet_dir: &str, filename: &str) -> String {
  let p = Path::new(filename);
  if p.is_absolute() {
    return filename.to_string();
  }
  PathBuf::from(wallet_dir)
    .join(filename)
    .to_string_lossy()
    .to_string()
}

fn unsupported (method: &str) -> Value {
  json!({
    "error": {
      "code": -32001,
      "message": format!("wallet2 backend: method `{method}` is not implemented yet")
    }
  })
}

#[async_trait]
impl WalletJsonRpc for Wallet2ApiClient {
  async fn call (&self, method: &str, params: &Value) -> Result<Value, WalletRpcError> {
    self.call_json(method, params).await
  }
}
