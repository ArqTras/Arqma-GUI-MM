#!/usr/bin/env bash
# Delete all assets attached to a GitHub Release (prepare for clean re-upload).
set -euo pipefail

REPO="${1:?repo owner/name}"
TAG="$(bash "$(dirname "$0")/resolve-release-tag.sh" "${2:-}")"
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"

if [[ -z "${TOKEN}" ]]; then
  echo "error: GH_TOKEN or GITHUB_TOKEN required" >&2
  exit 1
fi

if ! gh release view "${TAG}" -R "${REPO}" >/dev/null 2>&1; then
  echo "No release ${TAG} on ${REPO} — nothing to delete"
  exit 0
fi

count=0
while IFS= read -r row; do
  id="$(jq -r '.id' <<<"${row}")"
  name="$(jq -r '.name' <<<"${row}")"
  echo "Deleting release asset: ${name} (${id})"
  gh api -X DELETE -H "Accept: application/vnd.github+json" \
    "/repos/${REPO}/releases/assets/${id}" >/dev/null
  count=$((count + 1))
done < <(gh api "repos/${REPO}/releases/tags/${TAG}" --jq '.assets[] | @json')

echo "Deleted ${count} asset(s) from ${REPO} tag ${TAG}"
