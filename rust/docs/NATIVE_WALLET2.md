# Native `wallet2` backend (no JSON-RPC transport to wallet logic)

The GUI **always** links the real **`wallet2_api`** stack (`arqma-wallet2-api` → C++/FFI). That requires:

1. **Arqma core sources** (headers; after building upstream, also static libraries for linking).
2. **`npm run tauri:dev`** / **`npm run tauri:build`** / **`npm run ci:tauri`** — no extra Cargo feature flags; the Tauri crate always depends on the native bridge.

**CI note:** Native **`wallet_merged`** is always built from **[arqma/arqma](https://github.com/arqma/arqma)** (`master` branch by default via `clone-arqma.sh` / `ARQMA_UPSTREAM_REF`). The **`arqmad`** daemon binary bundled with the GUI comes from the **[latest GitHub Release of arqma/arqma](https://github.com/arqma/arqma/releases/latest)** (static bundles via [`build/download-binaries.js`](../../build/download-binaries.js); prefer full archives over `build-depends-*` when multiple assets exist). In [desktop release CI](../../.github/workflows/desktop-release.yml), the **tauri** matrix job builds **`wallet_merged`**, runs **`node build/download-binaries.js`**, extracts **`arqmad`** into `./bin`, copies **`arqmad` only** into `rust/tauri-app/src-tauri/bin/`, then **`npm run ci:tauri`**. **Windows** uses **`x86_64-pc-windows-gnu`** and MSYS2 MinGW (`npm run ci:tauri:native:windows-gnu`). The **flutter-*** jobs in the same workflow build **`wallet_merged` + `arqma-wallet-flutter-ffi`** and use the same release **`arqmad`** for macOS / Linux (`build/ci/fetch-arqmad-github-release.sh`) and Windows (`build/ci/flutter-windows-fetch-arqma-binaries.ps1`).

## 0. Building Arqma core on macOS (native + `libwallet_merged`)

To produce **`libwallet_merged.a`** (required for linking the GUI on macOS), reconfigure your CMake build with **`BUILD_GUI_DEPS=ON`** and build the **`wallet_merged`** target:

```bash
cd rust/arqma-rpc-upstream/build/<your_cmake_output_dir>/release
cmake -D BUILD_GUI_DEPS=ON -D CMAKE_BUILD_TYPE=Release ../../../..
cmake --build . --target wallet_merged -j"$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
```

If you already ran `make release` in that tree, you usually only need to reconfigure and run `wallet_merged` as above.

## 1. Upstream directory (headers)

From `rust/arqma-wallet2-api`, the default path is **`../arqma-rpc-upstream`**, i.e. in this repo: **`rust/arqma-rpc-upstream`** — the root of an Arqma checkout (must contain `src/wallet/api/wallet2_api.h`).

```bash
cd rust
git clone -b master https://github.com/arqma/arqma.git arqma-rpc-upstream
```

For the daemon only, use official binaries from **`arqma/arqma` Releases** (see `build/download-binaries.js`), not the checkout above.

Custom location:

```bash
export ARQMA_WALLET2_UPSTREAM_DIR=/path/to/Arqma
```

## 2. Building the Tauri GUI (native — default)

From **`rust/tauri-app`**:

```bash
npm run tauri:dev
npm run tauri:build
```

Legacy aliases (same as above): `tauri:dev:native`, `tauri:build:native`.

Without npm:

```bash
node scripts/with-rust-target.mjs tauri dev
node scripts/with-rust-target.mjs tauri build
```

## 3. Linking the C++ wallet library (by platform)

- **Windows (MSVC / GNU):** `build.rs` has helper paths; you may need **`ARQMA_WALLET2_LIB_DIR`** and optionally **`ARQMA_WALLET2_LIB_NAME`** after building `wallet_merged` in the upstream tree.
- **macOS:** `build.rs` searches Homebrew prefixes and can auto-detect `libwallet_merged.a` under `arqma-rpc-upstream/build/...`; ensure **`BUILD_GUI_DEPS`** / **`wallet_merged`** were built (section 0).
- **Linux:** you may need to set **`ARQMA_WALLET2_LIB_DIR`** (and matching system dev packages) similar to Windows until first-class auto-linking is added.

If the build fails on **missing `wallet2_api.h`**, fix **`ARQMA_WALLET2_UPSTREAM_DIR`** or clone upstream into **`rust/arqma-rpc-upstream`** (section 1).

## Windows MinGW (`x86_64-pc-windows-gnu`)

From **`rust/tauri-app`**, after installing MSYS2 **MINGW64** toolchain and deps (Boost, OpenSSL, … — mirror **`desktop-release.yml`** job **tauri** MSYS package list):

```bash
npm run clone:arqma
npm run build:arqma:mingw
```

Equivalent: run **`build/ci/clone-arqma.sh`** and **`build/ci/build-arqma-mingw.sh`** from a **MINGW64** shell (`bash`), with **`ARQMA_WALLET2_UPSTREAM_DIR`** pointing at your checkout if it is not **`rust/arqma-rpc-upstream`**.

1. **Rebuild upstream** after CMake fixes: **`build-arqma-mingw.sh`** sets **`CMAKE_SYSTEM_PROCESSOR=x86_64`** and **`ARCH=native`** so RandomX includes **`jit_compiler_x86`**. If **`librandomx.a`** was built without x86 JIT objects, GNU ld reports undefined references to **`randomx::JitCompilerX86::*`** when linking the Tauri DLL.
2. **`rust/tauri-app/scripts/with-rust-target.mjs`** sets **`CARGO_PROFILE_RELEASE_LTO=thin`** when the command line includes **`x86_64-pc-windows-gnu`** (unless **`CARGO_PROFILE_RELEASE_LTO`** is already set). Applies to **`npm run ci:tauri:native:windows-gnu`**, **`npm run release:win`**, and any **`node scripts/with-rust-target.mjs cargo … --target x86_64-pc-windows-gnu`**. This avoids occasional MinGW / libstdc++ issues such as **`__real___cxa_throw`** during the final link.
