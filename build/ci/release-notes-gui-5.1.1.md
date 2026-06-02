## Arqma Wallet 5.1.1

Desktop and mobile bundles for tag **5.1.1**. Wallet FFI **[1.0.10](https://github.com/ArqTras/FFI/releases/tag/1.0.10)** (full rescan live progress + async refresh/sync height polling). Desktop includes **`arqma_flutter_solo_pool`** built from this repo (solo-pool fixes below).

### Solo pool (desktop — Windows, Linux, macOS)

- **Block submission:** Detect network-valid blocks using the same difficulty rule as universal nodejs-pool (`hashDiff`), not only a compact 4-byte target approximation.
- **Template refresh:** Pool respects **Automatic block template refresh** and the **interval (seconds)** from settings; when disabled, templates refresh on new chain height.
- **VarDiff defaults:** Start 60k, max 5M, retarget 30s, max jump 50% — adjust per your hashrate in Solo Pool settings.

### Native wallet (FFI)

- **FFI:** [ArqTras/FFI](https://github.com/ArqTras/FFI/releases/latest) prebuilts for each platform, or build locally with `rust/tool/build_native_wallet_flutter_ffi_*`.
- **Android / iOS:** FFI only — **no** `arqma_flutter_solo_pool` sidecar.
- **Android / iOS:** Transaction history poll every **5 s** at tip, on new blocks, and right after relay (transfer / stake / sweep).

### Mobile builds (this release refresh)

- **iOS:** TestFlight build **5.1.1 (37)** — background sync persists wallet (`store` + checkpoint), resume reopens session and continues scan; full rescan starts only after RPC OK; no empty tx wipe on resume. Build **36**: footer Scanning/Synced + locales; build **35**: deferred tx refresh.
- **Android:** Rebuilt APK/AAB with tx-history poll every **5 s** (CI); FFI **1.0.10** when rebuilt after tag **5.1.1**.

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
- **Build 29:** Native wallet FFI **1.0.10** (rescan poller + `getheight` during background jobs).

### Desktop Flutter (5.1.1+3, release tag rebuild with FFI 1.0.10)

- **Staking Pools:** Compact status filter dropdown (same as mobile filter field; wide tabular list unchanged on desktop).

- Full rescan / sync footer progress: ignore stale pre-rescan `getheight` tip; complete only after real sub-tip catch-up (same logic as mobile).
- Inactivity auto-logout: paused when the app window is inactive/minimized and during `full_rescan_ui`.
- Wallet RPC: rescan height poller fix in `wallet2_client` (shipped in FFI **1.0.10** prebuilts).
- **macOS:** Optional Touch ID unlock (Keychain); tab navigation uses the same `IndexedStack` shell as mobile.
- **All desktop OS:** `NoTransitionPage` wallet routes; lazy tab builds; deduplicated store notifications during daemon/wallet heartbeat.

### Release assets (by platform)

| Platform | File(s) | How to run |
|----------|---------|------------|
| **Windows** | `Arqma-Wallet-Flutter-5.1.1-windows-x64.zip` (portable) or `Arqma-Wallet-Flutter-5.1.1-windows-x64-Setup.exe` (installer) | **ZIP:** unzip anywhere, run `Arqma-Wallet.exe` (keep all DLLs and `data\` beside the exe; `bin\arqmad.exe` and `bin\arqma_flutter_solo_pool.exe` for local daemon / solo pool). **Setup:** run installer, launch from Start menu. |
| **Linux** | `Arqma-Wallet-Flutter-5.1.1-linux-x64.tar.gz` and/or `Arqma-Wallet-Flutter-5.1.1-linux-x64.AppImage` | **tar.gz:** `tar xzf …tar.gz`, `cd` into folder, `./Arqma-Wallet` (or documented launcher). **AppImage:** `chmod +x *.AppImage`, `./Arqma-Wallet-Flutter-….AppImage`. |
| **macOS** | `Arqma-Wallet-Flutter-5.1.1-macos.zip` and/or `Arqma-Wallet-Flutter-5.1.1-macos.dmg` | Open **DMG**, drag **Arqma-Wallet.app** to Applications. If Gatekeeper blocks: `xattr -cr "/Applications/Arqma-Wallet.app"`. |
| **Android** | `Arqma-Wallet-Android-5.1.1-*.apk` (sideload), `Arqma-Wallet-Android-5.1.1-*.aab` (Play) | Install APK on device (unknown sources if needed). AAB is for Play Console upload only. |
| **iOS** | `Arqma-Wallet-Mobile-5.1.1-ios-testflight.ipa` (or development IPA) | TestFlight / Xcode install per your signing profile; build **37** (background persist + resume recover + rescan fixes). |

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
