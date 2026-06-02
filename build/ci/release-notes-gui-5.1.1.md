## Arqma Wallet 5.1.1

Desktop and mobile bundles for tag **5.1.1**. Wallet FFI **[1.0.14](https://github.com/ArqTras/FFI/releases/tag/1.0.14)** (large-stack `open_wallet`, serialized FFI, deferred refresh on open). Desktop includes **`arqma_flutter_solo_pool`** built from this repo (solo-pool fixes below).

### Solo pool (desktop — Windows, Linux, macOS)

- **Block submission:** Detect network-valid blocks using the same difficulty rule as universal nodejs-pool (`hashDiff`), not only a compact 4-byte target approximation.
- **Template refresh:** Pool respects **Automatic block template refresh** and the **interval (seconds)** from settings; when disabled, templates refresh on new chain height.
- **VarDiff defaults:** Start 60k, max 5M, retarget 30s, max jump 50% — adjust per your hashrate in Solo Pool settings.

### Native wallet (FFI)

- **FFI:** [ArqTras/FFI](https://github.com/ArqTras/FFI/releases/latest) prebuilts for each platform, or build locally with `rust/tool/build_native_wallet_flutter_ffi_*`.
- **Android / iOS:** FFI only — **no** `arqma_flutter_solo_pool` sidecar.
- **Android / iOS:** Transaction history poll every **5 s** at tip, on new blocks, and right after relay (transfer / stake / sweep).

### Mobile builds (this release refresh)

- **iOS:** TestFlight build **5.1.1 (43)** — reopen wallet after iOS background/sleep, clearer open errors, FFI **1.0.12+**; build **42**: FFI **1.0.12** + password prompt + restore UI; build **40**: FFI **1.0.11** + resume/rescan.
- **Android:** **5.1.1+12** — same Dart wallet guards + restore layout; use FFI **1.0.12** prebuilts when rebuilding APK/AAB.

### Wallet scan progress (FFI 1.0.9 — desktop + mobile)

- Async `rescanBlockchain` and **`refresh`/sync** with height polling — footer, status bar, and iOS Live Activity show **current / tip (%)** instead of staying at **0%** while the wallet catches up.
- Flutter desktop (Windows, macOS, Linux) uses the same FFI prebuilts as mobile.

### iOS (5.1.1 builds 17–26)

- **Face ID / Touch ID:** Unlock password-protected accounts with biometrics (Keychain). Enable via switch on the password dialog, after login, or in wallet settings (must enter wallet password).
- **Background sync:** Keeps wallet heartbeat running while the app is backgrounded (screen off) via iOS background tasks.
- **Build 18:** Fix password prompt when opening imported accounts (`password` null vs empty).
- **Build 25:** Face ID prompt runs after wallet screen loads; settings menu always prompts for password before Keychain save.
- **Build 26:** FFI **1.0.8** rescan progress UI.
- **Build 27:** Live Activity extension enabled (App Group + `com.arqma.arqmaWalletMobile.RescanLiveActivity`); FFI **1.0.9** sync/rescan progress; installable on device and TestFlight.
- **Build 28:** Background sync while screen locked; inactivity logout does not fire during lock/rescan; rescan progress no longer resets when opening from Live Activity.
- **Build 31:** Smoother tab switching (narrow GoRouter refresh); fewer periodic UI rebuilds in footer and transaction list.
- **Build 32:** Instant tab switches on iOS (`IndexedStack`, `NoTransitionPage`, lazy tab bodies).
- **Build 33:** Same tab performance stack on **iOS, Android, and desktop** (including Solo Pool tab on desktop).
- **Build 34:** **Staking Pools** layout on phones: compact operator/status filter dropdown; pool list uses stacked cards (no column overlap) instead of forcing horizontal scroll on narrow screens. Android build **11** includes the same staking UI.
- **Build 35:** Wallet heartbeat defers heavy `get_transfers` while switching tabs or scrolling tx history; inactive tabs skip rebuilds on 5 s polls (smoother UI during refresh).
- **Build 37:** Background `store` + session checkpoint before suspend; foreground recover (`refresh` / reopen); full rescan clears history only after RPC success; skip `store` during rescan.
- **Build 38:** Screen stays awake while the wallet screen is open (no auto-lock during sync/rescan on the foreground UI).
- **Build 39:** Foreground resume uses lightweight RPC nudge (history not cleared); interrupted full rescan restarts after wake; rescan retries when wallet is busy; failed rescan restores previous height and tx list.
- **Build 43:** iOS session rebuild after background; sanitize `basic_string` open errors; `open_wallet` waits for background idle (FFI).
- **Build 42:** FFI **1.0.12** (deferred refresh on open, `bad_alloc` user message) + open-password fix + responsive restore controls.
- **Build 40:** Native wallet FFI **1.0.11** (background job safety in Rust FFI) + same Dart fixes as build 39.
- **Build 29:** Native wallet FFI **1.0.10** (rescan poller + `getheight` during background jobs).

### Desktop Flutter (5.1.1+5, FFI 1.0.14)

- **Open wallet retry:** After a failed `open_wallet` or account switch, desktop FFI **re-configures** the native client (fixes spurious `open_wallet failed` / `call_json code=-4` on retry without restarting the app).
- **macOS wallet open:** FFI worker isolate stays responsive; `open_wallet` / restore run on an **8 MiB stack pthread** (fixes crash on large wallet caches; CLI parity).
- **Daemon target:** When local `arqmad` RPC is down, wallet FFI uses configured **remote** `host:port` (same path CLI users expect).
- **Open flow:** Serialized in-process FFI; no `refresh_async_start` during `open_wallet`; post-open UI loads asynchronously; parallel `getheight` / `getbalance` / `get_address`.
- **Accounts screen:** Non-blocking `close_wallet` before `list_wallets`; navigation via wallet status (no invalid `GoRouterState` after open).
- **Biometrics:** Face ID / Touch ID **disabled on desktop** (mobile-only).
- **Staking Pools:** Compact status filter dropdown (same as mobile filter field; wide tabular list unchanged on desktop).
- Full rescan / sync footer progress: ignore stale pre-rescan `getheight` tip; complete only after real sub-tip catch-up (same logic as mobile).
- Inactivity auto-logout: paused when the app window is inactive/minimized and during `full_rescan_ui`.
- Wallet RPC: rescan/safe-store guards in `desktop_native_bridge` (Dart); native `wallet2_client` safety in FFI **1.0.14** prebuilts.
- **All desktop OS:** `NoTransitionPage` wallet routes; lazy tab builds; deduplicated store notifications during daemon/wallet heartbeat.

### Release assets (by platform)

| Platform | File(s) | How to run |
|----------|---------|------------|
| **Windows** | `Arqma-Wallet-Flutter-5.1.1-windows-x64.zip` (portable) or `Arqma-Wallet-Flutter-5.1.1-windows-x64-Setup.exe` (installer) | **ZIP:** unzip anywhere, run `Arqma-Wallet.exe` (keep all DLLs and `data\` beside the exe; `bin\arqmad.exe` and `bin\arqma_flutter_solo_pool.exe` for local daemon / solo pool). **Setup:** run installer, launch from Start menu. |
| **Linux** | `Arqma-Wallet-Flutter-5.1.1-linux-x64.tar.gz` and/or `Arqma-Wallet-Flutter-5.1.1-linux-x64.AppImage` | **tar.gz:** `tar xzf …tar.gz`, `cd` into folder, `./Arqma-Wallet` (or documented launcher). **AppImage:** `chmod +x *.AppImage`, `./Arqma-Wallet-Flutter-….AppImage`. |
| **macOS** | `Arqma-Wallet-Flutter-5.1.1-macos.zip` and/or `Arqma-Wallet-Flutter-5.1.1-macos.dmg` | Open **DMG**, drag **Arqma-Wallet.app** to Applications. If Gatekeeper blocks: `xattr -cr "/Applications/Arqma-Wallet.app"`. |
| **Android** | `Arqma-Wallet-Android-5.1.1-*.apk` (sideload), `Arqma-Wallet-Android-5.1.1-*.aab` (Play) | Install APK on device (unknown sources if needed). AAB is for Play Console upload only. |
| **iOS** | `Arqma-Wallet-Mobile-5.1.1-ios-testflight.ipa` (or development IPA) | TestFlight / Xcode install per your signing profile; build **43** (iOS resume + open fixes). |

### Solo pool quick start (desktop)

1. Use a **local** `arqmad` (not remote-only daemon).
2. Wallet → **Solo Pool** → enable pool, set mining address, bind IP/port.
3. Point **XMRig** (or compatible miner) at `stratum+tcp://<bind-ip>:3333` with your wallet address; worker name in `pass` or `rig-id`.
4. After changing VarDiff settings, **save and restart** the solo pool.

### macOS — Gatekeeper

```bash
xattr -cr "/Applications/Arqma-Wallet.app"
```

**FFI releases:** https://github.com/ArqTras/FFI/releases

**Full changelog:** https://github.com/ArqTras/Arqma-GUI-MM/blob/main/CHANGELOG.md
