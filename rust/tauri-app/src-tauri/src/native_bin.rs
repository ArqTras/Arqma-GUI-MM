//! Resolve `arqmad` / `arqma-wallet-rpc` in `resource/bin` (bundle) or locally in dev.
use std::path::PathBuf;
use tauri::AppHandle;
use tauri::Manager;

/// Path to a file under `.../resource/bin/`, or in dev `./bin` or `./binaries`.
pub fn find_resource_bin (app: &AppHandle, win: &str, unix: &str) -> Option<PathBuf> {
  if let Ok(res) = app.path().resource_dir() {
    let p = if cfg!(windows) {
      res.join("bin").join(win)
    } else {
      res.join("bin").join(unix)
    };
    if p.is_file() {
      return Some(p);
    }
  }
  if cfg!(debug_assertions) {
    for base in [PathBuf::from("bin"), PathBuf::from("binaries")] {
      let p = if cfg!(windows) { base.join(win) } else { base.join(unix) };
      if p.is_file() {
        return Some(p);
      }
    }
  }
  None
}
