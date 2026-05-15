use std::fs;
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
        println!("cargo:rerun-if-env-changed=ARQMA_WALLET_FFI_STATIC_HYBRID");
        println!("cargo:rerun-if-env-changed=ARQMA_WALLET_FFI_DEPENDS_LIB_DIR");

        let upstream = arqma_upstream_root();
        if static_hybrid_enabled() {
            if let Some(ref libdir) = depends_vendor_lib_dir(&upstream) {
                println!(
                    "cargo:rustc-link-search=native={}",
                    path_for_ld(libdir)
                );
                println!(
                    "cargo:warning=arqma-wallet: Linux binaries link PIC static deps from {}",
                    libdir.display()
                );
                linux_emit_static_hybrid_bins(libdir);
            } else {
                for bin in ["arqma-wallet", "arqma_flutter_solo_pool"] {
                    linux_emit_distro_dynamic_follow_for_bin(bin);
                }
            }
        } else {
            // Distro dynamic libs (dev / no contrib/depends): append after crate link via rustc-link-arg-bin.
            for bin in ["arqma-wallet", "arqma_flutter_solo_pool"] {
                linux_emit_distro_dynamic_follow_for_bin(bin);
            }
        }
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

fn linux_emit_distro_dynamic_follow_for_bin(bin: &str) {
    let emit = |flag: &str| println!("cargo:rustc-link-arg-bin={bin}={flag}", bin = bin);
    emit("-Wl,--no-as-needed");
    emit("-Wl,--start-group");
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
        emit(&format!("-l{}", lib));
    }
    emit("-Wl,--end-group");
}

fn mingw_wallet2_native_libs_cdylib_args() {
    let emit = |flag: &str| {
        println!("cargo:rustc-cdylib-link-arg={}", flag);
        // Same crate also builds `[[bin]]`; `rustc-cdylib-link-arg` does not apply to the exe link.
        println!("cargo:rustc-link-arg={}", flag);
    };
    emit_mingw_upstream_aux_archives(&emit);
    // Keep static deps that are only referenced from other `.a` members (e.g. OpenSSL from epee).
    emit("-Wl,--no-as-needed");
    emit("-Wl,--allow-multiple-definition");

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
        "readline",
        "history",
    ] {
        emit(&format!("-l{}", lib));
    }
    emit("-Wl,--end-group");
    for lib in ["icuuc", "icuin", "icudt", "iconv"] {
        emit(&format!("-l{}", lib));
    }
    // RandomX is folded into `libwallet_merged.a` by upstream CMake (`wallet_merge_gnu_ar.cmake`).
    for lib in [
        "ws2_32", "iphlpapi", "crypt32", "advapi32", "shell32", "userenv", "kernel32",
    ] {
        emit(&format!("-l{}", lib));
    }
    emit("-lm");
    emit("-lmingwex");
    // Stack trace in merged wallet uses libunwind; RandomX JIT members must survive `-Wl,--gc-sections`.
    emit("-lunwind");
    emit("-lstdc++");
    // LMDB on MinGW Windows uses `_aligned_malloc` / `wcscpy` from the MSVC CRT import table.
    emit("-lmingw32");
    emit("-lmsvcrt");
    emit("-Wl,--no-gc-sections");
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
                .join("../../arqma-rpc-upstream")
        })
}

/// Same aux archives as `arqma-wallet-flutter-ffi/build.rs` (epee, easylogging, cryptonote_basic, lmdb).
fn emit_mingw_upstream_aux_archives(emit: &dyn Fn(&str)) {
    let upstream = arqma_upstream_root();
    for sub in [
        "build-mingw",
        "build/ci-depends-release",
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
        "cargo:warning=arqma-wallet: upstream aux archives (epee/easylogging/cryptonote/lmdb) not found — GNU wallet / solo pool link may fail"
    );
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

// --- Linux static-hybrid (contrib/depends PIC .a), mirrors `arqma-wallet-flutter-ffi/build.rs` ---

fn static_hybrid_enabled() -> bool {
    std::env::var("ARQMA_WALLET_FFI_STATIC_HYBRID")
        .map(|v| matches!(v.trim(), "1" | "true" | "TRUE" | "yes" | "YES"))
        .unwrap_or(false)
}

fn depends_host_triple_linux() -> Option<&'static str> {
    let os = std::env::var("CARGO_CFG_TARGET_OS").ok()?;
    let arch = std::env::var("CARGO_CFG_TARGET_ARCH").ok()?;
    match (os.as_str(), arch.as_str()) {
        ("linux", "x86_64") => Some("x86_64-unknown-linux-gnu"),
        _ => None,
    }
}

fn depends_vendor_lib_dir(upstream: &Path) -> Option<PathBuf> {
    if let Ok(p) = std::env::var("ARQMA_WALLET_FFI_DEPENDS_LIB_DIR") {
        let pb = PathBuf::from(p.trim());
        if pb.is_dir() {
            return Some(pb);
        }
    }
    let host = depends_host_triple_linux()?;
    let lib = upstream.join("contrib/depends").join(host).join("lib");
    if !lib.is_dir() {
        return None;
    }
    if lib.join("libssl.a").is_file() || lib.join("libzmq.a").is_file() {
        return Some(lib);
    }
    None
}

fn depends_vendor_archive_paths(libdir: &Path, stem: &str) -> Vec<PathBuf> {
    let mut out = Vec::new();
    match stem {
        "ssl" => out.push(libdir.join("libssl.a")),
        "crypto" => out.push(libdir.join("libcrypto.a")),
        s if s.starts_with("boost_") => {
            out.push(libdir.join(format!("lib{s}.a")));
            out.push(libdir.join(format!("lib{s}-mt.a")));
        }
        "hidapi-libusb" => {
            out.push(libdir.join("libhidapi-libusb.a"));
            out.push(libdir.join("libhidapi-hidraw.a"));
            out.push(libdir.join("libhidapi.a"));
        }
        _ => out.push(libdir.join(format!("lib{stem}.a"))),
    }
    out
}

fn depends_vendor_archive_fuzzy_boost(libdir: &Path, stem: &str) -> Option<PathBuf> {
    if !stem.starts_with("boost_") {
        return None;
    }
    let prefix = format!("lib{stem}");
    let mut hits: Vec<PathBuf> = fs::read_dir(libdir)
        .ok()?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.is_file()
                && p.extension().and_then(|x| x.to_str()) == Some("a")
                && p.file_name()
                    .and_then(|n| n.to_str())
                    .map(|n| {
                        if !n.starts_with(&prefix) {
                            return false;
                        }
                        let tail = &n[prefix.len()..];
                        tail.is_empty() || tail.starts_with('-') || tail.starts_with('.')
                    })
                    .unwrap_or(false)
        })
        .collect();
    hits.sort();
    hits.into_iter().next()
}

fn emit_depends_vendor_lib(emit: &dyn Fn(&str), libdir: &Path, stem: &str) {
    for p in depends_vendor_archive_paths(libdir, stem) {
        if p.is_file() {
            emit(&path_for_ld(&p));
            return;
        }
    }
    if let Some(p) = depends_vendor_archive_fuzzy_boost(libdir, stem) {
        emit(&path_for_ld(&p));
        return;
    }
    println!(
        "cargo:warning=arqma-wallet: contrib/depends has no static archive for `{stem}` under {}",
        libdir.display()
    );
    emit(&format!("-l{stem}"));
}

fn depends_vendor_icu_static_triple(libdir: &Path) -> Option<(PathBuf, PathBuf, PathBuf)> {
    let data = libdir.join("libicudata.a");
    let i18n = libdir.join("libicui18n.a");
    let uc = libdir.join("libicuuc.a");
    if data.is_file() && i18n.is_file() && uc.is_file() {
        Some((data, i18n, uc))
    } else {
        None
    }
}

fn emit_depends_icu_static_if_present(emit: &dyn Fn(&str), libdir: &Path) {
    if let Some((data, i18n, uc)) = depends_vendor_icu_static_triple(libdir) {
        println!(
            "cargo:warning=arqma-wallet: linking static ICU from {}",
            libdir.display()
        );
        emit(&path_for_ld(&data));
        emit(&path_for_ld(&i18n));
        emit(&path_for_ld(&uc));
    }
}

fn emit_upstream_aux_archives_linux(emit: &dyn Fn(&str)) {
    let upstream = arqma_upstream_root();
    for sub in [
        "build/ci-depends-release",
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
        "cargo:warning=arqma-wallet: upstream aux archives (epee/easylogging/cryptonote/lmdb) not found — Linux static-hybrid link may fail"
    );
}

fn upstream_librandomx_a_path_linux() -> Option<PathBuf> {
    let upstream = arqma_upstream_root();
    for sub in [
        "build/ci-depends-release",
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

/// Same order as `linux_hybrid_full_static_dep_libs` in `arqma-wallet-flutter-ffi/build.rs`.
const LINUX_HYBRID_FULL_STATIC_DEP_LIBS: &[&str] = &[
    "hidapi-libusb",
    "usb-1.0",
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
];

fn linux_emit_static_hybrid_bins(libdir: &Path) {
    let emit = |flag: &str| {
        for name in ["arqma-wallet", "arqma_flutter_solo_pool"] {
            println!("cargo:rustc-link-arg-bin={}={}", name, flag);
        }
    };

    emit_upstream_aux_archives_linux(&emit);

    emit("-Wl,-Bdynamic");
    emit("-lstdc++");

    emit("-Wl,-Bstatic");
    emit("-static-libgcc");

    emit("-Wl,--no-as-needed");
    emit("-Wl,--start-group");
    for stem in LINUX_HYBRID_FULL_STATIC_DEP_LIBS {
        emit_depends_vendor_lib(&emit, libdir, stem);
    }
    emit_depends_icu_static_if_present(&emit, libdir);
    emit("-Wl,--end-group");

    if let Some(rx) = upstream_librandomx_a_path_linux() {
        emit(&path_for_ld(&rx));
    }

    emit("-Wl,-Bdynamic");

    if depends_vendor_icu_static_triple(libdir).is_none() {
        for lib in ["icuuc", "icui18n", "icudata"] {
            emit(&format!("-l{lib}"));
        }
    }

    emit("-lz");
    emit("-ldl");
    emit("-lpthread");
    emit("-lm");
    emit("-lresolv");
    emit("-ltinfo");
    emit("-Wl,-z,origin");
    emit("-Wl,-rpath,$ORIGIN");
}
