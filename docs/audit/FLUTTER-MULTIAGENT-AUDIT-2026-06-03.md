# Flutter Multi-Agent Audit — Arqma Wallet (ArqTras/Arqma-GUI-MM)

**Date:** 2026-06-03  
**Branch:** `review`  
**Scope:** Flutter only — `flutter/arqma_wallet_gui`, `flutter-mobile/arqma_wallet_mobile`, `flutter-android/arqma_wallet_android`, Flutter CI/FFI scripts  
**Out of scope:** Electron/Quasar/Vue, Rust/Tauri app (excluded per audit charter)  
**Repository:** https://github.com/ArqTras/Arqma-GUI-MM  

---

# ENGLISH REPORT

## 1. Executive summary

### 1.1 One-page status

| Dimension | Rating | Notes |
|-----------|--------|-------|
| **Architecture** | Good | Three Flutter shells share bridge/FFI patterns; desktop uses worker isolate + ArqTras/FFI prebuilts; mobile remote-node model is clear |
| **Security** | **Needs work** | Critical stub env; password prompt conflated with crypto gate; cleartext daemon RPC; path traversal in wallet names |
| **Stability** | **Moderate** | Desktop improved (FFI re-configure after reset); mobile heartbeat/open races remain |
| **Performance** | **Moderate** | Desktop tab rebuild storm; large tx list O(n) equality checks |
| **CI / release** | **Needs work** | No Flutter tests in CI; Android release debug-signed; desktop FFI “Latest” non-reproducible |
| **Testing** | **Weak** | 3 real desktop unit tests; mobile widget tests are placeholders; no integration_test |
| **Production readiness** | **Conditional** | Suitable for **5.1.1** with informed users + remote nodes over TLS at infra layer; **not** “maximum security” until Critical/High issues closed |

### 1.2 Top risks

1. **Stub backend via env** in release builds ([#2](https://github.com/ArqTras/Arqma-GUI-MM/issues/2)) — Critical  
2. **Password bypass** when `promptForPassword` disabled ([#3](https://github.com/ArqTras/Arqma-GUI-MM/issues/3)) — High  
3. **Wallet filename path traversal** ([#4](https://github.com/ArqTras/Arqma-GUI-MM/issues/4)) — High  
4. **Cleartext daemon HTTP** ([#5](https://github.com/ArqTras/Arqma-GUI-MM/issues/5)) — High  
5. **Unvalidated custom remote nodes** ([#6](https://github.com/ArqTras/Arqma-GUI-MM/issues/6)) — High  
6. **Android release debug signing** ([#7](https://github.com/ArqTras/Arqma-GUI-MM/issues/7)) — High  
7. **Mobile heartbeat / open_wallet races** ([#8](https://github.com/ArqTras/Arqma-GUI-MM/issues/8), [#9](https://github.com/ArqTras/Arqma-GUI-MM/issues/9)) — High  
8. **No CI test gate** ([#10](https://github.com/ArqTras/Arqma-GUI-MM/issues/10)) — High  
9. **Non-reproducible FFI Latest** ([#11](https://github.com/ArqTras/Arqma-GUI-MM/issues/11)) — High  

### 1.3 Recommended next steps

1. **Immediate:** Fix #2, #3, #4; block stub env in release; sanitize wallet names; decouple password prompt from crypto verification.  
2. **This sprint:** #8, #9, #10; port desktop heartbeat mutex to mobile; serialize `open_wallet`; add CI `flutter test`.  
3. **Release hardening:** #7 Android signing; #11 pin FFI in release manifest; desktop checksums + signing roadmap.  
4. **Document threat model:** #5/#6 cleartext remote nodes — UI warnings + TLS at node operator side.

---

## 2. Risk register

| ID | Area | Severity | Likelihood | Impact | Description | Evidence | Fix | Effort | Issue |
|----|------|----------|------------|--------|-------------|----------|-----|--------|-------|
| R-001 | Security | Critical | Medium | Total loss of funds trust | Stub wallet via `ARQMA_FLUTTER_USE_STUB` | `native_bridge_resolver.dart:14-16` | Ignore in release | S | [#2](https://github.com/ArqTras/Arqma-GUI-MM/issues/2) |
| R-002 | Security | High | High | Key export without auth | `promptForPassword` skips verify | `mobile_native_bridge.dart:2982-2987` | Always verify via FFI | M | [#3](https://github.com/ArqTras/Arqma-GUI-MM/issues/3) |
| R-003 | Security | High | Medium | Files outside wallet dir | Unsanitized `filename` | `mobile_native_bridge.dart:4803-4805` | basename + jail | S | [#4](https://github.com/ArqTras/Arqma-GUI-MM/issues/4) |
| R-004 | Security | High | Medium | MITM daemon metadata | HTTP JSON-RPC | `daemon_json_rpc.dart:147-149` | TLS / pin / warn | L | [#5](https://github.com/ArqTras/Arqma-GUI-MM/issues/5) |
| R-005 | Security | High | Medium | Malicious remote node | Dead whitelist | `mobile_remote_nodes.dart:40` | Enforce or TLS | M | [#6](https://github.com/ArqTras/Arqma-GUI-MM/issues/6) |
| R-006 | Supply chain | High | Certain | Play/sideload trust | Debug release signing | `build.gradle.kts:41-46` | Release keystore | M | [#7](https://github.com/ArqTras/Arqma-GUI-MM/issues/7) |
| R-007 | Stability | High | High | Corrupt FFI session | Mobile HB no mutex | `mobile_native_bridge.dart:~2392` | Port `_walletHbInFlight` | S | [#8](https://github.com/ArqTras/Arqma-GUI-MM/issues/8) |
| R-008 | Stability | High | Medium | Failed open / -4 | Concurrent open | `wallet_select_index_page.dart:255-311` | Open lock | M | [#9](https://github.com/ArqTras/Arqma-GUI-MM/issues/9) |
| R-009 | QA/CI | High | Certain | Regressions ship | No `flutter test` in CI | `desktop-release.yml` | Test job | S | [#10](https://github.com/ArqTras/Arqma-GUI-MM/issues/10) |
| R-010 | Release | High | Medium | Audit/repro failure | FFI always Latest | `desktop-release.yml:43` | Pin + manifest | M | [#11](https://github.com/ArqTras/Arqma-GUI-MM/issues/11) |
| R-011 | Performance | Medium | High | UI jank | Desktop tab rebuilds | `wallet_tab_body.dart` | Tab visibility | M | [#12](https://github.com/ArqTras/Arqma-GUI-MM/issues/12) |
| R-012 | Observability | Medium | Low | Secret in logs | invoke debugPrint | `desktop_native_bridge.dart:~618` | Redact | S | [#13](https://github.com/ArqTras/Arqma-GUI-MM/issues/13) |
| R-013 | Security | Medium | Low | DLL hijack | `ARQMA_FLUTTER_WALLET_FFI` | `wallet_native_ffi.dart:251` | Release ignore | S | — |
| R-014 | Security | Medium | Medium | Keychain exposure | Biometric plaintext pwd | `wallet_biometric_unlock.dart:34-38` | Harden accessibility | M | — |
| R-015 | Stability | Medium | Medium | iOS wake races | bg pulse + recover | `mobile_background_wallet_sync.dart` | Single coordinator | M | — |
| R-016 | Performance | High | Medium | Slow cold start | sync init desktop | `main.dart:49-69` | Splash deferred init | M | — |
| R-017 | CI | Medium | Medium | Drift deps | No pubspec.lock | `pubspec.yaml` | Lock + audit | S | — |
| R-018 | CI | Medium | Low | iOS manual only | No ios workflow | `package_mobile_release.sh` | macOS CI or gate | L | — |

---

## 3. Findings by team role

### 3.1 Lead architect
- **Checked:** Three-app layout, FFI isolate worker, gateway store, remote vs local daemon, shared mobile/desktop bridges.  
- **Found:** Strong parity with legacy Tauri concepts via `GatewayStore` events; duplication across three trees (desktop / mobile / android).  
- **Risky:** Ownership boundaries between Dart bridge, FFI worker, and Rust `wallet2_client` error messages; “Latest” FFI policy vs tagged releases.  
- **Recommend:** Single shared package for `core/desktop/*` bridges; release manifest JSON (git tag + FFI tag + Flutter build).

### 3.2 Senior Flutter/Desktop engineer
- **Checked:** `desktop_native_bridge.dart`, FFI isolate, CMake install, Windows MinGW DLL layout.  
- **Found:** Re-configure after reset (recent fix) resolves `-4` retries; worker isolate + 8MiB stack pthread in FFI 1.0.14.  
- **Risky:** FFI fallback to UI thread; daemon heartbeat without in-flight guard; cold start blocks first frame.  
- **Recommend:** [#9](https://github.com/ArqTras/Arqma-GUI-MM/issues/9), [#12](https://github.com/ArqTras/Arqma-GUI-MM/issues/12); fail if isolate unavailable in release.

### 3.3 Application security engineer
- **Checked:** Stub env, IPC invoke, secure storage, clipboard, logs, env flags.  
- **Found:** [#2](https://github.com/ArqTras/Arqma-GUI-MM/issues/2)–[#6](https://github.com/ArqTras/Arqma-GUI-MM/issues/6), [#13](https://github.com/ArqTras/Arqma-GUI-MM/issues/13).  
- **Recommend:** Release-mode env denylist; redacting logger; threat model doc for daemon trust.

### 3.4 Cryptocurrency wallet security reviewer
- **Checked:** Seed display, private keys RPC, password flows, export, remote node privacy.  
- **Found:** Password prompt ≠ crypto gate ([#3](https://github.com/ArqTras/Arqma-GUI-MM/issues/3)); cleartext sync metadata ([#5](https://github.com/ArqTras/Arqma-GUI-MM/issues/5)).  
- **Recommend:** Monero-style trusted daemon docs; optional user-run node; never log mnemonics.

### 3.5 Supply chain / dependencies auditor
- **Checked:** pubspec, FFI fetch scripts, CI pins, Android signing.  
- **Found:** [#7](https://github.com/ArqTras/Arqma-GUI-MM/issues/7), [#11](https://github.com/ArqTras/Arqma-GUI-MM/issues/11); no `pubspec.lock`; `file_picker` version skew desktop vs mobile.  
- **Recommend:** Lockfiles; `dart pub audit` in CI; SHA256SUMS for desktop bundles (Android has sums).

### 3.6 Performance engineer
- **Checked:** Heartbeat intervals, tx list filtering, tab rebuilds, merge on UI isolate.  
- **Found:** [#12](https://github.com/ArqTras/Arqma-GUI-MM/issues/12); O(n) `_txListChangeToken`; receive page eager list.  
- **Recommend:** Selector snapshots everywhere; `compute()` for merge; lazy address list.

### 3.7 Reliability engineer
- **Checked:** Daemon restart, wallet open/close, iOS background, timeouts.  
- **Found:** [#8](https://github.com/ArqTras/Arqma-GUI-MM/issues/8), [#9](https://github.com/ArqTras/Arqma-GUI-MM/issues/9); `closeWalletSession` timeout swallowed.  
- **Recommend:** Hard FFI reset after close timeout; daemon restart debounce.

### 3.8 QA automation lead
- **Checked:** `test/` dirs, CI workflows.  
- **Found:** [#10](https://github.com/ArqTras/Arqma-GUI-MM/issues/10); placeholder mobile tests.  
- **Recommend:** See §6 Test strategy.

### 3.9 DevOps / CI / release engineer
- **Checked:** `desktop-release.yml`, `android-release.yml`, mirror script, FFI fetch.  
- **Found:** [#10](https://github.com/ArqTras/Arqma-GUI-MM/issues/10), [#11](https://github.com/ArqTras/Arqma-GUI-MM/issues/11); Flutter 3.41.9 desktop vs stable channel Android.  
- **Recommend:** Unified Flutter pin; test job; release signing secrets.

### 3.10 Packaging (Windows/macOS/Linux)
- **Checked:** `package_flutter_release.ps1`, `verify_windows_bundle.ps1`, Inno Setup, AppImage.  
- **Found:** MinGW DLL flat layout documented; FFI install CMake; solo pool + arqmad bundled.  
- **Recommend:** Desktop SHA256SUMS in CI; Authenticode/macOS notarize roadmap.

### 3.11 UX / a11y / i18n reviewer
- **Checked:** 12 locales, wallet flows, error messages, App Store review doc.  
- **Found:** Hardcoded strings (`arqma_field.dart` “Paste”, swap page); good i18n coverage via `en-US.json` (~5492 lines).  
- **Recommend:** `sync_locale_json.mjs` in CI; improve open_wallet error surfacing (was generic `basic_string` before FFI 1.0.14).

### 3.12 Observability engineer
- **Checked:** `debugPrint`, `developer.log`, daemon logs.  
- **Found:** [#13](https://github.com/ArqTras/Arqma-GUI-MM/issues/13); no crash analytics SDK (acceptable for privacy).  
- **Recommend:** User-exportable diagnostic bundle with redaction; log level from Settings.

### 3.13 Code quality / maintainability
- **Checked:** File sizes (`desktop_native_bridge.dart` 4600+ lines), duplication mobile/android.  
- **Found:** Large god-modules; shared logic copied 3×.  
- **Recommend:** Extract `wallet_heartbeat.dart` mixin; path package for shared core (long-term).

---

## 4. Priority remediation plan

| Horizon | Items |
|---------|--------|
| **Immediate (hotfix)** | #2 stub block; #3 password gate; #4 path sanitize |
| **Short-term (1–2 sprints)** | #8 #9 stability; #10 CI tests; #13 log redaction; mobile/desktop Flutter pin parity |
| **Medium-term (1–2 months)** | #5/#6 TLS/warnings; #7 Android signing; #11 FFI pin manifest; #12 perf; shared core package |
| **Long-term** | iOS CI workflow; notarize/sign all platforms; integration_test suite; monorepo melos |

---

## 5. Dependency & toolchain update plan

| Step | Change | Risk | Tests before merge |
|------|--------|------|---------------------|
| 1 | Pin Flutter **3.41.9** on Android CI | Low | `flutter test` desktop |
| 2 | Commit `pubspec.lock` (3 apps) | Low | CI `--enforce-lockfile` |
| 3 | Align `file_picker` versions | Medium | File import flows all platforms |
| 4 | `dart pub outdated` quarterly | Medium | Full smoke + open wallet |
| 5 | Flutter **3.42+** when stable | Medium | FFI rebuild all platforms |
| 6 | Bump `go_router` 14→17 | High | Navigation regression E2E |

**Safe now:** Flutter 3.41.9 pin, lockfiles, `dart pub audit`  
**Medium risk:** file_picker alignment, FFI patch releases  
**High risk:** go_router major, Flutter engine bump without FFI rebuild

---

## 6. Test strategy

### 6.1 Add first (highest ROI)
1. CI job: `flutter test` in `flutter/arqma_wallet_gui/test/` ([#10](https://github.com/ArqTras/Arqma-GUI-MM/issues/10))  
2. Unit: wallet name sanitization (new tests)  
3. Unit: `_walletPasswordOkForTx` behavior with mock config  
4. Widget: wallet select disables double-tap while loading  

### 6.2 Mocking
- **Wallet RPC:** `StubNativeBridge` / fake `ArqmaWalletRpcSession` injecting JSON responses  
- **Daemon:** mock `DaemonJsonRpc.getInfo` returning fixed height  

### 6.3 Critical E2E scenarios
- Create → open → send (testnet/stagenet)  
- Restore seed → sync → history filter by txid  
- Failed open → retry (FFI re-configure)  
- iOS background → foreground wallet still open  

### 6.4 CI matrix
| Job | OS | App | Steps |
|-----|----|----|-------|
| flutter-test | ubuntu | desktop | pub get, test |
| flutter-analyze | ubuntu | all 3 | analyze (optional) |
| integration (future) | windows | desktop | integration_test + FFI prebuilt |

---

## 7. Performance plan

| Metric | Target | Bottleneck | Fix |
|--------|--------|------------|-----|
| Cold start (desktop) | <2s to first frame | sync init in `main.dart` | Deferred init |
| Heartbeat CPU | 1 RPC/tick max | overlapping ticks [#8](https://github.com/ArqTras/Arqma-GUI-MM/issues/8) | Mutex |
| Tab switch | No rebuild inactive | `watch<GatewayStore>` [#12](https://github.com/ArqTras/Arqma-GUI-MM/issues/12) | Tab visibility |
| 1k tx list scroll | 60fps | O(n) token + merge on UI | Selector + isolate merge |

---

## 8. Security hardening checklist (Flutter scope)

- [ ] Block `ARQMA_FLUTTER_USE_STUB` in release ([#2](https://github.com/ArqTras/Arqma-GUI-MM/issues/2))  
- [ ] Denylist `ARQMA_FLUTTER_*` env in release builds  
- [ ] Sanitize wallet paths ([#4](https://github.com/ArqTras/Arqma-GUI-MM/issues/4))  
- [ ] Separate password UX from crypto verification ([#3](https://github.com/ArqTras/Arqma-GUI-MM/issues/3))  
- [ ] Redact logs ([#13](https://github.com/ArqTras/Arqma-GUI-MM/issues/13))  
- [ ] TLS or explicit cleartext warning ([#5](https://github.com/ArqTras/Arqma-GUI-MM/issues/5), [#6](https://github.com/ArqTras/Arqma-GUI-MM/issues/6))  
- [ ] Release signing Android ([#7](https://github.com/ArqTras/Arqma-GUI-MM/issues/7))  
- [ ] Pin FFI version per release ([#11](https://github.com/ArqTras/Arqma-GUI-MM/issues/11))  
- [ ] SHA256SUMS + optional Authenticode/notarize (desktop)  
- [ ] Secure clipboard policy for seeds  

---

## 9. Quick wins (high impact, low complexity)

1. `basename()` on wallet `filename` — [#4](https://github.com/ArqTras/Arqma-GUI-MM/issues/4)  
2. `if (kReleaseMode) ignore stub env` — [#2](https://github.com/ArqTras/Arqma-GUI-MM/issues/2)  
3. Add `_walletHbInFlight` to mobile — [#8](https://github.com/ArqTras/Arqma-GUI-MM/issues/8)  
4. CI `flutter test` job — [#10](https://github.com/ArqTras/Arqma-GUI-MM/issues/10)  
5. Redact `password` key in invoke logger — [#13](https://github.com/ArqTras/Arqma-GUI-MM/issues/13)  
6. Wire or delete `isAllowedMobileRemoteHost` — [#6](https://github.com/ArqTras/Arqma-GUI-MM/issues/6)  

---

## 10. Open questions

1. **Daemon TLS:** Will public Arqma nodes offer HTTPS JSON-RPC, or is cleartext an accepted threat model with user-run nodes? *(Changes #5 recommendation.)*  
2. **promptForPassword product intent:** Should disabling prompt only hide UI, or genuinely allow passwordless operation on encrypted wallets? *(Changes #3 fix.)*  
3. **Android signing:** Is Play Console upload planned with upload key separate from debug? *(Blocks #7.)*  
4. **Monorepo:** Should mobile and android merge into one Flutter module to end duplication? *(Architecture long-term.)*  

---

## 11. Production release readiness

**Verdict: Conditional GO for 5.1.1** with documented limitations.

- **Strengths:** Native FFI 1.0.14, worker isolate, serialized FFI calls, mature release CI, multi-platform artifacts, App Store review documentation.  
- **Blockers for “maximum security” label:** #2, #3, #4, #5 (mitigate with user education + own node), #7 for Play production.  
- **Blockers for “maximum stability” label:** #8, #9 on mobile/iOS.  

---

## 12. Project map (Flutter)

```
flutter/arqma_wallet_gui/          Desktop (Windows/macOS/Linux)
flutter-mobile/arqma_wallet_mobile/ iOS + mobile-oriented Android
flutter-android/arqma_wallet_android/ Android (remote node variant)
build/ci/                          FFI fetch, release scripts, flutter-version (3.41.9)
.prebuilt/                         Cached ArqTras/FFI prebuilts (local/CI)
.github/workflows/desktop-release.yml
.github/workflows/android-release.yml
```

**Entry:** `lib/main.dart` → `resolveAppNativeBridge()` → `GatewayStore` + GoRouter  
**Wallet:** in-process `arqma_wallet_flutter_ffi` (desktop/mobile); optional subprocess on mobile via env  
**Daemon:** spawn `arqmad` (desktop) or remote HTTP RPC (mobile)  

---

# RAPORT POLSKI

## 1. Streszczenie

### 1.1 Status aplikacji (jedna strona)

| Wymiar | Ocena | Uwagi |
|--------|-------|-------|
| **Architektura** | Dobra | Trzy aplikacje Flutter; wspólny mostek/FFI; desktop z isolate worker |
| **Bezpieczeństwo** | **Do poprawy** | Stub env; hasło vs prompt; HTTP daemon; path traversal |
| **Stabilność** | **Średnia** | Poprawka re-configure FFI; wyścigi heartbeat/open na mobile |
| **Wydajność** | **Średnia** | Rebuild zakładek desktop; duże listy tx |
| **CI / release** | **Do poprawy** | Brak testów; Android debug signing; FFI Latest |
| **Testy** | **Słabe** | 3 testy desktop; placeholdery mobile |
| **Gotowość produkcyjna** | **Warunkowa** | 5.1.1 OK dla świadomych użytkowników; nie „maks. bezpieczeństwo” bez High/Critical |

### 1.2 Największe zagrożenia

Patrz tabela w sekcji EN §1.2 — issues [#2](https://github.com/ArqTras/Arqma-GUI-MM/issues/2)–[#11](https://github.com/ArqTras/Arqma-GUI-MM/issues/11).

### 1.3 Zalecane dalsze kroki

1. **Natychmiast:** #2, #3, #4  
2. **Krótki termin:** #8, #9, #10  
3. **Release:** #7, #11  
4. **Dokumentacja:** model zagrożeń dla zdalnego węzła (HTTP)

---

## 2. Rejestr zagrożeń

Pełna tabela: sekcja EN §2 (identyfikatory R-001–R-018, odniesienia do issue #2–#13).

---

## 3. Ustalenia według roli

Szczegóły per rola (16 ról zespołu): sekcja EN §3 — treść merytoryczna identyczna; poniżej skrót PL.

| Rola | Sprawdzono | Ryzyko | Zalecenie |
|------|------------|--------|-----------|
| Architekt | 3 drzewa Flutter, FFI | Duplikacja kodu | Wspólny pakiet core |
| Flutter desktop | isolate, bridge | Fallback FFI na UI | Fail bez isolate |
| Bezpieczeństwo | env, logi | #2–#6 | Denylist env w release |
| Portfel krypto | seed, RPC | #3, #5 | Weryfikacja hasła zawsze |
| Supply chain | pubspec, CI | #7, #11 | lockfile + pin FFI |
| Wydajność | heartbeat, tabs | #12 | Tab visibility |
| Niezawodność | open/close | #8, #9 | Mutexy |
| QA | testy | #10 | CI flutter test |
| DevOps | workflow | pin Flutter | Android = 3.41.9 |
| Pakietowanie | verify_windows | brak sums desktop | SHA256 w CI |
| UX/i18n | 12 locale | hardcoded EN | sync_locale CI |
| Observability | debugPrint | #13 | Redakcja logów |
| Jakość kodu | 4600+ linii bridge | god-class | Refactor długoterminowy |

---

## 4. Priorytetowy plan napraw

| Horyzont | Działania |
|----------|-----------|
| **Natychmiastowe** | #2, #3, #4 |
| **Krótkoterminowe** | #8–#10, #13 |
| **Średnioterminowe** | #5–#7, #11–#12 |
| **Długoterminowe** | iOS CI, monorepo, E2E |

---

## 5. Plan aktualizacji zależności

Patrz EN §5 — Flutter 3.41.9 bezpieczny; `go_router` major wysokie ryzyko; lockfiles natychmiast.

---

## 6. Strategia testów

Patrz EN §6 — pierwszy krok: job CI `flutter test`; mocki RPC/daemon; E2E: open/retry/background iOS.

---

## 7. Plan wydajności

Metryki: cold start, heartbeat CPU, rebuild zakładek, scroll 1k tx — patrz EN §7.

---

## 8. Lista kontrolna wzmocnienia bezpieczeństwa (Flutter)

Checklist EN §8 — bez wzmocnień Electron/Tauri (poza zakresem).

---

## 9. Szybkie poprawki

EN §9 — basename, stub block, mobile mutex, CI test, redakcja logów, whitelist węzła.

---

## 10. Pytania otwarte

1. Czy publiczne węzły dostaną TLS?  
2. Czy `promptForPassword=false` ma wyłączyć tylko dialog?  
3. Klucz upload Android do Play?  
4. Scalanie mobile + android w jeden moduł?

---

## 11. Gotowość do wydania produkcyjnego

**Werdykt: warunkowe GO dla 5.1.1.**

Mocne strony: FFI 1.0.14, CI release, dokumentacja App Store.  
Do zamknięcia dla „maks. bezpieczeństwa”: issues #2–#7.  
Do zamknięcia dla „maks. stabilności” na mobile: #8, #9.

---

## 12. Utworzone zgłoszenia GitHub

| Issue | Tytuł | Severity |
|-------|-------|----------|
| [#2](https://github.com/ArqTras/Arqma-GUI-MM/issues/2) | ARQMA_FLUTTER_USE_STUB in release | Critical |
| [#3](https://github.com/ArqTras/Arqma-GUI-MM/issues/3) | Password bypass when prompt disabled | High |
| [#4](https://github.com/ArqTras/Arqma-GUI-MM/issues/4) | Path traversal wallet filename | High |
| [#5](https://github.com/ArqTras/Arqma-GUI-MM/issues/5) | Cleartext daemon HTTP | High |
| [#6](https://github.com/ArqTras/Arqma-GUI-MM/issues/6) | Custom remote nodes no whitelist | High |
| [#7](https://github.com/ArqTras/Arqma-GUI-MM/issues/7) | Android debug signing | High |
| [#8](https://github.com/ArqTras/Arqma-GUI-MM/issues/8) | Mobile heartbeat mutex | High |
| [#9](https://github.com/ArqTras/Arqma-GUI-MM/issues/9) | Concurrent open_wallet | High |
| [#10](https://github.com/ArqTras/Arqma-GUI-MM/issues/10) | No Flutter tests in CI | High |
| [#11](https://github.com/ArqTras/Arqma-GUI-MM/issues/11) | FFI Latest non-reproducible | High |
| [#12](https://github.com/ArqTras/Arqma-GUI-MM/issues/12) | Desktop tab rebuild perf | Medium |
| [#13](https://github.com/ArqTras/Arqma-GUI-MM/issues/13) | Sensitive invoke logging | Medium |

**Audyt wykluczył:** Electron/Quasar/Vue, Tauri (`rust/tauri-app`).

---

*Generated by multi-agent Flutter audit on branch `review`, 2026-06-03.*
