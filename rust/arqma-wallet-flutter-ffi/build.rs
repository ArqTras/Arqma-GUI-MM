//! Final-link flags for the `cdylib` wallet stack (same MinGW / Linux needs as `rust/tauri-app/src-tauri/build.rs`).
//! **Upstream archives:** `libepee.a`, `libeasylogging.a`, `libcryptonote_format_utils_basic.a`, `liblmdb.a` need
//! `-Wl,--whole-archive` or link fails with undefined symbols.
//!
//! **Default:** native deps linked as **dynamic** where `arqma-wallet2-api` emits `rustc-link-lib=dylib` (Linux/macOS),
//! or MSYS2-style `-l…` on **windows-gnu** (this crate always appends those flags on MinGW).
//!
//! **Experimental:** `ARQMA_WALLET_FFI_STATIC_HYBRID=1` — link Boost/OpenSSL/libsodium/zmq/hidapi/unbound (+ readline on Unix)
//! **statically** into the FFI shared library; keep **ICU + iconv** on Windows and **ICU** on Linux/macOS **dynamic**
//! (Boost.Locale). **libstdc++** stays dynamic on Windows/Linux; match toolchain defaults on macOS.
//! On Linux/macOS you must set this env when building `arqma-wallet-flutter-ffi` so `arqma-wallet2-api` skips duplicate
//! `dylib` link lines (see `arqma-wallet2-api/build.rs`).

use std::path::{Path, PathBuf};

fn main() {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let target_env = std::env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default();

    println!("cargo:rerun-if-env-changed=ARQMA_WALLET_FFI_STATIC_HYBRID");

    if target_os == "linux" {
        println!("cargo:rustc-link-arg=-Wl,-z,muldefs");
    }

    if target_os == "windows" && target_env == "gnu" {
        mingw_wallet2_native_libs_cdylib_args();
    } else if target_os == "linux" && static_hybrid_enabled() {
        println!(
            "cargo:warning=arqma-wallet-flutter-ffi: ARQMA_WALLET_FFI_STATIC_HYBRID=1 (Linux static-hybrid)"
        );
        linux_wallet_ffi_static_hybrid_cdylib_args();
    } else if target_os == "macos" && static_hybrid_enabled() {
        println!(
            "cargo:warning=arqma-wallet-flutter-ffi: ARQMA_WALLET_FFI_STATIC_HYBRID=1 (macOS static-hybrid)"
        );
        macos_wallet_ffi_static_hybrid_cdylib_args();
    }
}

fn static_hybrid_enabled() -> bool {
    std::env::var("ARQMA_WALLET_FFI_STATIC_HYBRID")
        .map(|v| matches!(v.trim(), "1" | "true" | "TRUE" | "yes" | "YES"))
        .unwrap_or(false)
}

fn mingw_wallet2_native_libs_cdylib_args() {
    let hybrid = static_hybrid_enabled();
    let emit = |flag: &str| {
        println!("cargo:rustc-cdylib-link-arg={flag}");
    };

    emit("-Wl,--no-as-needed");
    // GitHub `wallet_merged` already folds easylogging/epee/…; re-linking the same `.a` files then
    // causes GNU ld "multiple definition". Local/offline merges may omit them — keep aux archives.
    // Prefer resolving duplicates over missing symbols (identical object code in practice).
    emit("-Wl,--allow-multiple-definition");
    emit_upstream_aux_archives(&emit);

    if hybrid {
        emit("-Wl,-Bstatic");
        emit("-static-libgcc");
        // Do not use `-static-libstdc++` here: with Rust's link order it often fails to pull the full
        // archive before `-Wl,-Bdynamic`/ICU; link then misses libstdc++ symbols from `libepee.a`/Boost.
        // Boost/OpenSSL/… stay static via `-Bstatic` + `-l…`; libstdc++ remains dynamic (`-lstdc++` below).
    }

    emit("-Wl,--start-group");
    for lib in mingw_wallet_dep_libs() {
        emit(&format!("-l{lib}"));
    }
    emit("-Wl,--end-group");

    if let Some(rx) = upstream_librandomx_a_path() {
        emit(&path_for_ld(&rx));
    }

    if hybrid {
        emit("-Wl,-Bdynamic");
    }

    for lib in ["icuuc", "icuin", "icudt", "iconv"] {
        emit(&format!("-l{lib}"));
    }

    for lib in mingw_windows_system_libs() {
        emit(&format!("-l{lib}"));
    }
    emit("-lm");
    emit("-lmingwex");
    // `libmingwex` (e.g. gettimeofday) may need kernel32 imports resolved after the CRT block.
    emit("-lkernel32");
    emit("-lunwind");
    emit("-lstdc++");

    emit("-lmingw32");
    emit("-lmsvcrt");
    emit("-Wl,--no-gc-sections");
}

fn linux_wallet_ffi_static_hybrid_cdylib_args() {
    let emit = |flag: &str| println!("cargo:rustc-cdylib-link-arg={flag}");

    emit("-Wl,--no-as-needed");
    emit_upstream_aux_archives(&emit);

    emit("-Wl,-Bstatic");
    emit("-static-libgcc");

    emit("-Wl,--start-group");
    for lib in linux_hybrid_dep_libs() {
        emit(&format!("-l{lib}"));
    }
    emit("-Wl,--end-group");

    if let Some(rx) = upstream_librandomx_a_path() {
        emit(&path_for_ld(&rx));
    }

    emit("-Wl,-Bdynamic");

    for lib in ["icuuc", "icui18n", "icudata"] {
        emit(&format!("-l{lib}"));
    }

    emit("-lz");
    emit("-ldl");
    emit("-lpthread");
    emit("-lm");
    emit("-lresolv");
    emit("-ltinfo");
    emit("-lstdc++");
}

fn macos_wallet_ffi_static_hybrid_cdylib_args() {
    let emit = |flag: &str| println!("cargo:rustc-cdylib-link-arg={flag}");

    emit("-Wl,-search_paths_first,-headerpad_max_install_names");
    emit("-Wl,--no-as-needed");
    emit_upstream_aux_archives(&emit);

    emit("-Wl,-Bstatic");

    emit("-Wl,--start-group");
    for lib in macos_hybrid_dep_libs() {
        emit(&format!("-l{lib}"));
    }
    emit("-Wl,--end-group");

    if let Some(rx) = upstream_librandomx_a_path() {
        emit(&path_for_ld(&rx));
    }

    emit("-Wl,-Bdynamic");

    for lib in ["icuuc", "icui18n", "icudata", "z"] {
        emit(&format!("-l{lib}"));
    }

    for fw in ["AppKit", "IOKit", "CoreFoundation"] {
        emit(&format!("-framework {fw}"));
    }
}

fn mingw_wallet_dep_libs() -> &'static [&'static str] {
    &[
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
        // `readline_buffer.cpp` in folded epee / cryptonote archives (MSYS2 GNU readline).
        "readline",
        "history",
        "ncurses",
    ]
}

fn linux_hybrid_dep_libs() -> &'static [&'static str] {
    &[
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
    ]
}

fn macos_hybrid_dep_libs() -> &'static [&'static str] {
    &[
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
    ]
}

fn mingw_windows_system_libs() -> &'static [&'static str] {
    &[
        "ws2_32",
        "mswsock",
        "iphlpapi",
        "crypt32",
        "advapi32",
        "shell32",
        "userenv",
        "user32",
        "kernel32",
    ]
}

fn path_for_ld(p: &Path) -> String {
    p.display().to_string().replace('\\', "/")
}

fn arqma_upstream_root() -> PathBuf {
    std::env::var("ARQMA_WALLET2_UPSTREAM_DIR")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"))
                .join("../arqma-rpc-upstream")
        })
}

fn emit_upstream_aux_archives(emit: &dyn Fn(&str)) {
    let upstream = arqma_upstream_root();
    // CI macOS/Linux use `build/ci-native-release` (see build/ci/build-arqma-*.sh); MinGW uses `build-mingw`.
    for sub in [
        "build-mingw",
        "build/ci-native-release",
        "build",
    ] {
        let root = upstream.join(sub);
        let epee = root.join("contrib/epee/src/libepee.a");
        let elog = root.join("external/easylogging++/libeasylogging.a");
        let cn = root.join("src/cryptonote_basic/libcryptonote_format_utils_basic.a");
        let lmdb = root.join("src/lmdb/liblmdb/liblmdb.a");
        if epee.is_file() && elog.is_file() && cn.is_file() && lmdb.is_file() {
            emit("-Wl,--whole-archive");
            emit(&path_for_ld(&epee));
            emit(&path_for_ld(&elog));
            emit(&path_for_ld(&cn));
            emit(&path_for_ld(&lmdb));
            emit("-Wl,--no-whole-archive");
            return;
        }
    }
    println!(
        "cargo:warning=arqma-wallet-flutter-ffi: upstream aux archives (epee/easylogging/cryptonote/lmdb) not found under build-mingw, build/ci-native-release, or build - wallet link may fail"
    );
}

fn upstream_librandomx_a_path() -> Option<PathBuf> {
    let upstream = arqma_upstream_root();
    for sub in [
        "build-mingw",
        "build/ci-native-release",
        "build",
    ] {
        let lib = upstream.join(sub).join("external/randomarq/librandomx.a");
        if lib.is_file() {
            return Some(lib);
        }
    }
    None
}
