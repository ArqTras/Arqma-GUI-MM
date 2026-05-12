#!/usr/bin/env bash
# Emit rust_toolchain and flutter_version for GitHub Actions from repo-pinned files.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RT="$ROOT/rust-toolchain.toml"
if [[ ! -f "$RT" ]]; then
  echo "::error::missing $RT"
  exit 1
fi
t=$(sed -n 's/^[[:space:]]*channel[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$RT" | head -1)
if [[ -z "${t}" ]]; then
  echo "::error::could not parse channel= from $RT"
  exit 1
fi
FV="$ROOT/build/ci/flutter-version"
if [[ ! -f "$FV" ]]; then
  echo "::error::missing $FV"
  exit 1
fi
v=$(grep -v '^[[:space:]]*#' "$FV" | grep -v '^[[:space:]]*$' | head -1 | tr -d '[:space:]')
if [[ -z "${v}" ]]; then
  echo "::error::empty or invalid first version line in $FV"
  exit 1
fi
{
  echo "rust_toolchain=${t}"
  echo "flutter_version=${v}"
} >> "${GITHUB_OUTPUT}"
echo "Pinned Rust toolchain=${t} Flutter=${v}"
