#!/usr/bin/env bash
# True when argument looks like a semver release tag (5.1.1), not a branch name (main).
set -euo pipefail
t="$(bash "$(dirname "$0")/resolve-release-tag.sh" "${1:-}")"
if [[ "${t}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  exit 0
fi
exit 1
