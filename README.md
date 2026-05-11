# Arqma Wallet (GUI)

Desktop wallet for Arqma: **Electron** build (legacy/main pipeline) and **Tauri** + Rust shell (`rust/tauri-app`).

## Windows 10 — VC++ Redistributable

Windows 10 needs the **VC++ Redistributable** from Microsoft:

https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170  

x64: https://aka.ms/vs/17/release/vc_redist.x64.exe

## macOS — running on other Macs

The Mac build may be distributed **without** an Apple Developer signature. On **first launch**, Gatekeeper may show an “unidentified developer” warning.

**To open once:**

1. Open the folder with the app (e.g. after unzipping or mounting the DMG).
2. **Right-click** (or Control-click) **Arqma-Wallet.app**.
3. Choose **Open**, then confirm **Open** in the dialog.

After that, double-click works as usual. You can also allow the app under **System Settings → Privacy & Security** if needed.

### Bypass Gatekeeper

macOS will block the app from opening because it is not notarized.  
Run this once in Terminal:

```bash
xattr -cr "/Applications/Arqma-Wallet.app"
```

---

## Electron app (Quasar)

### Install dependencies

```bash
yarn
# or
npm install
```

Dependencies are pinned to compatible minor/patch versions for security (Node ≥ 18.19, same major Vue/Quasar/Electron). Check updates: `npm outdated`; safe fixes: `npm audit fix`.

### Development

```bash
quasar dev
```

### Lint / format

```bash
yarn lint
# or npm run lint

yarn format
# or npm run format
```

### Production build

```bash
quasar build
```

Quasar config: [quasar.config.js](https://v2.quasar.dev/quasar-cli-webpack/quasar-config-js).

### Log files (Electron)

- **Windows:** `%APPDATA%\Roaming\Arqma-Electron-Wallet\logs\Arqma.log`  
  Example: `C:\Users\{USERNAME}\AppData\Roaming\Arqma-Electron-Wallet\logs\Arqma.log`
- **Linux:** `~/.config/Arqma-Electron-Wallet/logs/Arqma.log`
- **macOS:** `~/Library/Application Support/Arqma-Electron-Wallet/logs/Arqma.log`

### Watching logs

**Linux**

```bash
watch tail -n 10 ~/.config/Arqma-Electron-Wallet/logs/Arqma.log
```

**macOS**

```bash
watch tail -n 10 ~/Library/Application\ Support/Arqma-Electron-Wallet/logs/Arqma.log
```

---

## Tauri app (Rust + Vue)

See **`rust/README.md`** for workspace layout, `cargo check` / `clippy`, and **release build** steps (`npm run ci:tauri` from `rust/tauri-app`).

Briefly:

```bash
# Optional: place Arqma binaries in ./bin, then:
node build/copy-to-tauri-bins.js

cd rust/tauri-app
npm install
npm run ci:tauri
```

---

## Flutter shell (`flutter/arqma_wallet_gui`)

Experimental **Flutter** UI on the same `GatewayStore` / `backend-receive` event model as Tauri. See **`flutter/arqma_wallet_gui/README.md`** for `flutter run` and **solo pool** (`arqma_flutter_solo_pool`) build hints.

---

## CI (GitHub Actions)

- **`tauri-app.yml`** — Tauri installers/bundles: tag `v*`, PRs and `workflow_dispatch` when paths under `rust/` and build scripts change.
- **`flutter-github-release.yml`** — Tag `v*`: Flutter desktop (macOS / Linux / Windows) with the native FFI chain and release assets on GitHub Releases.

---

## Contributing

See **[CONTRIBUTING.md](CONTRIBUTING.md)** (English commit messages / PR text, Rust and frontend notes).

---

## `rust/web/`

Placeholder for a future web build (Vite/SSR or WASM) sharing `rust/core` with Tauri. Keep it separate from `tauri-app/` (see `rust/web/README.md`).
