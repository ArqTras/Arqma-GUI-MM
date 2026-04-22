//! Port of `copyOldGuiWallets` from `wallet-rpc.js` (import legacy GUI wallet dirs into `wallets` + `old-gui`).

use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};

fn path_plus_ext (p: &Path, ext: &str) -> PathBuf {
  PathBuf::from(format!("{}{}", p.display(), ext))
}

/// Returns wallet directory names that failed to import (like `failed_wallets` in Node).
pub fn run_copy_old_gui_wallets (config: &Value, wallets: &[Value]) -> Result<Vec<String>, String> {
  let wallet_dir = crate::arqma_paths_config::wallet_files_dir(config).ok_or_else(|| {
    "copy_old_gui_wallets: missing wallet_data_dir or net_type in configuration".to_string()
  })?;
  let old_gui_path = wallet_dir.join("old-gui");
  let mut failed = Vec::new();

  for w in wallets {
    let typ = w.get("type").and_then(|t| t.as_str()).unwrap_or("mainnet");
    let Some(directory) = w.get("directory").and_then(|d| d.as_str()) else {
      continue;
    };

    let dir_path = wallet_dir.join(directory);
    if !dir_path.is_dir() {
      continue;
    }

    let wallet_file = dir_path.join(directory);
    let key_path = path_plus_ext(&wallet_file, ".keys");

    if !wallet_file.is_file() || !key_path.is_file() {
      failed.push(directory.to_string());
      continue;
    }

    let Some(dest_base) = crate::arqma_paths_config::wallet_files_dir_for_net(config, typ) else {
      failed.push(directory.to_string());
      continue;
    };

    fs::create_dir_all(&dest_base).map_err(|e| e.to_string())?;

    let new_path = dest_base.join(directory);
    let atom = path_plus_ext(&new_path, ".atom");
    let atom_keys = path_plus_ext(&new_path, ".atom.keys");

    if atom.exists() || atom_keys.exists() {
      failed.push(directory.to_string());
      continue;
    }

    let r: Result<(), String> = (|| {
      fs::copy(&wallet_file, &atom).map_err(|e| e.to_string())?;
      fs::copy(&key_path, &atom_keys).map_err(|e| e.to_string())?;

      fs::create_dir_all(&old_gui_path).map_err(|e| e.to_string())?;
      let destination_dir = old_gui_path.join(directory);
      if destination_dir.exists() {
        fs::remove_dir_all(&destination_dir).map_err(|e| e.to_string())?;
      }
      fs::rename(&dir_path, &destination_dir).map_err(|e| e.to_string())?;

      let final_keys = path_plus_ext(&new_path, ".keys");
      if !new_path.exists() && !final_keys.exists() {
        fs::rename(&atom, &new_path).map_err(|e| e.to_string())?;
        fs::rename(&atom_keys, &final_keys).map_err(|e| e.to_string())?;
      }
      Ok(())
    })();

    if r.is_err() {
      let _ = fs::remove_file(&atom);
      let _ = fs::remove_file(&atom_keys);
      failed.push(directory.to_string());
    }
  }

  Ok(failed)
}
