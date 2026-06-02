# Arqma Wallet Mobile — App Store Privacy Disclosure

**Purpose:** Support **App Store Connect → App Privacy** (Privacy Nutrition Labels), **App Review** questions, and future compliance reviews for a **non-custodial cryptocurrency wallet**.

**Companion documents:** [PRIVACY_POLICY.md](./PRIVACY_POLICY.md) · [APP_STORE_PUBLICATION_REQUIREMENTS.md](./APP_STORE_PUBLICATION_REQUIREMENTS.md)  
**App:** Arqma Wallet Mobile · **Bundle ID:** `com.arqma.arqmaWalletMobile`  
**Last updated:** 2026-05-27

---

## A. App category and reviewer context

| Item | Value |
|------|--------|
| **Category** | Finance → Cryptocurrency wallet (non-custodial) |
| **Custody** | **Non-custodial** — keys and wallet files on device; publisher does not hold user funds |
| **Network** | Arqma (ARQ) mainnet via user-configurable **remote full node** (HTTP JSON-RPC) |
| **Local daemon** | **Not included** on iOS/Android (remote node only) |
| **Mining / solo pool** | **Not included** on mobile |
| **Third-party ads / analytics SDKs** | **None** in application source |

**Review note:** The App allows users to connect to **user-defined remote servers** (including HTTP). This is required for blockchain wallet operation, similar to other self-custody wallets that accept custom RPC endpoints.

---

## B. Recommended App Store Connect privacy answers

Use App Store Connect **App Privacy** (Manage App Privacy). Adjust if Apple’s questionnaire wording changes.

### B.1 Data collection summary

| Collects data? | Linked to user? | Used for tracking? |
|----------------|-----------------|-------------------|
| **Yes** (limited types below) | Mostly **No** for publisher; see per-type notes | **No** |

**Tracking (Apple definition):** The App does **not** use data for tracking across apps/websites owned by other companies for advertising or data brokerage.

### B.2 Data types (typical mapping)

| Apple data type | Collected? | Linked to identity? | Purpose (Apple categories) | Notes |
|-----------------|------------|---------------------|----------------------------|-------|
| **User ID** | No | — | — | No account system |
| **Name, email, phone** | No | — | — | |
| **Financial info** | **Yes** (on device + via node) | **No** (publisher) | App functionality | Balances, tx history shown in UI; not sent to publisher servers |
| **Payment info** | No | — | — | No card processing; on-chain txs only |
| **Cryptocurrency wallet address / transaction** | **Yes** | **No** (publisher) | App functionality | Public blockchain data; relayed to **user-chosen remote node** |
| **Precise location** | No | — | — | |
| **Coarse location** | No | — | — | |
| **Contacts** | No | — | — | |
| **Photos or videos** | **Optional** | No | App functionality | Only if user picks image / camera for QR or import |
| **Audio, gameplay, browsing history** | No | — | — | |
| **Search history** | No | — | — | |
| **Device ID** | No | — | — | No advertising ID usage in app code |
| **Product interaction** | No | — | — | No analytics SDK |
| **Crash data / performance** | No* | — | — | *Unless you later enable Apple crash sharing only via OS |
| **Other diagnostic** | No | — | — | |
| **Sensitive info** | **Yes** (on device) | No (publisher) | App functionality | Wallet password / keys processed **locally**; optional Keychain storage for biometrics |

**Financial Info / Crypto:** Declare as collected **for App Functionality**, **not** for analytics or marketing. State data is **not linked** to the user’s identity **by the publisher** (no publisher account). Data is **not used for tracking**.

### B.3 Third-party partners (data shared with)

| Partner type | Shared? | Data shared |
|--------------|---------|-------------|
| **Publisher backend** | No | — |
| **Remote Arqma node operator** | Yes (user-directed) | RPC traffic: addresses, txs, IP (inherent to node use) |
| **Coin price APIs** (HTTPS) | Optional | IP + HTTP request metadata only; no wallet secrets |
| **Block explorer** (browser) | User-initiated | Tx id / address user opens |
| **Apple** (Live Activity, Keychain, BG tasks) | Yes (OS services) | Per Apple platform; scan progress integers in App Group |

---

## C. Connection architecture (technical)

```
┌─────────────────────────────────────────────────────────────┐
│  Arqma Wallet Mobile (iOS / Android)                        │
│  ┌─────────────┐    ┌──────────────────┐                    │
│  │ Flutter UI  │───▶│ Native wallet FFI │  keys stay local  │
│  └─────────────┘    │ (wallet2 in-proc) │                    │
│         │           └────────┬─────────┘                    │
│         │                    │ JSON-RPC shaped calls        │
│         ▼                    ▼                              │
│  Local storage: wallet files, config, optional Keychain pwd   │
└────────────────────────────┬────────────────────────────────┘
                             │ HTTP JSON-RPC (user-configured)
                             ▼
              ┌──────────────────────────────┐
              │ Remote Arqma full node        │
              │ e.g. node1.arqma.com:19994    │
              │ (default or custom host/port) │
              └──────────────────────────────┘
                             │
                             ▼
              ┌──────────────────────────────┐
              │ Arqma peer-to-peer network    │
              └──────────────────────────────┘

Optional HTTPS (display only):
  • CoinPaprika, TradeOgre, Blockchain.info — ARQ/fiat ticker
Optional user action:
  • Safari / browser — block explorer URLs
```

### C.1 Default remote nodes

Built-in suggestions (mainnet, port **19994**):

- `node1.arqma.com`
- `node2.arqma.com`
- `node3.arqma.com`
- `node4.arqma.com`

User may override **host** and **port** in app settings. Traffic is **not** encrypted by the App unless the endpoint supports HTTPS (most public Arqma RPC uses HTTP).

### C.2 iOS-specific capabilities

| Capability | Identifier / key | Data |
|------------|------------------|------|
| **Face ID** | `NSFaceIDUsageDescription` | Local authentication only |
| **Camera** | `NSCameraUsageDescription` | QR scan |
| **Photo library** | `NSPhotoLibraryUsageDescription` | Import / QR from photos |
| **App Transport Security** | `NSAllowsArbitraryLoads` | Allows user-defined node URLs (incl. HTTP) |
| **Background processing** | `UIBackgroundModes: processing` | Wallet sync continuation |
| **BGTaskScheduler** | `com.arqma.arqmaWalletMobile.wallet-sync` | Periodic sync when granted by iOS |
| **Live Activities** | App Group `group.com.arqma.arqmaWalletMobile` | Block height progress (no keys) |
| **Extension** | `com.arqma.arqmaWalletMobile.RescanLiveActivity` | Live Activity UI |

---

## D. Permissions matrix (iOS Info.plist)

| Permission | Required? | When requested |
|------------|-----------|----------------|
| Face ID | Optional | Enabling biometric unlock |
| Camera | Optional | QR scan / import flows |
| Photo library (read) | Optional | Picking backup or QR image |
| Photo library (add) | Optional | Saving QR/export if user chooses |
| Local network | No special entitlement | Internet for RPC + HTTPS |
| Background fetch / processing | Optional | During wallet sync when backgrounded |

---

## E. User privacy choices (in-app)

Document these in App Review notes and support:

1. **Remote node** — Settings → Remote node host/port (user trust choice).
2. **Biometric unlock** — Off by default; per-wallet opt-in; password required to enable; stored in Keychain/Keystore.
3. **Inactivity** — Auto-return to account list (does not delete wallets); configurable timeout.
4. **Live Activity** — Only during scan; user can disable system-wide.
5. **No cloud backup** by publisher — user responsible for seed backup.
6. **Uninstall** — Removes app sandbox including wallets unless user backed up files elsewhere.

---

## F. App Privacy Policy URL (App Store Connect)

Host the public policy where Apple can reach it, for example:

- **GitHub raw / Pages:** link to `PRIVACY_POLICY.md` in this repository path:  
  `flutter-mobile/arqma_wallet_mobile/docs/PRIVACY_POLICY.md`
- Or mirror the same text on `arqma.com` / project website if required for production.

In **App Store Connect → App Information → Privacy Policy URL**, use the canonical HTTPS URL you publish.

---

## G. Reviewer notes (paste into App Review Information if needed)

For **Guideline 2.1** (purchase/sale, restore, demo account) use the full paste block in **[APP_STORE_REVIEW_INFORMATION.md](./APP_STORE_REVIEW_INFORMATION.md) §3**.

Short summary:

> Arqma Wallet Mobile is a non-custodial Arqma (ARQ) cryptocurrency wallet submitted under an **Apple Developer Organization** account (Guideline 3.1.5(i)). Private keys and wallet files remain on the device inside the app sandbox. The app connects to a user-selected remote Arqma full node over HTTP JSON-RPC (default community nodes on port 19994) to synchronize balances and broadcast signed transactions. Optional Face ID stores the wallet password only in the iOS Keychain when the user explicitly enables biometric unlock. Optional Live Activities show blockchain scan progress (block heights only). The app does not include advertising or third-party analytics SDKs. NSAppTransportSecurity allows arbitrary loads so advanced users can specify custom node URLs. No local blockchain daemon or on-device mining is included on mobile. The app is not a licensed cryptocurrency exchange, ICO platform, or task-reward program. **Users cannot purchase or sell cryptocurrency in the app.** Account restore uses a local mnemonic seed (Accounts → Restore account from seed); demo credentials are in APP_STORE_REVIEW_INFORMATION.md. Swap and staking features sign transactions locally; the publisher does not custody user funds.

---

## H. Change log

| Date | Change |
|------|--------|
| 2026-05-27 | Initial disclosure for App Store (5.1.1+, FFI 1.0.10, Live Activity, background sync) |
| 2026-05-27 | Reviewer notes: org account, not exchange/ICO/mining; link to publication requirements |
