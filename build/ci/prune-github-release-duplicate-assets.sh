#!/usr/bin/env bash
# Remove stale GitHub Release assets with accidental build-metadata suffixes in filenames
# (e.g. Arqma-Wallet-Flutter-5.1.1-2-macos.zip). Keeps canonical names (slug = tag only).
set -euo pipefail

REPO="${1:?repo owner/name}"
TAG="$(bash "$(dirname "$0")/resolve-release-tag.sh" "${2:-}")"
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

if [[ -z "${TOKEN}" ]]; then
  echo "error: GH_TOKEN or GITHUB_TOKEN required" >&2
  exit 1
fi

if ! gh release view "${TAG}" -R "${REPO}" >/dev/null 2>&1; then
  echo "No release ${TAG} on ${REPO} — skip prune"
  exit 0
fi

while IFS= read -r row; do
  id="$(jq -r '.id' <<<"${row}")"
  name="$(jq -r '.name' <<<"${row}")"
  # Windows CI bug: 5.1.1+N became 5.1.1-N in filenames (e.g. ...-5.1.1-2-windows...).
  if [[ "${name}" =~ ^Arqma-Wallet-Flutter-${TAG}-[0-9]+- ]]; then
    echo "Deleting duplicate asset: ${name} (${id})"
    gh api -X DELETE -H "Accept: application/vnd.github+json" \
      "/repos/${REPO}/releases/assets/${id}" >/dev/null
  fi
done < <(gh api "repos/${REPO}/releases/tags/${TAG}" --jq '.assets[] | @json')

echo "Prune complete for ${REPO} tag ${TAG}"
