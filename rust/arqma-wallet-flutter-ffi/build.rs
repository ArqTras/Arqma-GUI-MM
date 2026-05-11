//! Final-link flags for the `cdylib` wallet stack (same MinGW / Linux needs as `rust/tauri-app/src-tauri/build.rs`).
//! `arqma-wallet2-api`'s `build.rs` only adds search paths on windows-gnu; Tauri previously supplied
//! `-lssl`, `-lboost_*`, etc. via `rustc-cdylib-link-arg`. This crate is a standalone `cdylib`, so we
//! emit those flags here.

use std::path::{Path, PathBuf};

fn main() {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let target_env = std::env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default();

    if target_os == "linux" {
        println!("cargo:rustc-link-arg=-Wl,-z,muldefs");
    }

    if target_os == "windows" && target_env == "gnu" {
        mingw_wallet2_native_libs_cdylib_args();
    }
}

fn mingw_wallet2_native_libs_cdylib_args() {
    let emit = |flag: &str| {
        println!("cargo:rustc-cdylib-link-arg={flag}");
    };
    emit("-Wl,--no-as-needed");

    emit("-Wl,--start-group");
    for lib in [
        "boost_atomic-mt",
        "boost_container-mt",
        "boost_filesystem-mt",
        "boost_thread-mt",
        "boost_chrono-mt",
        "boost_date_time-mt",
        "boost_serialization-mt",
        "boost_program_options-mt",
        "boost_locale-mt",
        "ssl",
        "crypto",
        "zmq",
        "sodium",
        "hidapi",
        "unbound",
    ] {
        emit(&format!("-l{lib}"));
    }
    emit("-Wl,--end-group");
    for lib in ["icuuc", "icuin", "icudt", "iconv"] {
        emit(&format!("-l{lib}"));
    }
    if let Some(rx) = mingw_librandomx_a_path() {
        emit(&mingw_path_for_ld(&rx));
    }
    for lib in [
        "ws2_32",
        "iphlpapi",
        "crypt32",
        "advapi32",
        "shell32",
        "userenv",
        "kernel32",
    ] {
        emit(&format!("-l{lib}"));
    }
    emit("-lm");
    emit("-lmingwex");
    emit("-lunwind");
    emit("-lstdc++");
    emit("-Wl,--no-gc-sections");
}

fn mingw_path_for_ld(p: &Path) -> String {
    p.display().to_string().replace('\\', "/")
}

fn mingw_librandomx_a_path() -> Option<PathBuf> {
    let upstream = std::env::var("ARQMA_WALLET2_UPSTREAM_DIR")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .map(PathBuf::from)
        .or_else(|| {
            let md = std::env::var_os("CARGO_MANIFEST_DIR")?;
            Some(PathBuf::from(md).join("../arqma-rpc-upstream"))
        })?;
    let lib = upstream.join("build-mingw/external/randomarq/librandomx.a");
    if lib.is_file() {
        Some(lib)
    } else {
        None
    }
}
