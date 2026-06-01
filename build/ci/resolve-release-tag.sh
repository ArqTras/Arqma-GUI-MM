#!/usr/bin/env bash
# Print normalized release tag (semver without leading v).
set -euo pipefail
raw="${1:-${GITHUB_REF_NAME:-}}"
raw="${raw#refs/tags/}"
raw="${raw#v}"
if [[ -z "${raw}" ]]; then
  echo "error: empty release tag" >&2
  exit 1
fi
printf '%s\n' "${raw}"
