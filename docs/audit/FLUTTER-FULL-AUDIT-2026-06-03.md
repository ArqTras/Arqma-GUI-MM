# Flutter Full Re-Audit — Arqma Wallet (ArqTras/Arqma-GUI-MM)

**Date:** 2026-06-03 (re-audit after `review` hardening)  
**Branch:** `review` (commits through `b03090e`)  
**Previous audit:** [FLUTTER-MULTIAGENT-AUDIT-2026-06-03.md](./FLUTTER-MULTIAGENT-AUDIT-2026-06-03.md)  
**Scope:** Flutter only — `flutter/arqma_wallet_gui` (Windows/Linux/macOS), `flutter-mobile/arqma_wallet_mobile` (iOS), `flutter-android/arqma_wallet_android` (Android), CI/FFI scripts  
**Out of scope:** Electron/Quasar/Vue, Rust/Tauri app  
**Repository:** https://github.com/ArqTras/Arqma-GUI-MM  

---

# ENGLISH REPORT

## 1. Executive summary

### 1.1 Status vs previous audit (2026-06-03 morning)

| Dimension | Previous | **Now (review)** | Delta |
|-----------|----------|------------------|-------|
| **Security** | Needs work | **Good** | Critical/High items #2–#4, #6 fixed; cleartext mitigated (#5 documented + UI) |
| **Stability** | Moderate | **Good** | Heartbeat mutex + `open_wallet` lane on desktop/mobile/android (#8, #9) |
| **Performance** | Moderate | **Good** | Desktop tab visibility ported (#12); footer uses `Selector` |
| **CI / release** | Needs work | **Moderate** | `flutter-test.yml` (analyze + test); Android signing wired (#7); FFI Latest policy unified (#11) |
| **Testing** | Weak | **Weak** | 5 desktop unit tests (+1); mobile/android placeholders only |
| **Cross-platform** | Good | **Good** | Shared fixes mirrored across three trees; path sanitize works on Linux CI |
| **Production readiness** | Conditional | **Ready for 5.1.1** with documented remote-node threat model; Android release needs GitHub signing secrets |

All GitHub audit issues **#2–#13 are CLOSED**. This re-audit tracks **residual** and **new** findings.

### 1.2 Architecture (unchanged strengths)

- **Three Flutter shells** share `core/desktop/*` FFI bridge, `GatewayStore` event model, and Tauri-parity wallet/daemon RPC semantics.
- **Desktop:** local `arqmad` + optional solo pool; wallet FFI in worker isolate (`wallet_ffi_isolate.dart`) with re-configure after reset.
- **Mobile / Android:** remote-node-only; preset + validated custom hosts; iOS background sync coordinator.
- **FFI supply chain:** intentional **GitHub Latest** [ArqTras/FFI](https://github.com/ArqTras/FFI/releases/latest) on all platforms via `build/ci/ensure-latest-ffi.*`; resolved tag stamped in `.prebuilt/arqma-wallet-ffi/.active-latest-version` and release manifests.

### 1.3 Verified fixes (evidence on `review`)

| ID | Topic | Status | Key files |
|----|-------|--------|-----------|
| R-001 | Stub env in release | **FIXED** | `flutter_env_guard.dart`, `native_bridge_resolver.dart` (all 3 apps) |
| R-002 | Password bypass | **FIXED** | `_walletPasswordOkForTx` always verifies digest; `promptForPassword` UI-only for `has_password` |
| R-003 | Path traversal | **FIXED** | `sanitizeWalletBaseName()` in `arqma_paths.dart`; used in open/create/import/restore |
| R-004 | Cleartext HTTP | **MITIGATED** | Wire still `http://`; `daemon_rpc_transport.dart` + footer/banner warnings |
| R-005 | Remote node validation | **FIXED** | `isValidMobileRemoteHost/Port`, picker + `apply_remote_node` + startup probe |
| R-006 | Android debug signing | **FIXED (code)** | `build.gradle.kts` + CI secrets; requires `ARQMA_ANDROID_KEYSTORE_*` in GitHub |
| R-007 | Mobile heartbeat race | **FIXED** | `_walletHbInFlight` in `mobile_native_bridge.dart` (+ android mirror) |
| R-008 | Concurrent open_wallet | **FIXED** | `_walletOpenLane` in desktop + mobile + android bridges |
| R-009 | CI test gate | **PARTIAL** | `flutter-test.yml`: analyze + test on **desktop only** |
| R-010 | FFI Latest | **POLICY** | By design; traceability via stamp + manifest, not semver pin |
| R-011 | Tab rebuild storm | **FIXED** | `wallet_tab_visibility.dart` + `watchGatewayStore()` on desktop wallet tabs |
| R-012 | Log redaction | **FIXED** | `redactBridgeArgs()` on `app_log_info` / `app_log_error` |
| R-013 | FFI path env override | **FIXED** | `flutterDebugEnvPath()` blocks `ARQMA_FLUTTER_WALLET_FFI` in release |

### 1.4 Local / CI verification (2026-06-03)

| Check | Result |
|-------|--------|
| `flutter analyze` (desktop) | **0 issues** |
| `flutter test` (desktop) | **5/5 pass** (incl. `wallet_safe_name_test` Linux-safe paths) |
| GitHub Actions `Flutter test` | **Green** on `review` after `45c0efc`, `b03090e` |

---

## 2. Residual & new risk register

| ID | Area | Severity | Status | Description | Evidence | Recommendation |
|----|------|----------|--------|-------------|----------|----------------|
| N-001 | CI | Medium | **FIXED** | Mobile/Android not in `flutter-test.yml` | Matrix: desktop + mobile (iOS tree) + android | — |
| N-002 | CI | Medium | **FIXED** | No `pubspec.lock` committed | Lock files from CI run 26879372063 | Keep in sync on pubspec.yaml changes |
| N-003 | CI | — | **WON'T FIX** | iOS build not in GitHub Actions | Manual `package_mobile_release.sh` | **By design** — no macOS/iOS Actions workflow; iOS tree covered by unit tests |
| N-004 | Security | Medium | **FIXED** | Debug env vars honored in release | Bridges + `arqma_executable_resolve` now use `flutter_env_guard` | — |
| N-005 | Security | Medium | **DOCUMENTED** | Biometric unlock stores session password | Threat model comment in `wallet_biometric_unlock.dart` | Token-based unlock optional future work |
| N-006 | Stability | Medium | **MITIGATED** | iOS background + foreground recovery overlap | `_walletSyncLane` serializes pulse/persist/recover | Monitor on device |
| N-007 | Performance | Low | **OPEN** | Non-tab widgets still `watch<GatewayStore>` | `swap_signature_list.dart`, dialogs, wallet-select pages | OK outside tabs; optional `Selector` |
| N-008 | Performance | Low | **OPEN** | UI double-tap open_wallet before bridge lane | `wallet_select_index_page.dart:255` — no UI `_openInFlight` | Optional UI debounce (bridge lane sufficient) |
| N-009 | Supply chain | Medium | **OPEN** | GitHub Dependabot: 23 vulnerabilities (default branch) | Push notifications from GitHub | Triage `file_picker`, transitive deps |
| N-010 | Maintainability | Medium | **OPEN** | Three duplicated trees (desktop/mobile/android) | ~59 files changed in review span 3 copies | Shared package / melos long-term |
| N-011 | Testing | High | **OPEN** | No integration / e2e tests | No `integration_test/` | `integration_test` smoke with stub FFI |
| N-012 | Dependencies | Low | **FIXED** | `file_picker` skew desktop `^8.1.4` vs mobile `^10.3.8` | Desktop aligned to `^10.3.8` | — |

---

## 3. Platform compatibility matrix

| Capability | Windows | Linux | macOS | Android | iOS |
|------------|---------|-------|-------|---------|-----|
| Wallet FFI Latest fetch | ✓ | ✓ | ✓ | ✓ | ✓ (via mobile tree) |
| Env stub block (release) | ✓ | ✓ | ✓ | ✓ | ✓ |
| Password digest gate | ✓ | ✓ | ✓ | ✓ | ✓ |
| Wallet name sanitize | ✓ | ✓ | ✓ | ✓ | ✓ |
| Heartbeat mutex | ✓ | ✓ | ✓ | ✓ | ✓ |
| open_wallet serialization | ✓ | ✓ | ✓ | ✓ | ✓ |
| Tab visibility (no HB rebuild) | ✓ | ✓ | ✓ | ✓ | ✓ |
| Remote node validation | n/a (local+remote) | n/a | n/a | ✓ | ✓ |
| Cleartext RPC warning | ✓ footer | ✓ | ✓ | ✓ banner | ✓ banner |
| Local arqmad / solo pool | ✓ | ✓ | ✓ | — | — |
| Release signing | Desktop unsigned zip/dmg | same | same | ✓ keystore CI | App Store manual |
| CI automated test | ✓ ubuntu | ✓ | ✓ | ✓ | ✓ (iOS tree, no device build) |

---

## 4. CI / release pipeline

| Workflow | Trigger | FFI policy | Tests | Notes |
|----------|---------|------------|-------|-------|
| `flutter-test.yml` | push/PR `main`, `review` | n/a | analyze + test **desktop + mobile (iOS tree) + android** | **Gate before merge**; no iOS build job |
| `desktop-release.yml` | tag / `main` | `ensure-latest-ffi` | none (relies on flutter-test) | Win/Linux/macOS artifacts |
| `android-release.yml` | tag / dispatch | `ensure-latest-ffi` via package script | none | Requires `ARQMA_ANDROID_KEYSTORE_*` secrets |

**FFI Latest policy (confirmed):** `build/ci/ensure-latest-ffi.sh` forces `ARQMA_FFI_RELEASE_VERSION=latest` unless `ARQMA_FFI_ALLOW_PIN=1` (emergency). Desktop wrapper `ensure-desktop-latest-ffi.*` delegates to unified script. Android manifest records resolved semver tag.

---

## 5. Testing inventory

| App | Test files | Real tests | Placeholder |
|-----|------------|------------|-------------|
| Desktop | 5 files | 7 cases (PBKDF2, address book, smoke, safe name ×2, redact ×2) | — |
| Mobile | 3 files | 8 cases (safe name ×2, remote nodes ×4, redact ×2) | — |
| Android | 3 files | 8 cases (same as mobile) | — |

**Gap:** no tests for `sanitizeWalletBaseName`, `isValidMobileRemoteHost`, `redactBridgeArgs`, bridge password logic in mobile tree.

---

## 6. Recommendations (priority)

### Immediate (before merge `review` → `main`)
1. Configure **Android signing secrets** in GitHub for `android-release` workflow.
2. Merge `review` — all audit issues addressed; CI green.

### Short-term (next sprint)
1. Extend **flutter-test** to mobile/android (at least analyze + placeholder replacement tests).
2. Commit **pubspec.lock** for all three apps.
3. Gate remaining debug env vars in release (`N-004`).
4. Triage **Dependabot** alerts.

### Medium-term
1. **Melos / shared package** for `core/desktop`, bridges, `gateway_store` (reduce triplication).
2. **integration_test** smoke (wallet select → stub open).
3. **iOS CI** on macOS runner — **not planned**; iOS release stays manual; iOS Dart code tested via `flutter-mobile` job.
4. TLS termination documentation for node operators (reverse proxy); optional `https://` probe fallback when daemons support it.

---

## 7. Production readiness verdict

**Verdict: APPROVED for 5.1.1 Flutter release** on `review` branch subject to:

- Android Play/sideload builds use configured release keystore in CI.
- Users informed that remote daemon sync uses **unencrypted HTTP** unless infra provides TLS.
- FFI builds always track **Latest** ArqTras/FFI — acceptable per project policy; manifest records resolved version.

Not claimed: “maximum security” until N-004, N-005, N-011 addressed and Dependabot triaged.

---

# RAPORT PL

## 1. Podsumowanie

Po hardeningu na branchu **`review`** (commity `e77f058` … `b03090e`) rozwiązanie Flutter osiąga **gotowość produkcyjną 5.1.1** z znanym modelem zagrożeń dla węzłów zdalnych.

| Obszar | Ocena | Komentarz |
|--------|-------|-----------|
| Bezpieczeństwo | **Dobre** | Naprawione #2–#4, #6; cleartext udokumentowany (#5) |
| Stabilność | **Dobra** | Mutex heartbeat, serializacja open_wallet |
| Wydajność | **Dobra** | Tab visibility na desktopie (#12) |
| CI | **Umiarkowane** | Testy tylko desktop; brak lock files |
| Testy | **Słabe** | 5 testów desktop; mobile/android — placeholdery |
| Cross-platform | **Dobre** | Poprawki w 3 drzewach; FFI Latest wszędzie |

Wszystkie issue audytu **#2–#13 zamknięte**.

## 2. Co naprawiono (skrót)

- Blokada stub / override FFI w release (`flutter_env_guard.dart`)
- Weryfikacja hasła PBKDF2 niezależnie od `promptForPassword`
- `sanitizeWalletBaseName()` — path traversal (także ścieżki Win/Unix na Linux CI)
- Walidacja custom remote nodes (mobile/android)
- `_walletHbInFlight`, `_walletOpenLane` (desktop + mobile + android)
- Redakcja logów bridge
- FFI **Latest** — polityka projektu, `ensure-latest-ffi.sh`
- Android release signing (Gradle + secrets CI)
- Ostrzeżenia cleartext w UI
- CI: `flutter analyze` + `flutter test`

## 3. Otwarte ryzyka (nowe / resztkowe)

| ID | Opis | Priorytet |
|----|------|-----------|
| N-001 | CI nie testuje mobile/android | **Naprawione** — matrix w Actions |
| N-002 | Brak pubspec.lock | **Naprawione** — locki z CI |
| N-003 | Brak iOS w Actions | **Zamierzone** — bez workflow iOS; testy iOS tree w CI |
| N-004 | Debug env w release | **Naprawione** (pełne pokrycie guard) |
| N-006 | iOS bg/fg overlap | **Złagodzone** (`_walletSyncLane`) |
| N-005 | Hasło w Keychain przy biometrii | **Udokumentowane** (threat model) |
| N-011 | Brak integration_test | Wysoki |
| N-009 | Dependabot 23 alertów | Średni |

## 4. Werdykt

**Merge `review` → `main` zalecany** po ustawieniu secretów Android w GitHub. Kolejna iteracja: rozszerzyć CI, lock files, testy mobile, shared package.

---

## Appendix: review branch commit log (audit-related)

| Commit | Summary |
|--------|---------|
| `a2a3863` | Initial multi-agent audit doc |
| `e77f058` | Security/stability hardening (#2–#4, #6, #8–#10, #13) |
| `287379e` | FFI Latest policy, tab visibility, cleartext, Android signing |
| `45c0efc` | Cross-platform path sanitize (Linux CI fix) |
| `b03090e` | CI analyze step; analyzer cleanup |

---

*Generated: 2026-06-03 — static analysis, codebase grep, local `flutter analyze`/`test`, CI run history on `review`.*
