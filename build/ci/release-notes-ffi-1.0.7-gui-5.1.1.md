## Arqma Wallet FFI 1.0.7

Prebuilt **arqma-wallet-flutter-ffi** and **arqma_flutter_solo_pool** libraries for desktop and mobile, plus **Arqma Wallet 5.1.1** GUI bundles built against this FFI.

**GUI release:** [Arqma-GUI-MM 5.1.1](https://github.com/ArqTras/Arqma-GUI-MM/releases/tag/5.1.1)

### FFI fixes (1.0.7)

- **Stake**: `wallet2` `stakePending` expects a decimal coin amount string (9 fractional digits); the in-process RPC layer was forwarding raw atomic units, causing `"Incorrect amount"` for typical stake sizes (e.g. 100–1000 ARQ).

### Mobile (5.1.1 refresh)

- **Android:** Rebuilt APK/AAB with tx-history poll every **5 s** at chain tip, on new blocks, and immediately after send (`5.1.1+10`).
- **iOS:** Local build **5.1.1 (15)** — TestFlight IPA + xcarchive attached below (FFI **1.0.7**, ArqTras/FFI Latest).

### Solo pool (desktop — Windows, Linux, macOS)

Bundled in **5.1.1** desktop builds and available as `arqma-wallet-solo-pool-*-1.0.7.zip` for custom packaging.

- **Block submission:** Detect network-valid blocks using the same difficulty rule as universal nodejs-pool (`hashDiff`), not only a compact 4-byte target approximation.
- **Template refresh:** Pool respects **Automatic block template refresh** and the **interval (seconds)** from settings; when disabled, templates refresh on new chain height.
- **VarDiff defaults:** Start 60k, max 5M, retarget 30s, max jump 50% — adjust per your hashrate in Solo Pool settings.

### Native wallet (FFI)

- **Desktop:** Download `arqma-wallet-ffi-<platform>-1.0.7.zip` below, or use the full **5.1.1** Flutter bundles (FFI already included).
- **Android / iOS:** `arqma-wallet-ffi-android-*-1.0.7.zip` / `arqma-wallet-ffi-ios-1.0.7.zip` — mobile builds have **no** `arqma_flutter_solo_pool` sidecar.
- **Local build:** `rust/tool/build_native_wallet_flutter_ffi_*` in [Arqma-GUI-MM](https://github.com/ArqTras/Arqma-GUI-MM).

### Release assets (by platform)

| Platform | File(s) | How to run |
|----------|---------|------------|
| **Windows** | `Arqma-Wallet-Flutter-5.1.1-windows-x64.zip` (portable) or `Arqma-Wallet-Flutter-5.1.1-windows-x64-Setup.exe` (installer) | **ZIP:** unzip anywhere, run `Arqma-Wallet.exe`. **Setup:** run installer, launch from Start menu. |
| **Linux** | `Arqma-Wallet-Flutter-5.1.1-linux-x64.tar.gz` and/or `Arqma-Wallet-Flutter-5.1.1-x86_64.AppImage` | **tar.gz:** extract and run `./Arqma-Wallet`. **AppImage:** `chmod +x` and run. |
| **macOS** | `Arqma-Wallet-Flutter-5.1.1-macos.zip` and/or `Arqma-Wallet-Flutter-5.1.1-macos.dmg` | Open **DMG**, drag **Arqma-Wallet.app** to Applications. |
| **Android** | `Arqma-Wallet-Android-5.1.1.apk` (sideload), `Arqma-Wallet-Android-5.1.1.aab` (Play) | Install APK on device. AAB for Play Console. |
| **iOS** | `Arqma-Wallet-Mobile-5.1.1-ios-testflight.ipa`, `*-ios.xcarchive.zip`, `*-ios-manifest.txt` | **Transporter** / Xcode → App Store Connect (TestFlight). Build **15**, signing profile required. |

**FFI-only zips:** `arqma-wallet-ffi-<os>-1.0.7.zip`, `arqma-wallet-solo-pool-<os>-1.0.7.zip` (desktop solo pool only).

**Checksums:** `SHA256SUMS-gui-5.1.1.txt`, `SHA256SUMS-android-5.1.1.txt`, `SHA256SUMS-ios.txt`

### Solo pool quick start (desktop)

1. Use a **local** `arqmad` (not remote-only daemon).
2. Wallet → **Solo Pool** → enable pool, set mining address, bind IP/port.
3. Point **XMRig** at `stratum+tcp://<bind-ip>:3333` with your wallet address.
4. After changing VarDiff settings, **save and restart** the solo pool.

### macOS — Gatekeeper

```bash
xattr -cr "/Applications/Arqma-Wallet.app"
```

**FFI changelog:** https://github.com/ArqTras/FFI/compare/1.0.6...1.0.7

**GUI changelog:** https://github.com/ArqTras/Arqma-GUI-MM/compare/5.1.0...5.1.1
