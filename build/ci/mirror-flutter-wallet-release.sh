#!/usr/bin/env bash
# Mirror ArqTras/Arqma-GUI-MM release assets + mobile docs to public arqma/Flutter-Wallet.
# Requires FLUTTER_WALLET_MIRROR_PAT (contents:write on arqma/Flutter-Wallet).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"

SOURCE_REPO="${ARQMA_SOURCE_REPO:-ArqTras/Arqma-GUI-MM}"
TARGET_REPO="${ARQMA_FLUTTER_WALLET_REPO:-arqma/Flutter-Wallet}"

if [[ -n "${RELEASE_TAG_INPUT:-}" ]]; then
  TAG="${RELEASE_TAG_INPUT}"
elif [[ -n "${RELEASE_TAG:-}" ]]; then
  TAG="${RELEASE_TAG}"
else
  TAG="$(bash build/ci/resolve-release-tag.sh "${GITHUB_REF_NAME:-}")"
fi
TAG="$(bash build/ci/resolve-release-tag.sh "${TAG}")"

MIRROR_PAT="${FLUTTER_WALLET_MIRROR_PAT:-}"
if [[ -z "${MIRROR_PAT}" ]]; then
  echo "error: FLUTTER_WALLET_MIRROR_PAT not set (needs write access to ${TARGET_REPO})" >&2
  exit 1
fi

export GH_TOKEN="${MIRROR_PAT}"

echo "==> Prune duplicate assets on ${SOURCE_REPO} tag ${TAG}"
GH_TOKEN="${GITHUB_TOKEN:-${MIRROR_PAT}}" bash build/ci/prune-github-release-duplicate-assets.sh "${SOURCE_REPO}" "${TAG}" || true

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT
ASSETS="${STAGE}/assets"
DOCS="${STAGE}/docs"
mkdir -p "${ASSETS}" "${DOCS}"

canonical_asset_names() {
  local t="$1"
  printf '%s\n' \
    "Arqma-Wallet-Flutter-${t}-macos.zip" \
    "Arqma-Wallet-Flutter-${t}-macos.dmg" \
    "Arqma-Wallet-Flutter-${t}-linux-x64.tar.gz" \
    "Arqma-Wallet-Flutter-${t}-x86_64.AppImage" \
    "Arqma-Wallet-Flutter-${t}-windows-x64.zip" \
    "Arqma-Wallet-Flutter-${t}-windows-x64-Setup.exe" \
    "Arqma-Wallet-Android-${t}.apk" \
    "Arqma-Wallet-Android-${t}.aab" \
    "Arqma-Wallet-Android-${t}-manifest.txt" \
    "SHA256SUMS-android-${t}.txt" \
    "Arqma-Wallet-Mobile-${t}-ios-testflight.ipa" \
    "Arqma-Wallet-Mobile-${t}-ios.xcarchive.zip" \
    "Arqma-Wallet-Mobile-${t}-ios-manifest.txt" \
    "SHA256SUMS-ios.txt"
}

echo "==> Download canonical release assets from ${SOURCE_REPO}@${TAG}"
if ! gh release view "${TAG}" -R "${SOURCE_REPO}" >/dev/null 2>&1; then
  echo "error: release ${TAG} not found on ${SOURCE_REPO}" >&2
  exit 1
fi

while IFS= read -r name; do
  [[ -z "${name}" ]] && continue
  if gh release download "${TAG}" -R "${SOURCE_REPO}" -p "${name}" -D "${ASSETS}" --clobber 2>/dev/null; then
    echo "  ok ${name}"
  else
    echo "  skip (not on release yet) ${name}"
  fi
done < <(canonical_asset_names "${TAG}")

n_assets="$(find "${ASSETS}" -type f | wc -l | tr -d ' ')"
if [[ "${n_assets}" -lt 1 ]]; then
  echo "error: no assets downloaded for ${TAG}" >&2
  exit 1
fi

echo "==> Copy documentation (incl. APP_STORE_REVIEW_INFORMATION.md → arqma/Flutter-Wallet/docs/)"
MOBILE_DOCS="${ROOT}/flutter-mobile/arqma_wallet_mobile/docs"
if [[ -d "${MOBILE_DOCS}" ]]; then
  for doc in README.md PRIVACY_POLICY.md APP_STORE_PRIVACY_DISCLOSURE.md \
    APP_STORE_PUBLICATION_REQUIREMENTS.md APP_STORE_REVIEW_INFORMATION.md; do
    if [[ -f "${MOBILE_DOCS}/${doc}" ]]; then
      cp -f "${MOBILE_DOCS}/${doc}" "${DOCS}/"
      echo "  ok docs/${doc}"
    fi
  done
fi
NOTES="${ROOT}/build/ci/release-notes-gui-${TAG}.md"
if [[ -f "${NOTES}" ]]; then
  cp -f "${NOTES}" "${DOCS}/RELEASE_NOTES-${TAG}.md"
fi

bash "${ROOT}/build/ci/generate-flutter-wallet-readme.sh" "${TAG}" "${STAGE}/README.md" "${SOURCE_REPO}"

# --- Update target git repository (docs on main) ---
WORK="$(mktemp -d)"
trap 'rm -rf "${STAGE}" "${WORK}"' EXIT
git clone --depth 1 "https://x-access-token:${MIRROR_PAT}@github.com/${TARGET_REPO}.git" "${WORK}/repo"
cd "${WORK}/repo"

git config user.name "ArqTras"
git config user.email "33489188+ArqTras@users.noreply.github.com"

cp -f "${STAGE}/README.md" README.md
mkdir -p docs
rm -f docs/*
cp -f "${DOCS}/"* docs/ 2>/dev/null || true

if [[ ! -f LICENSE ]]; then
  cat > LICENSE <<'EOF'
MIT License

Copyright (c) Arqma Project

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
fi

git add -A
if git diff --staged --quiet; then
  echo "No doc changes on main"
else
  git commit -m "docs: sync Arqma Wallet ${TAG} release documentation"
  git push origin HEAD:main
fi

echo "==> Publish GitHub Release on ${TARGET_REPO} tag ${TAG}"
export GH_TOKEN="${MIRROR_PAT}"

body_file="${DOCS}/RELEASE_NOTES-${TAG}.md"
if [[ ! -f "${body_file}" ]]; then
  body_file="${STAGE}/README.md"
fi

shopt -s nullglob
upload_paths=( "${ASSETS}"/* )
shopt -u nullglob

if gh release view "${TAG}" -R "${TARGET_REPO}" >/dev/null 2>&1; then
  echo "==> Replace existing release assets on ${TARGET_REPO}@${TAG}"
  bash "${ROOT}/build/ci/delete-github-release-assets.sh" "${TARGET_REPO}" "${TAG}"
  gh release upload "${TAG}" -R "${TARGET_REPO}" "${upload_paths[@]}"
else
  gh release create "${TAG}" -R "${TARGET_REPO}" \
    --title "Arqma Wallet ${TAG}" \
    --target main \
    --notes-file "${body_file}" \
    "${upload_paths[@]}"
fi

# Prune non-canonical assets on target (re-upload may leave orphans)
bash "${ROOT}/build/ci/prune-github-release-duplicate-assets.sh" "${TARGET_REPO}" "${TAG}" || true

echo "==> Mirror complete: https://github.com/${TARGET_REPO}/releases/tag/${TAG}"
