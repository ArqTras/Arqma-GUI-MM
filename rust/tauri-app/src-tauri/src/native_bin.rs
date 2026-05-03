//! Resolve `arqmad` / `arqma-wallet-rpc` from Arqma **build/install** output, `PATH`, or Tauri `resource/bin`.
use std::path::PathBuf;
use tauri::AppHandle;
use tauri::Manager;

/// Bundle + dev-tree search paths (Tauri `resource_dir/bin`, `./bin`, next to the running exe).
///
/// **`CARGO_MANIFEST_DIR`/bin** — canonical location from `src-tauri/bin/README.txt`; `cwd`-relative `bin/`
/// alone often points at `rust/tauri-app/bin`, so exes copied only under `src-tauri/bin/` were skipped.
pub fn bundled_exe_candidates (app: &AppHandle, win: &str, unix: &str) -> Vec<PathBuf> {
  let name = if cfg!(windows) { win } else { unix };
  let mut v = Vec::new();
  if let Ok(res) = app.path().resource_dir() {
    v.push(res.join("bin").join(name));
  }
  // Same crate as Cargo.toml (`rust/tauri-app/src-tauri`) — documented bundle dir independent of cwd.
  v.push(PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("bin").join(name));
  v.push(PathBuf::from("bin").join(name));
  v.push(PathBuf::from("binaries").join(name));
  if let Ok(exe) = std::env::current_exe() {
    if let Some(exe_dir) = exe.parent() {
      v.push(exe_dir.join("bin").join(name));
      v.push(exe_dir.join(name));
      if let Some(parent) = exe_dir.parent() {
        v.push(parent.join("bin").join(name));
      }
    }
  }
  v
}

/// Wallet JSON-RPC: upstream build → `PATH` → bundle (see [`arqma_wallet_rpc::resolve_wallet_rpc_path`]).
pub fn resolve_wallet_rpc_exe (app: &AppHandle) -> Option<PathBuf> {
  arqma_wallet_rpc::resolve_wallet_rpc_path(bundled_exe_candidates(
    app,
    "arqma-wallet-rpc.exe",
    "arqma-wallet-rpc",
  ))
}

/// Local daemon: same resolution as wallet RPC (see `ARQMA_DAEMON`, `ARQMA_BUILD_DIR`).
pub fn resolve_arqmad_exe (app: &AppHandle) -> Option<PathBuf> {
  arqma_wallet_rpc::resolve_daemon_path(bundled_exe_candidates(app, "arqmad.exe", "arqmad"))
}
