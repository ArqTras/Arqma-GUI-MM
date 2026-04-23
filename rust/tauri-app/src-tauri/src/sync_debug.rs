//! Extra diagnostics for wallet/daemon sync issues.
//!
//! Enable verbose traces: set environment variable **`ARQMA_SYNC_DEBUG=1`** (also `true`, `yes`, `on`)
//! before starting the app. Logs go to **stderr** (visible in `tauri dev` terminal or when launching
//! `Arqma Wallet.exe` from a console on Windows).

/// `true` when `ARQMA_SYNC_DEBUG` is set to a truthy value (case-insensitive).
pub fn is_sync_debug () -> bool {
  std::env::var("ARQMA_SYNC_DEBUG")
    .map(|v| {
      let s = v.trim().to_ascii_lowercase();
      matches!(s.as_str(), "1" | "true" | "yes" | "on")
    })
    .unwrap_or(false)
}
