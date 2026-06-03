#!/usr/bin/env bash
# Back-compat wrapper — see ensure-latest-ffi.sh (all Flutter platforms).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec bash "${ROOT}/build/ci/ensure-latest-ffi.sh"
