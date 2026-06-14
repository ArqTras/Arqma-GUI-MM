## Arqma Wallet 5.1.2

Desktop and mobile bundles for tag **5.1.2**. Wallet FFI **[1.0.15](https://github.com/ArqTras/FFI/releases/tag/1.0.15)** (sync near tip, solo pool sidecar lifecycle + rewards). Desktop bundles rebuilt from this tag.

### Release refresh (2026-06-13)

- **Android FFI (1.0.15 republish):** [ArqTras/FFI 1.0.15](https://github.com/ArqTras/FFI/releases/tag/1.0.15) — Android-only asset refresh links **`__clear_cache`** in static-hybrid `libarqma_wallet_flutter_ffi.so` (fixes `dlopen` / “wallet backend not running” on restore). iOS, Linux, macOS, Windows, and solo-pool zips on FFI **1.0.15** unchanged.
- **Android:** **5.1.2+15** — APK/AAB rebuilt with refreshed FFI **1.0.15** Android prebuilts (`Arqma-Wallet-Android-5.1.2.apk` / `.aab` on this release page).
- **Windows (desktop):** `Arqma-Wallet-Flutter-5.1.2-windows-x64-Setup.exe` republished — Inno Setup uses the bundled `app_icon.ico`; portable ZIP unchanged.

### Highlights

- **Solo pool (desktop):** Fixed `submit_block` — Stratum miner nonce in the **block-header nonce field** (not `reserved_offset`). Block reward stored from template/`get_block`; `solo_pool_block_found` triggers transaction refresh; desktop notifications on accept/reject. Sidecar stops on wallet close and app exit (fixes orphaned `arqma_flutter_solo_pool` on Linux).
- **Wallet sync (desktop + mobile + Android):** FFI **1.0.15** — `TIP_BAND` 1 block; footer scan progress uses 1-block tip tolerance; refresh when sync stalls near tip; transaction history refreshes on balance change during catch-up.
- **Desktop Flutter:** **5.1.2+6** — republished with FFI **1.0.15** and updated solo pool sidecar.
- **iOS / mobile:** **5.1.2+55** (TestFlight) — locale switching fix (UA/ZH/JA), wallet names with spaces, iOS sync resume after background (Face ID + password dialog), store-before-reopen for wallet safety, full locale strings, brighter sync progress text. FFI **1.0.15**, no solo pool on mobile.
- **Android:** **5.1.2+15** — sideload APK/AAB from this release; requires FFI **1.0.15** Android prebuilts (June 2026 republish).

### TestFlight — What to Test (5.1.2 build 55)

Paste into App Store Connect → TestFlight → build **5.1.2 (55)** → **What to Test**.

**Language switching**
• Switch to Ukrainian, Chinese, or Japanese from the footer (tap the language label).
• UI must stay usable — no yellow warning icons instead of menus or filters.
• Tap **Reset to English** at the bottom of the language list, or switch to another language.
• Force-quit and reopen — selected language should load without breaking the UI.

**Wallet name with spaces**
• Create or restore a wallet named `Arqma Wallet` or `My Wallet`.
• Should succeed (stored as `Arqma_Wallet` / `My_Wallet`) — no “Invalid wallet name” error.
• Invalid characters (e.g. `/`, `..`) should still show a validation message before submit.

**Sync after backgrounding (iOS)**
• Open a password-protected wallet and start blockchain scan/sync.
• Background the app for several minutes, then return.
• With Face ID enabled: sync should resume after biometric unlock when possible.
• Without Face ID (or if biometric is cancelled): a **Continue syncing** password dialog should appear — enter the wallet password and sync should resume.
• Cancel the dialog — after another background/foreground cycle, the dialog should be offered again (not stuck forever).
• Wrong password shows an error — re-enter the correct password and sync should continue.
• Remote node status in the footer should reconnect without reinstalling the app.

**Sync progress readability**
• While scanning, footer and transaction list progress text should be easier to read on the dark theme.

**Smoke test**
• Open wallet → Transactions / Send / Receive.
• Change language once and return to English.
• Create a test wallet with a spaced name, then open it.

**Please report:** language menu stuck / warning triangles, cannot switch back from UA/ZH/JA, sync frozen after background, resume dialog never reappears after cancel, remote node stuck on “Connecting…”, or “Invalid wallet name” for normal names with spaces.

**What's New (short):** Fixes locale switching (UA/ZH/JA), wallet names with spaces, iOS sync resume after background (Face ID + password dialog), brighter sync progress text, and safer wallet session reopen.

### Desktop install (artifact names use slug `5.1.2`)

| OS | File | Notes |
|----|------|--------|
| **Windows** | `Arqma-Wallet-Flutter-5.1.2-windows-x64.zip` or `…-Setup.exe` | Portable ZIP or installer (Setup includes app icon) |
| **Linux** | `Arqma-Wallet-Flutter-5.1.2-linux-x64.tar.gz` and/or `…-x86_64.AppImage` | tar.gz or AppImage |
| **macOS (signed)** | `Arqma-Wallet-Flutter-5.1.2-macos-signed.zip` and/or `…-macos-signed.dmg` | **Developer ID** signed + **notarized** (local `package_flutter_release.sh` with `.notenv`). Preferred for end users. |
| **macOS (unsigned)** | `Arqma-Wallet-Flutter-5.1.2-macos-unsigned.zip` and/or `…-macos-unsigned.dmg` | **GitHub Actions CI** build (adhoc signature, not Developer ID). For developers or re-signing locally. |

### Mobile install

| OS | File | Notes |
|----|------|--------|
| **Android** | `Arqma-Wallet-Android-5.1.2.apk` or `.aab` | CI debug-signed APK for sideload; Play upload needs your keystore |
| **iOS** | `Arqma-Wallet-Mobile-5.1.2-ios-testflight.ipa` | TestFlight / sideload; see manifest on this release |

**macOS signed builds** are **Developer ID signed** and **notarized** when repo-root `.notenv` contains valid `SIGNING_APPLE_ID` + app-specific `SIGNING_APP_PASSWORD` (from [appleid.apple.com](https://appleid.apple.com)). **Unsigned** CI artifacts (`…-macos-unsigned.*`) are adhoc only.

**Full Changelog:** https://github.com/ArqTras/Arqma-GUI-MM/compare/5.1.1...5.1.2
