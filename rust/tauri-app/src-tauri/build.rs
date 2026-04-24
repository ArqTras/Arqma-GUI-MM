fn main () {
  let manifest_dir = std::path::PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
  let dist_index = manifest_dir.join("../dist/index.html");
  let profile = std::env::var("PROFILE").unwrap_or_default();
  if (profile == "release" || profile == "local") && !dist_index.exists() {
    println!(
      "cargo:warning=arqma-wallet: ../dist/index.html missing — run `npm run build` in rust/tauri-app before release compile (with `custom-protocol` the UI still needs dist to embed assets)."
    );
  }
  tauri_build::build()
}
