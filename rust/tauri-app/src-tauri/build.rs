use std::path::{Path, PathBuf};

fn main() {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let target_env = std::env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default();

    // Native wallet2 pulls several whole-archived CMake `.a` files — some object files appear in
    // more than one archive (e.g. readline_buffer in epee + cryptonote_format_utils_basic).
    // `cargo:rustc-link-arg` on a dependency crate does not always reach the final `cdylib` link;
    // apply on the artifact crate here so rust-lld can coalesce duplicates (same as BFD `-z muldefs`).
    if target_os == "linux" {
        println!("cargo:rustc-link-arg=-Wl,-z,muldefs");
    }

    // `#[link]` for MSYS2 libs does not reach the final `cdylib` link line (no `-lboost_*` emitted).
    // `rustc-cdylib-link-arg` appends near the end so `-l…` runs after `libwallet_merged.a`.
    if target_os == "windows" && target_env == "gnu" {
        mingw_wallet2_native_libs_cdylib_args();
    }

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
    if target_os == "windows" && target_env == "gnu" {
        if let Ok(out_dir) = std::env::var("OUT_DIR") {
            let out_dir = std::path::PathBuf::from(out_dir);
            let resource_lib = out_dir.join("resource.lib");
            if resource_lib.exists() {
                let dummy_c = out_dir.join("resource_dummy.c");
                let dummy_o = out_dir.join("resource_dummy.o");
                let _ = std::fs::write(&dummy_c, "int __arqma_resource_dummy = 0;\n");
                let mingw_bin = mingw_tools_bin_from_env()
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

fn mingw_wallet2_native_libs_cdylib_args() {
    let emit = |flag: &str| {
        println!("cargo:rustc-cdylib-link-arg={}", flag);
        // Same crate also builds `[[bin]]`; `rustc-cdylib-link-arg` does not apply to the exe link.
        println!("cargo:rustc-link-arg={}", flag);
    };
    // Keep static deps that are only referenced from other `.a` members (e.g. OpenSSL from epee).
    emit("-Wl,--no-as-needed");

    // `#[link(+whole-archive)]` on `randomx` from a dependency does not reliably pull
    // `jit_compiler_x86.cpp.o` into the final PE link — force the archive once here.
    if let Some(rx) = mingw_librandomx_a_path() {
        emit("-Wl,--whole-archive");
        emit(&mingw_path_for_ld(&rx));
        emit("-Wl,--no-whole-archive");
    }

    emit("-Wl,--start-group");
    // MSYS2 Boost ≥1.86: `boost_system` is header-only — no `libboost_system-mt` (linker: cannot find -lboost_system-mt).
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
        emit(&format!("-l{}", lib));
    }
    emit("-Wl,--end-group");
    for lib in ["icuuc", "icuin", "icudt", "iconv"] {
        emit(&format!("-l{}", lib));
    }
    for lib in ["ws2_32", "iphlpapi", "crypt32", "userenv", "kernel32"] {
        emit(&format!("-l{}", lib));
    }
    emit("-lm");
    emit("-lmingwex");
    // Stack trace in merged wallet uses libunwind; RandomX JIT members must survive `-Wl,--gc-sections`.
    emit("-lunwind");
    emit("-lstdc++");
    emit("-Wl,--no-gc-sections");
}

fn mingw_path_for_ld(p: &Path) -> String {
    p.display().to_string().replace('\\', "/")
}

/// `librandomx.a` from the MinGW CMake tree (CI sets `ARQMA_WALLET2_UPSTREAM_DIR`).
fn mingw_librandomx_a_path() -> Option<PathBuf> {
    let upstream = std::env::var("ARQMA_WALLET2_UPSTREAM_DIR")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .map(PathBuf::from)
        .or_else(|| {
            let md = std::env::var_os("CARGO_MANIFEST_DIR")?;
            let p = PathBuf::from(md);
            Some(p.join("../../arqma-rpc-upstream"))
        })?;
    let lib = upstream.join("build-mingw/external/randomarq/librandomx.a");
    if lib.is_file() {
        Some(lib)
    } else {
        None
    }
}

fn mingw_tools_bin_from_env() -> Option<String> {
    if let Ok(p) = std::env::var("ARQMA_MINGW_BIN") {
        let t = p.trim().to_owned();
        if std::path::Path::new(&t)
            .join("x86_64-w64-mingw32-gcc.exe")
            .is_file()
        {
            return Some(t);
        }
    }
    std::env::var("ARQMA_WALLET2_MSYS_ROOT")
        .ok()
        .filter(|s| !s.trim().is_empty())
        .map(|r| format!(r"{}\bin", r.trim_end_matches(['\\', '/'])))
        .filter(|pb| {
            std::path::Path::new(pb)
                .join("x86_64-w64-mingw32-gcc.exe")
                .is_file()
        })
}
