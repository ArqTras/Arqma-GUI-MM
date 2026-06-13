# App Store Connect — upload-ready screenshots

Primary **iPhone 6.5" Display** set for version **5.1.2**.

Upload these three PNGs first (in order), then add optional screens from `../iphone_65_1284x2778/` if needed.

| Order | File | Screen |
|-------|------|--------|
| 1 | `iphone_65_1284x2778/01_splash.png` | App launch / loading with Arqma logo |
| 2 | `iphone_65_1284x2778/02_accounts.png` | Wallet list (Accounts) |
| 3 | `iphone_65_1284x2778/03_wallet.png` | Open wallet — balance & transactions |

## App Store Connect

1. [App Store Connect](https://appstoreconnect.apple.com) → **My Apps** → **Arqma Wallet** → **5.1.2** (or current version).
2. **App Store** tab → **Screenshots** → **iPhone 6.5" Display**.
3. Drag files from `upload_ready/iphone_65_1284x2778/` (1284×2778) or the parent folder (alt 1242×2688 also accepted).
4. Optional: **iPad 13" Display** — use matching files from `../ipad_13_2048x2732/`.
5. Save → submit for review when metadata is complete.

Regenerate: `./tool/generate_app_store_screenshots.sh`
