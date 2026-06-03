# Arqma Wallet Mobile — App Review information (Guideline 2.1)

**Purpose:** Copy-paste answers for **App Store Connect → App Review Information** and replies when Apple asks **Guideline 2.1 — Information Needed**. Keeps review notes consistent across resubmissions.

**App:** Arqma Wallet Mobile · **Bundle ID:** `com.arqma.arqmaWalletMobile`  
**Related:** [APP_STORE_PUBLICATION_REQUIREMENTS.md](./APP_STORE_PUBLICATION_REQUIREMENTS.md) · [APP_STORE_PRIVACY_DISCLOSURE.md](./APP_STORE_PRIVACY_DISCLOSURE.md)  
**Public mirror:** synced to [arqma/Flutter-Wallet](https://github.com/arqma/Flutter-Wallet/tree/main/docs) on each release (`build/ci/mirror-flutter-wallet-release.sh`).

**Last updated:** 2026-06-03

---

## 1. Where to paste this (before every review)

In **App Store Connect → App → App Store → [version] → App Review Information**:

| Field | What to enter |
|-------|----------------|
| **Sign-in required** | **No** |
| **User name** | Leave empty (no server account) |
| **Password** | Leave empty |
| **Contact phone / email** | Real person who can answer during review |
| **Notes** | Paste **§3** below (full block) |

After Apple sends a **Resolution Center** message, reply with **§4** (Transaction ID) or **§5** (purchase/sale + restore), as applicable.

---

## 2. Quick answers (Guideline 2.1)

### 2.1 Can users purchase or sell cryptocurrency in the app?

**No.**

- The app is a **non-custodial wallet** only (Apple Guideline **3.1.5(i)**).
- Users **do not** buy, sell, or swap crypto **for fiat** inside the app.
- There is **no** integrated exchange, broker, on-ramp, off-ramp, or payment processor.
- **Send** and **Receive** sign transactions **on device** and broadcast them to the Arqma network via a user-selected remote full node.
- Optional **swap / bridge** screens (if visible) are **user-initiated transaction signing** tools, not a custodial exchange or marketplace.
- **No In-App Purchase** unlocks crypto features.

### 2.2 How does the user restore an account?

There is **no publisher-hosted login**. An “account” is a **local wallet file** protected by a user-chosen password.

Restore options on the **Accounts** screen (dropdown menu):

| Menu item | Use |
|-----------|-----|
| **Restore account from seed** | Primary — 24/25-word mnemonic seed |
| **Restore account from viewkey** | View-only wallet (address + view key) |
| **Import account from file** | `.keys` wallet file from device storage |

**Typical restore (seed):**

1. Open app → **Accounts**.
2. Tap the **dropdown** (top) → **Restore account from seed**.
3. Enter **account name**, **mnemonic seed**, **password** (optional), confirm.
4. Leave **restore height** as default (app queries the remote node) unless advanced recovery is needed.
5. Tap **Restore Account** → wallet syncs from the remote Arqma node.

**Export seed (for backup / demo):**

1. **Create new account** (or open an existing wallet).
2. After create: copy the **seed words** on the confirmation screen, **or**
3. Open wallet → tap **account name / menu** (top) → **Show Private Keys** → enter wallet password → copy mnemonic.

**Remote node:** The app uses a public Arqma full node (default `node1.arqma.com:19994`, or user picks node1–node4 in **Settings**). Ensure network access during review.

### 2.3 What is “Transaction ID” and how does it work?

**Transaction ID** is the **on-chain transaction hash** (`txid`) of an Arqma (ARQ) blockchain transfer — the same public identifier used by block explorers and other wallets. It is **not** an Apple In-App Purchase ID, App Store receipt ID, or any payment-processor reference.

| Where in the app | What the user can do |
|------------------|----------------------|
| **Wallet → History** → **Filter by Transaction ID** | Type or paste a full or partial txid to **filter the local transaction list** (prefix match on transactions already synced to the device). |
| **History** → tap a row → **Transaction details** | View amount, fee, block height, timestamp, **Transaction ID**, optional Payment ID; **copy** the txid; open **View on explorer** (Safari → public block explorer). |
| **History** → long-press a row | **Copy Transaction ID** or **View on explorer** without opening the full details screen. |

**How it works technically:** After the wallet syncs with a remote Arqma full node, past transfers are stored locally. The filter compares the user’s input to each row’s `txid` string. No txid is sent to the publisher’s servers; filtering is **on device**. The app does **not** create, purchase, or sell anything via this field — it only helps users **find and verify** their own on-chain activity.

**Reviewer path (demo wallet):** Open **AppReviewDemo** → **History** → optional **Filter by Transaction ID** (empty list until the wallet has synced txs) → tap any row to see **Transaction id** and copy/explorer actions.

---

## 3. App Review Information — Notes (paste entire block)

```
Arqma Wallet Mobile — App Review notes (v5.1.1+)

ORGANIZATION & CATEGORY
• Non-custodial Arqma (ARQ) cryptocurrency wallet — Guideline 3.1.5(i).
• Submitted under an Apple Developer Organization account.
• Not a licensed exchange, ICO platform, on-device miner, or task-reward app.

SIGN-IN / ACCOUNTS
• No Sign in with Apple, email login, or publisher-hosted user accounts.
• Wallets exist only on device (app sandbox). Keys never sent to the publisher.

GUIDELINE 2.1 — TRANSACTION ID (blockchain tx hash, not IAP)
• "Transaction ID" = public Arqma blockchain transaction hash (txid) for a transfer.
• History → "Filter by Transaction ID" filters the local synced list (on-device prefix match).
• Transaction details / long-press: view, copy txid, or open public block explorer in Safari.
• Not used to buy/sell crypto; not an Apple or payment-processor transaction ID.

GUIDELINE 2.1 — PURCHASE / SALE OF CRYPTO
• Users CANNOT purchase or sell cryptocurrency in the app.
• No fiat on-ramp, off-ramp, order book, or custodial trading.
• Send/Receive are standard on-chain wallet operations signed locally.

GUIDELINE 2.1 — RESTORE ACCOUNT / DEMO
• Restore: Accounts → dropdown → "Restore account from seed" (24/25-word mnemonic).
• No server username/password. Demo below uses a local wallet password + mnemonic only.

DEMO — RESTORE A SPECIFIC ACCOUNT (recommended for reviewers)
Use this empty review-only wallet (no funds; safe for testing):

  Account name: AppReviewDemo
  Wallet password: AppReview2026
  Mnemonic seed (25 words):
  toaster tilt hire setup pipeline tanks woken hippo pioneer bugs revamp sake cunning giant inwardly tribal tolerant snake umbrella stunning wobbly yesterday ammo audio woken

Steps:
1. Launch app → complete welcome if shown → reach Accounts.
2. Dropdown → "Restore account from seed".
3. Enter name AppReviewDemo, paste mnemonic above, password AppReview2026.
4. Tap Restore Account → wait for sync (remote node required).
5. Open wallet to view balance/history/send/receive.

Alternative demo (no pre-shared seed):
1. Dropdown → "Create new account" → name ReviewTest, set password Review2026.
2. Copy seed from create screen OR wallet menu → "Show Private Keys".
3. Delete wallet from Accounts (long-press row → delete) or keep it.
4. Dropdown → "Restore account from seed" → paste copied seed → same password.

NETWORK
• Default remote nodes: node1–node4.arqma.com port 19994 (HTTP JSON-RPC).
• Settings → pick another node if one is slow.
• NSAppTransportSecurity allows custom node URLs for advanced users.

PRIVACY / ENCRYPTION
• No ads or third-party analytics SDKs.
• Optional Face ID stores wallet password in Keychain only when user enables it.
• Export compliance: standard encryption (HTTPS/TLS, OS crypto APIs).

CONTACT
• We monitor App Store Connect messages and the contact email/phone in this submission.
```

Replace `[PASTE YOUR REVIEW WALLET MNEMONIC HERE]` only if you rotate the demo wallet (see **§6**).

---

## 4. Resolution Center reply — Transaction ID (Guideline 2.1)

**Submission:** `2df0d11a-4f34-4bc5-b356-5ca08262a007` · **Version:** 5.1.1 (44) · **Review date:** 2026-06-03 · **Device:** iPad Air 11-inch (M3)

Paste as reply to Apple (English):

```
Hello App Review Team,

Thank you for your message regarding Guideline 2.1. Please find our answers about the "Transaction ID" feature below.

1) How does the "Transaction ID" feature of the app work?

"Transaction ID" refers to the public on-chain transaction hash (txid) of an Arqma (ARQ) blockchain transfer—the same identifier shown on public block explorers. It is not an Apple In-App Purchase ID or App Store receipt.

The feature appears in the wallet’s Transaction History:

• Filter by Transaction ID (History screen): The user can type or paste a full or partial txid. The app filters the wallet’s locally synced transaction list on the device (prefix match). No txid is uploaded to our servers.

• Transaction details: Tapping a history row opens a details screen showing amount, fee, block height, timestamp, Transaction ID, and optional Payment ID. The user can copy the txid or tap “View on explorer” to open the transaction in Safari on a public block explorer.

• Long-press on a history row: Quick actions to copy the Transaction ID or view it on the explorer.

Data comes from the user’s own wallet sync with a remote Arqma full node (user-configured; default public nodes node1–node4.arqma.com). The publisher does not host transaction lookup services.

2) What is this feature meant to allow the user to do?

It helps the user manage and verify their own non-custodial wallet activity:

• Find a specific past transfer in their history when they know (or partially know) the blockchain txid—for example after sending ARQ, receiving ARQ, or checking a transfer mentioned in support correspondence.

• Copy the txid to share with a counterparty, exchange withdrawal support, or block explorer lookup.

• Open the transaction on a public block explorer to independently verify amount, confirmations, and status on the Arqma network.

The app does not use Transaction ID to purchase or sell cryptocurrency, process payments, or unlock paid features. Send/Receive remain standard on-chain wallet operations signed on the device (Guideline 3.1.5(i)).

To test on iPad: restore demo wallet AppReviewDemo (see App Review notes), open History, and use Filter by Transaction ID or open any synced row’s details. An empty history simply means the demo wallet has no transactions yet; the filter and detail UI are still available.

Please let us know if you need a screen recording or additional details.

Best regards,
[Your name]
[Organization legal name]
```

---

## 5. Resolution Center reply — purchase / sale + restore (June 2026 template)

Paste as reply to Apple (English):

```
Hello App Review Team,

Thank you for your message. Please find our answers below.

1) Is the user able to purchase or sell cryptocurrency in the app?

No. Arqma Wallet Mobile is a non-custodial storage wallet only (Guideline 3.1.5(i)). The app does not allow users to purchase or sell cryptocurrency, does not operate an exchange or broker, and does not provide fiat on-ramps or off-ramps. Send and Receive are on-chain wallet functions that sign transactions on the device. There are no In-App Purchases for crypto features.

2) How does the user restore an account? Can you provide demo account information for restoring a specific account?

There is no publisher-hosted login. A wallet is restored locally using a mnemonic seed (or view key / file import).

Restore steps:
• Accounts → dropdown menu → "Restore account from seed"
• Enter account name, 24/25-word mnemonic, and wallet password
• Tap "Restore Account" — the app syncs via the configured remote Arqma node

Demo credentials for restore (empty review wallet, no funds):

  Account name: AppReviewDemo
  Wallet password: AppReview2026
  Mnemonic: toaster tilt hire setup pipeline tanks woken hippo pioneer bugs revamp sake cunning giant inwardly tribal tolerant snake umbrella stunning wobbly yesterday ammo audio woken

Alternative: create a new account, copy the seed via wallet menu → "Show Private Keys", then restore from that seed to verify the flow.

Remote nodes node1–node4.arqma.com:19994 should be reachable during review. No Sign-in is required.

Please let us know if you need a screen recording or additional details.

Best regards,
[Your name]
[Organization legal name]
```

---

## 6. Review demo wallet (pre-created, empty — no funds)

Use these credentials in App Store Connect **Notes** (§3) and Resolution Center replies (§4 / §5):

| Field | Value |
|-------|--------|
| **Account name** | `AppReviewDemo` |
| **Wallet password** | `AppReview2026` |
| **Mnemonic (25 words)** | `toaster tilt hire setup pipeline tanks woken hippo pioneer bugs revamp sake cunning giant inwardly tribal tolerant snake umbrella stunning wobbly yesterday ammo audio woken` |

**Restore test:** Accounts → dropdown → **Restore account from seed** → enter the fields above → **Restore Account** → wait for sync against `node1.arqma.com:19994` (or node2–node4 in Settings).

**Security:** Review-only wallet with **zero balance**. Rotate mnemonic periodically: create a new empty wallet, update this doc + App Store Connect notes, never fund the demo wallet.

### Rotate demo wallet (optional)

1. Install the release build (TestFlight or local IPA).
2. **Accounts** → dropdown → **Create new account** → name `AppReviewDemo`, password `AppReview2026`.
3. Copy **25-word seed** from the create screen or **Show Private Keys**.
4. Update **§3**, **§5**, and this table; paste the same text into App Store Connect.
5. Optionally delete locally and restore from seed to verify before submit.

---

## 7. iPad / iPhone

Review was performed on **iPad Air 11-inch (M3)**. UI is the same Flutter layout as iPhone; all flows above apply on iPad.

---

## 8. Change log

| Date | Change |
|------|--------|
| 2026-06-03 | Guideline 2.1 Transaction ID answers (Submission 2df0d11a, build 44, iPad Air M3) |
| 2026-06-03 | Pre-created AppReviewDemo wallet credentials; build 44 review notes |
| 2026-06-03 | Initial doc — Guideline 2.1 purchase/sale + restore/demo answers (Submission 0246e589) |
