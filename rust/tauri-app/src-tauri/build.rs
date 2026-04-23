fn main () {
  let manifest_dir = std::path::PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
  let dist_index = manifest_dir.join("../dist/index.html");
  let profile = std::env::var("PROFILE").unwrap_or_default();
  if profile == "release" && !dist_index.exists() {
    println!(
      "cargo:warning=arqma-wallet: ../dist/index.html missing — run `npm run build` in rust/tauri-app before release compile, otherwise the window will try localhost:1420 and show ERR_CONNECTION_REFUSED."
    );
  }
  tauri_build::build()
}
