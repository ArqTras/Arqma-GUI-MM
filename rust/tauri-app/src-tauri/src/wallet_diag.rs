//! Optional diagnostics (`ARQMA_WALLET_LOG=1` / `yes` / `true` or inherited `ARQMA_SYNC_DEBUG`).
//! Printed on stderr — visible under `npm run tauri dev` or when launching exe from console.

use crate::sync_debug::is_sync_debug;

fn wallet_log_truthy_env (name: &str) -> bool {
  std::env::var(name)
    .map(|v| {
      matches!(
        v.trim().to_ascii_lowercase().as_str(),
        "1" | "true" | "yes" | "on"
      )
    })
    .unwrap_or(false)
}

pub fn diag_enabled () -> bool {
  is_sync_debug() || wallet_log_truthy_env("ARQMA_WALLET_LOG")
}

#[inline]
pub fn log (msg: impl std::fmt::Display) {
  if diag_enabled() {
    eprintln!("[arqma-wallet-diag] {msg}");
  }
}

/// High-signal line even when diagnostics are off — use sparingly (open / close / fatal xfer skip).
#[inline]
pub fn log_always (msg: impl std::fmt::Display) {
  eprintln!("[arqma-wallet] {msg}");
}
