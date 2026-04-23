use serde_json::json;
use std::fs;
use std::path::Path;

/// Same as `listWallets` in `wallet-rpc.js` (file scan; legacy dir omitted in first version).
pub fn list_wallet_files (wallet_dir: &Path) -> Result<serde_json::Value, String> {
  let mut list = vec![];
  let mut directories = vec![];
  if !wallet_dir.is_dir() {
    return Ok(json!({ "list": [], "directories": [] }));
  }
  for ent in fs::read_dir(wallet_dir).map_err(|e| e.to_string())? {
    let ent = ent.map_err(|e| e.to_string())?;
    let filename = ent.file_name();
    let name = filename.to_string_lossy().to_string();
    match name.as_str() {
      ".DS_Store" | ".DS_Store?" | "._.DS_Store" | ".Spotlight-V100" | ".Trashes" | "Thumbs.db" | "ehthumbs.db" | "old-gui" => continue,
      _ => {}
    }
    let p = ent.path();
    if p.is_dir() {
      let wfile = p.join(&name);
      let keyf = wfile.to_string_lossy().to_string() + ".keys";
      if wfile.is_file() && Path::new(&keyf).is_file() {
        directories.push(name);
      }
      continue;
    }
    if p
      .extension()
      .is_some() {
      continue;
    }
    let mut wallet_data = json!({
      "name": name,
      "address": serde_json::Value::Null,
      "password_protected": serde_json::Value::Null
    });
    let meta = wallet_dir.join(format!("{name}.meta.json"));
    if meta.is_file() {
      if let Ok(s) = fs::read_to_string(&meta) {
        if let Ok(m) = serde_json::from_str::<serde_json::Value>(&s) {
          if let Some(a) = m.get("address") {
            wallet_data["address"] = a.clone();
          }
          if let Some(p) = m.get("password_protected") {
            wallet_data["password_protected"] = p.clone();
          }
        }
      }
    }
    let addrf = wallet_dir.join(format!("{name}.address.txt"));
    if addrf.is_file() {
      if let Ok(s) = fs::read_to_string(&addrf) {
        if !s.is_empty() {
          wallet_data["address"] = json!(s.trim());
        }
      }
    }
    list.push(wallet_data);
  }
  Ok(json!({ "list": list, "directories": directories }))
}
