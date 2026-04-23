//! Resolve `arqmad` / `arqma-wallet-rpc` in `resource/bin` (bundle) or locally in dev.
use std::path::PathBuf;
use tauri::AppHandle;
use tauri::Manager;

/// Path to a file under `.../resource/bin/`, or in dev `./bin` or `./binaries`.
pub fn find_resource_bin (app: &AppHandle, win: &str, unix: &str) -> Option<PathBuf> {
  let name = if cfg!(windows) { win } else { unix };
  if let Ok(res) = app.path().resource_dir() {
    let p = res.join("bin").join(name);
    if p.is_file() {
      return Some(p);
    }
  }

  // Fallbacks for running unpackaged release binary directly (e.g. target/release/*.exe).
  let mut candidates: Vec<PathBuf> = vec![PathBuf::from("bin").join(name), PathBuf::from("binaries").join(name)];
  if let Ok(exe) = std::env::current_exe() {
    if let Some(exe_dir) = exe.parent() {
      candidates.push(exe_dir.join("bin").join(name));
      candidates.push(exe_dir.join(name));
      if let Some(parent) = exe_dir.parent() {
        candidates.push(parent.join("bin").join(name));
      }
    }
  }
  for p in candidates {
    if p.is_file() {
      return Some(p);
    }
  }
  None
}
