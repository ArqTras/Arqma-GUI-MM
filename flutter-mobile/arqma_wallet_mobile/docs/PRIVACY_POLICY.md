# Arqma Wallet Mobile — Privacy Policy

**App name:** Arqma Wallet Mobile  
**Bundle ID (iOS):** `com.arqma.arqmaWalletMobile`  
**Last updated:** 2026-05-27  
**Publisher:** Arqma Project (distributed via [ArqTras/Arqma-GUI-MM](https://github.com/ArqTras/Arqma-GUI-MM))

This Privacy Policy describes how **Arqma Wallet Mobile** (“the App”, “we”) handles information when you use the non-custodial cryptocurrency wallet for the Arqma (ARQ) network on **iOS** and **Android**.

For Apple App Store privacy labels, publication checklist, and technical disclosure, see [APP_STORE_PRIVACY_DISCLOSURE.md](./APP_STORE_PRIVACY_DISCLOSURE.md) and [APP_STORE_PUBLICATION_REQUIREMENTS.md](./APP_STORE_PUBLICATION_REQUIREMENTS.md).

---

## 1. Summary

- The App is a **non-custodial wallet**: **private keys and wallet files stay on your device**. We do not operate a custodial service and do not receive your keys or passwords on our servers.
- The App connects to **Arqma network nodes** (remote RPC) that you choose or that are suggested by default, to read chain state and broadcast signed transactions.
- **Optional** features (Face ID / Touch ID, clipboard, camera/photos for QR, fiat price display, block explorer links) are described below. You can avoid optional features by not enabling them or not using related screens.
- The App does **not** include third-party advertising SDKs, analytics SDKs, or cross-app tracking for advertising.

---

## 2. What the App does (functions)

| Function | Description |
|----------|-------------|
| **Wallet management** | Create, restore, open, and close Arqma wallets stored locally on the device. |
| **Send / receive** | Build and sign transactions locally; relay signed data via the connected remote node. |
| **Transaction history** | Display transfers by syncing with the connected node and local wallet scan. |
| **Staking / service nodes** | Interact with Arqma staking features where supported by the wallet API. |
| **Address book** | Store labels and addresses locally in app configuration. |
| **Settings** | Remote node host/port, display language, inactivity timeout, transaction filter preferences. |
| **Biometric unlock (optional)** | Unlock with Face ID / Touch ID if you enable it and save your wallet password to the device secure store. |
| **QR codes** | Show receive QR; optional camera or photo library access to scan or import. |
| **Live Activity (iOS)** | Optional lock-screen / Dynamic Island progress during blockchain rescan (block heights only, no keys). |
| **Background sync (iOS)** | Limited background time to continue wallet sync when the app is backgrounded (see §5). |

The mobile app does **not** bundle a local `arqmad` daemon or solo mining pool (desktop-only features).

---

## 3. How the App connects to the network

### 3.1 Remote Arqma node (required for normal use)

- The App uses **HTTP JSON-RPC** to a **remote Arqma daemon** endpoint (`host` + port, default mainnet port **19994**).
- Default suggested hosts include community nodes such as `node1.arqma.com` … `node4.arqma.com`; you may change host/port in **Settings → Remote node**.
- Traffic includes: chain info (`get_info`), block height, and wallet-related RPC proxied to your **local in-process wallet** (native FFI). **Signed transactions** are sent to the node for propagation.
- Connections may use **cleartext HTTP** unless you configure a TLS-terminated endpoint yourself. The App’s iOS configuration allows arbitrary loads so user-defined node URLs can work; **you are responsible** for trusting your chosen node operator.

### 3.2 Public price APIs (optional, display only)

To show approximate **fiat value** of your balance, the App may request public market data from third-party HTTPS endpoints (e.g. CoinPaprika, TradeOgre, Blockchain.info). These requests **do not** include your wallet keys, addresses, or passwords. They may include your device’s IP address as with any HTTPS client.

### 3.3 Block explorer (optional)

Opening a transaction or address in an **external browser** uses URLs configured for Arqma / related explorers (e.g. `explorer.arqma.com`). Only the **transaction ID or address you choose** is passed to the browser.

### 3.4 No account on “Arqma Wallet servers”

Opening the App does **not** create a login account with the publisher. There is no central “Arqma Wallet” backend that stores your identity for authentication.

---

## 4. Data stored on your device

| Data | Where | Purpose |
|------|--------|---------|
| **Wallet files** (encrypted on disk per wallet password) | App sandbox documents (`arqma/`, `.arqma/` config) | Core wallet operation |
| **App settings** (language, remote node, filters, timeouts) | Local config files / preferences | Restore your choices |
| **Wallet password (optional)** | iOS Keychain / Android Keystore via `flutter_secure_storage` | Biometric unlock only if you enable it |
| **Biometric opt-in flags** | `SharedPreferences` | Remember that you enabled Face ID / Touch ID for a given wallet |
| **Live Activity state (iOS)** | App Group container `group.com.arqma.arqmaWalletMobile` | Show rescan/sync progress on lock screen (heights only) |

We do **not** upload your wallet files or seed to publisher servers as part of normal App operation.

---

## 5. Data processed when you use the App

### 5.1 On-device processing

- **Passwords** you enter are used locally to decrypt wallet files and to sign transactions; they are not sent to us.
- **Private keys** remain inside the native wallet library on the device during operation.

### 5.2 Sent to the remote node you connect to

When synced or sending funds, the remote node operator may see:

- Your wallet’s **public addresses** and **transaction data** needed to serve RPC and propagate txs (inherent to public blockchains).
- Your **IP address** and connection metadata (inherent to network TCP/HTTP).

The node operator is **not** the App publisher unless you connect to our suggested defaults; node policies vary by operator.

### 5.3 Clipboard (user-initiated)

If you copy an address or transaction ID, the OS clipboard is used. Other apps may read the clipboard depending on OS rules.

### 5.4 Camera and photo library (permission-based)

- **Camera:** scan QR codes (receive / import flows).
- **Photo library:** pick backup or QR images when you choose import from files/photos.

The App does not access camera or photos without the system permission prompt.

### 5.5 Background processing (iOS)

- **UIBackgroundTask** and **BGProcessingTask** (`com.arqma.arqmaWalletMobile.wallet-sync`) may run briefly to continue wallet heartbeat/sync when the app is backgrounded. No advertising or tracking runs in the background.

---

## 6. What we do not collect

- No sale of personal data.
- No third-party **advertising** or **analytics** SDKs (e.g. Firebase Analytics, Facebook SDK) in the App source as shipped.
- No **tracking** across other companies’ apps or websites for ads.
- No collection of contact lists, precise location, health, or browsing history.

---

## 7. Your choices and controls

| Choice | How |
|--------|-----|
| **Remote node** | Settings → change host/port or use your own node. |
| **Biometric unlock** | Optional; enable/disable per wallet in settings; requires password to configure. |
| **Face ID / camera / photos** | Deny or revoke in iOS Settings → Arqma Wallet Mobile → Privacy. |
| **Live Activity** | Disable in iOS Settings → Arqma Wallet Mobile → Live Activities, or when not scanning. |
| **Fiat price** | Balance still works; fiat line may show zero if price APIs fail or you are offline. |
| **Delete wallet data** | Remove wallet files from the app or uninstall the App (removes sandbox data). |
| **Inactivity lock** | App can auto-close wallet to account list after configurable idle time (does not delete files). |

---

## 8. Children

The App is not directed at children under 13 (or the minimum age in your region). We do not knowingly collect personal information from children.

---

## 9. Security

- Use a **strong wallet password** and secure your device (OS passcode, biometrics).
- **Backup** your seed or keys using official recovery procedures; loss of device without backup may mean loss of funds.
- **Verify** remote node hostnames and consider running your own node for maximum control.

---

## 10. International transfers

Blockchain nodes and public price APIs may be operated in various countries. By using the App you understand that network traffic may cross borders.

---

## 11. Changes

We may update this policy when the App changes. The “Last updated” date will be revised in this file in the repository. Continued use after changes constitutes acceptance of the updated policy.

---

## 12. Contact

For privacy questions about this App, open an issue or discussion on the project repository:  
https://github.com/ArqTras/Arqma-GUI-MM

For App Store distribution, the **seller** listed in App Store Connect is the data controller contact shown there.

---

## 13. Related documents

- [APP_STORE_PRIVACY_DISCLOSURE.md](./APP_STORE_PRIVACY_DISCLOSURE.md) — App Store Connect privacy questionnaire mapping and technical appendix for Apple review.
