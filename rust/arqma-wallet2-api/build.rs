use std::path::{Path, PathBuf};

fn newest_subdir (root: &Path) -> Option<PathBuf> {
  let mut dirs: Vec<PathBuf> = std::fs::read_dir(root)
    .ok()?
    .filter_map(|e| e.ok().map(|x| x.path()))
    .filter(|p| p.is_dir())
    .collect();
  dirs.sort();
  dirs.pop()
}

fn msvc_sdk_include_dirs () -> Vec<PathBuf> {
  let mut out = Vec::new();
  #[cfg(target_os = "windows")]
  {
    // Make native-wallet2 build independent from Developer Prompt.
    // We add common MSVC/Windows SDK include locations explicitly.
    if let Some(vc_tools) = newest_subdir(Path::new(
      r"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC",
    )) {
      out.push(vc_tools.join("include"));
    }
    if let Some(win10_inc_ver) = newest_subdir(Path::new(
      r"C:\Program Files (x86)\Windows Kits\10\Include",
    )) {
      out.push(win10_inc_ver.join("ucrt"));
      out.push(win10_inc_ver.join("shared"));
      out.push(win10_inc_ver.join("um"));
      out.push(win10_inc_ver.join("winrt"));
      out.push(win10_inc_ver.join("cppwinrt"));
    }
  }
  out
}

fn main () {
  if std::env::var_os("CARGO_FEATURE_NATIVE_WALLET2").is_none() {
    return;
  }

  let upstream_dir = std::env::var("ARQMA_WALLET2_UPSTREAM_DIR")
    .unwrap_or_else(|_| "../../arqma-rpc-upstream".to_string());
  let upstream_path = std::path::PathBuf::from(upstream_dir);
  let api_dir = upstream_path.join("src").join("wallet").join("api");
  let upstream_src_dir = upstream_path.join("src");

  println!("cargo:rerun-if-env-changed=ARQMA_WALLET2_UPSTREAM_DIR");
  println!("cargo:rerun-if-changed=src/native.rs");
  println!("cargo:rerun-if-changed=src/wallet2_api_wrapper.cpp");
  println!("cargo:rerun-if-changed=src/wallet2_api_wrapper.hpp");
  println!("cargo:rerun-if-changed={}", api_dir.join("wallet2_api.h").display());
  println!("cargo:rerun-if-env-changed=ARQMA_WALLET2_LIB_DIR");
  println!("cargo:rerun-if-env-changed=ARQMA_WALLET2_LIB_NAME");
  println!("cargo:rerun-if-env-changed=ARQMA_WALLET2_MSYS_ROOT");

  let target_env = std::env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default();
  let mut b = cxx_build::bridge("src/native.rs");
  if target_env == "gnu" {
    // On Windows GNU targets, force mingw g++ explicitly.
    b.compiler(r"C:\msys64\mingw64\bin\x86_64-w64-mingw32-g++.exe");
  }
  b
    .file("src/wallet2_api_wrapper.cpp")
    .include("src")
    .include(&upstream_src_dir)
    .include(api_dir)
    .flag_if_supported("-std=c++17");
  if target_env == "msvc" {
    for inc in msvc_sdk_include_dirs() {
      b.include(inc);
    }
  }
  b.compile("arqma_wallet2_api_bridge");

  let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
  if target_os == "windows" {
    configure_wallet2_linking(&upstream_path, &target_env);
  }
}

fn configure_wallet2_linking (upstream_path: &Path, target_env: &str) {
  // Allow explicit override from environment.
  if let Ok(lib_dir) = std::env::var("ARQMA_WALLET2_LIB_DIR") {
    if !lib_dir.trim().is_empty() {
      let lib_name = std::env::var("ARQMA_WALLET2_LIB_NAME")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| "wallet_merged".to_string());
      println!("cargo:rustc-link-search=native={lib_dir}");
      println!("cargo:rustc-link-lib=static={lib_name}");
      add_wallet2_external_libs(target_env);
      return;
    }
  }

  // Auto-detect mingw build output when target is windows-gnu.
  if target_env == "gnu" {
    let auto_lib_dir = upstream_path.join("build-mingw").join("src").join("wallet");
    if auto_lib_dir.join("libwallet_merged.a").exists() {
      println!("cargo:rustc-link-search=native={}", auto_lib_dir.display());
      println!("cargo:rustc-link-lib=static=wallet_merged");
      add_wallet2_external_libs(target_env);
      return;
    }
  }

  println!("cargo:warning=wallet2 merged library not linked automatically. Set ARQMA_WALLET2_LIB_DIR (and optional ARQMA_WALLET2_LIB_NAME).");
}

fn add_wallet2_external_libs (target_env: &str) {
  if target_env == "gnu" {
    let msys_root = std::env::var("ARQMA_WALLET2_MSYS_ROOT")
      .ok()
      .filter(|s| !s.trim().is_empty())
      .unwrap_or_else(|| r"C:\msys64\mingw64".to_string());
    println!("cargo:rustc-link-search=native={}\\lib", msys_root);
    // Additional libs installed from the Arqma build tree (epee/easylogging).
    if let Ok(upstream_dir) = std::env::var("ARQMA_WALLET2_UPSTREAM_DIR") {
      let upstream_dir = PathBuf::from(upstream_dir);
      let install_lib = upstream_dir
        .join("build-mingw")
        .join("install")
        .join("lib");
      if install_lib.exists() {
        println!("cargo:rustc-link-search=native={}", install_lib.display());
      }
      let randomx_lib = upstream_dir
        .join("build-mingw")
        .join("external")
        .join("randomarq");
      if randomx_lib.exists() {
        println!("cargo:rustc-link-search=native={}", randomx_lib.display());
      }
    }

    // External dependencies pulled by wallet_merged from mingw build.
    println!("cargo:rustc-link-lib=static=boost_filesystem-mt");
    println!("cargo:rustc-link-lib=static=boost_thread-mt");
    println!("cargo:rustc-link-lib=static=boost_chrono-mt");
    println!("cargo:rustc-link-lib=static=boost_date_time-mt");
    println!("cargo:rustc-link-lib=static=boost_serialization-mt");
    println!("cargo:rustc-link-lib=static=boost_program_options-mt");
    println!("cargo:rustc-link-lib=static=boost_locale-mt");
    println!("cargo:rustc-link-lib=static=ssl");
    println!("cargo:rustc-link-lib=static=crypto");
    println!("cargo:rustc-link-lib=static=zmq");
    println!("cargo:rustc-link-lib=static=sodium");
    println!("cargo:rustc-link-lib=static=hidapi");
    println!("cargo:rustc-link-lib=static=unbound");
    println!("cargo:rustc-link-lib=static=epee");
    println!("cargo:rustc-link-lib=static=easylogging");
    // RandomX has mutually-referencing objects; force full archive inclusion.
    println!("cargo:rustc-link-arg=-Wl,--whole-archive");
    println!("cargo:rustc-link-lib=static=randomx");
    println!("cargo:rustc-link-arg=-Wl,--no-whole-archive");
    println!("cargo:rustc-link-lib=static=lmdb");
    println!("cargo:rustc-link-lib=static=icuuc");
    println!("cargo:rustc-link-lib=static=icuin");
    println!("cargo:rustc-link-lib=static=icudt");
    println!("cargo:rustc-link-lib=static=iconv");
    println!("cargo:rustc-link-lib=ws2_32");
    println!("cargo:rustc-link-lib=iphlpapi");
    println!("cargo:rustc-link-lib=crypt32");
    println!("cargo:rustc-link-lib=userenv");
  }
}
