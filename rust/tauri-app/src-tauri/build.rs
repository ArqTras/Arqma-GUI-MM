fn main () {
  let manifest_dir = std::path::PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
  let dist_index = manifest_dir.join("../dist/index.html");
  let profile = std::env::var("PROFILE").unwrap_or_default();
  if (profile == "release" || profile == "local") && !dist_index.exists() {
    println!(
      "cargo:warning=arqma-wallet: ../dist/index.html missing — run `npm run build` in rust/tauri-app before release compile (with `custom-protocol` the UI still needs dist to embed assets)."
    );
  }
  tauri_build::build();

  // tauri-winres writes `resource.lib` in MSVC archive format, which GNU ld
  // cannot read. For windows-gnu builds, replace it with an empty GNU archive
  // at the same path so link args emitted by tauri-build stay valid.
  let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
  let target_env = std::env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default();
  if target_os == "windows" && target_env == "gnu" {
    if let Ok(out_dir) = std::env::var("OUT_DIR") {
      let out_dir = std::path::PathBuf::from(out_dir);
      let resource_lib = out_dir.join("resource.lib");
      if resource_lib.exists() {
        let dummy_c = out_dir.join("resource_dummy.c");
        let dummy_o = out_dir.join("resource_dummy.o");
        let _ = std::fs::write(&dummy_c, "int __arqma_resource_dummy = 0;\n");
        let mingw_bin = std::env::var("ARQMA_MINGW_BIN")
          .ok()
          .filter(|s| !s.trim().is_empty())
          .unwrap_or_else(|| r"C:\msys64\mingw64\bin".to_string());
        let gcc = std::path::PathBuf::from(&mingw_bin).join("x86_64-w64-mingw32-gcc.exe");
        let ar = std::path::PathBuf::from(&mingw_bin).join("ar.exe");
        // `ar` cannot overwrite archives in foreign formats (e.g. MSVC .lib).
        // Remove tauri-winres output first, then recreate as GNU archive.
        let _ = std::fs::remove_file(&resource_lib);
        let cc_status = std::process::Command::new(&gcc)
          .arg("-c")
          .arg(&dummy_c)
          .arg("-o")
          .arg(&dummy_o)
          .status();
        let ar_status = std::process::Command::new(&ar)
          .arg("rcs")
          .arg(&resource_lib)
          .arg(&dummy_o)
          .status();
        if cc_status.as_ref().map(|s| s.success()).unwrap_or(false)
          && ar_status.as_ref().map(|s| s.success()).unwrap_or(false)
        {
          println!("cargo:warning=arqma-wallet: replaced resource.lib with GNU archive for windows-gnu");
        } else {
          println!(
            "cargo:warning=arqma-wallet: failed to replace resource.lib (gcc={:?}, ar={:?}); linker may fail",
            cc_status,
            ar_status
          );
        }
      }
    }
  }
}
