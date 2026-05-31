## Arqma Wallet 5.1.1

Desktop and mobile bundles for tag **5.1.1**. Wallet FFI from [ArqTras/FFI](https://github.com/ArqTras/FFI/releases/latest) (CI default: **Latest**). Desktop includes **`arqma_flutter_solo_pool`** built from this repo (solo-pool fixes below).

### Solo pool (desktop — Windows, Linux, macOS)

- **Block submission:** Detect network-valid blocks using the same difficulty rule as universal nodejs-pool (`hashDiff`), not only a compact 4-byte target approximation.
- **Template refresh:** Pool respects **Automatic block template refresh** and the **interval (seconds)** from settings; when disabled, templates refresh on new chain height.
- **VarDiff defaults:** Start 60k, max 5M, retarget 30s, max jump 50% — adjust per your hashrate in Solo Pool settings.

### Native wallet (FFI)

- **FFI:** [ArqTras/FFI](https://github.com/ArqTras/FFI/releases/latest) prebuilts for each platform, or build locally with `rust/tool/build_native_wallet_flutter_ffi_*`.
- **Android / iOS:** FFI only — **no** `arqma_flutter_solo_pool` sidecar.
- **Android / iOS:** Transaction history poll every **5 s** at tip, on new blocks, and right after relay (transfer / stake / sweep).

### Mobile builds (this release refresh)

- **iOS:** TestFlight build **5.1.1 (15)** — latest wallet FFI (ArqTras/FFI **Latest**).
- **Android:** Rebuilt APK/AAB with the same tx-history refresh (CI).

### Release assets (by platform)

| Platform | File(s) | How to run |
|----------|---------|------------|
| **Windows** | `Arqma-Wallet-Flutter-5.1.1-windows-x64.zip` (portable) or `Arqma-Wallet-Flutter-5.1.1-windows-x64-Setup.exe` (installer) | **ZIP:** unzip anywhere, run `Arqma-Wallet.exe` (keep all DLLs and `data\` beside the exe; `bin\arqmad.exe` and `bin\arqma_flutter_solo_pool.exe` for local daemon / solo pool). **Setup:** run installer, launch from Start menu. |
| **Linux** | `Arqma-Wallet-Flutter-5.1.1-linux-x64.tar.gz` and/or `Arqma-Wallet-Flutter-5.1.1-linux-x64.AppImage` | **tar.gz:** `tar xzf …tar.gz`, `cd` into folder, `./Arqma-Wallet` (or documented launcher). **AppImage:** `chmod +x *.AppImage`, `./Arqma-Wallet-Flutter-….AppImage`. |
| **macOS** | `Arqma-Wallet-Flutter-5.1.1-macos.zip` and/or `Arqma-Wallet-Flutter-5.1.1-macos.dmg` | Open **DMG**, drag **Arqma-Wallet.app** to Applications. If Gatekeeper blocks: `xattr -cr "/Applications/Arqma-Wallet.app"`. |
| **Android** | `Arqma-Wallet-Android-5.1.1-*.apk` (sideload), `Arqma-Wallet-Android-5.1.1-*.aab` (Play) | Install APK on device (unknown sources if needed). AAB is for Play Console upload only. |
| **iOS** | `Arqma-Wallet-Mobile-5.1.1-ios-testflight.ipa` (or development IPA) | TestFlight / Xcode install per your signing profile; not for solo mining (no solo pool on iOS). |

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
