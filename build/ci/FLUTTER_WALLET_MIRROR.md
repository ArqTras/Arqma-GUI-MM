# Mirror releases to arqma/Flutter-Wallet

Public binaries and mobile legal docs are copied from **ArqTras/Arqma-GUI-MM** GitHub Releases to **[arqma/Flutter-Wallet](https://github.com/arqma/Flutter-Wallet)** with the **same tag** (e.g. `5.1.1`) and **canonical filenames** (no `5.1.1-2` build-metadata suffix).

## CI

- **Desktop:** `.github/workflows/desktop-release.yml` → `mirror-flutter-wallet` after `publish-release`
- **Android:** `.github/workflows/android-release.yml` → `mirror-flutter-wallet` after `github-release`
- **Manual:** Actions → **Mirror Flutter-Wallet release** → `release_tag`

## Secret (required)

In **ArqTras/Arqma-GUI-MM** repository secrets:

| Secret | Scopes |
|--------|--------|
| `FLUTTER_WALLET_MIRROR_PAT` | Fine-grained or classic PAT with **contents: write** on `arqma/Flutter-Wallet` and **read** on `ArqTras/Arqma-GUI-MM` |

## Local run

```bash
export FLUTTER_WALLET_MIRROR_PAT=ghp_...
export GITHUB_TOKEN=ghp_...   # optional, for prune on source repo
export RELEASE_TAG_INPUT=5.1.1
bash build/ci/mirror-flutter-wallet-release.sh
```

## Filename rules

Semver slug = release tag (text before `+` in `pubspec.yaml`). See `flutter-mobile/arqma_wallet_mobile/tool/RELEASE_NAMING.md`.
