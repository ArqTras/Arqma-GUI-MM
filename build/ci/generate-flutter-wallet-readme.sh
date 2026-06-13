#!/usr/bin/env bash
# Generate root README.md for arqma/Flutter-Wallet from release tag + asset list.
set -euo pipefail

TAG="${1:?tag}"
OUT="${2:?output path}"
SOURCE_REPO="${3:-ArqTras/Arqma-GUI-MM}"

cat > "${OUT}" <<EOF
# Arqma Wallet — prebuilt releases

Public distribution of **Arqma Wallet** desktop and mobile builds for version **${TAG}**.

- **Source code:** [${SOURCE_REPO}](https://github.com/${SOURCE_REPO})
- **Wallet FFI:** [ArqTras/FFI](https://github.com/ArqTras/FFI/releases)
- **License:** [MIT](LICENSE)

## Download (${TAG})

Installers and packages are attached to the [${TAG} release](https://github.com/arqma/Flutter-Wallet/releases/tag/${TAG}).

| Platform | Files |
|----------|--------|
| **Windows** | \`Arqma-Wallet-Flutter-${TAG}-windows-x64.zip\`, \`Arqma-Wallet-Flutter-${TAG}-windows-x64-Setup.exe\` |
| **Linux** | \`Arqma-Wallet-Flutter-${TAG}-linux-x64.tar.gz\`, \`Arqma-Wallet-Flutter-${TAG}-x86_64.AppImage\` |
| **macOS (signed)** | \`Arqma-Wallet-Flutter-${TAG}-macos-signed.zip\`, \`Arqma-Wallet-Flutter-${TAG}-macos-signed.dmg\` — **Developer ID** signed + **notarized** (preferred) |
| **macOS (unsigned)** | \`Arqma-Wallet-Flutter-${TAG}-macos-unsigned.zip\`, \`Arqma-Wallet-Flutter-${TAG}-macos-unsigned.dmg\` — CI adhoc only (when present) |
| **Android** | \`Arqma-Wallet-Android-${TAG}.apk\`, \`Arqma-Wallet-Android-${TAG}.aab\` |
| **iOS** | \`Arqma-Wallet-Mobile-${TAG}-ios-testflight.ipa\` (TestFlight / registered devices) |

Checksum files: \`SHA256SUMS-android-${TAG}.txt\`, \`SHA256SUMS-ios.txt\` (when present).

### macOS — signed vs unsigned

- **Signed** (\`…-macos-signed.*\`): **Developer ID** signed and **notarized** by the ArqTras release maintainer. Preferred for end users; Gatekeeper should accept without extra steps.
- **Unsigned** (\`…-macos-unsigned.*\`): **GitHub Actions CI** builds with adhoc signature only (not Developer ID). For developers or local re-signing.

If macOS still blocks launch, remove quarantine: \`xattr -cr "/Applications/Arqma-Wallet.app"\`.

## Privacy & App Store

- [Privacy Policy](docs/PRIVACY_POLICY.md)
- [App Store privacy disclosure](docs/APP_STORE_PRIVACY_DISCLOSURE.md)
- [App Store publication requirements](docs/APP_STORE_PUBLICATION_REQUIREMENTS.md)
- [App Store review information](docs/APP_STORE_REVIEW_INFORMATION.md) — Guideline 2.1 notes, demo restore wallet, Resolution Center replies

## Release notes

See [docs/RELEASE_NOTES-${TAG}.md](docs/RELEASE_NOTES-${TAG}.md) when available.

**Non-custodial wallet.** You control your keys. Verify checksums before install. No warranty.
EOF
