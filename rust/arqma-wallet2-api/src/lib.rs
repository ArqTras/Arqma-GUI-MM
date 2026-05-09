use serde::{Deserialize, Serialize};
use thiserror::Error;

// Whole-archive + bundle: macOS / Linux cdylib need it so static archive members are not dropped.
// windows-gnu: `+whole-archive` without `+bundle` (PE). RandomX needs full archive for JitCompilerX86.
// Do not also emit `rustc-link-lib=static=wallet_merged` from build.rs — rustc forbids mixing that
// with these #[link] modifiers ("overriding linking modifiers from command line").
// windows-gnu: `randomx` is not listed here — final `cdylib` link pulls `librandomx.a` with
// `-Wl,--whole-archive` from `rust/tauri-app/src-tauri/build.rs` so `JitCompilerX86` survives ld.
#[cfg(all(
  feature = "native-wallet2",
  not(all(target_os = "windows", target_env = "gnu"))
))]
mod force_wallet_static {
  #![allow(dead_code)]
  #[link(name = "wallet_merged", kind = "static", modifiers = "+bundle,+whole-archive")]
  extern "C" {}
  #[link(name = "epee", kind = "static", modifiers = "+bundle,+whole-archive")]
  extern "C" {}
  #[link(name = "easylogging", kind = "static", modifiers = "+bundle,+whole-archive")]
  extern "C" {}
  #[link(name = "randomx", kind = "static", modifiers = "+bundle,+whole-archive")]
  extern "C" {}
  #[link(name = "lmdb", kind = "static", modifiers = "+bundle,+whole-archive")]
  extern "C" {}
  #[link(
    name = "cryptonote_format_utils_basic",
    kind = "static",
    modifiers = "+bundle,+whole-archive"
  )]
  extern "C" {}
}

#[cfg(all(feature = "native-wallet2", target_os = "windows", target_env = "gnu"))]
mod force_wallet_static {
  #![allow(dead_code)]
  #[link(name = "wallet_merged", kind = "static", modifiers = "+whole-archive")]
  extern "C" {}
  #[link(name = "epee", kind = "static", modifiers = "+whole-archive")]
  extern "C" {}
  #[link(name = "easylogging", kind = "static", modifiers = "+whole-archive")]
  extern "C" {}
  #[link(name = "lmdb", kind = "static", modifiers = "+whole-archive")]
  extern "C" {}
  #[link(
    name = "cryptonote_format_utils_basic",
    kind = "static",
    modifiers = "+whole-archive"
  )]
  extern "C" {}
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum NetworkKind {
  Mainnet,
  Testnet,
  Stagenet,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Wallet2OpenConfig {
  pub wallet_path: String,
  pub password: String,
  pub daemon_address: String,
  pub network: NetworkKind,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Wallet2Balance {
  pub balance: u64,
  pub unlocked_balance: u64,
}

#[derive(Debug, Error)]
pub enum Wallet2Error {
  #[error("wallet2 native backend disabled (built with stub-wallet2 or without native-wallet2 — use default Cargo features and an Arqma core checkout; see rust/docs/NATIVE_WALLET2.md)")]
  NativeBackendDisabled,
  #[error("wallet2 operation failed: {0}")]
  OperationFailed(String),
}

pub type Wallet2Result<T> = Result<T, Wallet2Error>;

pub struct Wallet2Session {
  #[cfg(feature = "native-wallet2")]
  inner: native::NativeWallet2Session,
}

impl Wallet2Session {
  pub fn open (_cfg: &Wallet2OpenConfig) -> Wallet2Result<Self> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      let inner = native::NativeWallet2Session::open(_cfg)?;
      Ok(Self { inner })
    }
  }

  pub fn store (&mut self) -> Wallet2Result<()> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.store()
    }
  }

  pub fn close (&mut self) -> Wallet2Result<()> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.close()
    }
  }

  pub fn height (&self) -> Wallet2Result<u64> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.height()
    }
  }

  pub fn balance (&self) -> Wallet2Result<Wallet2Balance> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.balance()
    }
  }

  pub fn address (&self) -> Wallet2Result<String> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.address()
    }
  }

  pub fn seed (&self) -> Wallet2Result<String> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.seed()
    }
  }

  pub fn secret_spend_key (&self) -> Wallet2Result<String> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.secret_spend_key()
    }
  }

  pub fn secret_view_key (&self) -> Wallet2Result<String> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.secret_view_key()
    }
  }

  pub fn set_password (&mut self, new_password: &str) -> Wallet2Result<bool> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let _ = new_password;
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.set_password(new_password)
    }
  }

  pub fn set_tx_note (&mut self, txid: &str, note: &str) -> Wallet2Result<bool> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let (_a, _b) = (txid, note);
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.set_tx_note(txid, note)
    }
  }

  pub fn export_key_images (&self, filename: &str) -> Wallet2Result<bool> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let _ = filename;
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.export_key_images(filename)
    }
  }

  pub fn add_address_book (&mut self, address: &str, payment_id: &str, description: &str) -> Wallet2Result<bool> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let (_a, _b, _c) = (address, payment_id, description);
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.add_address_book(address, payment_id, description)
    }
  }

  pub fn delete_address_book (&mut self, row_id: u64) -> Wallet2Result<bool> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let _ = row_id;
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.delete_address_book(row_id)
    }
  }

  pub fn get_address_book_json (&self) -> Wallet2Result<String> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.get_address_book_json()
    }
  }

  pub fn get_transfer_by_txid_json (&self, txid: &str) -> Wallet2Result<String> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let _ = txid;
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.get_transfer_by_txid_json(txid)
    }
  }

  pub fn restore_deterministic_wallet (
    &mut self,
    path: &str,
    password: &str,
    seed: &str,
    restore_height: u64,
    network: &NetworkKind,
    daemon: &str,
  ) -> Wallet2Result<()> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let (_a, _b, _c, _d, _e, _f) = (path, password, seed, restore_height, network, daemon);
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self
        .inner
        .restore_deterministic_wallet(path, password, seed, restore_height, network, daemon)
    }
  }

  pub fn generate_from_keys (
    &mut self,
    path: &str,
    password: &str,
    language: &str,
    restore_height: u64,
    address: &str,
    view_key: &str,
    spend_key: &str,
    network: &NetworkKind,
    daemon: &str,
  ) -> Wallet2Result<()> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let (_a, _b, _c, _d, _e, _f, _g, _h, _i) = (
        path,
        password,
        language,
        restore_height,
        address,
        view_key,
        spend_key,
        network,
        daemon,
      );
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.generate_from_keys(
        path,
        password,
        language,
        restore_height,
        address,
        view_key,
        spend_key,
        network,
        daemon,
      )
    }
  }

  pub fn create_wallet (
    &mut self,
    path: &str,
    password: &str,
    language: &str,
    network: &NetworkKind,
    daemon: &str,
  ) -> Wallet2Result<()> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let (_a, _b, _c, _d, _e) = (path, password, language, network, daemon);
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.create_wallet(path, password, language, network, daemon)
    }
  }

  pub fn rescan_blockchain (&mut self) -> Wallet2Result<bool> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.rescan_blockchain()
    }
  }

  pub fn rescan_spent (&mut self) -> Wallet2Result<bool> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.rescan_spent()
    }
  }

  pub fn import_key_images (&self, filename: &str) -> Wallet2Result<bool> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let _ = filename;
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.import_key_images(filename)
    }
  }

  pub fn stake_prepare_json (&mut self, service_node_key: &str, amount: &str) -> Wallet2Result<String> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let (_a, _b) = (service_node_key, amount);
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.stake_prepare_json(service_node_key, amount)
    }
  }

  pub fn sweep_all_prepare_json (&mut self, address: &str, do_not_relay: bool) -> Wallet2Result<String> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let (_a, _b) = (address, do_not_relay);
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.sweep_all_prepare_json(address, do_not_relay)
    }
  }

  pub fn relay_tx_json (&mut self, metadata_hex: &str) -> Wallet2Result<String> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let _ = metadata_hex;
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.relay_tx_json(metadata_hex)
    }
  }

  pub fn get_accounts_json (&self, account_tag: u32) -> Wallet2Result<String> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let _ = account_tag;
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.get_accounts_json(account_tag)
    }
  }

  pub fn create_address_json (&mut self, account_index: u32, label: &str) -> Wallet2Result<String> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let (_a, _b) = (account_index, label);
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.create_address_json(account_index, label)
    }
  }

  pub fn validate_address_json (&self, address: &str, any_net_type: bool, allow_openalias: bool) -> Wallet2Result<String> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let (_a, _b, _c) = (address, any_net_type, allow_openalias);
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.validate_address_json(address, any_net_type, allow_openalias)
    }
  }

  pub fn transfer_split_prepare_json (
    &mut self,
    address: &str,
    amount: u64,
    priority: u32,
    do_not_relay: bool,
  ) -> Wallet2Result<String> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let (_a, _b, _c, _d) = (address, amount, priority, do_not_relay);
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self
        .inner
        .transfer_split_prepare_json(address, amount, priority, do_not_relay)
    }
  }

  #[allow(clippy::too_many_arguments)]
  pub fn get_transfers_json (
    &self,
    in_flag: bool,
    out_flag: bool,
    pending_flag: bool,
    failed_flag: bool,
    pool_flag: bool,
    min_height: u64,
    max_height: u64,
  ) -> Wallet2Result<String> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let (_a, _b, _c, _d, _e, _f, _g) = (
        in_flag,
        out_flag,
        pending_flag,
        failed_flag,
        pool_flag,
        min_height,
        max_height,
      );
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.get_transfers_json(
        in_flag,
        out_flag,
        pending_flag,
        failed_flag,
        pool_flag,
        min_height,
        max_height,
      )
    }
  }

  pub fn register_service_node_json (&mut self, register_service_node_str: &str) -> Wallet2Result<String> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let _ = register_service_node_str;
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.register_service_node_json(register_service_node_str)
    }
  }

  pub fn can_request_stake_unlock_json (&mut self, service_node_key: &str) -> Wallet2Result<String> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let _ = service_node_key;
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.can_request_stake_unlock_json(service_node_key)
    }
  }

  pub fn request_stake_unlock_json (&mut self, service_node_key: &str) -> Wallet2Result<String> {
    #[cfg(not(feature = "native-wallet2"))]
    {
      let _ = service_node_key;
      return Err(Wallet2Error::NativeBackendDisabled);
    }
    #[cfg(feature = "native-wallet2")]
    {
      self.inner.request_stake_unlock_json(service_node_key)
    }
  }
}

#[cfg(feature = "native-wallet2")]
mod native;
