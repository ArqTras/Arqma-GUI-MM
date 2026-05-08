# Native `wallet2` backend (no JSON-RPC transport to wallet logic)

**Default Tauri / Cargo settings** enable **`native-wallet2`** — the real `wallet2_api` (FFI + C++). That requires:

1. **Arqma core sources** (headers; after building upstream, also static libraries for linking).
2. A normal `npm run tauri:dev` / `npm run tauri:build` (no extra `--features`).

**Stub backend (no C++):** use Cargo feature **`stub-wallet2`** with **`--no-default-features`** when you have no upstream checkout (quick UI work or `npm run ci:tauri:stub`):

```bash
npm run tauri:dev:stub
# or
npm run tauri:build:stub
```

Equivalent Cargo:

```bash
cargo build -p arqma-wallet --no-default-features --features stub-wallet2
```

At runtime, `open_wallet` on the stub reports *wallet2 native backend disabled* unless you use the native build.

**CI note:** The [Tauri app workflow](../../.github/workflows/tauri-app.yml) clones **Arqma** (`arqtras/arqma`, `pospow`), builds **`libwallet_merged.a`**, then **`npm run ci:tauri:native`**. **Windows** uses the **`x86_64-pc-windows-gnu`** Rust target and MSYS2 MinGW. Quick builds without upstream: **`npm run ci:tauri:stub`**.

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
git clone -b pospow https://github.com/arqtras/arqma.git arqma-rpc-upstream
# alternatively: git clone https://github.com/Arqma/Arqma.git arqma-rpc-upstream
```

Custom location:

```bash
export ARQMA_WALLET2_UPSTREAM_DIR=/path/to/Arqma
```

## 2. Building the Tauri GUI (native — default)

From **`rust/tauri-app`**, default scripts already use **`native-wallet2`**:

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

If the build fails on **missing `wallet2_api.h`**, fix **`ARQMA_WALLET2_UPSTREAM_DIR`** or clone upstream into **`rust/arqma-rpc-upstream`** (section 1), or temporarily build with **`stub-wallet2`** (top of this file).
