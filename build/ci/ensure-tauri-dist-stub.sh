#!/usr/bin/env bash
# Minimal frontend dist for `cargo build --bin arqma_flutter_solo_pool` (no npm/vite).
# Tauri `generate_context!()` requires ../dist/index.html when `custom-protocol` is enabled.
set -eu

ROOT="${1:-}"
if [[ -z "${ROOT}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
fi

DIST="${ROOT}/rust/tauri-app/dist"
INDEX="${DIST}/index.html"
if [[ -f "${INDEX}" ]]; then
  echo "[ensure-tauri-dist-stub] OK: ${INDEX} exists"
  exit 0
fi

mkdir -p "${DIST}"
cat >"${INDEX}" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <title>Arqma-Wallet</title>
</head>
<body></body>
</html>
EOF
echo "[ensure-tauri-dist-stub] created ${INDEX}"
