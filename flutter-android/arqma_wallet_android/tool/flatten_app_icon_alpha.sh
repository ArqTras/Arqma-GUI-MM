#!/usr/bin/env bash
# Remove alpha from iOS AppIcon PNGs (App Store Connect error 90717).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec bash "${ROOT}/tool/generate_app_icons.sh"
