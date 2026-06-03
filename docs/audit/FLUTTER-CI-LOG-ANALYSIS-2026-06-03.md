# Flutter CI Log Analysis — Arqma Wallet

**Date:** 2026-06-03  
**Run:** [26879000615](https://github.com/ArqTras/Arqma-GUI-MM/actions/runs/26879000615)  
**Branch:** `review` @ `be9ea11`  
**Workflow:** `flutter-test.yml` (matrix: Desktop, Mobile iOS tree, Android)  
**Local log:** `.tmp/ci-flutter-test-26879000615.log`

---

## Summary

| Job | Analyze | Tests | Duration | Result |
|-----|---------|-------|----------|--------|
| Desktop | **0 issues** | **7/7 pass** | ~1m47s | ✅ |
| Mobile (iOS tree) | 2 info (deprecated Radio) | **8/8 pass** | ~1m54s | ✅ |
| Android | 2 info (deprecated Radio) | **8/8 pass** | ~1m50s | ✅ |

All jobs green. No errors or warnings blocking merge.

---

## Findings from logs

### F-001 — No `pubspec.lock` in repo (N-002)

Each job runs `flutter pub get` and reports **Changed 85–102 dependencies** on every run. Resolution is non-deterministic across CI runs until lock files are committed.

**Action:** CI now uploads `pubspec.lock` artifacts per matrix job; commit locks to close N-002.

### F-002 — Analyzer info: deprecated `RadioListTile.onChanged` (mobile/android)

```
info • 'onChanged' is deprecated … mobile_remote_node_picker.dart:149, :161
```

Flutter 3.41+ expects `RadioGroup` wrapper. Desktop unaffected (no picker).

**Action:** Migrated to `RadioGroup<String>` in mobile + android pickers.

### F-003 — Residual debug env reads (N-004 carry-over)

CI static review found unguarded env usage:

- `ARQMA_FLUTTER_NO_SOLO_POOL` (desktop bridge)
- `ARQMA_FLUTTER_WALLET_RPC_MODE=subprocess` (mobile/android RPC session)

**Action:** Routed through `flutter_env_guard`.

### F-004 — iOS background / foreground sync overlap (N-006)

Background pulse timer and foreground recovery could interleave on iOS (`pulseBackgroundWalletSync` vs `recoverWalletSessionAfterForeground`).

**Action:** Added `_walletSyncLane` serializing pulse, persist, and recover on mobile/android bridges.

### F-005 — Dependabot (N-009, unchanged)

Default branch: **23 alerts** (4 high, 17 medium, 3 low). Not introduced by `review`; triage separately.

### F-006 — Node.js 20 deprecation notice

GitHub Actions warns `actions/checkout@v4` on Node 20 until Sept 2026. Informational only.

---

## Test inventory (from CI)

| App | Tests |
|-----|-------|
| Desktop | smoke, PBKDF2, address book, safe name ×2, redact ×2 |
| Mobile | safe name ×2, remote nodes ×4, redact ×2 |
| Android | same as mobile |

---

## Follow-up (post this analysis)

| ID | Item | Status after fixes |
|----|------|-------------------|
| N-002 | pubspec.lock | **Closed** — committed from CI |
| N-004 | Debug env in release | **Closed** (full guard coverage) |
| N-006 | iOS sync overlap | **Mitigated** (`_walletSyncLane`) |
| N-009 | Dependabot | Open |
| N-011 | integration_test | Open |

*Generated from GitHub Actions run 26879000615 log export.*
