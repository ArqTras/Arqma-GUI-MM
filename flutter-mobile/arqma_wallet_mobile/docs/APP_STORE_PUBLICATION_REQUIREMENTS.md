# Arqma Wallet Mobile — App Store publication requirements

**Purpose:** Checklist and compliance mapping for **production release** on the Apple App Store (not only TestFlight). Use together with [APP_STORE_PRIVACY_DISCLOSURE.md](./APP_STORE_PRIVACY_DISCLOSURE.md) and [PRIVACY_POLICY.md](./PRIVACY_POLICY.md).

**App:** Arqma Wallet Mobile · **Bundle ID:** `com.arqma.arqmaWalletMobile`  
**Live Activity extension:** `com.arqma.arqmaWalletMobile.RescanLiveActivity`  
**Last updated:** 2026-05-27

---

## 1. Eligibility summary

| Requirement | Arqma Wallet Mobile |
|-------------|---------------------|
| **App type** | Non-custodial **virtual currency storage** wallet (Guideline **3.1.5(i)**) |
| **Developer account** | **Organization** enrollment required for crypto wallets (not Individual) |
| **Exchange / CEX** | **No** — not a licensed exchange; users sign txs locally |
| **On-device mining** | **No** — mobile build has no mining daemon or pool sidecar |
| **ICO / securities** | **No** ICO, futures, or securities trading |
| **Task rewards** | **No** crypto for downloads, referrals, or social posts |
| **IAP for unlock** | **No** — wallet is free; no crypto/IAP unlock of features (3.1.1) |
| **Sign in with Apple** | **N/A** — no third-party login; local wallet password only |

Apple’s guidelines (updated **February 2026**) are authoritative: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) — especially **§3.1.5 Cryptocurrencies**, **§5.1 Privacy**, **§2.1 App completeness**.

---

## 2. Apple Developer Program (prerequisites)

### 2.1 Organization account (mandatory for 3.1.5(i))

- Enroll as an **Organization** (company / legal entity), not **Individual**.
- Provide **D-U-N-S** number, legal entity name, and website consistent with App Store Connect seller name.
- **Team ID** used in this repo for signing: see `ios/ExportOptions-appstore.plist` (`teamID`).

### 2.2 Certificates, identifiers, capabilities

| Item | Value / action |
|------|----------------|
| **App ID** | `com.arqma.arqmaWalletMobile` |
| **App Group** | `group.com.arqma.arqmaWalletMobile` (Live Activity + widget data) |
| **Extension** | Live Activity target `RescanLiveActivity` |
| **Distribution cert** | Apple Distribution for App Store |
| **Provisioning** | Automatic signing in Xcode / `upload_testflight.sh` |

### 2.3 Agreements & tax

- Accept latest **Paid Applications** / **Apple Developer Program License Agreement** in App Store Connect.
- Complete **banking and tax** forms if you ever sell paid IAP (not required for a free wallet today).

---

## 3. Guideline mapping (what reviewers check)

### 3.1 §3.1.5 Cryptocurrencies

| Sub-rule | Requirement | This app |
|----------|-------------|----------|
| **(i) Wallets** | Storage only; **organization** developer | ✅ Non-custodial ARQ wallet |
| **(ii) Mining** | No on-device mining | ✅ No miner; `_syncSoloPoolSidecar` is a no-op on mobile |
| **(iii) Exchanges** | Licensed exchange per region | ✅ **Not applicable** — not an exchange order book |
| **(iv) ICOs** | Banks / licensed firms only | ✅ Not offered |
| **(v) Rewards** | No crypto for tasks | ✅ No reward programs |

**Clarifications for review:**

- **Send / receive / staking / service nodes:** On-chain wallet operations signed on device; not a centralized exchange.
- **Swap screen:** User-initiated **cross-chain swap / bridge signing** (parity with desktop), not a custodial exchange or fiat on-ramp. Disclaimers in UI; no order matching or custody by publisher.
- **§3.1.5(viii) Financial trading:** Applies to **trading/investing/money-management apps submitted by the institution that holds licenses**. This app is **self-custody storage**, not a broker or investment advisor.

### 3.2 Other common rules

| Guideline | Notes |
|-----------|--------|
| **2.1** Completeness | Final build, working URLs, no placeholder privacy/support pages |
| **2.3.8** Metadata | Accurate description; no misleading “guaranteed returns” |
| **2.5.2** Software | Current Xcode / iOS SDK per Apple’s deadline announcements |
| **4.2** Minimum functionality | Wallet must work without crashing; remote node must be reachable |
| **5.1.1** Data collection | Privacy policy URL + in-app disclosure |
| **5.1.2** Data use | App Privacy labels match behavior ([disclosure doc](./APP_STORE_PRIVACY_DISCLOSURE.md)) |
| **5.1.4** Kids | Not directed at children; age rating should reflect finance/crypto |

---

## 4. App Store Connect — metadata checklist

Complete **before** submitting for App Review (production).

| Field | Guidance |
|-------|----------|
| **Name** | Arqma Wallet (or product name; ≤30 chars) |
| **Subtitle** | Short value prop, e.g. non-custodial ARQ wallet |
| **Primary category** | **Finance** |
| **Secondary category** | Optional (e.g. Utilities) |
| **Privacy Policy URL** | Public **HTTPS** — see [§7](#7-privacy-policy-hosting) |
| **Support URL** | Working page (FAQ, contact, or GitHub issues) |
| **Marketing URL** | Optional — project site |
| **Copyright** | e.g. `2026 Arqma Project` |
| **Description** | Plain language: non-custodial, remote node, no custody, risks |
| **Keywords** | arqma, wallet, cryptocurrency, ARQ (no competitor trademarks) |
| **What's New** | Per release (build number / fixes) |
| **Screenshots** | See `store_assets/app_store/README.md` |
| **App Review contact** | Phone + email that Apple can reach |
| **Demo account** | **Not required** (no server account) — see [§6](#6-app-review-submission) |

### 4.1 Age rating (questionnaire)

Answer honestly in App Store Connect. Typical choices for a crypto wallet:

- **Gambling / contests:** No (unless you add such features).
- **Unrestricted web access:** Often **No** (in-app browser only for user-opened explorer links).
- **Made for kids:** **No**.
- **Financial features:** Indicate cryptocurrency / money-related features per questionnaire wording.

Result is often **17+** or **12+** depending on answers; re-run when features change.

### 4.2 App Privacy (nutrition labels)

Follow **[APP_STORE_PRIVACY_DISCLOSURE.md](./APP_STORE_PRIVACY_DISCLOSURE.md) §B** — declare financial/crypto data for **App Functionality**, **not** tracking.

### 4.3 Export compliance (encryption)

The app uses encryption (HTTPS, wallet cryptography, Keychain).

| Step | Action |
|------|--------|
| **App Store Connect → build** | When asked “Is your app designed to use encryption?” → **Yes** |
| **Exempt?** | Typically **Yes** — app qualifies for **standard encryption** exemption (HTTPS/TLS, OS crypto APIs) under U.S. export rules; **no** proprietary non-standard cipher for government review |
| **Annual self-classification** | File **CCATS / exemption** in Apple Developer account if prompted (many wallets use exemption documentation only) |

Document internally: FFI wallet uses standard algorithms (same family as Monero-style wallets); no custom escrow of keys on publisher servers.

### 4.4 Content rights & third-party content

- You have rights to **Arqma** branding and app assets.
- Do not imply **Apple endorsement**.
- Trademarks: follow [Apple trademark guidelines](https://developer.apple.com/support/terms/) for “App Store”, “iPhone”, etc. in marketing only.

---

## 5. Build & upload checklist

### 5.1 Versioning

- **Marketing version** + **build number:** `pubspec.yaml` (`version: x.y.z+build`).
- Each App Store upload needs a **new build number**.

### 5.2 Build commands (repo)

```bash
cd flutter-mobile/arqma_wallet_mobile
./tool/upload_testflight.sh
```

This script:

1. Prepares iOS FFI (`tool/prepare_ios_wallet_ffi.sh`).
2. `flutter build ipa` with `ios/ExportOptions-appstore-export.plist`.
3. Verifies **FFI is embedded as `.framework`** (avoids **ITMS-90426** loose dylib).
4. Uploads via `xcodebuild -exportArchive` and `ExportOptions-appstore.plist`.

### 5.3 Pre-upload verification

| Check | How |
|-------|-----|
| Release mode, no debug banners | Install TestFlight build on device |
| Wallet create / open / send / history | Manual smoke test |
| Remote node default or custom | Settings → node |
| Face ID flow | Optional path |
| Live Activity | During rescan (optional) |
| Crash-free cold start | Launch after kill |
| Symbols | `uploadSymbols` is `false` in export plist — accept or enable if you need symbolicated crash reports from Apple |

### 5.4 TestFlight → production

1. Upload build → wait for **Processing** → **Missing compliance** (export) → answer encryption questions.
2. **Internal testing** → fix blockers.
3. **External TestFlight** (optional) → beta review (lighter).
4. Attach build to **App Store** version → **Submit for Review**.

---

## 6. App Review submission

### 6.1 Demo account (Guideline 2.1)

There is **no publisher-hosted user account**. Provide in **App Review Information → Notes**:

1. Install app → **Create wallet** or **Restore** with test seed (reviewer may create empty wallet).
2. Ensure **default remote nodes** (`node1`–`node4.arqma.com:19994`) are online during review.
3. Optional: supply a **view-only** or low-value wallet address for screenshots consistency (never send mainnet high-value seeds in notes).

Offer **built-in demo mode** only if Apple requests it and legal/security allow it.

### 6.2 Reviewer notes (paste)

Use the block in **[APP_STORE_PRIVACY_DISCLOSURE.md](./APP_STORE_PRIVACY_DISCLOSURE.md) §G**, plus:

> Organization developer. App does not mine on device, operate a custodial exchange, or offer ICOs. Swap/staking are on-chain wallet features with user-held keys. Publisher does not receive wallet passwords or keys.

### 6.3 Attachments

- **Video:** Optional; only if flows are non-obvious.
- **Hardware:** Not required (iPhone only).

### 6.4 Common rejection themes & mitigations

| Risk | Mitigation |
|------|------------|
| Individual developer account | Switch to **Organization** before production submit |
| Mislabeled as exchange | Metadata + review notes: **non-custodial wallet** |
| Broken support / privacy URL | Host HTTPS pages before submit |
| Incomplete functionality | Test against live Arqma nodes |
| ATS / arbitrary HTTP loads | Explain custom RPC URLs in review notes (already in §G) |
| Missing purpose strings | Camera / Face ID / Photos strings in `Info.plist` |
| Background modes misuse | `processing` + BGTask only for wallet sync; document in notes |
| Guideline 3.1.1 IAP | Do not gate wallet features behind non-IAP crypto payments |

---

## 7. Privacy policy hosting

App Store Connect requires a **public HTTPS Privacy Policy URL**.

| Option | Steps |
|--------|--------|
| **GitHub Pages** | Publish `docs/PRIVACY_POLICY.md` (rendered HTML or static site) on `https://<org>.github.io/...` |
| **Project domain** | Mirror same text at `https://arqma.com/privacy` (or equivalent) |

Keep URL stable across releases; update **Last updated** in the markdown when practices change.

---

## 8. Legal & regional distribution (operator responsibility)

Apple does not replace legal counsel. Before enabling countries:

- Confirm **non-custodial wallet** status in target jurisdictions.
- **No fiat money transmission** by publisher if you do not hold licenses.
- **Sanctions / export** lists: do not promote use in embargoed regions if restricted by your policy.
- **Consumer warnings:** Volatile assets, irreversible transactions, user responsible for seed backup — belong in description and/or in-app (many wallets do both).

Use **App Store Connect → Pricing and Availability** to limit territories if needed.

---

## 9. Post-approval maintenance

| Event | Action |
|-------|--------|
| New data collection / SDK | Update privacy policy + App Privacy labels |
| New permissions | Update `Info.plist` usage strings + disclosure doc |
| Apple guideline changes | Re-read §3.1.5 yearly |
| Security incident | Rotate nodes/docs; expedited review if needed |
| FFI / wallet RPC changes | Regression test rescan, send, background sync |

---

## 10. Document index

| Document | Use |
|----------|-----|
| [APP_STORE_PUBLICATION_REQUIREMENTS.md](./APP_STORE_PUBLICATION_REQUIREMENTS.md) | This checklist — publication & review |
| [APP_STORE_PRIVACY_DISCLOSURE.md](./APP_STORE_PRIVACY_DISCLOSURE.md) | Privacy labels + technical disclosure |
| [PRIVACY_POLICY.md](./PRIVACY_POLICY.md) | End-user policy (host publicly) |
| [store_assets/app_store/README.md](../store_assets/app_store/README.md) | Screenshot sizes and regeneration |

---

## 11. Change log

| Date | Change |
|------|--------|
| 2026-05-27 | Initial publication requirements (Guideline 3.1.5 org wallet, Connect metadata, export, review, build pipeline) |
