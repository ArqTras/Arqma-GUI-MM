use std::path::{Path, PathBuf};

#[cfg(target_os = "windows")]
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
  #[cfg(not(target_os = "windows"))]
  {
    return Vec::new();
  }
  #[cfg(target_os = "windows")]
  {
    // Make native-wallet2 build independent from Developer Prompt.
    // We add common MSVC/Windows SDK include locations explicitly.
    let mut out = Vec::new();
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
    out
  }
}

fn main () {
  if std::env::var_os("CARGO_FEATURE_NATIVE_WALLET2").is_none() {
    return;
  }

  let manifest_dir =
    PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
  let upstream_path = match std::env::var("ARQMA_WALLET2_UPSTREAM_DIR") {
    Ok(p) if !p.trim().is_empty() => PathBuf::from(p),
    // `arqma-wallet2-api` lives in `rust/`; upstream clone is `rust/arqma-rpc-upstream`.
    _ => manifest_dir.join("../arqma-rpc-upstream"),
  };
  let api_dir = upstream_path.join("src").join("wallet").join("api");
  let upstream_src_dir = upstream_path.join("src");
  let header = api_dir.join("wallet2_api.h");
  if !header.is_file() {
    panic!(
      "native-wallet2: expected Arqma core headers at {} (missing {}).\n\
       From the `rust/` directory in this repo, run for example:\n\
         git clone -b pospow https://github.com/arqtras/arqma.git arqma-rpc-upstream\n\
       so that `rust/arqma-rpc-upstream/src/wallet/api/wallet2_api.h` exists, or set\n\
       ARQMA_WALLET2_UPSTREAM_DIR to the root of your Arqma core checkout.\n\
       See rust/docs/NATIVE_WALLET2.md",
      api_dir.display(),
      header.display()
    );
  }

  println!("cargo:rerun-if-env-changed=ARQMA_WALLET2_UPSTREAM_DIR");
  println!("cargo:rerun-if-changed=src/native.rs");
  println!("cargo:rerun-if-changed=src/wallet2_api_wrapper.cpp");
  println!("cargo:rerun-if-changed=src/wallet2_api_wrapper.hpp");
  println!("cargo:rerun-if-changed={}", api_dir.join("wallet2_api.h").display());
  println!("cargo:rerun-if-env-changed=ARQMA_WALLET2_LIB_DIR");
  println!("cargo:rerun-if-env-changed=ARQMA_WALLET2_LIB_NAME");
  println!("cargo:rerun-if-env-changed=ARQMA_WALLET2_MSYS_ROOT");

  let target_env = std::env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default();
  let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
  let mut b = cxx_build::bridge("src/native.rs");
  // `*-linux-gnu` also sets target_env=gnu — only pin MinGW when building for Windows GNU.
  if target_os == "windows" && target_env == "gnu" {
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

  if target_os == "windows" {
    configure_wallet2_linking(&upstream_path, &target_env);
  } else if target_os == "macos" {
    configure_wallet2_linking_macos(&upstream_path);
  } else if target_os == "linux" {
    configure_wallet2_linking_linux(&upstream_path);
  }
}

fn find_wallet_merged_dir (upstream: &Path) -> Option<PathBuf> {
  for root in [upstream.join("build"), upstream.join("build-mingw")] {
    if let Some(p) = find_wallet_merged_under(&root) {
      return Some(p);
    }
  }
  None
}

fn find_wallet_merged_under (root: &Path) -> Option<PathBuf> {
  if !root.is_dir() {
    return None;
  }
  let mut stack = vec![root.to_path_buf()];
  while let Some(dir) = stack.pop() {
    if dir.join("libwallet_merged.a").is_file() {
      return Some(dir);
    }
    if let Ok(entries) = std::fs::read_dir(&dir) {
      for e in entries.flatten() {
        let p = e.path();
        if p.is_dir() {
          stack.push(p);
        }
      }
    }
  }
  None
}

fn brew_prefix () -> PathBuf {
  std::env::var_os("HOMEBREW_PREFIX")
    .map(PathBuf::from)
    .filter(|p| p.is_dir())
    .unwrap_or_else(|| PathBuf::from("/opt/homebrew"))
}

fn configure_wallet2_linking_macos (upstream_path: &Path) {
  let lib_dir = std::env::var("ARQMA_WALLET2_LIB_DIR")
    .ok()
    .filter(|s| !s.trim().is_empty())
    .map(PathBuf::from)
    .or_else(|| find_wallet_merged_dir(upstream_path));

  let Some(lib_dir) = lib_dir else {
    println!("cargo:warning=native-wallet2 (macOS): build upstream with `-D BUILD_GUI_DEPS=ON`, run `cmake --build . --target wallet_merged`, or set ARQMA_WALLET2_LIB_DIR to the folder containing libwallet_merged.a.");
    return;
  };

  println!("cargo:rustc-link-search=native={}", lib_dir.display());
  if let Some(cmake_binary) = lib_dir.parent().and_then(|p| p.parent()) {
    for d in [
      "contrib/epee/src",
      "external/easylogging++",
      "external/randomarq",
      "src/lmdb/liblmdb",
      "src/cryptonote_basic",
    ] {
      let p = cmake_binary.join(d);
      if p.is_dir() {
        println!("cargo:rustc-link-search=native={}", p.display());
      }
    }
  }

  let bp = brew_prefix();
  println!(
    "cargo:rustc-link-arg=-Wl,-search_paths_first,-headerpad_max_install_names"
  );
  for rel in [
    "lib",
    "opt/openssl@3/lib",
    "opt/boost/lib",
    "opt/libsodium/lib",
    "opt/unbound/lib",
    "opt/readline/lib",
    "opt/hidapi/lib",
    "opt/icu4c/lib",
    "opt/icu4c@78/lib",
    "opt/lmdb/lib",
    "opt/zeromq/lib",
  ] {
    let p = bp.join(rel);
    if p.is_dir() {
      println!("cargo:rustc-link-search=native={}", p.display());
    }
  }

  for lib in [
    "hidapi",
    "boost_program_options",
    "boost_thread",
    "boost_container",
    "boost_date_time",
    "unbound",
    "boost_filesystem",
    "boost_atomic",
    "boost_chrono",
    "ssl",
    "crypto",
    "readline",
    "boost_serialization",
    "boost_regex",
    "boost_locale",
    "zmq",
    "sodium",
    "icuuc",
    "icui18n",
    "icudata",
    "z",
  ] {
    println!("cargo:rustc-link-lib=dylib={lib}");
  }

  println!("cargo:rustc-link-lib=framework=AppKit");
  println!("cargo:rustc-link-lib=framework=IOKit");
  println!("cargo:rustc-link-lib=framework=CoreFoundation");
}

fn configure_wallet2_linking_linux (upstream_path: &Path) {
  let lib_dir = std::env::var("ARQMA_WALLET2_LIB_DIR")
    .ok()
    .filter(|s| !s.trim().is_empty())
    .map(PathBuf::from)
    .or_else(|| find_wallet_merged_dir(upstream_path));

  let Some(lib_dir) = lib_dir else {
    println!("cargo:warning=native-wallet2 (Linux): build upstream with `-D BUILD_GUI_DEPS=ON`, target `wallet_merged`, or set ARQMA_WALLET2_LIB_DIR.");
    return;
  };

  println!("cargo:rustc-link-search=native={}", lib_dir.display());
  if let Some(cmake_binary) = lib_dir.parent().and_then(|p| p.parent()) {
    for d in [
      "contrib/epee/src",
      "external/easylogging++",
      "external/randomarq",
      "src/lmdb/liblmdb",
      "src/cryptonote_basic",
    ] {
      let p = cmake_binary.join(d);
      if p.is_dir() {
        println!("cargo:rustc-link-search=native={}", p.display());
      }
    }
  }

  for dir in ["/usr/lib/x86_64-linux-gnu", "/usr/lib", "/lib/x86_64-linux-gnu"] {
    if Path::new(dir).is_dir() {
      println!("cargo:rustc-link-search=native={dir}");
    }
  }

  for lib in [
    "hidapi-libusb",
    "boost_program_options",
    "boost_thread",
    "boost_container",
    "boost_date_time",
    "unbound",
    "boost_filesystem",
    "boost_atomic",
    "boost_chrono",
    "ssl",
    "crypto",
    "readline",
    "boost_serialization",
    "boost_regex",
    "boost_locale",
    "zmq",
    "sodium",
    "icuuc",
    "icui18n",
    "icudata",
    "z",
    "dl",
    "pthread",
  ] {
    println!("cargo:rustc-link-lib=dylib={lib}");
  }

  // Upstream CMake: `libepee.a` and `libcryptonote_format_utils_basic.a` both contain
  // `readline_buffer.cpp.o`. With `#[link(.., whole-archive)]` rustc surfaces duplicate globals;
  // GNU lld (Rust default on Linux CI) fails the final `cdylib` link without coalescing.
  println!("cargo:rustc-link-arg=-Wl,-z,muldefs");
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
