//! Arqma wallet RPC integration for the desktop GUI.
//!
//! Upstream wallet logic lives in C++ (`github.com/arqma/arqma`, e.g. `src/wallet/wallet_rpc_server.cpp`).
//! This crate defines the **contract** the Tauri shell should use so we can swap:
//! - today: subprocess `arqma-wallet-rpc` + HTTP digest ([`WalletRpcClient`] with feature **`http-digest`**),
//! - later: linked native code (FFI) or another transport.
//!
//! See repository root `docs/WALLET_RUST_PORT.md`.

mod error;
mod traits;
mod upstream_paths;

#[cfg(feature = "http-digest")]
mod http_digest;
mod unified_client;
mod wallet2_client;
#[cfg(feature = "http-digest")]
mod wallet_http_client;

pub use error::WalletRpcError;
pub use traits::WalletJsonRpc;
pub use upstream_paths::{
    find_in_path, resolve_arqma_executable, resolve_daemon_path, resolve_wallet_rpc_path,
    ArqmaExecutableKind,
};

pub use arqma_wallet2_api::NetworkKind;
pub use unified_client::WalletClient;
pub use wallet2_client::{Wallet2ApiClient, Wallet2ApiConfig};
#[cfg(feature = "http-digest")]
pub use wallet_http_client::WalletRpcClient;
