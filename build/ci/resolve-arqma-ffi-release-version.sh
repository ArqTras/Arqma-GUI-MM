#!/usr/bin/env bash
# Print the ArqTras/FFI release tag to use for prebuilt downloads.
# Default: GitHub "Latest" release. Override: ARQMA_FFI_RELEASE_VERSION=1.0.3 (or latest).
set -euo pipefail

REPO="${ARQMA_FFI_REPO:-ArqTras/FFI}"
RAW="${ARQMA_FFI_RELEASE_VERSION:-latest}"
RAW="${RAW#v}"

if [[ -n "${RAW}" && "${RAW}" != "latest" ]]; then
  echo "${RAW}"
  exit 0
fi

if command -v gh >/dev/null 2>&1; then
  tag="$(gh api "repos/${REPO}/releases/latest" --jq .tag_name 2>/dev/null || true)"
  if [[ -n "${tag}" ]]; then
    echo "${tag#v}"
    exit 0
  fi
fi

if command -v python3 >/dev/null 2>&1; then
  python3 - "${REPO}" <<'PY'
import json
import os
import sys
import urllib.request

repo = sys.argv[1]
url = f"https://api.github.com/repos/{repo}/releases/latest"
req = urllib.request.Request(
    url,
    headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "Arqma-GUI-MM",
    },
)
token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
if token:
    req.add_header("Authorization", f"Bearer {token}")
with urllib.request.urlopen(req, timeout=60) as resp:
    tag = json.load(resp)["tag_name"]
print(tag.lstrip("v"))
PY
  exit 0
fi

if command -v curl >/dev/null 2>&1 && command -v sed >/dev/null 2>&1; then
  curl_args=(-fsSL -H "Accept: application/vnd.github+json" -H "User-Agent: Arqma-GUI-MM")
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  elif [[ -n "${GH_TOKEN:-}" ]]; then
    curl_args+=(-H "Authorization: Bearer ${GH_TOKEN}")
  fi
  json="$(curl "${curl_args[@]}" "https://api.github.com/repos/${REPO}/releases/latest")"
  tag="$(printf '%s' "${json}" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  if [[ -n "${tag}" ]]; then
    echo "${tag#v}"
    exit 0
  fi
fi

echo "[resolve-arqma-ffi-release-version] error: cannot resolve latest release for ${REPO}" >&2
exit 1
